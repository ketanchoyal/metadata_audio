library;

import 'dart:convert';

import 'package:metadata_audio/src/asf/asf_guid.dart';
import 'package:metadata_audio/src/asf/asf_util.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parse_error.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

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
      objectId: AsfGuid.fromBytes(bytes),
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
      objectId: AsfGuid.fromBytes(bytes),
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
    this.streamNumber,
    this.encrypted,
    this.codecId,
    this.audioChannels,
    this.audioSampleRate,
    this.audioBitDepth,
    this.audioAvgBytesPerSec,
    this.videoPixelWidth,
    this.videoPixelHeight,
    this.bitrate,
  });

  final String? streamType;
  final AsfGuid errorCorrectionType;

  /// Stream number, or null for the default stream (0)
  final int? streamNumber;

  /// Whether the content published in this stream is encrypted
  final bool? encrypted;

  /// ASF codec id: '0x0160' for audio (format tag), or the video FourCC
  final String? codecId;

  final int? audioChannels;
  final int? audioSampleRate;
  final int? audioBitDepth;

  /// Average bytes per second of the audio payload
  final int? audioAvgBytesPerSec;

  final int? videoPixelWidth;
  final int? videoPixelHeight;

  /// Bitrate in bits per second (audio payload based)
  final int? bitrate;

  static const int minimumPayloadLength = 54;

  static AsfStreamPropertiesObject parse(List<int> bytes) {
    if (bytes.length < minimumPayloadLength) {
      throw AsfContentParseError('Truncated Stream Properties Object');
    }

    final typeSpecificSize = readUint32Le(bytes, 40);
    final correctionSize = readUint32Le(bytes, 44);
    if (typeSpecificSize + correctionSize > bytes.length - 54) {
      throw AsfContentParseError(
        'ASF stream data exceeds Stream Properties Object payload',
      );
    }

    final flags = readUint16Le(bytes, 48);
    final streamType = AsfGuid.decodeMediaType(AsfGuid.fromBytes(bytes));
    final data = bytes.sublist(54);

    var codecId = '';
    int? channels;
    int? sampleRate;
    int? bitDepth;
    int? avgBytesPerSec;
    int? pixelWidth;
    int? pixelHeight;

    if (streamType == 'audio' && typeSpecificSize >= 16) {
      codecId = '0x${readUint16Le(data, 0).toRadixString(16).padLeft(4, '0')}';
      channels = readUint16Le(data, 2);
      sampleRate = readUint32Le(data, 4);
      bitDepth = readUint16Le(data, 14);
      avgBytesPerSec = readUint32Le(data, 8);
    } else if (streamType == 'video' && typeSpecificSize >= 11) {
      // ASF specification 9.2: DWORD width, DWORD height, BYTE flags,
      // WORD format size. The packed BITMAPINFOHEADER follows at +11 and
      // its compression DWORD (FourCC) is at +16 beyond that (+27 total).
      pixelWidth = readUint32Le(data, 0);
      pixelHeight = readUint32Le(data, 4);
      final formatSize = readUint16Le(data, 9);
      if (formatSize > typeSpecificSize - 11) {
        throw AsfContentParseError('ASF video format data exceeds stream data');
      }
      if (formatSize >= 20 && data.length >= 31) {
        codecId = ascii.decode(data.sublist(27, 31), allowInvalid: true);
      }
    }

    return AsfStreamPropertiesObject(
      streamType: streamType,
      errorCorrectionType: AsfGuid.fromBytes(bytes, 16),
      streamNumber: flags & 0x7f,
      encrypted: (flags & 0x8000) != 0,
      codecId: codecId.isEmpty ? null : codecId,
      audioChannels: channels,
      audioSampleRate: sampleRate,
      audioBitDepth: bitDepth,
      audioAvgBytesPerSec: avgBytesPerSec,
      videoPixelWidth: pixelWidth,
      videoPixelHeight: pixelHeight,
      bitrate: avgBytesPerSec != null && avgBytesPerSec > 0
          ? avgBytesPerSec * 8
          : null,
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
      reserved1: AsfGuid.fromBytes(bytes),
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
  const AsfExtendedStreamPropertiesObject({
    this.startTime = 0,
    this.endTime = 0,
    this.dataBitrate = 0,
    this.streamNumber,
    this.averageTimePerFrame = 0,
    this.streamName,
    this.streamProperties,
  });

  final int startTime;
  final int endTime;

  /// Data bitrate of the stream payload (bits per second)
  final int dataBitrate;
  final int? streamNumber;

  /// Average time per frame in 100-nanosecond units (video streams)
  final int averageTimePerFrame;
  final String? streamName;
  final AsfStreamPropertiesObject? streamProperties;

  static const int minimumPayloadLength = 64;

  static AsfExtendedStreamPropertiesObject parse(List<int> bytes) {
    if (bytes.length < minimumPayloadLength) {
      throw AsfContentParseError('Truncated Extended Stream Properties Object');
    }

    final streamNumber = readUint16Le(bytes, 48) & 0x7f;
    final averageTimePerFrame = readUint64Le(bytes, 52).toInt();
    final streamNameCount = readUint16Le(bytes, 60);
    final payloadExtensionCount = readUint16Le(bytes, 62);

    var cursor = 64;
    var streamName = '';

    for (var i = 0; i < streamNameCount; i++) {
      if (cursor + 2 > bytes.length) {
        throw AsfContentParseError(
          'ASF extended stream data exceeds object payload',
        );
      }
      final nameLength = readUint16Le(bytes, cursor);
      cursor += 2;
      if (cursor + nameLength > bytes.length) {
        throw AsfContentParseError(
          'ASF extended stream data exceeds object payload',
        );
      }
      if (streamName.isEmpty && nameLength > 0) {
        streamName = parseUnicodeAttr(
          bytes.sublist(cursor, cursor + nameLength),
        );
      }
      cursor += nameLength;
    }

    for (var i = 0; i < payloadExtensionCount; i++) {
      if (cursor + 18 > bytes.length) {
        throw AsfContentParseError(
          'ASF extended stream data exceeds object payload',
        );
      }
      final dataLength = readUint16Le(bytes, cursor + 16);
      cursor += 18 + dataLength;
    }

    AsfStreamPropertiesObject? streamProperties;
    if (bytes.length - cursor >= 54 &&
        AsfGuid.fromBytes(
          bytes.sublist(cursor),
        ).equals(AsfGuid.streamPropertiesObject)) {
      streamProperties = AsfStreamPropertiesObject.parse(bytes.sublist(cursor));
    }

    return AsfExtendedStreamPropertiesObject(
      startTime: readUint64Le(bytes, 0).toInt(),
      endTime: readUint64Le(bytes, 8).toInt(),
      dataBitrate: readUint32Le(bytes, 16),
      streamNumber: streamNumber,
      averageTimePerFrame: averageTimePerFrame,
      streamName: streamName.isEmpty ? null : streamName,
      streamProperties: streamProperties,
    );
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

List<AsfNativeTag> parseMetadataLibraryObject(List<int> bytes) =>
    parseMetadataObject(bytes);

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
  // type (1) + declared size (4) — matches upstream's minimum header check.
  if (bytes.length < 5) {
    throw AsfContentParseError('Truncated ASF picture header: ${bytes.length}');
  }

  final typeId = bytes[0];
  var offset = 5;

  final formatTerm = _findUtf16LeNullTerminator(bytes, offset);
  if (formatTerm < 0) {
    throw AsfContentParseError('Unterminated ASF picture MIME type');
  }
  final format = parseUnicodeAttr(bytes.sublist(offset, formatTerm));
  offset = formatTerm + 2;

  final descTerm = _findUtf16LeNullTerminator(bytes, offset);
  if (descTerm < 0) {
    throw AsfContentParseError('Unterminated ASF picture description');
  }
  final description = parseUnicodeAttr(bytes.sublist(offset, descTerm));
  offset = descTerm + 2;

  // The declared size is kept as reported; the image data is everything
  // after the description, mirroring upstream behaviour where a wrong or
  // zero declared size must not truncate the payload.
  final imageData = bytes.sublist(offset);

  return Picture(
    format: format.isEmpty ? 'application/octet-stream' : format,
    data: imageData,
    description: description.isEmpty ? null : description,
    name: description.isEmpty ? null : description,
    type: _pictureTypeFromId(typeId),
  );
}

/// Returns the index of the terminating 0x0000 of a UTF-16LE string, or -1
/// when the string is not terminated.
int _findUtf16LeNullTerminator(List<int> bytes, int start) {
  var index = start;
  while (index + 2 <= bytes.length) {
    final codeUnit = bytes[index] | (bytes[index + 1] << 8);
    if (codeUnit == 0) {
      return index;
    }
    index += 2;
  }
  return -1;
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
