library;

import 'dart:convert';

class RiffChunkHeader {
  const RiffChunkHeader({required this.chunkId, required this.chunkSize});

  final String chunkId;
  final int chunkSize;
}

class RiffChunk {
  static const int headerLength = 8;

  static RiffChunkHeader parseHeader(List<int> bytes) {
    if (bytes.length < headerLength) {
      throw const FormatException('RIFF chunk header requires 8 bytes');
    }

    return RiffChunkHeader(
      chunkId: ascii.decode(bytes.sublist(0, 4), allowInvalid: true),
      chunkSize: readUint32Le(bytes, 4),
    );
  }

  static int readUint16Le(List<int> bytes, int offset) {
    if (offset < 0 || offset + 2 > bytes.length) {
      throw const FormatException('uint16 LE read out of bounds');
    }
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  static int readUint32Le(List<int> bytes, int offset) {
    if (offset < 0 || offset + 4 > bytes.length) {
      throw const FormatException('uint32 LE read out of bounds');
    }
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
}

class ListInfoTagValue {
  const ListInfoTagValue(this.tagHeader);

  final RiffChunkHeader tagHeader;

  int get paddedLength => tagHeader.chunkSize + (tagHeader.chunkSize & 1);

  String parse(List<int> bytes) {
    if (bytes.length < tagHeader.chunkSize) {
      throw const FormatException('RIFF LIST/INFO tag value is truncated');
    }

    return ascii.decode(
      bytes.sublist(0, tagHeader.chunkSize),
      allowInvalid: true,
    );
  }
}
