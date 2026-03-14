library;

import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/dsf/dsf_chunk.dart';
import 'package:audio_metadata/src/id3v2/id3v2_parser.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

class DsfParser {
  DsfParser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  Future<void> parse() async {
    final startPosition = tokenizer.position;
    final chunkHeader = DsfChunkHeader.fromBytes(
      tokenizer.readBytes(DsfChunkHeader.length),
    );
    if (chunkHeader.id != 'DSD ') {
      throw DsdContentError('Invalid chunk signature');
    }

    metadata.setFormat(
      container: 'DSF',
      lossless: true,
      hasAudio: true,
      hasVideo: false,
    );

    final dsdChunk = DsfDsdChunk.fromBytes(
      tokenizer.readBytes(DsfDsdChunk.length),
    );

    final bytesRemaining = dsdChunk.fileSize - chunkHeader.size;
    if (bytesRemaining > BigInt.zero) {
      _parseChunks(bytesRemaining);
    }

    if (dsdChunk.metadataPointer <= BigInt.zero) {
      return;
    }

    final id3Offset = dsdChunk.metadataPointer.toInt() + startPosition;
    final skip = id3Offset - tokenizer.position;
    if (skip > 0) {
      tokenizer.skip(skip);
    }

    final id3v2 = Id3v2Parser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await id3v2.parse();
  }

  void _parseChunks(BigInt bytesRemaining) {
    var remaining = bytesRemaining;

    while (remaining >= BigInt.from(DsfChunkHeader.length)) {
      final chunkHeader = DsfChunkHeader.fromBytes(
        tokenizer.readBytes(DsfChunkHeader.length),
      );

      switch (chunkHeader.id) {
        case 'fmt ':
          final payloadSize =
              (chunkHeader.size - BigInt.from(DsfChunkHeader.length)).toInt();
          if (payloadSize < DsfFormatChunk.length) {
            throw DsdContentError(
              'Unexpected format chunk size: ${chunkHeader.size}',
            );
          }

          final formatChunk = DsfFormatChunk.fromBytes(
            tokenizer.readBytes(DsfFormatChunk.length),
          );
          final toSkip = payloadSize - DsfFormatChunk.length;
          if (toSkip > 0) {
            tokenizer.skip(toSkip);
          }

          final sampleRate = formatChunk.samplingFrequency;
          final sampleCount = formatChunk.sampleCount.toInt();
          metadata.setFormat(
            numberOfChannels: formatChunk.channelNum,
            sampleRate: sampleRate,
            bitsPerSample: formatChunk.bitsPerSample,
            numberOfSamples: sampleCount,
            duration: sampleRate > 0 ? sampleCount / sampleRate : null,
            bitrate:
                formatChunk.bitsPerSample * sampleRate * formatChunk.channelNum,
          );
          return;

        default:
          final payloadSize =
              (chunkHeader.size - BigInt.from(DsfChunkHeader.length)).toInt();
          if (payloadSize > 0) {
            tokenizer.skip(payloadSize);
          }
      }

      remaining -= chunkHeader.size;
    }
  }
}
