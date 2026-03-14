library;

import 'dart:convert';

class IffChunkHeader {
  const IffChunkHeader({required this.chunkId, required this.chunkSize});

  final String chunkId;
  final int chunkSize;
}

class IffChunkHeader64 {
  const IffChunkHeader64({required this.chunkId, required this.chunkSize});

  final String chunkId;
  final BigInt chunkSize;
}

class IffParser {
  static const int chunkHeaderLength = 8;
  static const int chunkHeader64Length = 12;

  static IffChunkHeader parseChunkHeader(List<int> bytes) {
    if (bytes.length < chunkHeaderLength) {
      throw const FormatException('IFF chunk header requires 8 bytes');
    }

    return IffChunkHeader(
      chunkId: decodeFourCc(bytes),
      chunkSize: readUint32Be(bytes, 4),
    );
  }

  static IffChunkHeader64 parseChunkHeader64(List<int> bytes) {
    if (bytes.length < chunkHeader64Length) {
      throw const FormatException('IFF 64-bit chunk header requires 12 bytes');
    }

    return IffChunkHeader64(
      chunkId: decodeFourCc(bytes),
      chunkSize: readInt64Be(bytes, 4),
    );
  }

  static String decodeFourCc(List<int> bytes, [int offset = 0]) {
    if (offset < 0 || offset + 4 > bytes.length) {
      throw const FormatException('FourCC read out of bounds');
    }
    return ascii.decode(bytes.sublist(offset, offset + 4), allowInvalid: true);
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

  static BigInt readUint64Be(List<int> bytes, int offset) {
    final hi = readUint32Be(bytes, offset);
    final lo = readUint32Be(bytes, offset + 4);
    return (BigInt.from(hi) << 32) | BigInt.from(lo);
  }

  static BigInt readInt64Be(List<int> bytes, int offset) {
    final value = readUint64Be(bytes, offset);
    final signBit = BigInt.one << 63;
    if ((value & signBit) != BigInt.zero) {
      return value - (BigInt.one << 64);
    }
    return value;
  }
}
