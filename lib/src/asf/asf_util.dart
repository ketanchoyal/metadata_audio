library;

import 'dart:convert';
import 'dart:typed_data';

typedef AsfAttributeParser = dynamic Function(List<int> bytes);

class AsfDataType {
  static const int unicodeString = 0;
  static const int byteArray = 1;
  static const int bool = 2;
  static const int dWord = 3;
  static const int qWord = 4;
  static const int word = 5;
}

AsfAttributeParser? getParserForAttr(int type) {
  switch (type) {
    case AsfDataType.unicodeString:
      return parseUnicodeAttr;
    case AsfDataType.byteArray:
      return parseByteArrayAttr;
    case AsfDataType.bool:
      return parseBoolAttr;
    case AsfDataType.dWord:
      return parseDWordAttr;
    case AsfDataType.qWord:
      return parseQWordAttr;
    case AsfDataType.word:
      return parseWordAttr;
    default:
      return null;
  }
}

String parseUnicodeAttr(List<int> bytes) {
  final text = decodeUtf16Le(bytes);
  return stripNulls(text);
}

List<int> parseByteArrayAttr(List<int> bytes) => List<int>.from(bytes);

bool parseBoolAttr(List<int> bytes) => parseWordAttr(bytes) == 1;

int parseDWordAttr(List<int> bytes) => readUint32Le(bytes, 0);

BigInt parseQWordAttr(List<int> bytes) => readUint64Le(bytes, 0);

int parseWordAttr(List<int> bytes) => readUint16Le(bytes, 0);

int readUint16Le(List<int> bytes, int offset) {
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  return view.getUint16(offset, Endian.little);
}

int readUint32Le(List<int> bytes, int offset) {
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  return view.getUint32(offset, Endian.little);
}

int readInt32Le(List<int> bytes, int offset) {
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  return view.getInt32(offset, Endian.little);
}

BigInt readUint64Le(List<int> bytes, int offset) {
  final lo = readUint32Le(bytes, offset);
  final hi = readUint32Le(bytes, offset + 4);
  return (BigInt.from(hi) << 32) | BigInt.from(lo);
}

String decodeUtf16Le(List<int> bytes) {
  if (bytes.isEmpty) {
    return '';
  }

  final unitCount = bytes.length ~/ 2;
  final codeUnits = List<int>.filled(unitCount, 0);
  for (var i = 0; i < unitCount; i++) {
    final lo = bytes[i * 2];
    final hi = bytes[i * 2 + 1];
    codeUnits[i] = lo | (hi << 8);
  }

  return String.fromCharCodes(codeUnits);
}

String stripNulls(String value) {
  var start = 0;
  var end = value.length;

  while (start < end && value.codeUnitAt(start) == 0) {
    start++;
  }
  while (end > start && value.codeUnitAt(end - 1) == 0) {
    end--;
  }

  return value.substring(start, end);
}

String readUtf16LeNullTerminated(List<int> bytes, int start, int maxExclusive) {
  if (start >= maxExclusive) {
    return '';
  }

  var i = start;
  while (i + 1 < maxExclusive) {
    if (bytes[i] == 0 && bytes[i + 1] == 0) {
      break;
    }
    i += 2;
  }

  return parseUnicodeAttr(bytes.sublist(start, i));
}

int findUtf16LeNullTerminator(List<int> bytes, int start, int maxExclusive) {
  var i = start;
  while (i + 1 < maxExclusive) {
    if (bytes[i] == 0 && bytes[i + 1] == 0) {
      return i;
    }
    i += 2;
  }
  return maxExclusive;
}

String readLatin1String(List<int> bytes) =>
    latin1.decode(bytes, allowInvalid: true);
