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

  // Nero chapter list (chpl atom) chapters
  final List<_ChplChapter> _chplChapters = <_ChplChapter>[];

  Future<void> parse() async {
    var remaining = tokenizer.fileInfo?.size;

    while (remaining == null || remaining > 0) {
      try {
        // For HTTP-based tokenizers with on-demand fetching, ensure the
        // next atom header is available before reading. This is critical
        // after skipping large atoms (e.g. multi-GB mdat) where the
        // parser position moves beyond the initially prefetched data.
        if (tokenizer is HttpBasedTokenizer) {
          await (tokenizer as HttpBasedTokenizer).prefetchRange(
            tokenizer.position,
            tokenizer.position + 16, // 8-byte header + 8-byte extended size
          );
        }

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

    await _postProcessTracks();
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
      case 'co64':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseCo64(tokenizer.readBytes(payloadLength));
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
      case 'chpl':
        // Nero chapter list atom (inside udta)
        if (atom.parent?.header.name == 'udta') {
          _parseChpl(tokenizer.readBytes(payloadLength));
        } else {
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

    final version = payload[0];
    final trackIdOffset = version == 1 ? 20 : 12;
    if (payload.length < trackIdOffset + 4) {
      metadata.addWarning('Ignoring truncated tkhd atom for version=$version');
      return;
    }

    final trackId = AtomToken.readUint32Be(payload, trackIdOffset);
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

  void _parseCo64(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }
    track.chunkOffsetTable.addAll(AtomToken.parseCo64(payload));
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

  void _parseChpl(List<int> payload) {
    if (!options.includeChapters) {
      return;
    }

    if (payload.length < 9) {
      metadata.addWarning('chpl atom too small');
      return;
    }

    var offset = 0;

    // Version (1 byte)
    final version = payload[offset++];

    // Flags (3 bytes)
    // ignore: unused_local_variable
    final flags =
        (payload[offset++] << 16) |
        (payload[offset++] << 8) |
        payload[offset++];

    // Reserved (1 byte)
    offset++;

    // Chapter count (4 bytes)
    final chapterCount = AtomToken.readUint32Be(payload, offset);
    offset += 4;

    for (var i = 0; i < chapterCount && offset + 9 <= payload.length; i++) {
      // Timestamp (8 bytes) - use last 4 bytes for 32-bit values
      // as some files store 32-bit timestamps in 64-bit fields
      BigInt timestamp;
      if (version == 1) {
        // Full 64-bit timestamp
        timestamp = BigInt.zero;
        for (var j = 0; j < 8; j++) {
          timestamp =
              (timestamp << 8) | BigInt.from(payload[offset + j] & 0xFF);
        }
      } else {
        // 32-bit timestamp stored in last 4 bytes of 8-byte field
        final ts32 =
            (payload[offset + 4] << 24) |
            (payload[offset + 5] << 16) |
            (payload[offset + 6] << 8) |
            payload[offset + 7];
        timestamp = BigInt.from(ts32);
      }
      offset += 8;

      // Title length (1 byte)
      final titleLen = payload[offset++] & 0xFF;

      // Title string
      var title = '';
      if (titleLen > 0 && offset + titleLen <= payload.length) {
        title = utf8.decode(
          payload.sublist(offset, offset + titleLen),
          allowMalformed: true,
        );
        offset += titleLen;
      }

      _chplChapters.add(_ChplChapter(timestamp: timestamp, title: title));
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

  Future<void> _postProcessTracks() async {
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

    // Fallback chapter extraction after all atoms are parsed.
    // This handles files where mdat appears before moov/chapter tables.
    if (options.includeChapters && metadata.format.chapters == null) {
      await _tryParseChaptersFromTrackReferences();
    }

    // Process chpl (Nero chapter list) chapters if present.
    // chpl uses a fixed time base of 1/10000000.
    if (_chplChapters.isNotEmpty && options.includeChapters) {
      _processChplChapters();
    }
  }

  Future<bool> _tryParseChaptersFromTrackReferences() async {
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
    final chapters = await _parseChapterTrackByAbsoluteOffsets(
      chapterTrack,
      chapterOwnerTrack,
    );
    if (chapters == null || chapters.isEmpty) {
      return false;
    }

    metadata.setFormat(chapters: chapters);
    return true;
  }

  Future<List<Chapter>?> _parseChapterTrackByAbsoluteOffsets(
    _TrackDescription chapterTrack,
    _TrackDescription referencedTrack,
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

    final originalPosition = tokenizer.position;
    final chapters = <Chapter>[];

    // Prefetch chapter data ranges for HTTP-based tokenizers.
    // Chapter text samples are scattered in mdat (potentially multi-GB),
    // and only the small title samples need to be fetched.
    if (tokenizer case final HttpBasedTokenizer httpTokenizer) {
      try {
        final ranges = <(int, int)>[];
        for (var i = 0; i < chapterTrack.chunkOffsetTable.length; i++) {
          final chunkOffset = chapterTrack.chunkOffsetTable[i];
          final sampleSize = chapterTrack.sampleSize! > 0
              ? chapterTrack.sampleSize!
              : chapterTrack.sampleSizeTable[i];
          if (chunkOffset >= 0 && sampleSize > 0) {
            ranges.add((chunkOffset, chunkOffset + sampleSize));
          }
        }
        const batchSize = 4;
        for (var i = 0; i < ranges.length; i += batchSize) {
          final batch = ranges.skip(i).take(batchSize);
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

    for (var i = 0; i < chapterTrack.chunkOffsetTable.length; i++) {
      final chunkOffset = chapterTrack.chunkOffsetTable[i];
      if (chunkOffset < 0) {
        metadata.addWarning('Invalid MP4 chapter offset/size');
        return null;
      }

      final sampleSize = chapterTrack.sampleSize! > 0
          ? chapterTrack.sampleSize!
          : chapterTrack.sampleSizeTable[i];
      if (sampleSize < 0) {
        metadata.addWarning('Invalid MP4 chapter offset/size');
        return null;
      }

      tokenizer.seek(chunkOffset);
      final title = AtomToken.parseChapterText(tokenizer.readBytes(sampleSize));

      final chapterOffsetFromStts = _getSampleOffsetFromStts(chapterTrack, i);

      int chapterOffset;
      int startMs;
      if (chapterOffsetFromStts != null &&
          chapterTrack.timeScale != null &&
          chapterTrack.timeScale! > 0) {
        chapterOffset = chapterOffsetFromStts;
        startMs = ((chapterOffset * 1000) / chapterTrack.timeScale!).round();
      } else {
        chapterOffset = _findSampleOffset(referencedTrack, chunkOffset);
        startMs = ((chapterOffset * 1000) / referencedTrack.timeScale!).round();
      }

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
      var end = i + 1 < chapters.length
          ? chapters[i + 1].start
          : (referencedTrack.durationUnits != null
                ? ((referencedTrack.durationUnits! * 1000) /
                          referencedTrack.timeScale!)
                      .round()
                : null);

      if (end != null && end < current.start) {
        final fallbackDurationMs = metadata.format.duration != null
            ? (metadata.format.duration! * 1000).round()
            : null;
        end = fallbackDurationMs != null && fallbackDurationMs >= current.start
            ? fallbackDurationMs
            : current.start;
      }

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

    tokenizer.seek(originalPosition);
    return chapters;
  }

  /// Converts chpl chapters to the standard Chapter format and sets them in metadata.
  void _processChplChapters() {
    final fileDuration = metadata.format.duration;
    if (fileDuration == null || fileDuration <= 0) return;

    final inferredTimeBase = _inferChplTimeBase(fileDuration);
    if (inferredTimeBase == null || inferredTimeBase <= 0) return;

    final chapters = <Chapter>[];

    for (final chplChapter in _chplChapters) {
      // Convert timestamp to milliseconds
      final timestampMs =
          (chplChapter.timestamp * BigInt.from(1000)) ~/
          BigInt.from(inferredTimeBase);

      // Skip chapters with timestamps exceeding file duration (plus small tolerance)
      final maxDuration = BigInt.from((fileDuration * 1000 + 5000).round());
      if (timestampMs > maxDuration) {
        continue;
      }

      chapters.add(
        Chapter(
          title: chplChapter.title.isEmpty
              ? 'Chapter ${chapters.length + 1}'
              : chplChapter.title,
          start: timestampMs.toInt(),
          timeScale: 1000,
        ),
      );
    }

    // Sort chapters by timestamp
    chapters.sort((a, b) => a.start.compareTo(b.start));

    // Calculate end times
    for (var i = 0; i < chapters.length; i++) {
      final end = i + 1 < chapters.length
          ? chapters[i + 1].start
          : (fileDuration * 1000).round();
      chapters[i] = Chapter(
        id: chapters[i].id,
        title: chapters[i].title,
        url: chapters[i].url,
        sampleOffset: chapters[i].sampleOffset,
        start: chapters[i].start,
        end: end,
        timeScale: chapters[i].timeScale,
        image: chapters[i].image,
      );
    }

    if (chapters.isNotEmpty) {
      metadata.setFormat(chapters: chapters);
    }
  }

  /// Infer chpl time base from file timing data.
  ///
  /// Many files encode chpl timestamps in high-resolution units. We infer the
  /// scale factor by matching the largest chapter timestamp to media duration.
  int? _inferChplTimeBase(double fileDurationSeconds) {
    if (_chplChapters.isEmpty || fileDurationSeconds <= 0) {
      return null;
    }

    var maxTimestamp = BigInt.zero;
    for (final chapter in _chplChapters) {
      if (chapter.timestamp > maxTimestamp) {
        maxTimestamp = chapter.timestamp;
      }
    }

    if (maxTimestamp == BigInt.zero) {
      return null;
    }

    final inferred = (maxTimestamp.toDouble() / fileDurationSeconds).round();
    if (inferred <= 0) {
      return null;
    }

    return _normalizeTimeBase(inferred);
  }

  /// Normalize an inferred time base to a nearby canonical clock when possible.
  int _normalizeTimeBase(int inferred) {
    const candidates = <int>[
      1000,
      22050,
      44100,
      48000,
      90000,
      1000000,
      10000000,
    ];

    var best = inferred;
    var bestRelError = double.infinity;

    for (final candidate in candidates) {
      final relError = (candidate - inferred).abs() / inferred;
      if (relError < bestRelError) {
        bestRelError = relError;
        best = candidate;
      }
    }

    // Snap only when very close to avoid distorting truly custom bases.
    return bestRelError <= 0.02 ? best : inferred;
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

      // Prefer chapter track STTS timing when available. This is the canonical
      // source for chapter sample timestamps in QuickTime chapter tracks.
      final chapterOffsetFromStts = _getSampleOffsetFromStts(chapterTrack, i);

      int chapterOffset;
      int startMs;
      if (chapterOffsetFromStts != null &&
          chapterTrack.timeScale != null &&
          chapterTrack.timeScale! > 0) {
        chapterOffset = chapterOffsetFromStts;
        startMs = ((chapterOffset * 1000) / chapterTrack.timeScale!).round();
      } else {
        // Fallback for files without chapter track timing tables.
        chapterOffset = _findSampleOffset(referencedTrack, chunkOffset);
        startMs = ((chapterOffset * 1000) / referencedTrack.timeScale!).round();
      }

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
      var end = i + 1 < chapters.length
          ? chapters[i + 1].start
          : (referencedTrack.durationUnits != null
                ? ((referencedTrack.durationUnits! * 1000) /
                          referencedTrack.timeScale!)
                      .round()
                : null);

      if (end != null && end < current.start) {
        final fallbackDurationMs = metadata.format.duration != null
            ? (metadata.format.duration! * 1000).round()
            : null;
        end = fallbackDurationMs != null && fallbackDurationMs >= current.start
            ? fallbackDurationMs
            : current.start;
      }

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

  int? _getSampleOffsetFromStts(_TrackDescription track, int sampleIndex) {
    if (sampleIndex < 0 || track.timeToSampleTable.isEmpty) {
      return null;
    }

    var remaining = sampleIndex;
    var offset = 0;

    for (final entry in track.timeToSampleTable) {
      if (remaining <= 0) {
        return offset;
      }

      final take = remaining < entry.count ? remaining : entry.count;
      offset += take * entry.duration;
      remaining -= take;
    }

    if (remaining == 0) {
      return offset;
    }

    return null;
  }

  int _findSampleOffset(_TrackDescription track, int chapterOffset) {
    var chunkIndex = 0;
    while (chunkIndex < track.chunkOffsetTable.length &&
        track.chunkOffsetTable[chunkIndex] < chapterOffset) {
      chunkIndex++;
    }

    // chapterOffset points to chapter text sample bytes in mdat and may land
    // inside a chunk. For timeline mapping we need the start of that chunk,
    // not the following one.
    final chunkId = chunkIndex == 0 ? 1 : chunkIndex;
    return _getChunkDuration(chunkId, track);
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

/// Internal representation of a chapter from a chpl (Nero Chapter List) atom.
class _ChplChapter {
  _ChplChapter({required this.timestamp, required this.title});

  /// Timestamp in timescale units.
  final BigInt timestamp;

  /// Chapter title.
  final String title;
}
