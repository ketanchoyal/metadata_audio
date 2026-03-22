library;

import 'dart:convert';

import 'package:metadata_audio/src/id3v2/id3v2_token.dart';
import 'package:metadata_audio/src/model/types.dart';

class FrameParser {
  const FrameParser(this.majorVersion, {this.warningCollector});
  final Id3v2MajorVersion majorVersion;
  final void Function(String warning)? warningCollector;

  dynamic readData(
    List<int> bytes,
    String frameId, {
    bool includeCovers = true,
  }) {
    if (bytes.isEmpty) {
      warningCollector?.call(
        'ID3v2.$majorVersion frame $frameId has empty payload',
      );
      return null;
    }

    final normalizedType = frameId != 'TXXX' && frameId.startsWith('T')
        ? 'T*'
        : frameId;
    switch (normalizedType) {
      case 'T*':
      case 'GRP1':
      case 'GP1':
      case 'IPLS':
      case 'MVIN':
      case 'MVNM':
      case 'PCS':
      case 'PCST':
        return _parseTextFrame(bytes, frameId);

      case 'TXXX':
        return _parseUserTextFrame(bytes, frameId);

      case 'COMM':
      case 'COM':
        return _parseCommentFrame(bytes);

      case 'APIC':
      case 'PIC':
        if (!includeCovers) {
          return null;
        }
        return _parseAttachedPicture(bytes, frameId);

      case 'UFID':
        return _parseUfidFrame(bytes);

      default:
        return null;
    }
  }

  dynamic _parseTextFrame(List<int> bytes, String frameId) {
    final encoding = ID3v2Token.textEncodingFromByte(bytes[0]);
    final decoded = _trimNullPadding(_decodeString(bytes.sublist(1), encoding));

    switch (frameId) {
      case 'TRK':
      case 'TRCK':
      case 'TPOS':
      case 'TIT1':
      case 'TIT2':
      case 'TIT3':
        return decoded;
      default:
        return _splitValue(frameId, decoded);
    }
  }

  Map<String, dynamic> _parseUserTextFrame(List<int> bytes, String frameId) {
    final encoding = ID3v2Token.textEncodingFromByte(bytes[0]);
    final payload = bytes.sublist(1);
    final identifierAndData = _readIdentifierAndData(payload, encoding);
    final text = _decodeString(
      identifierAndData.data,
      encoding,
    ).replaceAll(RegExp(r'\x00+$'), '');

    return {
      'description': identifierAndData.id,
      'text': _splitValue(frameId, text),
    };
  }

  Comment _parseCommentFrame(List<int> bytes) {
    final header = ID3v2Token.parseTextHeader(bytes);
    var offset = 4;

    final descriptorValue = _readNullTerminatedString(
      bytes.sublist(offset),
      header.encoding,
    );
    offset += descriptorValue.len;

    final textValue = _readNullTerminatedString(
      bytes.sublist(offset),
      header.encoding,
    );

    return Comment(
      language: header.language,
      descriptor: descriptorValue.text,
      text: textValue.text,
    );
  }

  Picture _parseAttachedPicture(List<int> bytes, String frameId) {
    final encoding = ID3v2Token.textEncodingFromByte(bytes[0]);
    var offset = 1;
    String mimeType;

    if (frameId == 'PIC' || majorVersion == 2) {
      if (bytes.length < offset + 3) {
        throw const Id3v2ContentError('PIC frame too short for image format');
      }
      mimeType = latin1.decode(bytes.sublist(offset, offset + 3));
      offset += 3;
    } else {
      final mimeValue = _readNullTerminatedString(
        bytes.sublist(offset),
        const TextEncodingInfo(encoding: 'latin1'),
      );
      mimeType = mimeValue.text;
      offset += mimeValue.len;
    }

    if (bytes.length <= offset) {
      throw const Id3v2ContentError('APIC frame missing picture type');
    }
    final pictureTypeByte = bytes[offset++];

    final descriptionValue = _readNullTerminatedString(
      bytes.sublist(offset),
      encoding,
    );
    offset += descriptionValue.len;

    final imageData = offset <= bytes.length ? bytes.sublist(offset) : <int>[];

    return Picture(
      format: _fixPictureMimeType(mimeType),
      type: ID3v2Token.attachedPictureType[pictureTypeByte],
      description: descriptionValue.text,
      data: imageData,
    );
  }

  Map<String, dynamic> _parseUfidFrame(List<int> bytes) {
    // Find null terminator for owner identifier
    final nullIndex = bytes.indexWhere((b) => b == 0);
    if (nullIndex <= 0) {
      return {'owner': '', 'identifier': <int>[]};
    }

    final owner = latin1.decode(bytes.sublist(0, nullIndex));
    final identifier = bytes.sublist(nullIndex + 1);

    return {'owner': owner, 'identifier': identifier};
  }

  List<String> _splitValue(String frameId, String text) {
    List<String> values;
    if (majorVersion < 4) {
      values = text.split('\u0000');
      if (values.length > 1) {
        warningCollector?.call(
          'ID3v2.$majorVersion $frameId uses non-standard null separator',
        );
      } else {
        values = text.split('/');
      }
    } else {
      values = text.split('\u0000');
    }

    return values.map((value) => _trimNullPadding(value).trim()).toList();
  }

  _NullTerminatedText _readNullTerminatedString(
    List<int> bytes,
    TextEncodingInfo encoding,
  ) {
    final bomSize = encoding.bom ? 2 : 0;
    final valueBytes = bomSize > 0 && bytes.length >= bomSize
        ? bytes.sublist(bomSize)
        : bytes;
    final zeroIndex = _findZero(valueBytes, encoding.encoding);

    if (zeroIndex >= valueBytes.length) {
      return _NullTerminatedText(
        text: _decodeString(valueBytes, encoding),
        len: bytes.length,
      );
    }

    final txtBytes = valueBytes.sublist(0, zeroIndex);
    final len = bomSize + zeroIndex + _nullTerminatorLength(encoding.encoding);

    return _NullTerminatedText(
      text: _decodeString(txtBytes, encoding),
      len: len,
    );
  }

  _IdentifierAndData _readIdentifierAndData(
    List<int> bytes,
    TextEncodingInfo encoding,
  ) {
    final id = _readNullTerminatedString(bytes, encoding);
    return _IdentifierAndData(id: id.text, data: bytes.sublist(id.len));
  }

  static String _trimNullPadding(String value) {
    var end = value.length;
    while (end > 0 && value.codeUnitAt(end - 1) == 0) {
      end--;
    }
    return end == value.length ? value : value.substring(0, end);
  }

  static int _nullTerminatorLength(String encoding) =>
      encoding.startsWith('utf16') ? 2 : 1;

  static int _findZero(List<int> bytes, String encoding) {
    if (encoding.startsWith('utf16')) {
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        if (bytes[i] == 0 && bytes[i + 1] == 0) {
          return i;
        }
      }
      return bytes.length;
    }

    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0) {
        return i;
      }
    }
    return bytes.length;
  }

  static String _fixPictureMimeType(String mimeType) {
    final lower = mimeType.toLowerCase();
    switch (lower) {
      case 'jpg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return lower;
    }
  }

  static String _decodeString(List<int> bytes, TextEncodingInfo encoding) {
    if (bytes.isEmpty) {
      return '';
    }

    switch (encoding.encoding) {
      case 'latin1':
        return latin1.decode(bytes, allowInvalid: true);
      case 'utf8':
        return utf8.decode(bytes, allowMalformed: true);
      case 'utf16':
        return _decodeUtf16WithOptionalBom(bytes, expectBom: encoding.bom);
      case 'utf16be':
        return _decodeUtf16BigEndian(bytes);
      default:
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  static String _decodeUtf16WithOptionalBom(
    List<int> bytes, {
    required bool expectBom,
  }) {
    if (bytes.length < 2) {
      return '';
    }

    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16LittleEndian(bytes.sublist(2));
    }
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16BigEndian(bytes.sublist(2));
    }

    if (expectBom) {
      return _decodeUtf16LittleEndian(bytes);
    }
    return _decodeUtf16LittleEndian(bytes);
  }

  static String _decodeUtf16LittleEndian(List<int> bytes) {
    final codeUnits = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(codeUnits);
  }

  static String _decodeUtf16BigEndian(List<int> bytes) {
    final codeUnits = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      codeUnits.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(codeUnits);
  }
}

class _NullTerminatedText {
  const _NullTerminatedText({required this.text, required this.len});
  final String text;
  final int len;
}

class _IdentifierAndData {
  const _IdentifierAndData({required this.id, required this.data});
  final String id;
  final List<int> data;
}
