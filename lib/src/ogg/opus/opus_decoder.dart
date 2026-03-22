library;

import 'dart:convert';

import 'package:metadata_audio/src/ogg/ogg_token.dart';
import 'package:metadata_audio/src/ogg/vorbis/vorbis_decoder.dart';

class OpusIdHeader {
  const OpusIdHeader({
    required this.version,
    required this.channelCount,
    required this.preSkip,
    required this.inputSampleRate,
    required this.outputGain,
    required this.channelMapping,
  });

  final int version;
  final int channelCount;
  final int preSkip;
  final int inputSampleRate;
  final int outputGain;
  final int channelMapping;
}

class OpusDecoder {
  static const int idHeaderMinLength = 19;

  static bool isIdHeader(List<int> data) =>
      data.length >= 8 && _ascii(data, 0, 8) == 'OpusHead';

  static bool isTagsHeader(List<int> data) =>
      data.length >= 8 && _ascii(data, 0, 8) == 'OpusTags';

  static OpusIdHeader parseIdHeader(List<int> data) {
    if (!isIdHeader(data) || data.length < idHeaderMinLength) {
      throw const FormatException('Invalid Opus ID header');
    }

    return OpusIdHeader(
      version: data[8],
      channelCount: data[9],
      preSkip: _uint16Le(data, 10),
      inputSampleRate: OggToken.uint32Le(data, 12),
      outputGain: _int16Le(data, 16),
      channelMapping: data[18],
    );
  }

  static VorbisCommentHeader parseTags(List<int> data) {
    if (!isTagsHeader(data)) {
      throw const FormatException('Invalid OpusTags header');
    }

    return VorbisDecoder.parseCommentData(data, 8);
  }

  static int _uint16Le(List<int> data, int offset) {
    if (offset < 0 || offset + 2 > data.length) {
      throw const FormatException('Unexpected end of Opus header');
    }
    return data[offset] | (data[offset + 1] << 8);
  }

  static int _int16Le(List<int> data, int offset) {
    final value = _uint16Le(data, offset);
    return value >= 0x8000 ? value - 0x10000 : value;
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
