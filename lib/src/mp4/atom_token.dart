library;

import 'dart:convert';

import 'package:metadata_audio/src/common/js_safe_numbers.dart';
import 'package:metadata_audio/src/parse_error.dart';

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

class SttsEntry {
  const SttsEntry({required this.count, required this.duration});

  final int count;
  final int duration;
}

class StscEntry {
  const StscEntry({required this.firstChunk, required this.samplesPerChunk});

  final int firstChunk;
  final int samplesPerChunk;
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

    final extendedLength = _readUint64BeAsBigInt(bytes, 8);
    // Dart int is 64-bit on native and 53-bit safe on web (dart2js).
    // Guard against values that exceed the JS safe integer range so that
    // both platforms can represent the atom length accurately.
    if (extendedLength > BigInt.from(maxSafeJsInt)) {
      throw Mp4ContentError('Atom too large for parser: $extendedLength bytes');
    }

    return AtomHeader(
      length: extendedLength.toInt(),
      name: name,
      headerLength: 16,
    );
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
      final creation = _readUint64BeAsBigInt(bytes, 4);
      final modification = _readUint64BeAsBigInt(bytes, 12);
      final timeScale = readUint32Be(bytes, 20);
      final duration = _readUint64BeAsBigInt(bytes, 24);
      return MvhdAtomData(
        creationTime: _macEpochToDateBigInt(creation),
        modificationTime: _macEpochToDateBigInt(modification),
        timeScale: timeScale,
        duration: duration.toInt(),
      );
    }

    final creation = readUint32Be(bytes, 4);
    final modification = readUint32Be(bytes, 8);
    final timeScale = readUint32Be(bytes, 12);
    final duration = readUint32Be(bytes, 16);
    return MvhdAtomData(
      creationTime: _macEpochToDateInt(creation),
      modificationTime: _macEpochToDateInt(modification),
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
        duration: _readUint64BeAsBigInt(bytes, 24).toInt(),
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

  static List<SttsEntry> parseStts(List<int> bytes) {
    if (bytes.length < 8) {
      throw Mp4ContentError('stts atom payload too short');
    }

    final entryCount = readUint32Be(bytes, 4);
    final entries = <SttsEntry>[];
    var offset = 8;
    for (var i = 0; i < entryCount; i++) {
      _ensureRange(bytes, offset, 8);
      entries.add(
        SttsEntry(
          count: readUint32Be(bytes, offset),
          duration: readUint32Be(bytes, offset + 4),
        ),
      );
      offset += 8;
    }
    return entries;
  }

  static List<StscEntry> parseStsc(List<int> bytes) {
    if (bytes.length < 8) {
      throw Mp4ContentError('stsc atom payload too short');
    }

    final entryCount = readUint32Be(bytes, 4);
    final entries = <StscEntry>[];
    var offset = 8;
    for (var i = 0; i < entryCount; i++) {
      _ensureRange(bytes, offset, 12);
      entries.add(
        StscEntry(
          firstChunk: readUint32Be(bytes, offset),
          samplesPerChunk: readUint32Be(bytes, offset + 4),
        ),
      );
      offset += 12;
    }
    return entries;
  }

  static (int, List<int>) parseStsz(List<int> bytes) {
    if (bytes.length < 12) {
      throw Mp4ContentError('stsz atom payload too short');
    }

    final sampleSize = readUint32Be(bytes, 4);
    final entryCount = readUint32Be(bytes, 8);
    final entries = <int>[];
    var offset = 12;
    for (var i = 0; i < entryCount; i++) {
      _ensureRange(bytes, offset, 4);
      entries.add(readUint32Be(bytes, offset));
      offset += 4;
    }
    return (sampleSize, entries);
  }

  static List<int> parseStco(List<int> bytes) {
    if (bytes.length < 8) {
      throw Mp4ContentError('stco atom payload too short');
    }

    final entryCount = readUint32Be(bytes, 4);
    final entries = <int>[];
    var offset = 8;
    for (var i = 0; i < entryCount; i++) {
      _ensureRange(bytes, offset, 4);
      entries.add(readUint32Be(bytes, offset));
      offset += 4;
    }
    return entries;
  }

  static List<int> parseCo64(List<int> bytes) {
    if (bytes.length < 8) {
      throw Mp4ContentError('co64 atom payload too short');
    }

    final entryCount = readUint32Be(bytes, 4);
    final entries = <int>[];
    var offset = 8;
    for (var i = 0; i < entryCount; i++) {
      _ensureRange(bytes, offset, 8);
      entries.add(readUint64Be(bytes, offset));
      offset += 8;
    }
    return entries;
  }

  static String parseChapterText(List<int> bytes) {
    if (bytes.length < 2) {
      return '';
    }
    final titleLength = readUint16Be(bytes, 0);
    final availableLength = bytes.length - 2;
    final actualLength = titleLength > availableLength
        ? availableLength
        : titleLength;
    return utf8.decode(
      bytes.sublist(2, 2 + actualLength),
      allowMalformed: true,
    );
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
    final value = _readUint64BeAsBigInt(bytes, offset);
    if (value > maxSignedInt64) {
      throw Mp4ContentError('64-bit integer overflow for parser runtime');
    }
    return value.toInt();
  }

  static BigInt _readUint64BeAsBigInt(List<int> bytes, int offset) {
    _ensureRange(bytes, offset, 8);
    return (BigInt.from(bytes[offset]) << 56) |
        (BigInt.from(bytes[offset + 1]) << 48) |
        (BigInt.from(bytes[offset + 2]) << 40) |
        (BigInt.from(bytes[offset + 3]) << 32) |
        (BigInt.from(bytes[offset + 4]) << 24) |
        (BigInt.from(bytes[offset + 5]) << 16) |
        (BigInt.from(bytes[offset + 6]) << 8) |
        BigInt.from(bytes[offset + 7]);
  }

  static DateTime _macEpochToDateInt(int secondsSinceMacEpoch) =>
      _macEpochToDateBigInt(BigInt.from(secondsSinceMacEpoch));

  static DateTime _macEpochToDateBigInt(BigInt secondsSinceMacEpoch) {
    const macToUnixEpochSeconds = 2082844800;
    const maxDateTimeMilliseconds = 8640000000000000;
    const minDateTimeMilliseconds = -8640000000000000;
    final unixSeconds =
        secondsSinceMacEpoch - BigInt.from(macToUnixEpochSeconds);
    final milliseconds = unixSeconds * BigInt.from(1000);

    if (milliseconds > BigInt.from(maxDateTimeMilliseconds)) {
      return DateTime.fromMillisecondsSinceEpoch(
        maxDateTimeMilliseconds,
        isUtc: true,
      );
    }

    if (milliseconds < BigInt.from(minDateTimeMilliseconds)) {
      return DateTime.fromMillisecondsSinceEpoch(
        minDateTimeMilliseconds,
        isUtc: true,
      );
    }

    return DateTime.fromMillisecondsSinceEpoch(
      milliseconds.toInt(),
      isUtc: true,
    );
  }

  static void _ensureRange(List<int> bytes, int offset, int length) {
    if (offset < 0 || offset + length > bytes.length) {
      throw Mp4ContentError('Requested token range is out of bounds');
    }
  }
}
