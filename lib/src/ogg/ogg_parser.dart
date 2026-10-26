library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/common/allocation.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/flac/flac_token.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/ogg/flac_stream.dart';
import 'package:metadata_audio/src/ogg/ogg_token.dart';
import 'package:metadata_audio/src/ogg/opus/opus_decoder.dart';
import 'package:metadata_audio/src/ogg/speex/speex_decoder.dart';
import 'package:metadata_audio/src/ogg/theora/theora_decoder.dart';
import 'package:metadata_audio/src/ogg/vorbis/vorbis_decoder.dart';
import 'package:metadata_audio/src/parse_error.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class OggContentError extends UnexpectedFileContentError {
  OggContentError(String message) : super('Ogg', message);
}

class OggParser {
  OggParser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  final Map<int, _OggStreamState> _streams = <int, _OggStreamState>{};
  final Map<int, String> _vorbisChapterFields = <int, String>{};

  Future<void> parse() async {
    var reachedEndOfStream = false;
    final maxLogicalStreams = getMaxMetadataEntries(options);

    try {
      while (true) {
        final header = OggToken.parsePageHeader(
          tokenizer.readBytes(OggToken.pageHeaderLength),
        );
        if (header.capturePattern != 'OggS') {
          throw OggContentError('Invalid Ogg capture pattern');
        }

        final segmentTable = OggToken.parseSegmentTable(
          tokenizer.readBytes(header.pageSegments),
          header.pageSegments,
        );
        final pageData = tokenizer.readBytes(segmentTable.totalPageSize);

        final existing = _streams[header.streamSerialNumber];
        if (existing == null && _streams.length >= maxLogicalStreams) {
          throw OggContentError('Logical stream count exceeds entry limit');
        }
        final stream = existing ??
            _OggStreamState(streamSerial: header.streamSerialNumber);
        _streams[header.streamSerialNumber] = stream;
        stream.payloadBytes += pageData.length;
        if (stream.pendingOpusTagLength != null &&
            !header.headerType.continued) {
          stream.lastTagPageOffset =
              tokenizer.position - stream.pendingOpusTagLength!;
          stream.pendingOpusTagLength = null;
        }
        if (stream.codec == 'Opus' && OpusDecoder.isTagsHeader(pageData)) {
          stream.pendingOpusTagLength = pageData.length;
        }
        stream.pageNumber = header.pageSequenceNo;
        if (header.absoluteGranulePosition >= 0 &&
            header.absoluteGranulePosition > stream.maxGranulePosition) {
          stream.maxGranulePosition = header.absoluteGranulePosition;
        }

        if (header.headerType.firstPage) {
          _identifyStream(stream, header, pageData, segmentTable.lacingValues);
        } else {
          _parseStreamPage(stream, header, pageData, segmentTable.lacingValues);
        }

        if (header.headerType.lastPage) {
          stream.closed = true;
        }

        if (_streams.isNotEmpty &&
            _streams.values.every((item) => item.closed)) {
          break;
        }
      }
    } on TokenizerException {
      reachedEndOfStream = true;
    } on OggContentError {
      metadata.addWarning('Corrupt Ogg content at ${tokenizer.position}');
    }

    _finalizeStreams(reachedEndOfStream);
  }

  void _identifyStream(
    _OggStreamState stream,
    OggPageHeader header,
    List<int> pageData,
    List<int> lacing,
  ) {
    final codec = _identifyCodec(pageData);
    if (codec == null) {
      metadata.addWarning(
        'Ogg codec not recognized for stream ${stream.streamSerial}',
      );
      return;
    }

    stream.codec = codec;

    switch (codec) {
      case 'Vorbis I':
        _parseVorbisFirstPage(stream, pageData);
        break;
      case 'Opus':
        _parseOpusFirstPage(stream, pageData);
        break;
      case 'Speex':
        _parseSpeexFirstPage(stream, pageData);
        break;
      case 'FLAC':
        metadata.setFormat(
          codec: codec,
          lossless: true,
          hasAudio: true,
          hasVideo: metadata.format.hasVideo ?? false,
        );
        _consumeFlacPage(stream, header, pageData, lacing);
        break;
      case 'Theora':
        metadata.setFormat(codec: codec, hasVideo: true);
        if (TheoraDecoder.isIdentificationHeader(pageData)) {
          final header = TheoraDecoder.parseIdentificationHeader(pageData);
          stream.theoraIdentification = header;
          metadata.setFormat(bitrate: header.bitrate);
        }
        break;
    }
  }

  void _parseVorbisFirstPage(_OggStreamState stream, List<int> pageData) {
    if (pageData.length < VorbisDecoder.commonHeaderLength) {
      throw OggContentError('Truncated Vorbis packet header');
    }
    final packetType = pageData[0];
    final magic = _ascii(pageData, 1, 6);
    if (magic != 'vorbis') {
      throw OggContentError('Metadata does not look like Vorbis');
    }
    if (packetType != 1) {
      throw OggContentError(
        'First Ogg page should be type 1: the identification header',
      );
    }
    if (pageData.length < VorbisDecoder.commonHeaderLength + 23) {
      throw OggContentError('Truncated Vorbis identification header');
    }
    final header = VorbisDecoder.parseIdentificationHeader(pageData);
    stream.sampleRate = header.sampleRate;
    stream.numberOfChannels = header.channelMode;
    stream.nominalBitrate = header.bitrateNominal > 0
        ? header.bitrateNominal
        : null;
    metadata.setFormat(
      codec: 'Vorbis I',
      sampleRate: header.sampleRate,
      numberOfChannels: header.channelMode,
      bitrate: header.bitrateNominal > 0 ? header.bitrateNominal : null,
      hasAudio: true,
      hasVideo: metadata.format.hasVideo ?? false,
    );
  }

  void _parseOpusFirstPage(_OggStreamState stream, List<int> pageData) {
    final header = OpusDecoder.parseIdHeader(pageData);
    stream.opusPreSkip = header.preSkip;
    stream.sampleRate = header.inputSampleRate > 0
        ? header.inputSampleRate
        : 48000;
    stream.numberOfChannels = header.channelCount;
    metadata.setFormat(
      codec: 'Opus',
      sampleRate: stream.sampleRate,
      numberOfChannels: header.channelCount,
      hasAudio: true,
      hasVideo: metadata.format.hasVideo ?? false,
    );
  }

  void _parseSpeexFirstPage(_OggStreamState stream, List<int> pageData) {
    final header = SpeexDecoder.parseHeader(pageData);
    stream.sampleRate = header.sampleRate > 0 ? header.sampleRate : null;
    stream.numberOfChannels = header.numberOfChannels > 0
        ? header.numberOfChannels
        : null;
    stream.nominalBitrate = header.bitrate >= 0 ? header.bitrate : null;
    metadata.setFormat(
      codec: header.version.isEmpty ? 'Speex' : 'Speex ${header.version}',
      sampleRate: stream.sampleRate,
      numberOfChannels: stream.numberOfChannels,
      bitrate: header.bitrate >= 0 ? header.bitrate : null,
      hasAudio: true,
      hasVideo: metadata.format.hasVideo ?? false,
    );
  }

  void _parseStreamPage(
    _OggStreamState stream,
    OggPageHeader header,
    List<int> pageData,
    List<int> lacing,
  ) {
    switch (stream.codec) {
      case 'Vorbis I':
      case 'Opus':
      case 'Speex':
        _consumeVorbisFamilyPage(stream, header, pageData);
        break;
      case 'FLAC':
        _consumeFlacPage(stream, header, pageData, lacing);
        break;
      default:
        break;
    }
  }

  void _consumeVorbisFamilyPage(
    _OggStreamState stream,
    OggPageHeader header,
    List<int> pageData,
  ) {
    if (header.headerType.continued) {
      if (stream.pageSegments.isEmpty) {
        throw OggContentError('Cannot continue on previous page');
      }
      if (stream.pageSegments.length >= getMaxMetadataEntries(options)) {
        throw OggContentError('Buffered Ogg page count exceeds entry limit');
      }
      stream.pageSegments.add(pageData);
      stream.bufferedPageLength += pageData.length;
    }
    if (header.headerType.lastPage || !header.headerType.continued) {
      if (stream.pageSegments.isNotEmpty) {
        final merged = <int>[];
        for (final segment in stream.pageSegments) {
          merged.addAll(segment);
        }
        _parseVorbisFamilyFullPage(stream, merged);
      }
      stream.bufferedPageLength =
          header.headerType.lastPage ? 0 : pageData.length;
      stream.pageSegments =
          header.headerType.lastPage ? <List<int>>[] : <List<int>>[pageData];
    }
  }

  void _parseVorbisFamilyFullPage(_OggStreamState stream, List<int> pageData) {
    if (pageData.isNotEmpty && (pageData[0] & 1) == 0) {
      return;
    }
    if (pageData.length < VorbisDecoder.commonHeaderLength) {
      throw OggContentError('Truncated Vorbis packet header');
    }
    final codec = stream.codec;
    if (codec == 'Vorbis I') {
      final packetType = pageData[0];
      if (_ascii(pageData, 1, 6) != 'vorbis') {
        throw OggContentError('Metadata does not look like Vorbis');
      }
      switch (packetType) {
        case 3:
          final comments = VorbisDecoder.parseCommentHeader(
            pageData,
            maxComments: getMaxMetadataEntries(options),
          );
          _applyVorbisCommentHeader(comments);
          break;
        case 1:
        case 5:
          break;
      }
    } else if (codec == 'Opus') {
      if (pageData.length >= 8 &&
          _ascii(pageData, 0, 8) == 'OpusTags') {
        final comments = OpusDecoder.parseTags(
          pageData,
          maxComments: getMaxMetadataEntries(options),
        );
        _applyVorbisCommentHeader(comments);
      }
    } else if (codec == 'Speex') {
      if (!stream.speexCommentHeaderParsed) {
        stream.speexCommentHeaderParsed = true;
        final comments = VorbisDecoder.parseCommentData(
          pageData,
          0,
          maxComments: getMaxMetadataEntries(options),
        );
        _applyVorbisCommentHeader(comments);
      }
    }
  }

  void _consumeFlacPage(
    _OggStreamState stream,
    OggPageHeader header,
    List<int> pageData,
    List<int> lacing,
  ) {
    if (stream.flacMetadataComplete) {
      return;
    }
    if (header.headerType.continued != (stream.packetLength > 0)) {
      throw OggContentError('Invalid Ogg/FLAC packet continuation');
    }
    final lacingSum = lacing.fold<int>(0, (sum, value) => sum + value);
    if (lacingSum != pageData.length) {
      throw OggContentError('Ogg/FLAC lacing does not match page data');
    }
    var offset = 0;
    for (final length in lacing) {
      if (stream.packetLength + length >
          getMaxMemoryAllocation(options)) {
        throw OggContentError(
          'Metadata size ${stream.packetLength + length} exceeds allocation limit ${getMaxMemoryAllocation(options)} (buffering limit)',
        );
      }
      if (length > 0) {
        if (stream.packetParts.length >= getMaxMetadataEntries(options)) {
          throw OggContentError(
            'Buffered Ogg/FLAC segment count exceeds entry limit',
          );
        }
        stream.packetParts.add(pageData.sublist(offset, offset + length));
        stream.packetLength += length;
      }
      offset += length;
      if (length < 255) {
        final packet = <int>[];
        for (final part in stream.packetParts) {
          packet.addAll(part);
        }
        stream.packetParts.clear();
        stream.packetLength = 0;
        _parseFlacPacket(stream, packet);
        if (stream.flacMetadataComplete) {
          break;
        }
      }
    }
    if (header.headerType.lastPage) {
      _flushFlac(stream);
    }
  }

  void _parseFlacPacket(_OggStreamState stream, List<int> packet) {
    if (!stream.identified) {
      _parseFlacFirstPacket(stream, packet);
      stream.identified = true;
      return;
    }
    if (packet.length < FlacToken.blockHeaderLength) {
      throw OggContentError('Truncated Ogg/FLAC metadata header');
    }
    final header = FlacToken.parseBlockHeader(packet);
    if (header.type == FlacBlockType.streamInfo) {
      throw OggContentError('Unexpected repeated Ogg/FLAC STREAMINFO');
    }
    if (header.length != packet.length - FlacToken.blockHeaderLength) {
      throw OggContentError('Ogg/FLAC metadata block length does not match packet');
    }
    if (header.type == FlacBlockType.picture && !options.skipCovers) {
      _validateFlacPicture(packet.sublist(FlacToken.blockHeaderLength));
    }
    try {
      final block = OggFlacStream.parseMetadataBlock(packet);
      _applyFlacMetadataBlock(stream, block);
    } on FormatException catch (error) {
      throw OggContentError('Invalid Ogg/FLAC metadata block: ${error.message}');
    }
    stream.flacMetadataComplete = header.lastBlock;
  }

  void _parseFlacFirstPacket(_OggStreamState stream, List<int> packet) {
    if (packet.length != 13 + FlacToken.blockHeaderLength + FlacToken.blockStreamInfoLength) {
      throw OggContentError('Invalid Ogg/FLAC identification packet length');
    }
    if (packet[0] != 0x7F ||
        _ascii(packet, 1, 4) != 'FLAC' ||
        packet[5] != 1 ||
        _ascii(packet, 9, 4) != 'fLaC') {
      throw OggContentError('Invalid Ogg/FLAC preamble or mapping version');
    }
    final header = FlacToken.parseBlockHeader(packet, 13);
    if (header.type != FlacBlockType.streamInfo ||
        header.length != FlacToken.blockStreamInfoLength) {
      throw OggContentError('Invalid Ogg/FLAC STREAMINFO header');
    }
    if (header.type == FlacBlockType.picture && !options.skipCovers) {
      _validateFlacPicture(packet.sublist(17));
    }
    try {
      final block = OggFlacStream.parseMetadataBlock(packet.sublist(13));
      _applyFlacMetadataBlock(stream, block);
    } on FormatException catch (error) {
      throw OggContentError('Invalid Ogg/FLAC metadata block: ${error.message}');
    }
    stream.flacMetadataComplete = header.lastBlock;
  }

  void _validateFlacPicture(List<int> data) {
    if (data.length < 32) {
      throw OggContentError('Truncated Ogg/FLAC picture');
    }
    final view = ByteData.sublistView(Uint8List.fromList(data));
    final mimeLength = view.getUint32(4, Endian.big);
    if (mimeLength > data.length - 32) {
      throw OggContentError('Ogg/FLAC picture MIME length exceeds block');
    }
    final descriptionLength = view.getUint32(8 + mimeLength, Endian.big);
    if (descriptionLength > data.length - 32 - mimeLength) {
      throw OggContentError('Ogg/FLAC picture description length exceeds block');
    }
    final headerLength = 32 + mimeLength + descriptionLength;
    if (view.getUint32(headerLength - 4, Endian.big) != data.length - headerLength) {
      throw OggContentError('Ogg/FLAC picture data length does not match block');
    }
  }

  void _flushFlac(_OggStreamState stream) {
    if (stream.packetLength > 0 ||
        (stream.identified && !stream.flacMetadataComplete)) {
      throw OggContentError('Truncated Ogg/FLAC metadata packet');
    }
  }
  void _applyFlacMetadataBlock(
    _OggStreamState stream,
    OggFlacMetadataBlock block,
  ) {
    if (block.streamInfo != null) {
      final streamInfo = block.streamInfo!;
      stream.sampleRate = streamInfo.sampleRate;
      stream.numberOfChannels = streamInfo.channels;
      stream.bitsPerSample = streamInfo.bitsPerSample;
      stream.totalSamples = streamInfo.totalSamples;
      metadata.setFormat(
        sampleRate: streamInfo.sampleRate,
        numberOfChannels: streamInfo.channels,
        bitsPerSample: streamInfo.bitsPerSample,
        numberOfSamples: streamInfo.totalSamples > 0
            ? streamInfo.totalSamples
            : null,
        audioMD5: streamInfo.audioMd5,
      );

      if (streamInfo.totalSamples > 0 && streamInfo.sampleRate > 0) {
        metadata.setFormat(
          duration: streamInfo.totalSamples / streamInfo.sampleRate,
        );
      }
    }

    if (block.comments != null) {
      for (final comment in block.comments!) {
        final separator = comment.indexOf('=');
        final key =
            (separator == -1 ? comment : comment.substring(0, separator))
                .toUpperCase();
        final value = separator == -1 ? '' : comment.substring(separator + 1);
        _addVorbisTag(key, value);
      }
    }

    if (block.picture != null && !options.skipCovers) {
      metadata.addNativeTag('vorbis', 'METADATA_BLOCK_PICTURE', block.picture!);
    }

    if (block.cueSheet != null && options.includeChapters) {
      _applyFlacCueSheet(stream, block.cueSheet!);
    }

    if (block.lastBlock) {
      stream.flacMetadataComplete = true;
    }
  }

  void _applyFlacCueSheet(_OggStreamState stream, FlacCueSheet cueSheet) {
    final sampleRate = stream.sampleRate ?? metadata.format.sampleRate;
    if (sampleRate == null || sampleRate <= 0) return;

    // Filter tracks with valid offsets (non-zero track number)
    final tracks = cueSheet.tracks.where((t) => t.number > 0).toList()
      ..sort((a, b) => a.offset.compareTo(b.offset));

    if (tracks.isEmpty) return;

    final chapters = <Chapter>[];
    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      // Prefer INDEX 01 if available, otherwise use track offset
      var trackOffset = track.offset;
      if (track.indices.isNotEmpty) {
        final idx01 = track.indices.where((idx) => idx.number == 1).firstOrNull;
        if (idx01 != null) {
          trackOffset = idx01.offset;
        }
      }

      // Calculate end from next track
      int? endOffset;
      if (i + 1 < tracks.length) {
        final nextTrack = tracks[i + 1];
        endOffset = nextTrack.offset;
        // Also check for INDEX 01 on next track
        if (nextTrack.indices.isNotEmpty) {
          final nextIdx01 = nextTrack.indices
              .where((idx) => idx.number == 1)
              .firstOrNull;
          if (nextIdx01 != null) {
            endOffset = nextIdx01.offset;
          }
        }
      }

      chapters.add(
        Chapter(
          id: 'cue-${track.number}',
          title: 'Track ${track.number}',
          start: ((trackOffset * 1000) / sampleRate).round(),
          end: endOffset == null
              ? null
              : ((endOffset * 1000) / sampleRate).round(),
          timeScale: 1000,
        ),
      );
    }

    if (chapters.isNotEmpty) {
      metadata.setFormat(chapters: chapters);
    }
  }

  void _applyVorbisCommentHeader(VorbisCommentHeader commentHeader) {
    if (commentHeader.vendor.isNotEmpty) {
      metadata.setFormat(tool: commentHeader.vendor);
    }

    for (final comment in commentHeader.comments) {
      _addVorbisTag(comment.key, comment.value);
    }
  }

  void _addVorbisTag(String key, String value) {
    if (key == 'ENCODER' && value.isNotEmpty) {
      metadata.setFormat(tool: value);
    }

    if (key == 'METADATA_BLOCK_PICTURE' && value.isNotEmpty) {
      if (options.skipCovers) {
        return;
      }

      try {
        final pictureData = base64.decode(value);
        final picture = FlacToken.parsePicture(pictureData);
        metadata.addNativeTag('vorbis', key, picture);
      } on FormatException {
        metadata.addWarning('Invalid METADATA_BLOCK_PICTURE payload');
      }
      return;
    }

    _collectVorbisChapterField(key, value);

    metadata.addNativeTag('vorbis', key, value);
  }

  void _collectVorbisChapterField(String key, String value) {
    if (!options.includeChapters) {
      return;
    }
    final match = RegExp(r'^CHAPTER(\d{3})(NAME)?$').firstMatch(key);
    if (match == null) {
      return;
    }
    final chapterNo = int.parse(match.group(1)!);
    final suffix = match.group(2);
    _vorbisChapterFields[_chapterFieldKey(
          chapterNo,
          suffix == null ? 'time' : 'name',
        )] =
        value;
  }

  String? _identifyCodec(List<int> pageData) {
    if (VorbisDecoder.isIdentificationHeader(pageData)) {
      return 'Vorbis I';
    }

    if (OpusDecoder.isIdHeader(pageData)) {
      return 'Opus';
    }

    if (SpeexDecoder.isHeader(pageData)) {
      return 'Speex';
    }

    if (OggFlacStream.isFirstPage(pageData)) {
      return 'FLAC';
    }

    if (TheoraDecoder.isIdentificationHeader(pageData)) {
      return 'Theora';
    }

    if (pageData.length >= 7 && _ascii(pageData, 0, 7) == 'fishead') {
      return 'Theora';
    }

    return null;
  }

  String _ascii(List<int> bytes, int offset, int length) {
    if (offset < 0 || offset + length > bytes.length) {
      return '';
    }
    return ascii.decode(
      bytes.sublist(offset, offset + length),
      allowInvalid: true,
    );
  }

  void _finalizeStreams(bool reachedEndOfStream) {
    for (final stream in _streams.values) {
      if (!stream.closed) {
        metadata.addWarning(
          'End-of-stream reached before last page in Ogg stream serial=${stream.streamSerial}',
        );
        // Flush any buffered packet segments (upstream parity, #2861).
        if (stream.codec == 'Vorbis I' ||
            stream.codec == 'Opus' ||
            stream.codec == 'Speex') {
          if (stream.pageSegments.isNotEmpty) {
            final merged = <int>[];
            for (final segment in stream.pageSegments) {
              merged.addAll(segment);
            }
            _parseVorbisFamilyFullPage(stream, merged);
          }
        } else if (stream.codec == 'FLAC') {
          _flushFlac(stream);
        }
      }

      if (stream.maxGranulePosition <= 0) {
        continue;
      }

      if (stream.codec == 'Opus') {
        final preSkip = stream.opusPreSkip ?? 0;
        final samples = stream.maxGranulePosition - preSkip;
        if (samples > 0) {
          metadata.setFormat(
            numberOfSamples: samples,
            duration: samples / 48000.0,
          );
          final fileSize = tokenizer.fileInfo?.size;
          final lastTagPageOffset = stream.lastTagPageOffset;
          if (fileSize != null && lastTagPageOffset != null) {
            metadata.setFormat(
              bitrate: 8 * (fileSize - lastTagPageOffset) / (samples / 48000.0),
            );
          }
        }
        continue;
      }

      if (stream.sampleRate != null && stream.sampleRate! > 0) {
        metadata.setFormat(
          numberOfSamples: stream.maxGranulePosition,
          duration: stream.maxGranulePosition / stream.sampleRate!,
        );
      }
    }

    _addStreamTracks();

    if (!options.duration && reachedEndOfStream && _streams.isEmpty) {
      throw OggContentError('Unexpected end-of-stream while reading Ogg pages');
    }

    final fileSize = tokenizer.fileInfo?.size;
    final duration = metadata.format.duration;
    if (fileSize != null &&
        duration != null &&
        duration > 0 &&
        metadata.format.bitrate == null) {
      metadata.setFormat(bitrate: 8 * fileSize / duration);
    }

    _applyVorbisChapters();
  }

  /// Adds a [TrackInfo] per logical stream (upstream parity: each
  /// discovered audio/video stream becomes its own `format.trackInfo`
  /// entry with the Ogg stream serial as `id`).
  void _addStreamTracks() {
    for (final stream in _streams.values) {
      final codec = stream.codec;
      if (codec == null) {
        continue;
      }

      if (codec == 'Theora') {
        final header = stream.theoraIdentification;
        if (header == null) {
          // Skeleton (fishead) streams do not carry an identification header.
          continue;
        }
        metadata.addStreamInfo(
          TrackInfo(
            type: 'video',
            codecName: codec,
            id: stream.streamSerial,
            bitrate: header.bitrate > 0 ? header.bitrate.toDouble() : null,
            video: VideoTrack(
              pixelWidth: header.pixelWidth,
              pixelHeight: header.pixelHeight,
              displayWidth: header.pictureWidth > 0
                  ? header.pictureWidth
                  : null,
              displayHeight: header.pictureHeight > 0
                  ? header.pictureHeight
                  : null,
              frameRate: header.frameRate,
            ),
          ),
        );
        continue;
      }

      if (stream.maxGranulePosition <= 0) {
        continue;
      }

      final (samples, duration) = _trackSamplesAndDuration(stream);
      if (duration == null || duration <= 0) {
        continue;
      }

      metadata.addStreamInfo(
        TrackInfo(
          type: 'audio',
          codecName: codec,
          id: stream.streamSerial,
          duration: duration,
          bitrate: _trackBitrate(stream, duration),
          lossless: codec == 'FLAC' ? true : null,
          audio: AudioTrack(
            samplingFrequency: stream.sampleRate,
            outputSamplingFrequency:
                codec == 'Opus' && (stream.sampleRate ?? 48000) != 48000
                ? 48000
                : null,
            channels: stream.numberOfChannels,
            bitDepth: codec == 'FLAC' ? stream.bitsPerSample : null,
            numberOfSamples: samples,
          ),
        ),
      );
    }
  }

  /// The number of samples and duration attributed to a single audio stream.
  (int?, double?) _trackSamplesAndDuration(_OggStreamState stream) {
    switch (stream.codec) {
      case 'Opus':
        final samples = stream.maxGranulePosition - (stream.opusPreSkip ?? 0);
        return (
          samples > 0 ? samples : null,
          samples > 0 ? samples / 48000.0 : null,
        );
      case 'FLAC':
        if (stream.totalSamples != null && stream.totalSamples! > 0) {
          return (
            stream.totalSamples,
            stream.sampleRate != null && stream.sampleRate! > 0
                ? stream.totalSamples! / stream.sampleRate!
                : null,
          );
        }
        return _granuleSamples(stream);
      default:
        return _granuleSamples(stream);
    }
  }

  (int?, double?) _granuleSamples(_OggStreamState stream) {
    final rate = stream.sampleRate;
    if (rate == null || rate <= 0) {
      return (null, null);
    }
    return (
      stream.maxGranulePosition,
      stream.maxGranulePosition / rate.toDouble(),
    );
  }

  double? _trackBitrate(_OggStreamState stream, double duration) {
    if (!stream.closed) {
      return null;
    }
    switch (stream.codec) {
      case 'Opus':
      case 'FLAC':
        if (stream.payloadBytes > 0) {
          return stream.payloadBytes * 8 / duration;
        }
        return null;
      default:
        final nominal = stream.nominalBitrate;
        return nominal != null && nominal > 0 ? nominal.toDouble() : null;
    }
  }

  void _applyVorbisChapters() {
    if (!options.includeChapters || _vorbisChapterFields.isEmpty) {
      return;
    }

    final chapterNumbers = <int>{};
    for (final key in _vorbisChapterFields.keys) {
      chapterNumbers.add(key ~/ 10);
    }
    final ordered = chapterNumbers.toList()..sort();
    final chapters = <Chapter>[];
    for (final chapterNo in ordered) {
      final startMs = _parseVorbisChapterTimestamp(
        _vorbisChapterFields[_chapterFieldKey(chapterNo, 'time')],
      );
      if (startMs == null) {
        continue;
      }
      chapters.add(
        Chapter(
          id: 'chapter-${chapterNo.toString().padLeft(3, '0')}',
          title:
              _vorbisChapterFields[_chapterFieldKey(chapterNo, 'name')] ??
              'Chapter ${chapterNo.toString().padLeft(3, '0')}',
          start: startMs,
          timeScale: 1000,
        ),
      );
    }

    for (var i = 0; i < chapters.length; i++) {
      final end = i + 1 < chapters.length ? chapters[i + 1].start : null;
      chapters[i] = Chapter(
        id: chapters[i].id,
        title: chapters[i].title,
        start: chapters[i].start,
        end: end,
        timeScale: chapters[i].timeScale,
      );
    }

    if (chapters.isNotEmpty) {
      metadata.setFormat(chapters: chapters);
    }
  }

  int _chapterFieldKey(int chapterNo, String field) =>
      chapterNo * 10 + (field == 'name' ? 1 : 0);

  int? _parseVorbisChapterTimestamp(String? value) {
    if (value == null) {
      return null;
    }
    final match = RegExp(
      r'^(\d+):(\d{2}):(\d{2})(?:\.(\d{1,3}))?$',
    ).firstMatch(value.trim());
    if (match == null) {
      metadata.addWarning('Invalid Vorbis chapter timestamp: $value');
      return null;
    }
    final hours = int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    final seconds = int.parse(match.group(3)!);
    final millisRaw = match.group(4);
    final millis = millisRaw == null
        ? 0
        : int.parse(millisRaw.padRight(3, '0'));
    return (((hours * 60 + minutes) * 60) + seconds) * 1000 + millis;
  }
}

class _OggStreamState {
  _OggStreamState({required this.streamSerial});

  final int streamSerial;
  int pageNumber = 0;
  bool closed = false;
  int maxGranulePosition = 0;
  String? codec;
  int? sampleRate;
  int? numberOfChannels;

  /// Sum of payload bytes carried by this stream's pages (upstream tracks
  /// per-stream payload to compute an independent track bitrate)
  int payloadBytes = 0;
  int? bitsPerSample;
  int? totalSamples;
  int? nominalBitrate;
  int? opusPreSkip;
  int? lastTagPageOffset;
  int? pendingOpusTagLength;
  bool flacMetadataComplete = false;
  TheoraIdentificationHeader? theoraIdentification;

  // Vorbis-family page buffering (#2861).
  List<List<int>> pageSegments = <List<int>>[];
  int bufferedPageLength = 0;
  bool speexCommentHeaderParsed = false;

  // FLAC-in-Ogg packet assembly (#2861).
  bool identified = false;
  List<List<int>> packetParts = <List<int>>[];
  int packetLength = 0;
}
