library;

import 'dart:convert';

import 'package:metadata_audio/src/ogg/ogg_token.dart';

class SpeexHeader {
  const SpeexHeader({
    required this.version,
    required this.sampleRate,
    required this.numberOfChannels,
    required this.bitrate,
  });

  final String version;
  final int sampleRate;
  final int numberOfChannels;
  final int bitrate;
}

class SpeexDecoder {
  static const int headerLength = 80;

  static bool isHeader(List<int> data) => data.length >= 8 && _ascii(data, 0, 8) == 'Speex   ';

  static SpeexHeader parseHeader(List<int> data) {
    if (!isHeader(data) || data.length < headerLength) {
      throw const FormatException('Invalid Speex header');
    }

    final version = _trimRightNull(_ascii(data, 8, 20));
    final sampleRate = _int32Le(data, 36);
    final channels = _int32Le(data, 48);
    final bitrate = _int32Le(data, 52);

    return SpeexHeader(
      version: version,
      sampleRate: sampleRate,
      numberOfChannels: channels,
      bitrate: bitrate,
    );
  }

  static int _int32Le(List<int> data, int offset) {
    final value = OggToken.uint32Le(data, offset);
    return value >= 0x80000000 ? value - 0x100000000 : value;
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

  static String _trimRightNull(String value) {
    final index = value.indexOf('\u0000');
    return index == -1 ? value.trimRight() : value.substring(0, index);
  }
}
