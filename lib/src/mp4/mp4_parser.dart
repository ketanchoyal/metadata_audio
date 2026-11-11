library;

import 'dart:convert';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:metadata_audio/src/common/allocation.dart';
import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/mp4/atom.dart';
import 'package:metadata_audio/src/mp4/atom_token.dart';
import 'package:metadata_audio/src/tokenizer/http_tokenizers.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:metadata_audio/src/utils/cache_types.dart';
import 'package:metadata_audio/src/utils/m4a_muxer.dart';

class Mp4Parser {
  Mp4Parser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
    this.collectSampleTables = false,
  });

  static const int _maxMoovPrefetchBytes = 2 * 1024 * 1024;
  static const int _maxInlineAudioStszBytes = 256 * 1024;
  static const int _maxAudioChapterSupportTableBytes = 1 * 1024 * 1024;
  static const int _maxChapterHintTableBytes = 256 * 1024;

  List<Mp4TrackInfo> getTrackInfos() => _tracks.values.map((track) {
    final desc = track.sampleDescriptions.isEmpty
        ? null
        : track.sampleDescriptions.first;
    return Mp4TrackInfo(
      trackId: track.trackId,
      handlerType: track.handlerType,
      timeScale: track.timeScale,
      sampleSize: track.sampleSize,
      sampleSizeTable: track.sampleSizeTable,
      timeToSampleTable: track.timeToSampleTable,
      isAudio: track.isAudio,
      sampleRate: desc?.sampleRate,
      numberOfChannels: desc?.numberOfChannels,
      rawStsdBox: track.rawStsdBox,
    );
  }).toList();

  /// Returns the raw `stsc` (sample-to-chunk) table for [trackId].
  ///
  /// Exposed so callers can persist it as part of a metadata cache entry
  /// without having to re-parse the container on future access.
  List<StscEntry>? getSampleToChunkTable(int trackId) =>
      _tracks[trackId]?.sampleToChunkTable;

  /// Returns the raw `stco`/`co64` (chunk-offset) table for [trackId].
  ///
  /// Exposed so callers can persist it as part of a metadata cache entry
  /// without having to re-parse the container on future access.
  List<int>? getChunkOffsetTable(int trackId) =>
      _tracks[trackId]?.chunkOffsetTable;

  int? getByteOffsetForSample(int trackId, int targetSampleIndex) {
    final track = _tracks[trackId];
    if (track == null) return null;
    return _getByteOffsetForSample(track, targetSampleIndex);
  }

  int? getSampleIndexForTime(int trackId, int timeOffset) {
    final track = _tracks[trackId];
    if (track == null) return null;
    return _getSampleIndexForTime(track, timeOffset);
  }

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;
  final bool collectSampleTables;

  final Map<int, _TrackDescription> _tracks = <int, _TrackDescription>{};

  _TrackDescription? _currentTrack;
  bool _hasAudioTrack = false;
  bool _hasVideoTrack = false;
  int? _audioLengthInBytes;

  // Nero chapter list (chpl atom) chapters
  final List<_ChplChapter> _chplChapters = <_ChplChapter>[];
  List<int>? _chplPayload;

  /// Byte offset and size of the `moov` box, when encountered.
  int? moovOffset;
  int? moovSize;

  /// Raw `moov.udta` box bytes (with `chpl` stripped) and `moov.meta` box bytes
  /// captured when `!options.skipCovers` on a seekable tokenizer.
  List<int>? rawUdtaBox;
  List<int>? rawMetaBox;

  Future<void> parse({int startOffset = 0, bool stopAfterMoov = false}) async {
    if (startOffset > 0 && tokenizer.canSeek) {
      tokenizer.seek(startOffset);
    }
    final totalSize = tokenizer.fileInfo?.size;
    var remaining = totalSize != null ? (totalSize - startOffset) : null;

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

        // For HTTP-based tokenizers, prefetch small/moderate moov atoms up
        // front so parsing takes a single Range request. Larger moov atoms
        // (e.g. audiobooks with multi-megabyte audio stsz tables) are
        // prefetched atom-by-atom so skipped sample tables are not downloaded.
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
          final maxPrefetch = min(
            getMaxMemoryAllocation(options),
            _maxMoovPrefetchBytes,
          );
          if (moovSize > 0 && moovSize <= maxPrefetch) {
            await _prefetchRange(
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
          prefetchRange: tokenizer is HttpBasedTokenizer ? _prefetchRange : null,
        );

        if (atom.header.name == 'moov') {
          moovOffset = atom.offset;
          if (atom.header.length > 0) {
            moovSize = atom.header.length;
          }
          if (collectSampleTables && tokenizer.canSeek && !options.skipCovers) {
            _captureMoovMetadataBoxes(atom);
          }
          if (stopAfterMoov) {
            break;
          }
        }

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

  void _validatePayloadLength(int length) {
    validateAllocation(length, options, Mp4ContentError.new);
  }

  Future<void> _prefetchRange(int start, int end) {
    final t = tokenizer;
    if (t is HttpBasedTokenizer && end > start) {
      final total = t.fileInfo?.size;
      final lastByte = total != null && end > total ? total - 1 : end - 1;
      if (lastByte >= start) {
        return t.prefetchRange(start, lastByte);
      }
    }
    return Future<void>.value();
  }

  Future<List<int>> _readPayloadBytes(int payloadLength) async {
    _validatePayloadLength(payloadLength);
    await _prefetchRange(
      tokenizer.position,
      tokenizer.position + payloadLength,
    );
    return tokenizer.readBytes(payloadLength);
  }

  bool _isReferencedChapterTrack(int trackId) =>
      _tracks.values.any((t) => t.chapterTrackIds.contains(trackId));

  bool _shouldKeepNonMediaSampleTable(
    _TrackDescription track,
    int payloadLength,
  ) {
    final isChapterCandidate =
        track.handlerType == 'text' ||
        track.handlerType == 'sbtl' ||
        track.handlerType == 'subt' ||
        _isReferencedChapterTrack(track.trackId);
    if (!isChapterCandidate) {
      return false;
    }
    final limit = getMaxMemoryAllocation(options);
    return payloadLength <= _maxChapterHintTableBytes && payloadLength <= limit;
  }

  bool _shouldParseSampleTableAtom(
    _TrackDescription? track,
    int payloadLength,
  ) {
    if (track == null) {
      return false;
    }
    if (collectSampleTables) {
      return true;
    }
    if (track.isAudio || track.isVideo) {
      if (!options.includeChapters) {
        return false;
      }
      final maxAlloc = getMaxMemoryAllocation(options);
      return payloadLength <= maxAlloc &&
          payloadLength <= _maxAudioChapterSupportTableBytes;
    }
    if (options.includeChapters) {
      return true;
    }
    return _shouldKeepNonMediaSampleTable(track, payloadLength);
  }

  Future<void> _handleStszAtom(Mp4Atom atom, int payloadLength) async {
    if (!_isTrackScopedAtom(atom)) {
      tokenizer.skip(payloadLength);
      return;
    }
    final track = _currentTrack;
    if (track == null) {
      tokenizer.skip(payloadLength);
      return;
    }
    if (collectSampleTables) {
      _parseStsz(await _readPayloadBytes(payloadLength));
      return;
    }
    if (track.isAudio || track.isVideo) {
      if (!options.includeChapters || payloadLength < 12) {
        tokenizer.skip(payloadLength);
        return;
      }

      // Read only the 12-byte stsz header (version/flags, sampleSize, entryCount)
      // instead of buffering multi-megabyte audio sample tables into RAM.
      await _prefetchRange(tokenizer.position, tokenizer.position + 12);
      tokenizer.readUint32(); // version & flags
      final sampleSize = tokenizer.readUint32();
      final entryCount = tokenizer.readUint32();
      track
        ..sampleSize = sampleSize
        ..sampleCount = entryCount;

      final remaining = payloadLength - 12;
      if (sampleSize != 0) {
        tokenizer.skip(remaining);
        return;
      }

      if (tokenizer.canSeek && tokenizer is! HttpBasedTokenizer) {
        if (entryCount >= 0 && entryCount * 4 <= remaining) {
          track
            ..stszEntriesOffset = tokenizer.position
            ..stszEntryCount = entryCount;
        }
        tokenizer.skip(remaining);
        return;
      }

      final inlineLimit = min(
        getMaxMemoryAllocation(options),
        _maxInlineAudioStszBytes,
      );
      if (payloadLength <= inlineLimit &&
          entryCount >= 0 &&
          entryCount * 4 <= remaining) {
        await _prefetchRange(
          tokenizer.position,
          tokenizer.position + remaining,
        );
        final entryBytes = tokenizer.readBytes(remaining);
        final entries = _parseStszEntries(entryBytes, entryCount);
        _assignSampleSizeTable(track, entries);
      } else {
        tokenizer.skip(remaining);
      }
      return;
    }

    if (!options.includeChapters &&
        !_shouldKeepNonMediaSampleTable(track, payloadLength)) {
      tokenizer.skip(payloadLength);
      return;
    }
    _parseStsz(await _readPayloadBytes(payloadLength));
  }

  Future<void> _handleAtom(Mp4Atom atom, int payloadLength) async {
    switch (atom.header.name) {
      case 'ftyp':
        _parseFtyp(await _readPayloadBytes(payloadLength));
        return;
      case 'mvhd':
        _parseMvhd(await _readPayloadBytes(payloadLength));
        return;
      case 'tkhd':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseTkhd(await _readPayloadBytes(payloadLength));
        return;
      case 'mdhd':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseMdhd(await _readPayloadBytes(payloadLength));
        return;
      case 'hdlr':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseHdlr(await _readPayloadBytes(payloadLength));
        return;
      case 'stsd':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseStsd(await _readPayloadBytes(payloadLength));
        return;
      case 'stts':
        if (!_isTrackScopedAtom(atom) ||
            !_shouldParseSampleTableAtom(_currentTrack, payloadLength)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseStts(await _readPayloadBytes(payloadLength));
        return;
      case 'stsc':
        if (!_isTrackScopedAtom(atom) ||
            !_shouldParseSampleTableAtom(_currentTrack, payloadLength)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseStsc(await _readPayloadBytes(payloadLength));
        return;
      case 'stsz':
        await _handleStszAtom(atom, payloadLength);
        return;
      case 'stco':
        if (!_isTrackScopedAtom(atom) ||
            !_shouldParseSampleTableAtom(_currentTrack, payloadLength)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseStco(await _readPayloadBytes(payloadLength));
        return;
      case 'co64':
        if (!_isTrackScopedAtom(atom) ||
            !_shouldParseSampleTableAtom(_currentTrack, payloadLength)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseCo64(await _readPayloadBytes(payloadLength));
        return;
      case 'chap':
        if (!_isTrackScopedAtom(atom)) {
          // Orphan track-specific box may not modify whichever track happens
          // to be registered last.
          metadata.addWarning(
            'Ignoring track-specific atom ${atom.atomPath} outside a track',
          );
          tokenizer.skip(payloadLength);
          return;
        }
        _parseChap(await _readPayloadBytes(payloadLength));
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
          if (options.includeChapters) {
            final chplBytes = await _readPayloadBytes(payloadLength);
            _chplPayload = chplBytes is Uint8List
                ? chplBytes
                : Uint8List.fromList(chplBytes);
            _parseChpl(chplBytes);
          } else if (payloadLength >= 9 &&
              payloadLength <= getMaxMemoryAllocation(options)) {
            final chplBytes = await _readPayloadBytes(payloadLength);
            _chplPayload = chplBytes is Uint8List
                ? chplBytes
                : Uint8List.fromList(chplBytes);
          } else {
            tokenizer.skip(payloadLength);
          }
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

    final boxLength = payload.length + 8;
    final stsdBox = Uint8List(boxLength);
    stsdBox[0] = (boxLength >> 24) & 0xFF;
    stsdBox[1] = (boxLength >> 16) & 0xFF;
    stsdBox[2] = (boxLength >> 8) & 0xFF;
    stsdBox[3] = boxLength & 0xFF;
    stsdBox[4] = 0x73; // 's'
    stsdBox[5] = 0x74; // 't'
    stsdBox[6] = 0x73; // 's'
    stsdBox[7] = 0x64; // 'd'
    stsdBox.setRange(8, boxLength, payload);
    track.rawStsdBox = stsdBox;

    final descriptions = AtomToken.parseStsd(payload);
    track.sampleDescriptions.addAll(descriptions);
  }

  void _parseStts(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }
    final parsed = AtomToken.parseStts(payload);
    if (track.timeToSampleTable.isEmpty) {
      track.timeToSampleTable = parsed;
    } else {
      track.timeToSampleTable = <SttsEntry>[
        ...track.timeToSampleTable,
        ...parsed,
      ];
    }
  }

  void _parseStsc(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }
    final parsed = AtomToken.parseStsc(payload);
    if (track.sampleToChunkTable.isEmpty) {
      track.sampleToChunkTable = parsed;
    } else {
      track.sampleToChunkTable = <StscEntry>[
        ...track.sampleToChunkTable,
        ...parsed,
      ];
    }
  }

  void _parseStsz(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }
    final stsz = AtomToken.parseStsz(payload);
    track
      ..sampleSize = stsz.$1
      ..sampleCount = stsz.$2;
    _assignSampleSizeTable(track, stsz.$3);
  }

  void _assignSampleSizeTable(_TrackDescription track, List<int> entries) {
    if (entries.isEmpty) {
      return;
    }
    if (track.sampleSizeTable.isEmpty) {
      track.sampleSizeTable = entries;
    } else {
      track.sampleSizeTable = <int>[...track.sampleSizeTable, ...entries];
    }
  }

  List<int> _parseStszEntries(List<int> bytes, int entryCount) {
    final entries = Uint32List(entryCount);
    if (bytes is Uint8List) {
      final data = ByteData.sublistView(bytes);
      for (var i = 0; i < entryCount; i++) {
        entries[i] = data.getUint32(i * 4);
      }
    } else {
      for (var i = 0; i < entryCount; i++) {
        entries[i] = AtomToken.readUint32Be(bytes, i * 4);
      }
    }
    return entries;
  }

  void _parseStco(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }
    final parsed = AtomToken.parseStco(payload);
    if (track.chunkOffsetTable.isEmpty) {
      track.chunkOffsetTable = parsed;
    } else {
      track.chunkOffsetTable = <int>[...track.chunkOffsetTable, ...parsed];
    }
  }

  void _parseCo64(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }
    final parsed = AtomToken.parseCo64(payload);
    if (track.chunkOffsetTable.isEmpty) {
      track.chunkOffsetTable = parsed;
    } else {
      track.chunkOffsetTable = <int>[...track.chunkOffsetTable, ...parsed];
    }
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
    if (version > 1) {
      metadata.addWarning('Unsupported chpl version: $version');
      return;
    }

    // Flags (3 bytes)
    final flags =
        (payload[offset++] << 16) |
        (payload[offset++] << 8) |
        payload[offset++];

    // Version 0 header is 4 bytes; version 1 adds 4
    // more header bytes (8 in total) before the single-byte chapter count.
    if (version == 1) {
      offset += 4;
    }

    if (offset + 9 > payload.length) {
      metadata.addWarning('chpl atom too small');
      return;
    }

    // Chapter count (1 byte)
    final chapterCount = payload[offset++] & 0xFF;
    final maxChapterCount = getMaxChapterCount(options);
    if (chapterCount > maxChapterCount) {
      metadata.addWarning(
        'Chapter count exceeds the $maxChapterCount chapter limit',
      );
    }

    for (
      var i = 0;
      i < chapterCount &&
          offset + 9 <= payload.length &&
          _chplChapters.length < maxChapterCount;
      i++
    ) {
      // Timestamp (8 bytes, 64-bit; time base: 10,000,000 ticks per second)
      var timestamp = BigInt.zero;
      for (var j = 0; j < 8; j++) {
        timestamp = (timestamp << 8) | BigInt.from(payload[offset + j] & 0xFF);
      }
      offset += 8;

      // Title length (1 byte)
      final titleLen = payload[offset++] & 0xFF;

      // Title string. A title that exceeds the remaining payload ends the
      // chapter list; continuing would re-read the same offset.
      if (offset + titleLen > payload.length) {
        break;
      }

      var title = '';
      if (titleLen > 0) {
        title = utf8.decode(
          payload.sublist(offset, offset + titleLen),
          allowMalformed: true,
        );
        offset += titleLen;
      }

      _chplChapters.add(
        _ChplChapter(timestamp: timestamp, title: title, flags: flags),
      );
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
            if (options.skipCovers && itemAtom.header.name == 'covr') {
              tokenizer.skip(atomPayloadLength);
              return;
            }
            final data = AtomToken.parseDataAtom(
              await _readPayloadBytes(atomPayloadLength),
            );
            final value = _decodeDataValue(itemAtom.header.name, data);
            if (value != null) {
              dataValues.add(value);
            }
            return;
          }

          if (atom.header.name == 'mean') {
            mean = AtomToken.parseNameAtom(
              await _readPayloadBytes(atomPayloadLength),
            );
            return;
          }

          if (atom.header.name == 'name') {
            name = AtomToken.parseNameAtom(
              await _readPayloadBytes(atomPayloadLength),
            );
            return;
          }

          tokenizer.skip(atomPayloadLength);
        },
        itemAtom,
        remaining,
        prefetchRange: tokenizer is HttpBasedTokenizer ? _prefetchRange : null,
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
        return Picture(
          format: 'image/jpeg',
          data: value is Uint8List ? value : Uint8List.fromList(value),
        );
      case 14:
        if (options.skipCovers) {
          return null;
        }
        return Picture(
          format: 'image/png',
          data: value is Uint8List ? value : Uint8List.fromList(value),
        );
      case 27:
        if (options.skipCovers) {
          return null;
        }
        return Picture(
          format: 'image/bmp',
          data: value is Uint8List ? value : Uint8List.fromList(value),
        );
      case 21:
        return _readSignedBeInteger(value);
      case 22:
        return _readUnsignedBeInteger(value);
      case 65:
        // INT8: signed 8-bit integer.
        return value.isEmpty
            ? null
            : (value[0] < 128 ? value[0] : value[0] - 256);
      case 66:
        // INT16_BE: signed big-endian 16-bit integer.
        if (value.length < 2) {
          return null;
        }
        final int16 = AtomToken.readUint16Be(value, 0);
        return int16 > 0x7FFF ? int16 - 0x10000 : int16;
      case 67:
        // INT32_BE: signed big-endian 32-bit integer.
        if (value.length < 4) {
          return null;
        }
        final int32 = AtomToken.readUint32Be(value, 0);
        return int32 > 0x7FFFFFFF ? int32 - 0x100000000 : int32;
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
      case 'covr':
        if (options.skipCovers || value.isEmpty) {
          return null;
        }
        return Picture(
          format: _detectImageMimeType(value),
          data: value is Uint8List ? value : Uint8List.fromList(value),
        );
      default:
        return null;
    }
  }

  static String _detectImageMimeType(List<int> bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'image/jpeg';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return 'image/gif';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return 'image/bmp';
    }
    return 'image/jpeg';
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
      try {
        await _tryParseChaptersFromTrackReferences();
      } catch (e) {
        if (_chplChapters.isEmpty) {
          rethrow;
        }
        metadata.addWarning('Cannot read QuickTime chapter track: $e');
      }
    }

    // Process chpl (Nero chapter list) chapters if present.
    // In files with both, QuickTime chapters are preferred UNLESS
    // QuickTime chapters had no titles (empty strings) and Nero has titles,
    // or QuickTime chapter extraction yielded no chapters.
    final existingChapters = metadata.format.chapters;
    final quickTimeHasTitles = existingChapters != null &&
        existingChapters.any((c) => c.title.trim().isNotEmpty);

    if (_chplChapters.isNotEmpty &&
        options.includeChapters &&
        !quickTimeHasTitles) {
      _processChplChapters();
    }
  }

  Future<bool> _tryParseChaptersFromTrackReferences() async {
    final tracksWithChapters = _tracks.values
        .where((track) => track.chapterTrackIds.isNotEmpty)
        .toList();
    if (tracksWithChapters.isEmpty) {
      return false;
    }

    final chapterTrackIds = tracksWithChapters
        .expand((track) => track.chapterTrackIds)
        .toSet();
    if (chapterTrackIds.isEmpty) {
      return false;
    }

    // Resolve the referenced chapter track.
    _TrackDescription? chapterTrack;
    for (final id in chapterTrackIds) {
      chapterTrack = _tracks[id];
      if (chapterTrack != null) {
        break;
      }
    }
    if (chapterTrack == null) {
      return false;
    }

    // Prefer an audio track as referenced track;
    // fallback to video or any owner.
    final chapterOwnerTrack = tracksWithChapters.firstWhere(
      (track) => track.isAudio,
      orElse: () => tracksWithChapters.firstWhere(
        (track) => track.isVideo,
        orElse: () => tracksWithChapters.first,
      ),
    );

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
    final chapterSamples = _buildChapterSampleEntries(chapterTrack);
    if (chapterSamples == null || chapterSamples.isEmpty) {
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
        for (final sample in chapterSamples) {
          if (sample.absoluteOffset >= 0 && sample.sampleSize > 0) {
            ranges.add((
              sample.absoluteOffset,
              sample.absoluteOffset + sample.sampleSize,
            ));
          }
        }
        // Prefetch the full set once; a single transient range failure
        // (e.g. archive.org HTTP 500) is retried once before giving up.
        const batchSize = 4;
        for (var pass = 0; pass < 2; pass++) {
          try {
            for (var i = 0; i < ranges.length; i += batchSize) {
              final batch = ranges.skip(i).take(batchSize);
              await Future.wait(
                batch.map(
                  (range) => httpTokenizer.prefetchRange(range.$1, range.$2),
                ),
              );
            }
            break;
          } on FileDownloadError {
            // prefetchRange natively retries transient errors; a failure
            // here most often means the whole batch raced a slow mirror.
            if (pass == 0) {
              await Future<void>.delayed(const Duration(seconds: 1));
              continue;
            }
            rethrow;
          }
        }
      } on Exception catch (e) {
        metadata.addWarning('Failed to prefetch chapter data: $e');
        return null;
      }
    }

    for (final sample in chapterSamples) {
      if (sample.absoluteOffset < 0 || sample.sampleSize < 0) {
        metadata.addWarning('Invalid MP4 chapter offset/size');
        return null;
      }

      tokenizer.seek(sample.absoluteOffset);
      _validatePayloadLength(sample.sampleSize);
      final title = AtomToken.parseChapterText(
        tokenizer.readBytes(sample.sampleSize),
      );

      final resolved = _resolveChapterTimingAndOffset(
        chapterTrack,
        referencedTrack,
        sample,
      );

      chapters.add(
        Chapter(
          title: title,
          start: resolved.startMs,
          byteOffset: resolved.byteOffset,
          timeScale: 1000,
        ),
      );
    }

    final durationUnits =
        chapterTrack.durationUnits ?? referencedTrack.durationUnits;
    final timeScale =
        (chapterTrack.durationUnits != null ? chapterTrack.timeScale : null) ??
        referencedTrack.timeScale;

    for (var i = 0; i < chapters.length; i++) {
      final current = chapters[i];
      var end = i + 1 < chapters.length
          ? chapters[i + 1].start
          : (durationUnits != null && timeScale != null && timeScale > 0
                ? ((durationUnits * 1000) / timeScale).round()
                : null);

      if (end != null && end <= current.start) {
        final fallbackDurationMs = metadata.format.duration != null
            ? (metadata.format.duration! * 1000).round()
            : null;
        end = fallbackDurationMs != null && fallbackDurationMs >= current.start
            ? fallbackDurationMs
            : current.start;
      }

      final endByteOffset = i + 1 < chapters.length
          ? chapters[i + 1].byteOffset
          : tokenizer.fileInfo?.size;

      chapters[i] = Chapter(
        id: current.id,
        title: current.title,
        url: current.url,
        byteOffset: current.byteOffset,
        endByteOffset: endByteOffset,
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

    // chpl timestamps use the spec base of 10,000,000 ticks per second.
    const chplTimestampTimescale = 10000000;

    final chapters = <Chapter>[];
    final audioTrack = _tracks.values.where((t) => t.isAudio).firstOrNull;

    for (final chplChapter in _chplChapters) {
      // Convert timestamp to milliseconds
      final timestampMs =
          (chplChapter.timestamp * BigInt.from(1000)) ~/
          BigInt.from(chplTimestampTimescale);

      // Skip chapters with timestamps exceeding file duration (plus small tolerance)
      final maxDuration = BigInt.from((fileDuration * 1000 + 5000).round());
      if (timestampMs > maxDuration) {
        continue;
      }

      int? byteOffset;
      if (audioTrack != null && audioTrack.timeScale != null) {
        final audioTimeOffset =
            (timestampMs * BigInt.from(audioTrack.timeScale!)) ~/
            BigInt.from(1000);
        byteOffset = _getByteOffsetForTime(audioTrack, audioTimeOffset.toInt());
      }

      chapters.add(
        Chapter(
          title: chplChapter.title.isEmpty
              ? 'Chapter ${chapters.length + 1}'
              : chplChapter.title,
          start: timestampMs.toInt(),
          byteOffset: byteOffset,
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

      final endByteOffset = i + 1 < chapters.length
          ? chapters[i + 1].byteOffset
          : tokenizer.fileInfo?.size;

      chapters[i] = Chapter(
        id: chapters[i].id,
        title: chapters[i].title,
        url: chapters[i].url,
        byteOffset: chapters[i].byteOffset,
        endByteOffset: endByteOffset,
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

  Future<bool> _tryParseChaptersFromMdat(int payloadLength) async {
    if (!options.includeChapters) {
      return false;
    }

    final tracksWithChapters = _tracks.values
        .where((track) => track.chapterTrackIds.isNotEmpty)
        .toList();
    if (tracksWithChapters.isEmpty) {
      return false;
    }

    final chapterTrackIds = tracksWithChapters
        .expand((track) => track.chapterTrackIds)
        .toSet();
    if (chapterTrackIds.isEmpty) {
      return false;
    }

    // Resolve the referenced chapter track.
    _TrackDescription? chapterTrack;
    for (final id in chapterTrackIds) {
      chapterTrack = _tracks[id];
      if (chapterTrack != null) {
        break;
      }
    }
    if (chapterTrack == null) {
      return false;
    }

    // Prefer an audio track as referenced track; fallback to video or
    // any owner.
    final chapterOwnerTrack = tracksWithChapters.firstWhere(
      (track) => track.isAudio,
      orElse: () => tracksWithChapters.firstWhere(
        (track) => track.isVideo,
        orElse: () => tracksWithChapters.first,
      ),
    );

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
    final chapterSamples = _buildChapterSampleEntries(chapterTrack);
    if (chapterSamples == null || chapterSamples.isEmpty) {
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
    for (final sample in chapterSamples) {
      final skipLength = sample.absoluteOffset - virtualPosition;
      if (skipLength >= 0 &&
          sample.sampleSize >= 0 &&
          tempRemaining >= skipLength + sample.sampleSize) {
        chapterRanges.add((
          sample.absoluteOffset,
          sample.absoluteOffset + sample.sampleSize,
        ));
        tempRemaining -= skipLength + sample.sampleSize;
        virtualPosition = sample.absoluteOffset + sample.sampleSize;
      }
    }

    // Prefetch individual chapter data ranges for HTTP-based tokenizers.
    // We fetch each range individually in small batches rather than the entire
    // min-to-max span, since chapter data may be scattered across a huge
    // mdat atom (e.g. 300MB+) and we only need the small title samples.
    if (chapterRanges.isNotEmpty) {
      if (tokenizer case final HttpBasedTokenizer httpTokenizer) {
        const batchSize = 4;
        try {
          // Batch prefetch to avoid overwhelming the server
          for (var i = 0; i < chapterRanges.length; i += batchSize) {
            final batch = chapterRanges.skip(i).take(batchSize);
            await Future.wait(
              batch.map(
                (range) => httpTokenizer.prefetchRange(range.$1, range.$2),
              ),
            );
          }
        } on FileDownloadError {
          // One retry after transient range-fetch failures (e.g. shared
          // hosts returning HTTP 500 under load); prefetchRange already
          // retries internally, so failing again here is persistent.
          await Future<void>.delayed(const Duration(seconds: 1));
          try {
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
        } on Exception catch (e) {
          metadata.addWarning('Failed to prefetch chapter data: $e');
          return null;
        }
      }
    }

    var remaining = payloadLength;
    final chapters = <Chapter>[];
    for (final sample in chapterSamples) {
      if (remaining <= 0) {
        break;
      }

      final skipLength = sample.absoluteOffset - tokenizer.position;
      if (skipLength < 0 || sample.sampleSize < 0) {
        metadata.addWarning('Invalid MP4 chapter offset/size');
        return null;
      }
      remaining -= skipLength + sample.sampleSize;
      if (remaining < 0) {
        metadata.addWarning('MP4 chapter chunk exceeds mdat payload');
        return null;
      }

      tokenizer.skip(skipLength);
      _validatePayloadLength(sample.sampleSize);
      final title = AtomToken.parseChapterText(
        tokenizer.readBytes(sample.sampleSize),
      );

      final resolved = _resolveChapterTimingAndOffset(
        chapterTrack,
        referencedTrack,
        sample,
      );

      chapters.add(
        Chapter(
          title: title,
          start: resolved.startMs,
          byteOffset: resolved.byteOffset,
          timeScale: 1000,
        ),
      );
    }

    final durationUnits =
        chapterTrack.durationUnits ?? referencedTrack.durationUnits;
    final timeScale =
        (chapterTrack.durationUnits != null ? chapterTrack.timeScale : null) ??
        referencedTrack.timeScale;

    for (var i = 0; i < chapters.length; i++) {
      final current = chapters[i];
      var end = i + 1 < chapters.length
          ? chapters[i + 1].start
          : (durationUnits != null && timeScale != null && timeScale > 0
                ? ((durationUnits * 1000) / timeScale).round()
                : null);

      if (end != null && end <= current.start) {
        final fallbackDurationMs = metadata.format.duration != null
            ? (metadata.format.duration! * 1000).round()
            : null;
        end = fallbackDurationMs != null && fallbackDurationMs >= current.start
            ? fallbackDurationMs
            : current.start;
      }

      final endByteOffset = i + 1 < chapters.length
          ? chapters[i + 1].byteOffset
          : tokenizer.fileInfo?.size;

      chapters[i] = Chapter(
        id: current.id,
        title: current.title,
        url: current.url,
        byteOffset: current.byteOffset,
        endByteOffset: endByteOffset,
        start: current.start,
        end: end,
        timeScale: current.timeScale,
        image: current.image,
      );
    }

    tokenizer.skip(remaining);
    return chapters;
  }

  ({int startMs, int? byteOffset}) _resolveChapterTimingAndOffset(
    _TrackDescription chapterTrack,
    _TrackDescription referencedTrack,
    _ChapterSampleEntry sample,
  ) {
    final chapterOffsetFromStts = _getSampleOffsetFromStts(
      chapterTrack,
      sample.sampleIndex,
    );

    final int referencedOffset;
    final int startMs;
    if (chapterOffsetFromStts != null &&
        chapterTrack.timeScale != null &&
        chapterTrack.timeScale! > 0) {
      startMs = ((chapterOffsetFromStts * 1000) / chapterTrack.timeScale!)
          .round();
      referencedOffset =
          ((BigInt.from(chapterOffsetFromStts) *
                      BigInt.from(referencedTrack.timeScale!)) ~/
                  BigInt.from(chapterTrack.timeScale!))
              .toInt();
    } else {
      referencedOffset = _findSampleOffset(
        referencedTrack,
        sample.absoluteOffset,
      );
      startMs = ((referencedOffset * 1000) / referencedTrack.timeScale!)
          .round();
    }

    final byteOffset = _getByteOffsetForTime(referencedTrack, referencedOffset);
    return (startMs: startMs, byteOffset: byteOffset);
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

  List<_ChapterSampleEntry>? _buildChapterSampleEntries(
    _TrackDescription track,
  ) {
    final sampleSize = track.sampleSize;
    if (sampleSize == null || track.chunkOffsetTable.isEmpty) {
      return null;
    }

    if (sampleSize > 0) {
      if (track.sampleToChunkTable.isNotEmpty) {
        final samples = <_ChapterSampleEntry>[];
        var sampleIndex = 0;
        final totalSamples = track.sampleCount ?? 0x7FFFFFFF;
        for (
          var chunkIndex = 0;
          chunkIndex < track.chunkOffsetTable.length &&
              sampleIndex < totalSamples;
          chunkIndex++
        ) {
          var absoluteOffset = track.chunkOffsetTable[chunkIndex];
          final samplesPerChunk = _getSamplesPerChunk(chunkIndex + 1, track);
          if (absoluteOffset < 0 || samplesPerChunk <= 0) {
            return null;
          }

          for (
            var i = 0;
            i < samplesPerChunk && sampleIndex < totalSamples;
            i++
          ) {
            samples.add(
              _ChapterSampleEntry(
                sampleIndex: sampleIndex,
                absoluteOffset: absoluteOffset,
                sampleSize: sampleSize,
              ),
            );
            absoluteOffset += sampleSize;
            sampleIndex++;
          }
        }
        return samples;
      }

      return <_ChapterSampleEntry>[
        for (var i = 0; i < track.chunkOffsetTable.length; i++)
          _ChapterSampleEntry(
            sampleIndex: i,
            absoluteOffset: track.chunkOffsetTable[i],
            sampleSize: sampleSize,
          ),
      ];
    }

    if (track.sampleToChunkTable.isEmpty || track.sampleSizeTable.isEmpty) {
      return null;
    }

    final samples = <_ChapterSampleEntry>[];
    var sampleIndex = 0;
    for (
      var chunkIndex = 0;
      chunkIndex < track.chunkOffsetTable.length;
      chunkIndex++
    ) {
      var absoluteOffset = track.chunkOffsetTable[chunkIndex];
      final samplesPerChunk = _getSamplesPerChunk(chunkIndex + 1, track);
      if (absoluteOffset < 0 || samplesPerChunk <= 0) {
        return null;
      }

      for (var i = 0; i < samplesPerChunk; i++) {
        if (sampleIndex >= track.sampleSizeTable.length) {
          return null;
        }

        final currentSampleSize = track.sampleSizeTable[sampleIndex];
        if (currentSampleSize < 0) {
          return null;
        }

        samples.add(
          _ChapterSampleEntry(
            sampleIndex: sampleIndex,
            absoluteOffset: absoluteOffset,
            sampleSize: currentSampleSize,
          ),
        );
        absoluteOffset += currentSampleSize;
        sampleIndex++;
      }
    }

    if (sampleIndex != track.sampleSizeTable.length) {
      return null;
    }

    return samples;
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

  int? _getSampleIndexForTime(_TrackDescription track, int timeOffset) {
    if (track.timeToSampleTable.isEmpty) {
      return null;
    }

    var remainingTime = timeOffset;
    var sampleIndex = 0;

    for (final entry in track.timeToSampleTable) {
      if (remainingTime <= 0) {
        return sampleIndex;
      }

      final sampleDuration = entry.duration;
      if (sampleDuration <= 0) {
        return null;
      }

      final maxSamplesToConsume = entry.count;
      final samplesNeeded = remainingTime ~/ sampleDuration;

      if (samplesNeeded < maxSamplesToConsume) {
        return sampleIndex + samplesNeeded;
      }

      sampleIndex += maxSamplesToConsume;
      remainingTime -= maxSamplesToConsume * sampleDuration;
    }

    return sampleIndex;
  }

  int? _getByteOffsetForSample(_TrackDescription track, int targetSampleIndex) {
    if (track.chunkOffsetTable.isEmpty || track.sampleToChunkTable.isEmpty) {
      return null;
    }

    var currentSampleIndex = 0;
    var currentChunkId = 1;
    var chunkIndexInTable = 0;
    var samplesPerChunk = track.sampleToChunkTable[0].samplesPerChunk;

    while (true) {
      final nextRunFirstChunk =
          (chunkIndexInTable + 1 < track.sampleToChunkTable.length)
          ? track.sampleToChunkTable[chunkIndexInTable + 1].firstChunk
          : track.chunkOffsetTable.length + 1;

      final chunksInRun = nextRunFirstChunk - currentChunkId;
      final totalSamplesInRun = chunksInRun * samplesPerChunk;

      if (targetSampleIndex < currentSampleIndex + totalSamplesInRun) {
        final relativeSampleIndex = targetSampleIndex - currentSampleIndex;
        final chunkOffsetInRun = relativeSampleIndex ~/ samplesPerChunk;
        final sampleOffsetInChunk = relativeSampleIndex % samplesPerChunk;

        final targetChunkId = currentChunkId + chunkOffsetInRun;
        if (targetChunkId - 1 >= track.chunkOffsetTable.length) return null;

        final chunkByteOffset = track.chunkOffsetTable[targetChunkId - 1];
        var sampleByteOffset = 0;
        final firstSampleInChunkIndex =
            currentSampleIndex + chunkOffsetInRun * samplesPerChunk;

        if (sampleOffsetInChunk > 0) {
          if (track.sampleSize != null && track.sampleSize! > 0) {
            sampleByteOffset = sampleOffsetInChunk * track.sampleSize!;
          } else if (track.sampleSizeTable.isNotEmpty) {
            for (var i = 0; i < sampleOffsetInChunk; i++) {
              final idx = firstSampleInChunkIndex + i;
              if (idx < track.sampleSizeTable.length) {
                sampleByteOffset += track.sampleSizeTable[idx];
              }
            }
          } else if (track.stszEntriesOffset != null &&
              track.stszEntryCount != null &&
              tokenizer.canSeek) {
            final available = track.stszEntryCount! - firstSampleInChunkIndex;
            final count = sampleOffsetInChunk < available
                ? sampleOffsetInChunk
                : available;
            if (count > 0) {
              sampleByteOffset = _sumStszEntries(
                track.stszEntriesOffset!,
                firstSampleInChunkIndex,
                count,
              );
            }
          }
        }
        return chunkByteOffset + sampleByteOffset;
      }

      currentSampleIndex += totalSamplesInRun;
      currentChunkId = nextRunFirstChunk;
      chunkIndexInTable++;
      if (chunkIndexInTable >= track.sampleToChunkTable.length) break;
      samplesPerChunk =
          track.sampleToChunkTable[chunkIndexInTable].samplesPerChunk;
    }
    return null;
  }

  int _sumStszEntries(int entriesOffset, int startIndex, int count) {
    final savedPos = tokenizer.position;
    try {
      const batchEntries = 4096;
      var sum = 0;
      var remaining = count;
      var cursor = startIndex;
      while (remaining > 0) {
        final take = remaining < batchEntries ? remaining : batchEntries;
        tokenizer.seek(entriesOffset + cursor * 4);
        final bytes = tokenizer.readBytes(take * 4);
        if (bytes is Uint8List) {
          final data = ByteData.sublistView(bytes);
          for (var i = 0; i < take; i++) {
            sum += data.getUint32(i * 4);
          }
        } else {
          for (var i = 0; i < take; i++) {
            sum += AtomToken.readUint32Be(bytes, i * 4);
          }
        }
        cursor += take;
        remaining -= take;
      }
      return sum;
    } finally {
      tokenizer.seek(savedPos);
    }
  }

  int? _getByteOffsetForTime(_TrackDescription track, int timeOffset) {
    final sampleIndex = _getSampleIndexForTime(track, timeOffset);
    if (sampleIndex == null) return null;
    return _getByteOffsetForSample(track, sampleIndex);
  }

  void _captureMoovMetadataBoxes(Mp4Atom moovAtom) {
    final maxAlloc = getMaxMemoryAllocation(options);
    final savedPos = tokenizer.position;
    try {
      for (final child in moovAtom.children) {
        final len = child.header.length;
        if (len <= 0 || len > maxAlloc) continue;
        if (child.header.name == 'udta' && rawUdtaBox == null) {
          tokenizer.seek(child.offset);
          final bytes = tokenizer.readBytes(len);
          rawUdtaBox = M4aMuxer.sanitizeUdtaForSlice(bytes);
        } else if (child.header.name == 'meta' && rawMetaBox == null) {
          tokenizer.seek(child.offset);
          rawMetaBox = M4aMuxer.sanitizeMetaForSlice(tokenizer.readBytes(len));
        }
      }
    } on Object catch (_) {
      // Best-effort capture; never fail parsing if seeking back fails.
    } finally {
      try {
        tokenizer.seek(savedPos);
      } on Object catch (_) {}
    }
  }

  /// Builds a [CachedMp4ChapterInfo] snapshot from parsed `moov` tables so
  /// a later parse with `includeChapters: true` can resolve chapters without
  /// re-fetching `moov` or other metadata.
  CachedMp4ChapterInfo getCachedChapterInfo() {
    final tracksWithChapters = _tracks.values
        .where((track) => track.chapterTrackIds.isNotEmpty)
        .toList();

    _TrackDescription? chapterTrack;
    _TrackDescription? ownerTrack;
    if (tracksWithChapters.isNotEmpty) {
      final chapterTrackIds = tracksWithChapters
          .expand((track) => track.chapterTrackIds)
          .toSet();
      for (final id in chapterTrackIds) {
        chapterTrack = _tracks[id];
        if (chapterTrack != null) break;
      }
      if (chapterTrack != null) {
        ownerTrack = tracksWithChapters.firstWhere(
          (track) => track.isAudio,
          orElse: () => tracksWithChapters.firstWhere(
            (track) => track.isVideo,
            orElse: () => tracksWithChapters.first,
          ),
        );
      }
    }

    final audioFallback = _tracks.values.where((t) => t.isAudio).firstOrNull;
    final refTrack = ownerTrack ?? audioFallback;

    final hasSource =
        _chplPayload != null ||
        (chapterTrack != null && ownerTrack != null);

    return CachedMp4ChapterInfo(
      hasChapterSource: hasSource,
      chplPayload: _chplPayload,
      chapterTrack: chapterTrack == null ? null : _toCachedTrack(chapterTrack),
      referencedTrack: refTrack == null ? null : _toCachedTrack(refTrack),
    );
  }

  static CachedMp4TrackData _toCachedTrack(_TrackDescription t) =>
      CachedMp4TrackData(
        trackId: t.trackId,
        timeScale: t.timeScale,
        durationUnits: t.durationUnits,
        sampleSize: t.sampleSize,
        sampleSizeTable: List<int>.from(t.sampleSizeTable),
        timeToSampleTable: List<SttsEntry>.from(t.timeToSampleTable),
        sampleToChunkTable: List<StscEntry>.from(t.sampleToChunkTable),
        chunkOffsetTable: List<int>.from(t.chunkOffsetTable),
      );

  static _TrackDescription _fromCachedTrack(
    CachedMp4TrackData d, {
    String? handlerType,
  }) => _TrackDescription(d.trackId)
    ..handlerType = handlerType
    ..timeScale = d.timeScale
    ..durationUnits = d.durationUnits
    ..sampleSize = d.sampleSize
    ..sampleSizeTable = d.sampleSizeTable
    ..timeToSampleTable = d.timeToSampleTable
    ..sampleToChunkTable = d.sampleToChunkTable
    ..chunkOffsetTable = d.chunkOffsetTable;

  /// Resolves MP4 chapters from a cached [CachedMp4ChapterInfo] without
  /// re-parsing `moov` or metadata tags.
  ///
  /// For Nero `chpl` chapters (or files without chapters) this requires zero
  /// I/O. For QuickTime `chap` tracks it reads only the chapter text sample
  /// byte ranges from [tokenizer].
  static Future<({List<Chapter>? chapters, List<ParserWarning> warnings})>
  resolveChaptersFromCache({
    required CachedMp4ChapterInfo chapterInfo,
    required Tokenizer tokenizer,
    required ParseOptions options,
    double? fileDuration,
  }) async {
    if (!chapterInfo.hasChapterSource) {
      return (chapters: null, warnings: const <ParserWarning>[]);
    }

    final collector = MetadataCollector(
      CombinedTagMapper(),
      options.copyWith(includeChapters: true),
    );
    if (fileDuration != null) {
      collector.setFormat(duration: fileDuration);
    }

    final parser = Mp4Parser(
      metadata: collector,
      tokenizer: tokenizer,
      options: options.copyWith(includeChapters: true),
    );

    if (chapterInfo.referencedTrack != null) {
      final ref = _fromCachedTrack(
        chapterInfo.referencedTrack!,
        handlerType: 'soun',
      );
      parser._tracks[ref.trackId] = ref;
    }

    if (chapterInfo.chapterTrack != null &&
        chapterInfo.referencedTrack != null) {
      final ct = _fromCachedTrack(chapterInfo.chapterTrack!);
      final rt = parser._tracks[chapterInfo.referencedTrack!.trackId]!;
      parser._tracks[ct.trackId] = ct;
      try {
        final chapters = await parser._parseChapterTrackByAbsoluteOffsets(
          ct,
          rt,
        );
        if (chapters != null && chapters.isNotEmpty) {
          collector.setFormat(chapters: chapters);
        }
      } catch (e) {
        if (chapterInfo.chplPayload == null) {
          rethrow;
        }
        collector.addWarning('Cannot read QuickTime chapter track: $e');
      }
    }

    final existingChapters = collector.toAudioMetadata().format.chapters;
    final quickTimeHasTitles =
        existingChapters != null &&
        existingChapters.any((c) => c.title.trim().isNotEmpty);

    if (!quickTimeHasTitles && chapterInfo.chplPayload != null) {
      parser._parseChpl(chapterInfo.chplPayload!);
      if (parser._chplChapters.isNotEmpty) {
        parser._processChplChapters();
      }
    }

    final resolved = collector.toAudioMetadata();
    return (
      chapters: resolved.format.chapters,
      warnings: resolved.quality.warnings,
    );
  }
}

class _TrackDescription {
  _TrackDescription(this.trackId);

  final int trackId;
  String? handlerType;
  int? timeScale;
  int? durationUnits;
  int? sampleSize;
  int? sampleCount;
  final List<SampleDescription> sampleDescriptions = <SampleDescription>[];
  List<SttsEntry> timeToSampleTable = const <SttsEntry>[];
  List<StscEntry> sampleToChunkTable = const <StscEntry>[];
  List<int> sampleSizeTable = const <int>[];
  List<int> chunkOffsetTable = const <int>[];
  int? stszEntriesOffset;
  int? stszEntryCount;
  final List<int> chapterTrackIds = <int>[];
  List<int>? rawStsdBox;

  bool get isAudio => handlerType == 'soun' || handlerType == 'audi';
  bool get isVideo => handlerType == 'vide';
}

class _ChapterSampleEntry {
  const _ChapterSampleEntry({
    required this.sampleIndex,
    required this.absoluteOffset,
    required this.sampleSize,
  });

  final int sampleIndex;
  final int absoluteOffset;
  final int sampleSize;
}

/// Internal representation of a chapter from a chpl (Nero Chapter List) atom.
class _ChplChapter {
  _ChplChapter({required this.timestamp, required this.title, this.flags = 0});

  /// Timestamp in timescale units.
  final BigInt timestamp;

  /// Chapter title.
  final String title;

  /// chpl flags from the atom header (currently unused downstream).
  final int flags;
}

class Mp4TrackInfo {
  Mp4TrackInfo({
    required this.trackId,
    required this.handlerType,
    required this.timeScale,
    required this.sampleSize,
    required this.sampleSizeTable,
    required this.timeToSampleTable,
    required this.isAudio,
    required this.sampleRate,
    required this.numberOfChannels,
    this.rawStsdBox,
  });

  final int trackId;
  final String? handlerType;
  final int? timeScale;
  final int? sampleSize;
  final List<int> sampleSizeTable;
  final List<SttsEntry> timeToSampleTable;
  final bool isAudio;
  final int? sampleRate;
  final int? numberOfChannels;
  final List<int>? rawStsdBox;
}
