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
    this.streamCount = 1,
    this.coupledCount = 0,
    this.channelMappingTable = const [],
  });

  final int version;
  final int channelCount;
  final int preSkip;
  final int inputSampleRate;
  final int outputGain;
  final int channelMapping;
  final int streamCount;
  final int coupledCount;
  final List<int> channelMappingTable;

  /// Output gain in decibels (Q7.8 format: outputGain / 256.0).
  double get outputGainDb => outputGain / 256.0;
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

    final channelCount = data[9];
    if (channelCount <= 0) {
      throw const FormatException('Opus channel count must be greater than 0');
    }

    final channelMapping = data[18];
    var streamCount = 1;
    var coupledCount = channelCount > 1 ? 1 : 0;
    var channelMappingTable = const <int>[];

    if (channelMapping == 0) {
      channelMappingTable = channelCount == 1 ? const [0] : const [0, 1];
    } else {
      final requiredLength = 21 + channelCount;
      if (data.length < requiredLength) {
        throw const FormatException(
          'Opus ID header with channel mapping table is truncated',
        );
      }
      streamCount = data[19];
      coupledCount = data[20];
      channelMappingTable = List<int>.unmodifiable(
        data.sublist(21, 21 + channelCount),
      );
    }

    return OpusIdHeader(
      version: data[8],
      channelCount: channelCount,
      preSkip: _uint16Le(data, 10),
      inputSampleRate: OggToken.uint32Le(data, 12),
      outputGain: _int16Le(data, 16),
      channelMapping: channelMapping,
      streamCount: streamCount,
      coupledCount: coupledCount,
      channelMappingTable: channelMappingTable,
    );
  }

  /// Maps Opus channel counts and channel mapping families to standard speaker layout.
  static List<String>? channelPositions(int channelCount, int family) {
    if (family == 0) {
      if (channelCount == 1) return const ['mono'];
      if (channelCount == 2) return const ['front-left', 'front-right'];
      return null;
    }
    if (family == 1) {
      switch (channelCount) {
        case 1:
          return const ['front-center'];
        case 2:
          return const ['front-left', 'front-right'];
        case 3:
          return const ['front-left', 'front-center', 'front-right'];
        case 4:
          return const ['front-left', 'front-right', 'rear-left', 'rear-right'];
        case 5:
          return const [
            'front-left',
            'front-center',
            'front-right',
            'rear-left',
            'rear-right',
          ];
        case 6:
          return const [
            'front-left',
            'front-center',
            'front-right',
            'rear-left',
            'rear-right',
            'lfe',
          ];
        case 7:
          return const [
            'front-left',
            'front-center',
            'front-right',
            'side-left',
            'side-right',
            'rear-center',
            'lfe',
          ];
        case 8:
          return const [
            'front-left',
            'front-center',
            'front-right',
            'side-left',
            'side-right',
            'rear-left',
            'rear-right',
            'lfe',
          ];
      }
    }
    return null;
  }

  static VorbisCommentHeader parseTags(
    List<int> data, {
    int maxComments = 100000,
  }) {
    if (!isTagsHeader(data)) {
      throw const FormatException('Invalid OpusTags header');
    }

    return VorbisDecoder.parseCommentData(data, 8, maxComments: maxComments);
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
