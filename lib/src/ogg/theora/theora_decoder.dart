library;

import 'dart:convert';

class TheoraIdentificationHeader {
  const TheoraIdentificationHeader({required this.bitrate});

  final int bitrate;
}

class TheoraDecoder {
  static const int identificationHeaderLength = 42;

  static bool isIdentificationHeader(List<int> data) =>
      data.length >= 7 && data[0] == 0x80 && _ascii(data, 1, 6) == 'theora';

  static TheoraIdentificationHeader parseIdentificationHeader(List<int> data) {
    if (!isIdentificationHeader(data) ||
        data.length < identificationHeaderLength) {
      throw const FormatException('Invalid Theora identification header');
    }

    return TheoraIdentificationHeader(
      bitrate: (data[37] << 16) | (data[38] << 8) | data[39],
    );
  }

  static String _ascii(List<int> data, int offset, int length) {
    if (offset < 0 || offset + length > data.length) {
      return '';
    }

    return ascii.decode(
      data.sublist(offset, offset + length),
      allowInvalid: true,
    );
  }
}
