library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata/src/aiff/aiff_token.dart';
import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/id3v2/id3v2_parser.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

class AiffParser {
  AiffParser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  bool? _isCompressed;

  Future<void> parse() async {
    final formHeader = AiffToken.parseChunkHeader(
      tokenizer.readBytes(AiffToken.chunkHeaderLength),
    );
    if (formHeader.chunkId != 'FORM') {
      throw AiffContentError("Invalid Chunk-ID, expected 'FORM'");
    }

    final type = _decodeAscii(tokenizer.readBytes(4));
    switch (type) {
      case 'AIFF':
        metadata.setFormat(container: 'AIFF');
        _isCompressed = false;
      case 'AIFC':
        metadata.setFormat(container: 'AIFF-C');
        _isCompressed = true;
      default:
        throw AiffContentError('Unsupported AIFF type: $type');
    }

    metadata.setFormat(
      lossless: !(_isCompressed ?? false),
      hasAudio: true,
      hasVideo: false,
    );

    await _readChunks(formHeader.chunkSize - 4);
  }

  Future<void> _readChunks(int remaining) async {
    var bytesRemaining = remaining;

    while (bytesRemaining >= AiffToken.chunkHeaderLength) {
      final chunkHeader = AiffToken.parseChunkHeader(
        tokenizer.readBytes(AiffToken.chunkHeaderLength),
      );
      bytesRemaining -= AiffToken.chunkHeaderLength;

      final declaredSize = chunkHeader.chunkSize;
      var readableSize = declaredSize;
      if (readableSize > bytesRemaining) {
        metadata.addWarning('Data chunk size exceeds file size');
        readableSize = bytesRemaining;
      }

      final bytesRead = await _readData(chunkHeader.chunkId, readableSize);
      if (readableSize > bytesRead) {
        tokenizer.skip(readableSize - bytesRead);
      }

      bytesRemaining -= readableSize;

      if (declaredSize.isOdd && bytesRemaining > 0) {
        tokenizer.skip(1);
        bytesRemaining -= 1;
      }
    }
  }

  Future<int> _readData(String chunkId, int chunkSize) async {
    switch (chunkId) {
      case 'COMM':
        if (_isCompressed == null) {
          throw AiffContentError(
            'Failed to parse AIFF.COMM chunk when compression type is unknown',
          );
        }

        final common = AiffCommonChunk.fromBytes(
          tokenizer.readBytes(chunkSize),
          isAifc: _isCompressed!,
        );
        metadata.setFormat(
          bitsPerSample: common.sampleSize,
          sampleRate: common.sampleRate,
          numberOfChannels: common.numChannels,
          numberOfSamples: common.numSampleFrames,
          duration: common.sampleRate > 0
              ? common.numSampleFrames / common.sampleRate
              : null,
        );
        final codec = common.compressionName;
        if (codec != null && codec.isNotEmpty) {
          metadata.setFormat(codec: codec);
        } else if (common.compressionType != null) {
          metadata.setFormat(
            codec:
                compressionTypes[common.compressionType!] ??
                common.compressionType,
          );
        }
        return chunkSize;

      case 'ID3 ':
        final id3Bytes = tokenizer.readBytes(chunkSize);
        final id3Tokenizer = BytesTokenizer(
          Uint8List.fromList(id3Bytes),
          fileInfo: FileInfo(size: id3Bytes.length),
        );
        final parser = Id3v2Parser(
          metadata: metadata,
          tokenizer: id3Tokenizer,
          options: options,
        );
        await parser.parse();
        return chunkSize;

      case 'SSND':
        final duration = metadata.format.duration;
        if (duration != null && duration > 0) {
          metadata.setFormat(bitrate: (8 * chunkSize / duration).round());
        }
        return 0;

      case 'NAME':
      case 'AUTH':
      case '(c) ':
      case 'ANNO':
        return _readTextChunk(chunkId, chunkSize);

      default:
        metadata.addWarning('Ignore chunk: AIFF/$chunkId');
        return 0;
    }
  }

  int _readTextChunk(String chunkId, int chunkSize) {
    final text = ascii.decode(
      tokenizer.readBytes(chunkSize),
      allowInvalid: true,
    );
    final values = text
        .split('\x00')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    for (final value in values) {
      metadata.addNativeTag('AIFF', chunkId, value);
    }
    return chunkSize;
  }

  static String _decodeAscii(List<int> bytes) {
    return ascii.decode(bytes, allowInvalid: true);
  }
}
