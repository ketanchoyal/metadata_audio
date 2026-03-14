library;

import 'package:audio_metadata/src/asf/asf_guid.dart';
import 'package:audio_metadata/src/asf/asf_util.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/parse_error.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

class AsfContentParseError extends UnexpectedFileContentError {
  AsfContentParseError(String message) : super('ASF', message);
}

class AsfNativeTag {
  const AsfNativeTag({required this.id, required this.value});

  final String id;
  final dynamic value;
}

class AsfObjectHeader {
  const AsfObjectHeader({required this.objectId, required this.objectSize});

  final AsfGuid objectId;
  final int objectSize;

  static const int length = 24;

  int get payloadSize => objectSize - length;

  static AsfObjectHeader parse(List<int> bytes) {
    if (bytes.length < length) {
      throw AsfContentParseError(
        'ASF object header requires $length bytes, got ${bytes.length}',
      );
    }

    return AsfObjectHeader(
      objectId: AsfGuid.fromBytes(bytes, 0),
      objectSize: readUint64Le(bytes, 16).toInt(),
    );
  }
}

class AsfTopLevelHeader extends AsfObjectHeader {
  const AsfTopLevelHeader({
    required super.objectId,
    required super.objectSize,
    required this.numberOfHeaderObjects,
  });

  final int numberOfHeaderObjects;

  static const int length = 30;

  static AsfTopLevelHeader parse(List<int> bytes) {
    if (bytes.length < length) {
      throw AsfContentParseError(
        'ASF top-level header requires $length bytes, got ${bytes.length}',
      );
    }

    return AsfTopLevelHeader(
      objectId: AsfGuid.fromBytes(bytes, 0),
      objectSize: readUint64Le(bytes, 16).toInt(),
      numberOfHeaderObjects: readUint32Le(bytes, 24),
    );
  }
}

class AsfFilePropertiesObject {
  const AsfFilePropertiesObject({
    required this.playDuration,
    required this.preroll,
    required this.maximumBitrate,
  });

  final BigInt playDuration;
  final BigInt preroll;
  final int maximumBitrate;

  static AsfFilePropertiesObject parse(List<int> bytes) {
    if (bytes.length < 80) {
      throw AsfContentParseError(
        'File Properties payload must be >= 80 bytes, got ${bytes.length}',
      );
    }

    return AsfFilePropertiesObject(
      playDuration: readUint64Le(bytes, 40),
      preroll: readUint64Le(bytes, 56),
      maximumBitrate: readUint32Le(bytes, 76),
    );
  }
}

class AsfStreamPropertiesObject {
  const AsfStreamPropertiesObject({
    required this.streamType,
    required this.errorCorrectionType,
  });

  final String? streamType;
  final AsfGuid errorCorrectionType;

  static AsfStreamPropertiesObject parse(List<int> bytes) {
    if (bytes.length < 32) {
      throw AsfContentParseError(
        'Stream Properties payload must be >= 32 bytes, got ${bytes.length}',
      );
    }

    final mediaTypeGuid = AsfGuid.fromBytes(bytes, 0);

    return AsfStreamPropertiesObject(
      streamType: AsfGuid.decodeMediaType(mediaTypeGuid),
      errorCorrectionType: AsfGuid.fromBytes(bytes, 16),
    );
  }
}

class AsfHeaderExtensionObject {
  const AsfHeaderExtensionObject({
    required this.reserved1,
    required this.reserved2,
    required this.extensionDataSize,
  });

  final AsfGuid reserved1;
  final int reserved2;
  final int extensionDataSize;

  static const int length = 22;

  static AsfHeaderExtensionObject parse(List<int> bytes) {
    if (bytes.length < length) {
      throw AsfContentParseError(
        'Header Extension payload must be >= $length bytes, got ${bytes.length}',
      );
    }

    return AsfHeaderExtensionObject(
      reserved1: AsfGuid.fromBytes(bytes, 0),
      reserved2: readUint16Le(bytes, 16),
      extensionDataSize: readUint32Le(bytes, 18),
    );
  }
}

class AsfCodecEntry {
  const AsfCodecEntry({
    required this.isVideoCodec,
    required this.isAudioCodec,
    required this.codecName,
    required this.description,
    required this.information,
  });

  final bool isVideoCodec;
  final bool isAudioCodec;
  final String codecName;
  final String description;
  final List<int> information;
}

Future<List<AsfCodecEntry>> readCodecEntries(
  Tokenizer tokenizer,
  int payloadSize,
) async {
  if (payloadSize < 20) {
    throw AsfContentParseError(
      'Codec List payload must be >= 20 bytes, got $payloadSize',
    );
  }

  var remaining = payloadSize;
  final header = tokenizer.readBytes(20);
  remaining -= 20;
  final entryCount = readUint16Le(header, 16);

  final entries = <AsfCodecEntry>[];
  for (var i = 0; i < entryCount; i++) {
    if (remaining < 2) {
      throw AsfContentParseError('Codec entry header truncated');
    }

    final type = readUint16Le(tokenizer.readBytes(2), 0);
    remaining -= 2;

    final codecNameRes = _readCodecString(tokenizer);
    remaining -= codecNameRes.consumed;

    final descriptionRes = _readCodecString(tokenizer);
    remaining -= descriptionRes.consumed;

    if (remaining < 2) {
      throw AsfContentParseError('Codec information length missing');
    }
    final infoLength = readUint16Le(tokenizer.readBytes(2), 0);
    remaining -= 2;

    if (remaining < infoLength) {
      throw AsfContentParseError('Codec information truncated');
    }
    final information = tokenizer.readBytes(infoLength);
    remaining -= infoLength;

    entries.add(
      AsfCodecEntry(
        isVideoCodec: (type & 0x0001) != 0,
        isAudioCodec: (type & 0x0002) != 0,
        codecName: codecNameRes.value,
        description: descriptionRes.value,
        information: information,
      ),
    );
  }

  if (remaining > 0) {
    tokenizer.skip(remaining);
  }

  return entries;
}

List<AsfNativeTag> parseContentDescriptionObject(List<int> bytes) {
  if (bytes.length < 10) {
    throw AsfContentParseError(
      'Content Description payload must be >= 10 bytes, got ${bytes.length}',
    );
  }

  const names = <String>[
    'Title',
    'Author',
    'Copyright',
    'Description',
    'Rating',
  ];

  final tags = <AsfNativeTag>[];
  var pos = 10;
  for (var i = 0; i < names.length; i++) {
    final length = readUint16Le(bytes, i * 2);
    if (length <= 0) {
      continue;
    }
    if (pos + length > bytes.length) {
      throw AsfContentParseError('Content Description value exceeds payload');
    }

    tags.add(
      AsfNativeTag(
        id: names[i],
        value: parseUnicodeAttr(bytes.sublist(pos, pos + length)),
      ),
    );
    pos += length;
  }

  return tags;
}

List<AsfNativeTag> parseExtendedContentDescriptionObject(List<int> bytes) {
  if (bytes.length < 2) {
    throw AsfContentParseError(
      'Extended Content Description payload too short: ${bytes.length}',
    );
  }

  final tags = <AsfNativeTag>[];
  final attrCount = readUint16Le(bytes, 0);
  var pos = 2;

  for (var i = 0; i < attrCount; i++) {
    if (pos + 8 > bytes.length) {
      throw AsfContentParseError('Extended Content Description attribute cut');
    }

    final nameLen = readUint16Le(bytes, pos);
    pos += 2;
    if (pos + nameLen > bytes.length) {
      throw AsfContentParseError('Extended Content Description name cut');
    }
    final name = parseUnicodeAttr(bytes.sublist(pos, pos + nameLen));
    pos += nameLen;

    final valueType = readUint16Le(bytes, pos);
    pos += 2;
    final valueLen = readUint16Le(bytes, pos);
    pos += 2;

    if (pos + valueLen > bytes.length) {
      throw AsfContentParseError('Extended Content Description value cut');
    }
    final data = bytes.sublist(pos, pos + valueLen);
    pos += valueLen;

    tags.add(_postProcessTag(name, valueType, data));
  }

  return tags;
}

class AsfExtendedStreamPropertiesObject {
  const AsfExtendedStreamPropertiesObject();

  static AsfExtendedStreamPropertiesObject parse(List<int> bytes) {
    if (bytes.length < 64) {
      throw AsfContentParseError(
        'Extended Stream Properties payload too short: ${bytes.length}',
      );
    }
    return const AsfExtendedStreamPropertiesObject();
  }
}

List<AsfNativeTag> parseMetadataObject(List<int> bytes) {
  if (bytes.length < 2) {
    throw AsfContentParseError('Metadata payload too short: ${bytes.length}');
  }

  final tags = <AsfNativeTag>[];
  final recordCount = readUint16Le(bytes, 0);
  var pos = 2;

  for (var i = 0; i < recordCount; i++) {
    if (pos + 12 > bytes.length) {
      throw AsfContentParseError('Metadata description record cut');
    }

    pos += 4;
    final nameLen = readUint16Le(bytes, pos);
    pos += 2;
    final dataType = readUint16Le(bytes, pos);
    pos += 2;
    final dataLen = readUint32Le(bytes, pos);
    pos += 4;

    if (pos + nameLen > bytes.length) {
      throw AsfContentParseError('Metadata record name cut');
    }
    final name = parseUnicodeAttr(bytes.sublist(pos, pos + nameLen));
    pos += nameLen;

    if (pos + dataLen > bytes.length) {
      throw AsfContentParseError('Metadata record data cut');
    }
    final data = bytes.sublist(pos, pos + dataLen);
    pos += dataLen;

    tags.add(_postProcessTag(name, dataType, data));
  }

  return tags;
}

List<AsfNativeTag> parseMetadataLibraryObject(List<int> bytes) {
  return parseMetadataObject(bytes);
}

AsfNativeTag _postProcessTag(String name, int valueType, List<int> data) {
  if (name == 'WM/Picture') {
    return AsfNativeTag(id: name, value: parseWmPicture(data));
  }

  final parser = getParserForAttr(valueType);
  if (parser == null) {
    throw AsfContentParseError('Unexpected ASF attribute type: $valueType');
  }

  return AsfNativeTag(id: name, value: parser(data));
}

Picture parseWmPicture(List<int> bytes) {
  if (bytes.length < 7) {
    throw AsfContentParseError('WM/Picture payload too short: ${bytes.length}');
  }

  final typeId = bytes[0];
  final declaredSize = readUint32Le(bytes, 1);
  var offset = 5;

  final formatTerm = findUtf16LeNullTerminator(bytes, offset, bytes.length);
  final format = parseUnicodeAttr(bytes.sublist(offset, formatTerm));
  offset = formatTerm + 2;
  if (offset > bytes.length) {
    throw AsfContentParseError('WM/Picture format not null-terminated');
  }

  final descTerm = findUtf16LeNullTerminator(bytes, offset, bytes.length);
  final description = parseUnicodeAttr(bytes.sublist(offset, descTerm));
  offset = descTerm + 2;
  if (offset > bytes.length) {
    throw AsfContentParseError('WM/Picture description not null-terminated');
  }

  var imageData = bytes.sublist(offset);
  if (declaredSize <= imageData.length) {
    imageData = imageData.sublist(0, declaredSize);
  }

  return Picture(
    format: format.isEmpty ? 'application/octet-stream' : format,
    data: imageData,
    description: description.isEmpty ? null : description,
    name: description.isEmpty ? null : description,
    type: _pictureTypeFromId(typeId),
  );
}

String? _pictureTypeFromId(int typeId) {
  switch (typeId) {
    case 0:
      return 'Other';
    case 1:
      return '32x32 pixels file icon';
    case 2:
      return 'Other file icon';
    case 3:
      return 'Cover (front)';
    case 4:
      return 'Cover (back)';
    case 5:
      return 'Leaflet page';
    case 6:
      return 'Media';
    case 7:
      return 'Lead artist/lead performer/soloist';
    case 8:
      return 'Artist/performer';
    case 9:
      return 'Conductor';
    case 10:
      return 'Band/Orchestra';
    case 11:
      return 'Composer';
    case 12:
      return 'Lyricist/text writer';
    case 13:
      return 'Recording Location';
    case 14:
      return 'During recording';
    case 15:
      return 'During performance';
    case 16:
      return 'Movie/video screen capture';
    case 17:
      return 'A bright coloured fish';
    case 18:
      return 'Illustration';
    case 19:
      return 'Band/artist logotype';
    case 20:
      return 'Publisher/Studio logotype';
    default:
      return null;
  }
}

({String value, int consumed}) _readCodecString(Tokenizer tokenizer) {
  final rawLen = tokenizer.readBytes(2);
  final charLength = readUint16Le(rawLen, 0);
  if (charLength == 0) {
    return (value: '', consumed: 2);
  }

  final raw = tokenizer.readBytes(charLength * 2);
  return (value: parseUnicodeAttr(raw), consumed: 2 + (charLength * 2));
}
