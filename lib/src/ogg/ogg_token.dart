library;

import 'dart:convert';

class OggHeaderType {
  const OggHeaderType({
    required this.continued,
    required this.firstPage,
    required this.lastPage,
  });

  final bool continued;
  final bool firstPage;
  final bool lastPage;
}

class OggPageHeader {
  const OggPageHeader({
    required this.capturePattern,
    required this.version,
    required this.headerType,
    required this.absoluteGranulePosition,
    required this.streamSerialNumber,
    required this.pageSequenceNo,
    required this.pageChecksum,
    required this.pageSegments,
  });

  final String capturePattern;
  final int version;
  final OggHeaderType headerType;
  final int absoluteGranulePosition;
  final int streamSerialNumber;
  final int pageSequenceNo;
  final int pageChecksum;
  final int pageSegments;
}

class OggSegmentTable {
  const OggSegmentTable({
    required this.totalPageSize,
    required this.lacingValues,
  });

  final int totalPageSize;
  final List<int> lacingValues;
}

class OggToken {
  static const int pageHeaderLength = 27;

  static OggPageHeader parsePageHeader(List<int> bytes, [int offset = 0]) {
    _expectLength(bytes, offset, pageHeaderLength, 'Ogg page header');

    return OggPageHeader(
      capturePattern: ascii.decode(
        bytes.sublist(offset, offset + 4),
        allowInvalid: true,
      ),
      version: bytes[offset + 4],
      headerType: _parseHeaderType(bytes[offset + 5]),
      absoluteGranulePosition: uint64Le(bytes, offset + 6),
      streamSerialNumber: uint32Le(bytes, offset + 14),
      pageSequenceNo: uint32Le(bytes, offset + 18),
      pageChecksum: uint32Le(bytes, offset + 22),
      pageSegments: bytes[offset + 26],
    );
  }

  static OggSegmentTable parseSegmentTable(
    List<int> bytes,
    int segmentCount, [
    int offset = 0,
  ]) {
    _expectLength(bytes, offset, segmentCount, 'Ogg segment table');
    final lacingValues = bytes.sublist(offset, offset + segmentCount);
    var totalPageSize = 0;
    for (final value in lacingValues) {
      totalPageSize += value;
    }
    return OggSegmentTable(
      totalPageSize: totalPageSize,
      lacingValues: lacingValues,
    );
  }

  static OggHeaderType _parseHeaderType(int value) => OggHeaderType(
      continued: (value & 0x01) != 0,
      firstPage: (value & 0x02) != 0,
      lastPage: (value & 0x04) != 0,
    );

  static int uint32Le(List<int> bytes, [int offset = 0]) {
    _expectLength(bytes, offset, 4, 'unsigned 32-bit integer (LE)');
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  static int uint64Le(List<int> bytes, [int offset = 0]) {
    _expectLength(bytes, offset, 8, 'unsigned 64-bit integer (LE)');
    final low = uint32Le(bytes, offset);
    final high = uint32Le(bytes, offset + 4);
    return low + (high << 32);
  }

  static void _expectLength(
    List<int> bytes,
    int offset,
    int length,
    String what,
  ) {
    if (offset < 0 || length < 0 || offset + length > bytes.length) {
      throw RangeError(
        'Insufficient bytes for $what: required ${offset + length}, available ${bytes.length}',
      );
    }
  }
}
