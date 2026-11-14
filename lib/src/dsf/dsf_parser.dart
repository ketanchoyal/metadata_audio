library;

import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/dsf/dsf_chunk.dart';
import 'package:metadata_audio/src/id3v2/id3v2_parser.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

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
          final duration = sampleRate > 0 ? sampleCount / sampleRate : null;
          final bitrate =
              formatChunk.bitsPerSample * sampleRate * formatChunk.channelNum;
          final channelPositions = _mapDsfChannelPositions(
            formatChunk.channelType,
          );

          metadata.setFormat(
            numberOfChannels: formatChunk.channelNum,
            sampleRate: sampleRate,
            bitsPerSample: formatChunk.bitsPerSample,
            numberOfSamples: sampleCount,
            duration: duration,
            bitrate: bitrate,
          );

          metadata.addStreamInfo(
            TrackInfo(
              type: 'audio',
              codecName: 'DSD',
              duration: duration,
              bitrate: bitrate.toDouble(),
              lossless: true,
              audio: AudioTrack(
                samplingFrequency: sampleRate,
                channels: formatChunk.channelNum,
                channelPositions: channelPositions,
                bitDepth: formatChunk.bitsPerSample,
                numberOfSamples: sampleCount,
              ),
            ),
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

  static List<int>? _mapDsfChannelPositions(int channelType) {
    switch (channelType) {
      case 1:
        return const [0x04];
      case 2:
        return const [0x01, 0x02];
      case 3:
        return const [0x01, 0x02, 0x04];
      case 4:
        return const [0x01, 0x02, 0x10, 0x20];
      case 5:
        return const [0x01, 0x02, 0x04, 0x100];
      case 6:
        return const [0x01, 0x02, 0x04, 0x10, 0x20];
      case 7:
        return const [0x01, 0x02, 0x04, 0x08, 0x10, 0x20];
      default:
        return null;
    }
  }

  /// Maps DSF channel types to human-readable speaker layout names.
  static List<String>? channelNames(int channelType) {
    switch (channelType) {
      case 1:
        return const ['mono'];
      case 2:
        return const ['front-left', 'front-right'];
      case 3:
        return const ['front-left', 'front-right', 'front-center'];
      case 4:
        return const ['front-left', 'front-right', 'rear-left', 'rear-right'];
      case 5:
        return const [
          'front-left',
          'front-right',
          'front-center',
          'rear-center',
        ];
      case 6:
        return const [
          'front-left',
          'front-center',
          'front-right',
          'rear-left',
          'rear-right',
        ];
      case 7:
        return const [
          'front-left',
          'front-center',
          'front-right',
          'rear-left',
          'rear-right',
          'lfe',
        ];
      default:
        return null;
    }
  }
}
