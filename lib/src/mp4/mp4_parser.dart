library;

import 'dart:convert';

import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/mp4/atom.dart';
import 'package:metadata_audio/src/mp4/atom_token.dart';
import 'package:metadata_audio/src/tokenizer/http_tokenizers.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class Mp4Parser {
  Mp4Parser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  final Map<int, _TrackDescription> _tracks = <int, _TrackDescription>{};

  _TrackDescription? _currentTrack;
  bool _hasAudioTrack = false;
  bool _hasVideoTrack = false;
  int? _audioLengthInBytes;

  Future<void> parse() async {
    var remaining = tokenizer.fileInfo?.size;

    while (remaining == null || remaining > 0) {
      try {
        final probe = tokenizer.peekBytes(8);
        final probeName = ascii.decode(probe.sublist(4, 8), allowInvalid: true);
        if (probeName == '\x00\x00\x00\x00') {
          metadata.addWarning(
            'Error at offset=${tokenizer.position}: box.id=0',
          );
          break;
        }

        // For HTTP-based tokenizers, prefetch the entire moov atom
        // since it can be much larger than the initial prefetch window
        // (e.g. audiobooks often have 5-10MB moov atoms)
        if (probeName == 'moov' && tokenizer is HttpBasedTokenizer) {
          var moovSize =
              (probe[0] << 24) | (probe[1] << 16) | (probe[2] << 8) | probe[3];
          if (moovSize == 1) {
            // Extended size: read 16 bytes to get the 64-bit size
            try {
              final extProbe = tokenizer.peekBytes(16);
              moovSize = 0;
              for (var i = 8; i < 16; i++) {
                moovSize = (moovSize << 8) | extProbe[i];
              }
            } on TokenizerException catch (_) {
              moovSize = 0;
            }
          }
          if (moovSize > 0) {
            await (tokenizer as HttpBasedTokenizer).prefetchRange(
              tokenizer.position,
              tokenizer.position + moovSize,
            );
          }
        }

        final atom = await Mp4Atom.readAtom(
          tokenizer,
          _handleAtom,
          null,
          remaining ?? 0x7FFFFFFF,
        );

        if (remaining != null) {
          if (atom.header.length == 0) {
            break;
          }
          remaining -= atom.header.length;
          if (remaining < 0) {
            break;
          }
        }
      } on TokenizerException {
        break;
      }
    }

    _postProcessTracks();
  }

  Future<void> _handleAtom(Mp4Atom atom, int payloadLength) async {
    switch (atom.header.name) {
      case 'ftyp':
        _parseFtyp(tokenizer.readBytes(payloadLength));
        return;
      case 'mvhd':
        _parseMvhd(tokenizer.readBytes(payloadLength));
        return;
      case 'tkhd':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseTkhd(tokenizer.readBytes(payloadLength));
        return;
      case 'mdhd':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseMdhd(tokenizer.readBytes(payloadLength));
        return;
      case 'hdlr':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseHdlr(tokenizer.readBytes(payloadLength));
        return;
      case 'stsd':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseStsd(tokenizer.readBytes(payloadLength));
        return;
      case 'stts':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseStts(tokenizer.readBytes(payloadLength));
        return;
      case 'stsc':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseStsc(tokenizer.readBytes(payloadLength));
        return;
      case 'stsz':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseStsz(tokenizer.readBytes(payloadLength));
        return;
      case 'stco':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseStco(tokenizer.readBytes(payloadLength));
        return;
      case 'chap':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseChap(tokenizer.readBytes(payloadLength));
        return;
      case 'mdat':
        _audioLengthInBytes = payloadLength;
        if (!await _tryParseChaptersFromMdat(payloadLength)) {
          tokenizer.skip(payloadLength);
        }
        return;
      default:
        if (atom.parent?.header.name == 'ilst') {
          await _parseMetadataItem(atom, payloadLength);
        } else {
          tokenizer.skip(payloadLength);
        }
        return;
    }
  }

  bool _isTrackScopedAtom(Mp4Atom atom) =>
      atom.atomPath.startsWith('moov.trak.') ||
      atom.atomPath.contains('.trak.');

  void _parseFtyp(List<int> payload) {
    final brands = AtomToken.parseFtypBrands(payload);
    if (brands.isEmpty) {
      return;
    }

    final orderedDistinct = <String>[];
    for (final brand in brands) {
      if (!orderedDistinct.contains(brand)) {
        orderedDistinct.add(brand);
      }
    }

    metadata.setFormat(container: orderedDistinct.join('/'));
  }

  void _parseMvhd(List<int> payload) {
    final mvhd = AtomToken.parseMvhd(payload);
    metadata.setFormat(
      creationTime: mvhd.creationTime,
      modificationTime: mvhd.modificationTime,
    );

    if (mvhd.timeScale > 0 && mvhd.duration > 0) {
      metadata.setFormat(duration: mvhd.duration / mvhd.timeScale);
    }
  }

  void _parseTkhd(List<int> payload) {
    if (payload.length < 24) {
      metadata.addWarning('Ignoring truncated tkhd atom');
      return;
    }

    final trackId = AtomToken.readUint32Be(payload, 12);
    final track = _tracks.putIfAbsent(
      trackId,
      () => _TrackDescription(trackId),
    );
    _currentTrack = track;
  }

  void _parseMdhd(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }

    final mdhd = AtomToken.parseMdhd(payload);
    track.timeScale = mdhd.timeScale;
    track.durationUnits = mdhd.duration;
  }

  void _parseHdlr(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }

    final handler = AtomToken.parseHandlerType(payload);
    track.handlerType = handler;

    if (handler == 'soun' || handler == 'audi') {
      _hasAudioTrack = true;
    }
    if (handler == 'vide') {
      _hasVideoTrack = true;
    }
  }

  void _parseStsd(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }

    final descriptions = AtomToken.parseStsd(payload);
    track.sampleDescriptions.addAll(descriptions);
  }

  void _parseStts(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }
    track.timeToSampleTable.addAll(AtomToken.parseStts(payload));
  }

  void _parseStsc(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }
    track.sampleToChunkTable.addAll(AtomToken.parseStsc(payload));
  }

  void _parseStsz(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }
    final stsz = AtomToken.parseStsz(payload);
    track.sampleSize = stsz.$1;
    track.sampleSizeTable.addAll(stsz.$2);
  }

  void _parseStco(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }
    track.chunkOffsetTable.addAll(AtomToken.parseStco(payload));
  }

  void _parseChap(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }
    var offset = 0;
    while (offset + 4 <= payload.length) {
      track.chapterTrackIds.add(AtomToken.readUint32Be(payload, offset));
      offset += 4;
    }
  }

  Future<void> _parseMetadataItem(Mp4Atom itemAtom, int payloadLength) async {
    final itemPayloadEnd = tokenizer.position + payloadLength;

    final dataValues = <dynamic>[];
    String? mean;
    String? name;

    while (tokenizer.position < itemPayloadEnd) {
      final remaining = itemPayloadEnd - tokenizer.position;
      if (remaining < 8) {
        tokenizer.skip(remaining);
        break;
      }

      final child = await Mp4Atom.readAtom(
        tokenizer,
        (atom, atomPayloadLength) async {
          if (atom.header.name == 'data') {
            final data = AtomToken.parseDataAtom(
              tokenizer.readBytes(atomPayloadLength),
            );
            final value = _decodeDataValue(itemAtom.header.name, data);
            if (value != null) {
              dataValues.add(value);
            }
            return;
          }

          if (atom.header.name == 'mean') {
            mean = AtomToken.parseNameAtom(
              tokenizer.readBytes(atomPayloadLength),
            );
            return;
          }

          if (atom.header.name == 'name') {
            name = AtomToken.parseNameAtom(
              tokenizer.readBytes(atomPayloadLength),
            );
            return;
          }

          tokenizer.skip(atomPayloadLength);
        },
        itemAtom,
        remaining,
      );

      if (child.header.length == 0) {
        break;
      }
    }

    final tagKey = itemAtom.header.name == '----'
        ? _buildCustomTagKey(mean, name)
        : itemAtom.header.name;

    if (tagKey == null) {
      return;
    }

    for (final value in dataValues) {
      metadata.addNativeTag('iTunes', tagKey, value);
    }
  }

  dynamic _decodeDataValue(String tagKey, DataAtom dataAtom) {
    if (dataAtom.type.set != 0) {
      metadata.addWarning('Unsupported MP4 data atom set=${dataAtom.type.set}');
      return null;
    }

    final value = dataAtom.value;
    switch (dataAtom.type.type) {
      case 0:
        return _decodeTypeReserved(tagKey, value);
      case 1:
      case 18:
        return utf8.decode(value, allowMalformed: true);
      case 13:
        if (options.skipCovers) {
          return null;
        }
        return Picture(format: 'image/jpeg', data: List<int>.from(value));
      case 14:
        if (options.skipCovers) {
          return null;
        }
        return Picture(format: 'image/png', data: List<int>.from(value));
      case 21:
        return _readSignedBeInteger(value);
      case 22:
        return _readUnsignedBeInteger(value);
      case 65:
        return value.isEmpty ? null : value[0];
      case 66:
        return value.length < 2 ? null : AtomToken.readUint16Be(value, 0);
      case 67:
        return value.length < 4 ? null : AtomToken.readUint32Be(value, 0);
      default:
        metadata.addWarning(
          'Unknown MP4 data type ${dataAtom.type.type} for tag=$tagKey',
        );
        return null;
    }
  }

  dynamic _decodeTypeReserved(String tagKey, List<int> value) {
    switch (tagKey) {
      case 'trkn':
      case 'disk':
        if (value.length < 6) {
          return null;
        }
        final number = value[3];
        final total = value[5];
        return '$number/$total';
      case 'rate':
        return ascii.decode(value, allowInvalid: true).trim();
      default:
        return null;
    }
  }

  int? _readSignedBeInteger(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > 8) {
      return null;
    }
    var value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte & 0xFF);
    }
    final bits = bytes.length * 8;
    final signBit = BigInt.one << (bits - 1);
    if ((value & signBit) != BigInt.zero) {
      value -= BigInt.one << bits;
    }
    if (value > BigInt.from(0x7FFFFFFF) || value < BigInt.from(-0x80000000)) {
      return null;
    }
    return value.toInt();
  }

  int? _readUnsignedBeInteger(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > 8) {
      return null;
    }
    var value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte & 0xFF);
    }
    if (value > BigInt.from(0x7FFFFFFF)) {
      return null;
    }
    return value.toInt();
  }

  String? _buildCustomTagKey(String? mean, String? name) {
    final normalizedMean = mean?.trim();
    final normalizedName = name?.trim();
    if (normalizedMean == null || normalizedMean.isEmpty) {
      return null;
    }
    if (normalizedName == null || normalizedName.isEmpty) {
      return null;
    }
    return '----:$normalizedMean:$normalizedName';
  }

  void _postProcessTracks() {
    final audioTracks = _tracks.values.where((t) => t.isAudio).toList();
    final videoTracks = _tracks.values.where((t) => t.isVideo).toList();

    _hasAudioTrack = _hasAudioTrack || audioTracks.isNotEmpty;
    _hasVideoTrack = _hasVideoTrack || videoTracks.isNotEmpty;

    final primaryAudio = audioTracks.isNotEmpty ? audioTracks.first : null;
    if (primaryAudio != null) {
      final firstSample = primaryAudio.sampleDescriptions.isNotEmpty
          ? primaryAudio.sampleDescriptions.first
          : null;

      if (firstSample != null) {
        metadata.setFormat(
          codec: _formatCodec(firstSample.dataFormat),
          sampleRate: firstSample.sampleRate,
          bitsPerSample: firstSample.bitsPerSample,
          numberOfChannels: firstSample.numberOfChannels,
          lossless: _isLossless(firstSample.dataFormat),
        );
      }

      if (primaryAudio.timeScale != null &&
          primaryAudio.durationUnits != null &&
          primaryAudio.timeScale! > 0 &&
          primaryAudio.durationUnits! > 0) {
        metadata.setFormat(
          duration: primaryAudio.durationUnits! / primaryAudio.timeScale!,
        );
      }
    }

    final currentDuration = metadata.format.duration;
    final audioLength = _audioLengthInBytes;
    if (audioLength != null && currentDuration != null && currentDuration > 0) {
      metadata.setFormat(bitrate: 8 * audioLength / currentDuration);
    } else {
      final fileSize = tokenizer.fileInfo?.size;
      if (fileSize != null && currentDuration != null && currentDuration > 0) {
        metadata.setFormat(bitrate: 8 * fileSize / currentDuration);
      }
    }

    metadata.setFormat(hasAudio: _hasAudioTrack, hasVideo: _hasVideoTrack);
  }

  Future<bool> _tryParseChaptersFromMdat(int payloadLength) async {
    if (!options.includeChapters) {
      return false;
    }

    final tracksWithChapters = _tracks.values
        .where((track) => track.chapterTrackIds.isNotEmpty)
        .toList();
    if (tracksWithChapters.length != 1) {
      return false;
    }

    final chapterOwnerTrack = tracksWithChapters.single;
    final chapterTracks = _tracks.values
        .where(
          (track) => chapterOwnerTrack.chapterTrackIds.contains(track.trackId),
        )
        .toList();
    if (chapterTracks.length != 1) {
      return false;
    }

    final chapterTrack = chapterTracks.single;
    final chapters = await _parseChapterTrack(
      chapterTrack,
      chapterOwnerTrack,
      payloadLength,
    );
    if (chapters == null || chapters.isEmpty) {
      return false;
    }

    metadata.setFormat(chapters: chapters);
    return true;
  }

  Future<List<Chapter>?> _parseChapterTrack(
    _TrackDescription chapterTrack,
    _TrackDescription referencedTrack,
    int payloadLength,
  ) async {
    if (chapterTrack.chunkOffsetTable.isEmpty) {
      return null;
    }
    if (chapterTrack.sampleSize == null) {
      return null;
    }
    if (chapterTrack.sampleSize == 0 &&
        chapterTrack.chunkOffsetTable.length !=
            chapterTrack.sampleSizeTable.length) {
      metadata.addWarning('Invalid MP4 chapter track sample sizing');
      return null;
    }
    if (referencedTrack.timeScale == null || referencedTrack.timeScale! <= 0) {
      return null;
    }

    // Calculate all chapter data ranges for prefetching
    final chapterRanges = <(int, int)>[];
    var tempRemaining = payloadLength;
    var virtualPosition = tokenizer.position;
    for (
      var i = 0;
      i < chapterTrack.chunkOffsetTable.length && tempRemaining > 0;
      i++
    ) {
      final chunkOffset = chapterTrack.chunkOffsetTable[i];
      final skipLength = chunkOffset - virtualPosition;
      final sampleSize = chapterTrack.sampleSize! > 0
          ? chapterTrack.sampleSize!
          : chapterTrack.sampleSizeTable[i];
      if (skipLength >= 0 &&
          sampleSize >= 0 &&
          tempRemaining >= skipLength + sampleSize) {
        chapterRanges.add((chunkOffset, chunkOffset + sampleSize));
        tempRemaining -= skipLength + sampleSize;
        virtualPosition = chunkOffset + sampleSize;
      }
    }

    // Prefetch individual chapter data ranges for HTTP-based tokenizers.
    // We fetch each range individually in small batches rather than the entire
    // min-to-max span, since chapter data may be scattered across a huge
    // mdat atom (e.g. 300MB+) and we only need the small title samples.
    if (chapterRanges.isNotEmpty) {
      if (tokenizer case final HttpBasedTokenizer httpTokenizer) {
        try {
          // Batch prefetch to avoid overwhelming the server
          const batchSize = 4;
          for (var i = 0; i < chapterRanges.length; i += batchSize) {
            final batch = chapterRanges.skip(i).take(batchSize);
            await Future.wait(
              batch.map(
                (range) => httpTokenizer.prefetchRange(range.$1, range.$2),
              ),
            );
          }
        } on Exception catch (e) {
          metadata.addWarning('Failed to prefetch chapter data: $e');
          return null;
        }
      }
    }

    var remaining = payloadLength;
    final chapters = <Chapter>[];
    for (
      var i = 0;
      i < chapterTrack.chunkOffsetTable.length && remaining > 0;
      i++
    ) {
      final chunkOffset = chapterTrack.chunkOffsetTable[i];
      final skipLength = chunkOffset - tokenizer.position;
      final sampleSize = chapterTrack.sampleSize! > 0
          ? chapterTrack.sampleSize!
          : chapterTrack.sampleSizeTable[i];
      if (skipLength < 0 || sampleSize < 0) {
        metadata.addWarning('Invalid MP4 chapter offset/size');
        return null;
      }
      remaining -= skipLength + sampleSize;
      if (remaining < 0) {
        metadata.addWarning('MP4 chapter chunk exceeds mdat payload');
        return null;
      }

      tokenizer.skip(skipLength);
      final title = AtomToken.parseChapterText(tokenizer.readBytes(sampleSize));
      final chapterOffset = _findSampleOffset(
        referencedTrack,
        tokenizer.position,
      );
      final startMs = ((chapterOffset * 1000) / referencedTrack.timeScale!)
          .round();
      chapters.add(
        Chapter(
          title: title,
          start: startMs,
          sampleOffset: chapterOffset,
          timeScale: 1000,
        ),
      );
    }

    for (var i = 0; i < chapters.length; i++) {
      final current = chapters[i];
      final end = i + 1 < chapters.length
          ? chapters[i + 1].start
          : (referencedTrack.durationUnits != null
                ? ((referencedTrack.durationUnits! * 1000) /
                          referencedTrack.timeScale!)
                      .round()
                : null);
      chapters[i] = Chapter(
        id: current.id,
        title: current.title,
        url: current.url,
        sampleOffset: current.sampleOffset,
        start: current.start,
        end: end,
        timeScale: current.timeScale,
        image: current.image,
      );
    }

    tokenizer.skip(remaining);
    return chapters;
  }

  int _findSampleOffset(_TrackDescription track, int chapterOffset) {
    var chunkIndex = 0;
    while (chunkIndex < track.chunkOffsetTable.length &&
        track.chunkOffsetTable[chunkIndex] < chapterOffset) {
      chunkIndex++;
    }
    return _getChunkDuration(chunkIndex + 1, track);
  }

  int _getChunkDuration(int chunkId, _TrackDescription track) {
    if (track.timeToSampleTable.isEmpty || track.sampleToChunkTable.isEmpty) {
      return 0;
    }
    var timeToSampleIndex = 0;
    var remainingCount = track.timeToSampleTable[timeToSampleIndex].count;
    var sampleDuration = track.timeToSampleTable[timeToSampleIndex].duration;
    var currentChunkId = 1;
    var samplesPerChunk = _getSamplesPerChunk(currentChunkId, track);
    var totalDuration = 0;

    while (currentChunkId < chunkId) {
      final numberOfSamples = remainingCount < samplesPerChunk
          ? remainingCount
          : samplesPerChunk;
      totalDuration += numberOfSamples * sampleDuration;
      remainingCount -= numberOfSamples;
      samplesPerChunk -= numberOfSamples;

      if (samplesPerChunk == 0) {
        currentChunkId++;
        samplesPerChunk = _getSamplesPerChunk(currentChunkId, track);
      } else {
        timeToSampleIndex++;
        if (timeToSampleIndex >= track.timeToSampleTable.length) {
          break;
        }
        remainingCount = track.timeToSampleTable[timeToSampleIndex].count;
        sampleDuration = track.timeToSampleTable[timeToSampleIndex].duration;
      }
    }

    return totalDuration;
  }

  int _getSamplesPerChunk(int chunkId, _TrackDescription track) {
    final table = track.sampleToChunkTable;
    for (var i = 0; i < table.length - 1; i++) {
      if (chunkId >= table[i].firstChunk && chunkId < table[i + 1].firstChunk) {
        return table[i].samplesPerChunk;
      }
    }
    return table.last.samplesPerChunk;
  }

  String _formatCodec(String dataFormat) {
    switch (dataFormat) {
      case 'mp4a':
        return 'MPEG-4/AAC';
      case 'alac':
        return 'ALAC';
      case 'ac-3':
        return 'AC-3';
      default:
        return dataFormat;
    }
  }

  bool _isLossless(String dataFormat) {
    switch (dataFormat) {
      case 'alac':
      case 'raw':
        return true;
      default:
        return false;
    }
  }
}

class _TrackDescription {
  _TrackDescription(this.trackId);

  final int trackId;
  String? handlerType;
  int? timeScale;
  int? durationUnits;
  int? sampleSize;
  final List<SampleDescription> sampleDescriptions = <SampleDescription>[];
  final List<SttsEntry> timeToSampleTable = <SttsEntry>[];
  final List<StscEntry> sampleToChunkTable = <StscEntry>[];
  final List<int> sampleSizeTable = <int>[];
  final List<int> chunkOffsetTable = <int>[];
  final List<int> chapterTrackIds = <int>[];

  bool get isAudio => handlerType == 'soun' || handlerType == 'audi';
  bool get isVideo => handlerType == 'vide';
}
