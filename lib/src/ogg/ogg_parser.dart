library;

import 'dart:convert';

import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/flac/flac_token.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/ogg/flac_stream.dart';
import 'package:audio_metadata/src/ogg/ogg_token.dart';
import 'package:audio_metadata/src/ogg/opus/opus_decoder.dart';
import 'package:audio_metadata/src/ogg/speex/speex_decoder.dart';
import 'package:audio_metadata/src/ogg/theora/theora_decoder.dart';
import 'package:audio_metadata/src/ogg/vorbis/vorbis_decoder.dart';
import 'package:audio_metadata/src/parse_error.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

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

  Future<void> parse() async {
    var reachedEndOfStream = false;

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

        final stream = _streams.putIfAbsent(
          header.streamSerialNumber,
          () => _OggStreamState(streamSerial: header.streamSerialNumber),
        );
        if (stream.pendingOpusTagLength != null &&
            !header.headerType.continued) {
          stream.lastTagPageOffset =
              tokenizer.position - stream.pendingOpusTagLength!;
          stream.pendingOpusTagLength = null;
        }
        stream.pageNumber = header.pageSequenceNo;
        stream.maxGranulePosition =
            header.absoluteGranulePosition > stream.maxGranulePosition
            ? header.absoluteGranulePosition
            : stream.maxGranulePosition;

        if (header.headerType.firstPage) {
          _identifyStream(stream, pageData);
        } else {
          _parseStreamPage(stream, pageData);
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
    }

    _finalizeStreams(reachedEndOfStream);
  }

  void _identifyStream(_OggStreamState stream, List<int> pageData) {
    final codec = _identifyCodec(pageData);
    if (codec == null) {
      metadata.addWarning(
        'Ogg codec not recognized for stream ${stream.streamSerial}',
      );
      return;
    }

    stream.codec = codec;

    try {
      switch (codec) {
        case 'Vorbis I':
          final header = VorbisDecoder.parseIdentificationHeader(pageData);
          stream.sampleRate = header.sampleRate;
          stream.numberOfChannels = header.channelMode;
          metadata.setFormat(
            codec: codec,
            sampleRate: header.sampleRate,
            numberOfChannels: header.channelMode,
            bitrate: header.bitrateNominal > 0 ? header.bitrateNominal : null,
            hasAudio: true,
            hasVideo: metadata.format.hasVideo ?? false,
          );
          break;
        case 'Opus':
          final header = OpusDecoder.parseIdHeader(pageData);
          stream.opusPreSkip = header.preSkip;
          stream.sampleRate = header.inputSampleRate > 0
              ? header.inputSampleRate
              : 48000;
          stream.numberOfChannels = header.channelCount;
          metadata.setFormat(
            codec: codec,
            sampleRate: stream.sampleRate,
            numberOfChannels: header.channelCount,
            hasAudio: true,
            hasVideo: metadata.format.hasVideo ?? false,
          );
          break;
        case 'Speex':
          final header = SpeexDecoder.parseHeader(pageData);
          stream.sampleRate = header.sampleRate > 0 ? header.sampleRate : null;
          stream.numberOfChannels = header.numberOfChannels > 0
              ? header.numberOfChannels
              : null;
          metadata.setFormat(
            codec: header.version.isEmpty ? codec : 'Speex ${header.version}',
            sampleRate: stream.sampleRate,
            numberOfChannels: stream.numberOfChannels,
            bitrate: header.bitrate >= 0 ? header.bitrate : null,
            hasAudio: true,
            hasVideo: metadata.format.hasVideo ?? false,
          );
          break;
        case 'FLAC':
          final block = OggFlacStream.parseFirstPage(pageData);
          metadata.setFormat(
            codec: codec,
            lossless: true,
            hasAudio: true,
            hasVideo: metadata.format.hasVideo ?? false,
          );
          _applyFlacMetadataBlock(stream, block);
          break;
        case 'Theora':
          metadata.setFormat(codec: codec, hasVideo: true);
          if (TheoraDecoder.isIdentificationHeader(pageData)) {
            final header = TheoraDecoder.parseIdentificationHeader(pageData);
            metadata.setFormat(bitrate: header.bitrate);
          }
          break;
      }
    } on FormatException catch (error) {
      metadata.addWarning(
        'Failed to parse $codec header for stream ${stream.streamSerial}: $error',
      );
    }
  }

  void _parseStreamPage(_OggStreamState stream, List<int> pageData) {
    final codec = stream.codec;
    if (codec == null) {
      return;
    }

    try {
      switch (codec) {
        case 'Vorbis I':
          if (VorbisDecoder.isCommentHeader(pageData)) {
            final comments = VorbisDecoder.parseCommentHeader(pageData);
            _applyVorbisCommentHeader(comments);
          }
          break;
        case 'Opus':
          if (OpusDecoder.isTagsHeader(pageData)) {
            stream.pendingOpusTagLength = pageData.length;
            final comments = OpusDecoder.parseTags(pageData);
            _applyVorbisCommentHeader(comments);
          }
          break;
        case 'FLAC':
          if (!stream.flacMetadataComplete && pageData.length >= 4) {
            final block = OggFlacStream.parseMetadataBlock(pageData);
            _applyFlacMetadataBlock(stream, block);
          }
          break;
      }
    } on FormatException catch (error) {
      metadata.addWarning(
        'Failed to parse Ogg $codec page for stream ${stream.streamSerial}: $error',
      );
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

    if (block.lastBlock) {
      stream.flacMetadataComplete = true;
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

    metadata.addNativeTag('vorbis', key, value);
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

    if (!options.duration && reachedEndOfStream && _streams.isEmpty) {
      throw OggContentError('Unexpected end-of-stream while reading Ogg pages');
    }

    final fileSize = tokenizer.fileInfo?.size;
    final duration = metadata.format.duration;
    if (fileSize != null &&
        duration != null &&
        duration > 0 &&
        metadata.format.bitrate == null) {
      metadata.setFormat(bitrate: (8 * fileSize / duration).round());
    }
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
  int? opusPreSkip;
  int? lastTagPageOffset;
  int? pendingOpusTagLength;
  bool flacMetadataComplete = false;
}
