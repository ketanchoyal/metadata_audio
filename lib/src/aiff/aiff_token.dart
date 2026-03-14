library;

import 'dart:convert';

import 'package:audio_metadata/src/parse_error.dart';

const Map<String, String> compressionTypes = <String, String>{
  'NONE': 'not compressed PCM Apple Computer',
  'sowt': 'PCM (byte swapped)',
  'fl32': '32-bit floating point IEEE 32-bit float',
  'fl64': '64-bit floating point IEEE 64-bit float Apple Computer',
  'alaw': 'Alaw 2:1 8-bit ITU-T G.711 A-law',
  'ulaw': 'uLaw 2:1 8-bit ITU-T G.711 u-law Apple Computer',
  'ULAW': 'CCITT G.711 u-law 8-bit ITU-T G.711 u-law',
  'ALAW': 'CCITT G.711 A-law 8-bit ITU-T G.711 A-law',
  'FL32': 'Float 32 IEEE 32-bit float',
};

class AiffContentError extends UnexpectedFileContentError {
  AiffContentError(String message) : super('AIFF', message);
}

class AiffChunkHeader {
  const AiffChunkHeader({required this.chunkId, required this.chunkSize});

  final String chunkId;
  final int chunkSize;
}

class AiffToken {
  static const int chunkHeaderLength = 8;

  static AiffChunkHeader parseChunkHeader(List<int> bytes) {
    if (bytes.length < chunkHeaderLength) {
      throw const FormatException('AIFF chunk header requires 8 bytes');
    }

    return AiffChunkHeader(
      chunkId: ascii.decode(bytes.sublist(0, 4), allowInvalid: true),
      chunkSize: readUint32Be(bytes, 4),
    );
  }

  static int readUint16Be(List<int> bytes, int offset) {
    if (offset < 0 || offset + 2 > bytes.length) {
      throw const FormatException('uint16 BE read out of bounds');
    }
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  static int readUint32Be(List<int> bytes, int offset) {
    if (offset < 0 || offset + 4 > bytes.length) {
      throw const FormatException('uint32 BE read out of bounds');
    }
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }
}

class AiffCommonChunk {
  const AiffCommonChunk({
    required this.numChannels,
    required this.numSampleFrames,
    required this.sampleSize,
    required this.sampleRate,
    this.compressionType,
    this.compressionName,
  });

  final int numChannels;
  final int numSampleFrames;
  final int sampleSize;
  final int sampleRate;
  final String? compressionType;
  final String? compressionName;

  static AiffCommonChunk fromBytes(List<int> bytes, {required bool isAifc}) {
    final minimumChunkSize = isAifc ? 22 : 18;
    if (bytes.length < minimumChunkSize) {
      throw AiffContentError(
        'COMMON CHUNK size should always be at least $minimumChunkSize',
      );
    }

    final shift = AiffToken.readUint16Be(bytes, 8) - 16398;
    final baseSampleRate = AiffToken.readUint16Be(bytes, 10);
    final sampleRate = shift < 0
        ? (baseSampleRate >> shift.abs())
        : (baseSampleRate << shift);

    String? compressionType;
    String? compressionName;

    if (isAifc) {
      compressionType = ascii.decode(bytes.sublist(18, 22), allowInvalid: true);
      if (bytes.length > 22) {
        final strLen = bytes[22];
        if (strLen > 0) {
          final padding = (strLen + 1) % 2;
          if (23 + strLen + padding != bytes.length) {
            throw AiffContentError('Illegal pstring length');
          }
          compressionName = latin1.decode(
            bytes.sublist(23, 23 + strLen),
            allowInvalid: true,
          );
        }
      }
    } else {
      compressionName = 'PCM';
    }

    return AiffCommonChunk(
      numChannels: AiffToken.readUint16Be(bytes, 0),
      numSampleFrames: AiffToken.readUint32Be(bytes, 2),
      sampleSize: AiffToken.readUint16Be(bytes, 6),
      sampleRate: sampleRate,
      compressionType: compressionType,
      compressionName: compressionName,
    );
  }
}
