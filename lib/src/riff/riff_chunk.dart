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

  /// Decodes the tag value with [encoding] and truncates at the first NUL.
  ///
  /// Supported encodings:
  /// - `latin1` (default; absent/zero/28591 RIFF CSET code page)
  /// - `windows-1252` (RIFF CSET code page 1252)
  /// - `windows-1250` (RIFF CSET code page 1250)
  /// - `windows-1251` (RIFF CSET code page 1251)
  /// - `utf-16le` (RIFF CSET code page 1200)
  /// - `utf-16be` (RIFF CSET code page 1201)
  /// - `utf-8` (RIFF CSET code page 65001)
  String parse(List<int> bytes, {String encoding = 'latin1'}) {
    if (bytes.length < tagHeader.chunkSize) {
      throw const FormatException('RIFF LIST/INFO tag value is truncated');
    }

    final decoded = _decode(bytes.sublist(0, tagHeader.chunkSize), encoding);
    // Truncate at the first NUL instead of stripping every zero.
    final nulIndex = decoded.indexOf('\x00');
    return nulIndex == -1 ? decoded : decoded.substring(0, nulIndex);
  }

  static String _decode(List<int> bytes, String encoding) {
    switch (encoding) {
      case 'utf-8':
        return utf8.decode(bytes, allowMalformed: true);
      case 'windows-1252':
        return _decodeWindows1252(bytes);
      case 'windows-1250':
        return _decodeWindows1250(bytes);
      case 'windows-1251':
        return _decodeWindows1251(bytes);
      case 'utf-16le':
        return _decodeUtf16Le(bytes);
      case 'utf-16be':
        return _decodeUtf16Be(bytes);
      case 'latin1':
      default:
        return latin1.decode(bytes, allowInvalid: true);
    }
  }

  static String _decodeUtf16Le(List<int> bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final code = bytes[i] | (bytes[i + 1] << 8);
      buffer.writeCharCode(code);
    }
    return buffer.toString();
  }

  static String _decodeUtf16Be(List<int> bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final code = (bytes[i] << 8) | bytes[i + 1];
      buffer.writeCharCode(code);
    }
    return buffer.toString();
  }

  static String _decodeWindows1250(List<int> bytes) {
    const highChars1250 = <String>[
      '\u20AC', '\u0081', '\u201A', '\u0083', '\u201E', '\u2026', '\u2020', '\u2021',
      '\u0088', '\u2030', '\u0160', '\u2039', '\u015A', '\u0164', '\u017D', '\u0179',
      '\u0090', '\u2018', '\u2019', '\u201C', '\u201D', '\u2022', '\u2013', '\u2014',
      '\u0098', '\u2122', '\u0161', '\u203A', '\u015B', '\u0165', '\u017E', '\u017A',
    ];
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (byte >= 0x80 && byte <= 0x9F) {
        buffer.write(highChars1250[byte - 0x80]);
      } else {
        buffer.writeCharCode(byte);
      }
    }
    return buffer.toString();
  }

  static String _decodeWindows1251(List<int> bytes) {
    const highChars1251 = <String>[
      '\u0402', '\u0403', '\u201A', '\u0453', '\u201E', '\u2026', '\u2020', '\u2021',
      '\u20AC', '\u2030', '\u0409', '\u2039', '\u040A', '\u040B', '\u040C', '\u040F',
      '\u0452', '\u2018', '\u2019', '\u201C', '\u201D', '\u2022', '\u2013', '\u2014',
      '\u0098', '\u2122', '\u0459', '\u203A', '\u045A', '\u045B', '\u045C', '\u045F',
      '\u00A0', '\u040E', '\u045E', '\u0408', '\u00A4', '\u0490', '\u00A6', '\u00A7',
      '\u0401', '\u00A9', '\u0404', '\u00AB', '\u00AC', '\u00AD', '\u00AE', '\u0407',
      '\u00B0', '\u00B1', '\u0406', '\u0456', '\u0491', '\u00B5', '\u00B6', '\u00B7',
      '\u0451', '\u2116', '\u0454', '\u00BB', '\u0458', '\u0405', '\u0455', '\u0457',
    ];
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (byte >= 0x80 && byte <= 0xBF) {
        buffer.write(highChars1251[byte - 0x80]);
      } else if (byte >= 0xC0 && byte <= 0xFF) {
        buffer.writeCharCode(0x0410 + (byte - 0xC0));
      } else {
        buffer.writeCharCode(byte);
      }
    }
    return buffer.toString();
  }

  /// Windows-1252 shares latin1 below 0x80 and above 0x9F; only the
  /// 0x80-0x9F range remaps to printable characters.
  static String _decodeWindows1252(List<int> bytes) {
    const highChars = <String>[
      '\u20AC',
      '\u0081',
      '\u201A',
      '\u0192',
      '\u201E',
      '\u2026',
      '\u2020',
      '\u2021',
      '\u02C6',
      '\u2030',
      '\u0160',
      '\u2039',
      '\u0152',
      '\u008D',
      '\u017D',
      '\u008F',
      '\u0090',
      '\u2018',
      '\u2019',
      '\u201C',
      '\u201D',
      '\u2022',
      '\u2013',
      '\u2014',
      '\u02DC',
      '\u2122',
      '\u0161',
      '\u203A',
      '\u0153',
      '\u009D',
      '\u017E',
      '\u0178',
    ];
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (byte >= 0x80 && byte <= 0x9F) {
        buffer.write(highChars[byte - 0x80]);
      } else {
        buffer.writeCharCode(byte);
      }
    }
    return buffer.toString();
  }
}
