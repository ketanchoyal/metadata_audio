library;

import 'dart:convert';

import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/ogg/ogg_token.dart';
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
        stream.pageNumber = header.pageSequenceNo;
        stream.maxGranulePosition =
            header.absoluteGranulePosition > stream.maxGranulePosition
            ? header.absoluteGranulePosition
            : stream.maxGranulePosition;

        if (header.headerType.firstPage) {
          _identifyStream(stream, pageData);
        }

        if (header.headerType.lastPage) {
          stream.closed = true;
        }

        if (!options.duration && stream.pageNumber > 12) {
          break;
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
    metadata.setFormat(codec: codec);

    if (codec == 'Theora') {
      stream.hasVideo = true;
      metadata.setFormat(hasVideo: true);
      return;
    }

    stream.hasAudio = true;
    metadata.setFormat(
      hasAudio: true,
      hasVideo: metadata.format.hasVideo ?? false,
    );

    if (codec == 'FLAC') {
      metadata.setFormat(lossless: true);
    }

    final streamInfo = _readSampleRateAndChannels(codec, pageData);
    if (streamInfo != null) {
      stream.sampleRate = streamInfo.sampleRate;
      stream.numberOfChannels = streamInfo.numberOfChannels;
      metadata.setFormat(
        sampleRate: streamInfo.sampleRate,
        numberOfChannels: streamInfo.numberOfChannels,
      );
    }
  }

  String? _identifyCodec(List<int> pageData) {
    if (pageData.length >= 7 &&
        pageData[0] == 0x01 &&
        _ascii(pageData, 1, 6) == 'vorbis') {
      return 'Vorbis I';
    }

    if (pageData.length >= 8 && _ascii(pageData, 0, 8) == 'OpusHead') {
      return 'Opus';
    }

    if (pageData.length >= 8 && _ascii(pageData, 0, 8) == 'Speex   ') {
      return 'Speex';
    }

    if (pageData.length >= 5 &&
        pageData[0] == 0x7F &&
        _ascii(pageData, 1, 4) == 'FLAC') {
      return 'FLAC';
    }

    if (pageData.length >= 7 &&
        pageData[0] == 0x80 &&
        _ascii(pageData, 1, 6) == 'theora') {
      return 'Theora';
    }

    if (pageData.length >= 7 && _ascii(pageData, 0, 7) == 'fishead') {
      return 'Theora';
    }

    return null;
  }

  _StreamInfo? _readSampleRateAndChannels(String codec, List<int> pageData) {
    if (codec == 'Vorbis I' && pageData.length >= 16) {
      return _StreamInfo(
        sampleRate: OggToken.uint32Le(pageData, 12),
        numberOfChannels: pageData[11],
      );
    }

    if (codec == 'Opus' && pageData.length >= 16) {
      return _StreamInfo(
        sampleRate: OggToken.uint32Le(pageData, 12),
        numberOfChannels: pageData[9],
      );
    }

    if (codec == 'Speex' && pageData.length >= 52) {
      return _StreamInfo(
        sampleRate: OggToken.uint32Le(pageData, 36),
        numberOfChannels: OggToken.uint32Le(pageData, 48),
      );
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

      if (options.duration &&
          stream.sampleRate != null &&
          stream.sampleRate! > 0 &&
          stream.maxGranulePosition > 0) {
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
    if (fileSize != null && duration != null && duration > 0) {
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
  bool hasAudio = false;
  bool hasVideo = false;
}

class _StreamInfo {
  const _StreamInfo({required this.sampleRate, required this.numberOfChannels});

  final int sampleRate;
  final int numberOfChannels;
}
