library;

import 'dart:convert';

import 'package:audio_metadata/src/parse_error.dart';

class Mp4ContentError extends UnexpectedFileContentError {
  Mp4ContentError(String message) : super('MP4', message);
}

class AtomHeader {
  const AtomHeader({
    required this.length,
    required this.name,
    required this.headerLength,
  });

  final int length;
  final String name;
  final int headerLength;
}

class MvhdAtomData {
  const MvhdAtomData({
    required this.creationTime,
    required this.modificationTime,
    required this.timeScale,
    required this.duration,
  });

  final DateTime creationTime;
  final DateTime modificationTime;
  final int timeScale;
  final int duration;
}

class MdhdAtomData {
  const MdhdAtomData({required this.timeScale, required this.duration});

  final int timeScale;
  final int duration;
}

class SampleDescription {
  const SampleDescription({
    required this.dataFormat,
    required this.numberOfChannels,
    required this.bitsPerSample,
    required this.sampleRate,
  });

  final String dataFormat;
  final int? numberOfChannels;
  final int? bitsPerSample;
  final int? sampleRate;
}

class DataAtomType {
  const DataAtomType({required this.set, required this.type});

  final int set;
  final int type;
}

class DataAtom {
  const DataAtom({
    required this.type,
    required this.locale,
    required this.value,
  });

  final DataAtomType type;
  final int locale;
  final List<int> value;
}

class AtomToken {
  static const int headerLength = 8;

  static AtomHeader parseHeader(List<int> bytes) {
    if (bytes.length < headerLength) {
      throw Mp4ContentError('Invalid MP4 atom header length');
    }

    final length32 = readUint32Be(bytes, 0);
    final name = latin1.decode(bytes.sublist(4, 8), allowInvalid: true);

    return AtomHeader(length: length32, name: name, headerLength: headerLength);
  }

  static AtomHeader parseHeaderWithExtendedSize(List<int> bytes) {
    if (bytes.length < 16) {
      throw Mp4ContentError('Invalid MP4 extended atom header length');
    }

    final length32 = readUint32Be(bytes, 0);
    final name = latin1.decode(bytes.sublist(4, 8), allowInvalid: true);

    if (length32 != 1) {
      return AtomHeader(
        length: length32,
        name: name,
        headerLength: headerLength,
      );
    }

    final extendedLength = readUint64Be(bytes, 8);
    if (extendedLength > 0x7FFFFFFF) {
      throw Mp4ContentError('Atom too large for parser: $extendedLength bytes');
    }

    return AtomHeader(length: extendedLength, name: name, headerLength: 16);
  }

  static List<String> parseFtypBrands(List<int> bytes) {
    final brands = <String>[];
    var offset = 0;
    while (offset + 4 <= bytes.length) {
      final brand = ascii.decode(bytes.sublist(offset, offset + 4));
      final normalized = brand.replaceAll(RegExp(r'\W'), '');
      if (normalized.isNotEmpty) {
        brands.add(normalized);
      }
      offset += 4;
    }
    return brands;
  }

  static MvhdAtomData parseMvhd(List<int> bytes) {
    if (bytes.length < 24) {
      throw Mp4ContentError('mvhd atom payload too short');
    }

    final version = bytes[0];
    if (version == 1) {
      if (bytes.length < 32) {
        throw Mp4ContentError('mvhd version 1 payload too short');
      }
      final creation = readUint64Be(bytes, 4);
      final modification = readUint64Be(bytes, 12);
      final timeScale = readUint32Be(bytes, 20);
      final duration = readUint64Be(bytes, 24);
      return MvhdAtomData(
        creationTime: _macEpochToDate(creation),
        modificationTime: _macEpochToDate(modification),
        timeScale: timeScale,
        duration: duration,
      );
    }

    final creation = readUint32Be(bytes, 4);
    final modification = readUint32Be(bytes, 8);
    final timeScale = readUint32Be(bytes, 12);
    final duration = readUint32Be(bytes, 16);
    return MvhdAtomData(
      creationTime: _macEpochToDate(creation),
      modificationTime: _macEpochToDate(modification),
      timeScale: timeScale,
      duration: duration,
    );
  }

  static MdhdAtomData parseMdhd(List<int> bytes) {
    if (bytes.length < 24) {
      throw Mp4ContentError('mdhd atom payload too short');
    }

    final version = bytes[0];
    if (version == 1) {
      if (bytes.length < 36) {
        throw Mp4ContentError('mdhd version 1 payload too short');
      }
      return MdhdAtomData(
        timeScale: readUint32Be(bytes, 20),
        duration: readUint64Be(bytes, 24),
      );
    }

    return MdhdAtomData(
      timeScale: readUint32Be(bytes, 12),
      duration: readUint32Be(bytes, 16),
    );
  }

  static String parseHandlerType(List<int> bytes) {
    if (bytes.length < 12) {
      throw Mp4ContentError('hdlr atom payload too short');
    }
    return ascii.decode(bytes.sublist(8, 12), allowInvalid: true);
  }

  static List<SampleDescription> parseStsd(List<int> bytes) {
    if (bytes.length < 8) {
      throw Mp4ContentError('stsd atom payload too short');
    }

    final entryCount = readUint32Be(bytes, 4);
    final descriptions = <SampleDescription>[];
    var offset = 8;

    for (var i = 0; i < entryCount; i++) {
      if (offset + 8 > bytes.length) {
        throw Mp4ContentError('stsd entry header out of bounds');
      }
      final entrySize = readUint32Be(bytes, offset);
      if (entrySize < 8 || offset + entrySize > bytes.length) {
        throw Mp4ContentError('Invalid stsd entry size: $entrySize');
      }

      final format = ascii.decode(
        bytes.sublist(offset + 4, offset + 8),
        allowInvalid: true,
      );

      int? channels;
      int? bitsPerSample;
      int? sampleRate;

      final sampleEntryOffset = offset + 8;
      final sampleEntryLength = entrySize - 8;
      if (sampleEntryLength >= 28) {
        channels = readUint16Be(bytes, sampleEntryOffset + 16);
        bitsPerSample = readUint16Be(bytes, sampleEntryOffset + 18);
        sampleRate = readUint32Be(bytes, sampleEntryOffset + 24) >> 16;
      }

      descriptions.add(
        SampleDescription(
          dataFormat: format,
          numberOfChannels: channels,
          bitsPerSample: bitsPerSample,
          sampleRate: sampleRate,
        ),
      );

      offset += entrySize;
    }

    return descriptions;
  }

  static DataAtom parseDataAtom(List<int> bytes) {
    if (bytes.length < 8) {
      throw Mp4ContentError('data atom payload too short');
    }

    return DataAtom(
      type: DataAtomType(set: bytes[0], type: readUint24Be(bytes, 1)),
      locale: readUint32Be(bytes, 4),
      value: bytes.sublist(8),
    );
  }

  static String parseNameAtom(List<int> bytes) {
    if (bytes.length < 4) {
      return '';
    }
    return utf8.decode(bytes.sublist(4), allowMalformed: true);
  }

  static int readUint16Be(List<int> bytes, int offset) {
    _ensureRange(bytes, offset, 2);
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  static int readUint24Be(List<int> bytes, int offset) {
    _ensureRange(bytes, offset, 3);
    return (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
  }

  static int readUint32Be(List<int> bytes, int offset) {
    _ensureRange(bytes, offset, 4);
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  static int readUint64Be(List<int> bytes, int offset) {
    _ensureRange(bytes, offset, 8);
    final value =
        (BigInt.from(bytes[offset]) << 56) |
        (BigInt.from(bytes[offset + 1]) << 48) |
        (BigInt.from(bytes[offset + 2]) << 40) |
        (BigInt.from(bytes[offset + 3]) << 32) |
        (BigInt.from(bytes[offset + 4]) << 24) |
        (BigInt.from(bytes[offset + 5]) << 16) |
        (BigInt.from(bytes[offset + 6]) << 8) |
        BigInt.from(bytes[offset + 7]);
    if (value > BigInt.from(0x7FFFFFFF)) {
      throw Mp4ContentError('64-bit integer overflow for parser runtime');
    }
    return value.toInt();
  }

  static DateTime _macEpochToDate(int secondsSinceMacEpoch) {
    const macToUnixEpochSeconds = 2082844800;
    final unixSeconds = secondsSinceMacEpoch - macToUnixEpochSeconds;
    return DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);
  }

  static void _ensureRange(List<int> bytes, int offset, int length) {
    if (offset < 0 || offset + length > bytes.length) {
      throw Mp4ContentError('Requested token range is out of bounds');
    }
  }
}
