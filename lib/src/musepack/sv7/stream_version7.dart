library;

// ignore_for_file: public_member_api_docs

import 'dart:convert';

class Sv7Header {
  const Sv7Header({
    required this.signature,
    required this.streamMinorVersion,
    required this.streamMajorVersion,
    required this.frameCount,
    required this.intensityStereo,
    required this.midSideStereo,
    required this.maxBand,
    required this.profile,
    required this.link,
    required this.sampleFrequency,
    required this.maxLevel,
    required this.titleGain,
    required this.titlePeak,
    required this.albumGain,
    required this.albumPeak,
    required this.trueGapless,
    required this.lastFrameLength,
  });

  final String signature;
  final int streamMinorVersion;
  final int streamMajorVersion;
  final int frameCount;
  final bool intensityStereo;
  final bool midSideStereo;
  final int maxBand;
  final int profile;
  final int link;
  final int sampleFrequency;
  final int maxLevel;
  final int titleGain;
  final int titlePeak;
  final int albumGain;
  final int albumPeak;
  final bool trueGapless;
  final int lastFrameLength;
}

class StreamVersion7 {
  static const int headerLength = 6 * 4;

  static Sv7Header parseHeader(List<int> bytes, {int offset = 0}) {
    if (offset < 0 || offset + headerLength > bytes.length) {
      throw const FormatException('Invalid Musepack SV7 header length');
    }

    final streamMinorVersion = _getBitAlignedNumber(bytes, offset + 3, 0, 4);
    final streamMajorVersion = _getBitAlignedNumber(bytes, offset + 3, 4, 4);

    final frameCount = _readUint32Le(bytes, offset + 4);
    final maxLevel = _readUint16Le(bytes, offset + 8);
    final sampleFrequency = const <int>[
      44100,
      48000,
      37800,
      32000,
    ][_getBitAlignedNumber(bytes, offset + 10, 0, 2)];
    final link = _getBitAlignedNumber(bytes, offset + 10, 2, 2);
    final profile = _getBitAlignedNumber(bytes, offset + 10, 4, 4);
    final maxBand = _getBitAlignedNumber(bytes, offset + 11, 0, 6);
    final intensityStereo = _isBitSet(bytes, offset + 11, 6);
    final midSideStereo = _isBitSet(bytes, offset + 11, 7);

    final titlePeak = _readUint16Le(bytes, offset + 12);
    final titleGain = _readUint16Le(bytes, offset + 14);
    final albumPeak = _readUint16Le(bytes, offset + 16);
    final albumGain = _readUint16Le(bytes, offset + 18);

    final trueGapless = _isBitSet(bytes, offset + 23, 0);
    final word5 = _readUint32Le(bytes, offset + 20);
    final lastFrameLength = trueGapless ? (word5 >> 20) & 0x7FF : 0;

    return Sv7Header(
      signature: latin1.decode(bytes.sublist(offset, offset + 3)),
      streamMinorVersion: streamMinorVersion,
      streamMajorVersion: streamMajorVersion,
      frameCount: frameCount,
      intensityStereo: intensityStereo,
      midSideStereo: midSideStereo,
      maxBand: maxBand,
      profile: profile,
      link: link,
      sampleFrequency: sampleFrequency,
      maxLevel: maxLevel,
      titleGain: titleGain,
      titlePeak: titlePeak,
      albumGain: albumGain,
      albumPeak: albumPeak,
      trueGapless: trueGapless,
      lastFrameLength: lastFrameLength,
    );
  }

  static int _readUint16Le(List<int> bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  static int _readUint32Le(List<int> bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  static bool _isBitSet(List<int> bytes, int offset, int bitOffsetFromLsb) =>
      ((bytes[offset] >> bitOffsetFromLsb) & 0x01) == 0x01;

  static int _getBitAlignedNumber(
    List<int> bytes,
    int offset,
    int bitOffset,
    int len,
  ) {
    var value = 0;
    for (var i = 0; i < len; i++) {
      final absoluteBit = bitOffset + i;
      final byteIndex = offset + (absoluteBit >> 3);
      final bitInByteFromMsb = absoluteBit & 0x07;
      final shift = 7 - bitInByteFromMsb;
      final bit = (bytes[byteIndex] >> shift) & 0x01;
      value = (value << 1) | bit;
    }
    return value;
  }
}
