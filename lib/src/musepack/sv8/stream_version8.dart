library;

// ignore_for_file: parameter_assignments, public_member_api_docs

import 'dart:convert';

import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

class Sv8PacketHeader {
  const Sv8PacketHeader({required this.key, required this.payloadLength});

  final String key;
  final int payloadLength;
}

class Sv8VariableSize {
  const Sv8VariableSize({required this.len, required this.value});

  final int len;
  final int value;
}

class Sv8StreamHeader {
  const Sv8StreamHeader({
    required this.crc,
    required this.streamVersion,
    required this.sampleCount,
    required this.beginningOfSilence,
    required this.sampleFrequency,
    required this.maxUsedBands,
    required this.channelCount,
    required this.msUsed,
    required this.audioBlockFrames,
  });

  final int crc;
  final int streamVersion;
  final int sampleCount;
  final int beginningOfSilence;
  final int sampleFrequency;
  final int maxUsedBands;
  final int channelCount;
  final bool msUsed;
  final int audioBlockFrames;
}

class StreamVersion8Reader {
  StreamVersion8Reader(this._tokenizer);

  final Tokenizer _tokenizer;

  Future<Sv8PacketHeader> readPacketHeader() async {
    final key = latin1.decode(_tokenizer.readBytes(2), allowInvalid: true);
    final size = await readVariableSizeField();
    return Sv8PacketHeader(key: key, payloadLength: size.value - 2 - size.len);
  }

  Future<Sv8StreamHeader> readStreamHeader(int size) async {
    var remainingSize = size;
    if (remainingSize < 7) {
      throw FormatException(
        'Invalid Musepack SV8 stream header size: $remainingSize',
      );
    }

    final part1 = _tokenizer.readBytes(5);
    remainingSize -= 5;

    final sampleCount = await readVariableSizeField();
    remainingSize -= sampleCount.len;

    final beginningOfSilence = await readVariableSizeField();
    remainingSize -= beginningOfSilence.len;

    if (remainingSize < 2) {
      throw const FormatException(
        'Invalid Musepack SV8 stream header tail size',
      );
    }

    final part3 = _tokenizer.readBytes(2);
    remainingSize -= 2;

    if (remainingSize > 0) {
      _tokenizer.skip(remainingSize);
    }

    final sampleFrequencyIndex = _getBitAlignedNumber(part3, 0, 0, 3);

    return Sv8StreamHeader(
      crc: _readUint32Le(part1, 0),
      streamVersion: part1[4],
      sampleCount: sampleCount.value,
      beginningOfSilence: beginningOfSilence.value,
      sampleFrequency: const <int>[
        44100,
        48000,
        37800,
        32000,
      ][sampleFrequencyIndex],
      maxUsedBands: _getBitAlignedNumber(part3, 0, 3, 5),
      channelCount: _getBitAlignedNumber(part3, 1, 0, 4) + 1,
      msUsed: _isBitSet(part3, 1, 4),
      audioBlockFrames: _getBitAlignedNumber(part3, 1, 5, 3),
    );
  }

  Future<Sv8VariableSize> readVariableSizeField([
    int len = 1,
    int hb = 0,
  ]) async {
    var n = _tokenizer.readUint8();
    if ((n & 0x80) == 0) {
      return Sv8VariableSize(len: len, value: hb + n);
    }

    n &= 0x7F;
    n += hb;
    return readVariableSizeField(len + 1, n << 7);
  }

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
