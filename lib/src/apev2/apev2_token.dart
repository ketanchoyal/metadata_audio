library;

import 'dart:convert';

class ApeDescriptor {
  const ApeDescriptor({
    required this.id,
    required this.version,
    required this.descriptorBytes,
    required this.headerBytes,
    required this.seekTableBytes,
    required this.headerDataBytes,
    required this.apeFrameDataBytes,
    required this.apeFrameDataBytesHigh,
    required this.terminatingDataBytes,
    required this.fileMd5,
  });

  final String id;
  final int version;
  final int descriptorBytes;
  final int headerBytes;
  final int seekTableBytes;
  final int headerDataBytes;
  final int apeFrameDataBytes;
  final int apeFrameDataBytesHigh;
  final int terminatingDataBytes;
  final List<int> fileMd5;
}

class ApeHeader {
  const ApeHeader({
    required this.compressionLevel,
    required this.formatFlags,
    required this.blocksPerFrame,
    required this.finalFrameBlocks,
    required this.totalFrames,
    required this.bitsPerSample,
    required this.channel,
    required this.sampleRate,
  });

  final int compressionLevel;
  final int formatFlags;
  final int blocksPerFrame;
  final int finalFrameBlocks;
  final int totalFrames;
  final int bitsPerSample;
  final int channel;
  final int sampleRate;
}

class ApeTagFlags {
  const ApeTagFlags({
    required this.containsHeader,
    required this.containsFooter,
    required this.isHeader,
    required this.readOnly,
    required this.dataType,
  });

  final bool containsHeader;
  final bool containsFooter;
  final bool isHeader;
  final bool readOnly;
  final int dataType;
}

class ApeTagFooter {
  const ApeTagFooter({
    required this.id,
    required this.version,
    required this.size,
    required this.fields,
    required this.flags,
  });

  final String id;
  final int version;
  final int size;
  final int fields;
  final ApeTagFlags flags;
}

class ApeTagItemHeader {
  const ApeTagItemHeader({required this.size, required this.flags});

  final int size;
  final ApeTagFlags flags;
}

class ApePicture {
  const ApePicture({required this.description, required this.data});

  final String description;
  final List<int> data;
}

class Apev2DataType {
  static const int textUtf8 = 0;
  static const int binary = 1;
  static const int externalInfo = 2;
  static const int reserved = 3;
}

class Apev2Token {
  static const String preamble = 'APETAGEX';
  static const int descriptorLength = 52;
  static const int headerLength = 24;
  static const int tagFooterLength = 32;
  static const int tagItemHeaderLength = 8;

  static ApeDescriptor parseDescriptor(List<int> bytes) {
    if (bytes.length < descriptorLength) {
      throw const FormatException('APEv2 descriptor requires 52 bytes');
    }

    return ApeDescriptor(
      id: ascii.decode(bytes.sublist(0, 4), allowInvalid: true),
      version: _readUint32Le(bytes, 4),
      descriptorBytes: _readUint32Le(bytes, 8),
      headerBytes: _readUint32Le(bytes, 12),
      seekTableBytes: _readUint32Le(bytes, 16),
      headerDataBytes: _readUint32Le(bytes, 20),
      apeFrameDataBytes: _readUint32Le(bytes, 24),
      apeFrameDataBytesHigh: _readUint32Le(bytes, 28),
      terminatingDataBytes: _readUint32Le(bytes, 32),
      fileMd5: bytes.sublist(36, 52),
    );
  }

  static ApeHeader parseHeader(List<int> bytes) {
    if (bytes.length < headerLength) {
      throw const FormatException('APEv2 header requires 24 bytes');
    }

    return ApeHeader(
      compressionLevel: _readUint16Le(bytes, 0),
      formatFlags: _readUint16Le(bytes, 2),
      blocksPerFrame: _readUint32Le(bytes, 4),
      finalFrameBlocks: _readUint32Le(bytes, 8),
      totalFrames: _readUint32Le(bytes, 12),
      bitsPerSample: _readUint16Le(bytes, 16),
      channel: _readUint16Le(bytes, 18),
      sampleRate: _readUint32Le(bytes, 20),
    );
  }

  static ApeTagFooter parseTagFooter(List<int> bytes, [int offset = 0]) {
    if (offset < 0 || offset + tagFooterLength > bytes.length) {
      throw const FormatException('APEv2 tag footer requires 32 bytes');
    }

    return ApeTagFooter(
      id: ascii.decode(bytes.sublist(offset, offset + 8), allowInvalid: true),
      version: _readUint32Le(bytes, offset + 8),
      size: _readUint32Le(bytes, offset + 12),
      fields: _readUint32Le(bytes, offset + 16),
      flags: parseTagFlags(_readUint32Le(bytes, offset + 20)),
    );
  }

  static ApeTagItemHeader parseTagItemHeader(List<int> bytes) {
    if (bytes.length < tagItemHeaderLength) {
      throw const FormatException('APEv2 item header requires 8 bytes');
    }

    return ApeTagItemHeader(
      size: _readUint32Le(bytes, 0),
      flags: parseTagFlags(_readUint32Le(bytes, 4)),
    );
  }

  static ApeTagFlags parseTagFlags(int flags) => ApeTagFlags(
      containsHeader: _isBitSet(flags, 31),
      containsFooter: _isBitSet(flags, 30),
      isHeader: _isBitSet(flags, 29),
      readOnly: _isBitSet(flags, 0),
      dataType: (flags & 6) >> 1,
    );

  static bool _isBitSet(int value, int bit) => (value & (1 << bit)) != 0;

  static int _readUint16Le(List<int> bytes, int offset) {
    if (offset < 0 || offset + 2 > bytes.length) {
      throw const FormatException('uint16 LE read out of bounds');
    }
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  static int _readUint32Le(List<int> bytes, int offset) {
    if (offset < 0 || offset + 4 > bytes.length) {
      throw const FormatException('uint32 LE read out of bounds');
    }
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
}
