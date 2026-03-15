library;

class ReplayGainNameCode {
  static const int notSet = 0;
  static const int radio = 1;
  static const int audiophile = 2;
}

class ReplayGainOriginator {
  static const int unspecified = 0;
  static const int engineer = 1;
  static const int user = 2;
  static const int automatic = 3;
  static const int rmsAverage = 4;
}

class ReplayGainData {

  const ReplayGainData({
    required this.type,
    required this.origin,
    required this.adjustment,
  });
  final int type;
  final int origin;
  final double adjustment;
}

class ReplayGainDataFormat {
  static const int length = 2;

  static ReplayGainData? parse(List<int> bytes, {int offset = 0}) {
    if (offset < 0 || offset + length > bytes.length) {
      return null;
    }

    final gainType = _getBitAlignedNumber(bytes, offset, 0, 3);
    if (gainType <= ReplayGainNameCode.notSet) {
      return null;
    }

    final sign = _getBitAlignedNumber(bytes, offset, 6, 1);
    final gainAdj = _getBitAlignedNumber(bytes, offset, 7, 9) / 10.0;

    return ReplayGainData(
      type: gainType,
      origin: _getBitAlignedNumber(bytes, offset, 3, 3),
      adjustment: sign == 1 ? -gainAdj : gainAdj,
    );
  }

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
