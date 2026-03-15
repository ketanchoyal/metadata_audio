library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/ebml/types.dart';
import 'package:metadata_audio/src/parse_error.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

/// EBML parser content error.
class EbmlContentError extends UnexpectedFileContentError {
  /// Creates an [EbmlContentError].
  EbmlContentError(String message) : super('EBML', message);
}

/// Extensible Binary Meta Language (EBML) iterator.
class EbmlIterator {
  /// Creates an [EbmlIterator].
  EbmlIterator(this._tokenizer);

  final Tokenizer _tokenizer;

  static const int _ebmlMaxIDLength = 4;
  static const int _ebmlMaxSizeLength = 8;

  /// Iterate over EBML elements using [dtdElement] definitions.
  Future<EbmlTree> iterate(
    EbmlElementType dtdElement,
    int posDone,
    EbmlElementListener listener,
  ) async => _parseContainer(linkParents(dtdElement), posDone, listener);

  Future<EbmlTree> _parseContainer(
    LinkedEbmlElementType dtdElement,
    int posDone,
    EbmlElementListener listener,
  ) async {
    final tree = <String, Object?>{};

    while (posDone < 0 || _tokenizer.position < posDone) {
      final elementPosition = _tokenizer.position;
      final EbmlHeader element;
      try {
        element = _readElement();
      } on TokenizerException catch (error) {
        if (_isEndOfStream(error)) {
          break;
        }
        rethrow;
      }

      final child = dtdElement.container?[element.id];
      if (child == null) {
        _skipUnknownElement(element);
        continue;
      }

      final action = listener.startNext(child);
      switch (action) {
        case ParseAction.readNext:
          await _readKnownElement(
            tree: tree,
            child: child,
            element: element,
            elementPosition: elementPosition,
            listener: listener,
          );
          break;
        case ParseAction.skipElement:
          break;
        case ParseAction.ignoreElement:
          _tokenizer.skip(element.len);
          break;
        case ParseAction.skipSiblings:
          if (posDone >= 0) {
            _tokenizer.skip(posDone - _tokenizer.position);
          }
          break;
        case ParseAction.terminateParsing:
          return tree;
      }
    }

    return tree;
  }

  Future<void> _readKnownElement({
    required EbmlTree tree,
    required LinkedEbmlElementType child,
    required EbmlHeader element,
    required int elementPosition,
    required EbmlElementListener listener,
  }) async {
    if (child.container != null) {
      final nestedPosDone = element.len >= 0
          ? _tokenizer.position + element.len
          : -1;
      final nestedTree = await _parseContainer(child, nestedPosDone, listener);

      if (child.multiple) {
        final existing = tree[child.name];
        final collection = existing is List<EbmlTree>
            ? <EbmlTree>[...existing]
            : <EbmlTree>[];
        final updated = <EbmlTree>[...collection, nestedTree];
        tree[child.name] = updated;
      } else {
        tree[child.name] = nestedTree;
      }

      await listener.elementValue(child, nestedTree, elementPosition);
      return;
    }

    final valueType = child.value;
    if (valueType == null) {
      _tokenizer.skip(element.len);
      return;
    }

    final value = _readElementValue(valueType, element);
    tree[child.name] = value;
    await listener.elementValue(child, value, elementPosition);
  }

  EbmlValue _readElementValue(EbmlDataType dataType, EbmlHeader header) {
    switch (dataType) {
      case EbmlDataType.uint:
        return _readUint(header);
      case EbmlDataType.string:
        return _readString(header);
      case EbmlDataType.binary:
      case EbmlDataType.uid:
        return _readBuffer(header);
      case EbmlDataType.bool:
        return _readFlag(header);
      case EbmlDataType.float:
        return _readFloat(header);
    }
  }

  void _skipUnknownElement(EbmlHeader element) {
    switch (element.id) {
      case 0xec:
        _tokenizer.skip(element.len);
        return;
      default:
        _tokenizer.skip(element.len);
    }
  }

  Uint8List _readVintData(int maxLength) {
    final msb = _tokenizer.peekUint8();
    var mask = 0x80;
    var octets = 1;

    while ((msb & mask) == 0) {
      if (octets > maxLength) {
        throw EbmlContentError('VINT value exceeding maximum size');
      }
      octets++;
      mask >>= 1;
    }

    return Uint8List.fromList(_tokenizer.readBytes(octets));
  }

  EbmlHeader _readElement() {
    final id = _readVintData(_ebmlMaxIDLength);
    final lenField = _readVintData(_ebmlMaxSizeLength);
    lenField[0] ^= 0x80 >> (lenField.length - 1);

    return EbmlHeader(
      id: _readUIntBE(id, id.length),
      len: _readUIntBE(lenField, lenField.length),
    );
  }

  double _readFloat(EbmlHeader header) {
    switch (header.len) {
      case 0:
        return 0;
      case 4:
        final bytes = _readBuffer(header);
        return ByteData.sublistView(bytes).getFloat32(0);
      case 8:
        final bytes = _readBuffer(header);
        return ByteData.sublistView(bytes).getFloat64(0);
      case 10:
        final bytes = _readBuffer(header);
        final truncated = Uint8List.sublistView(bytes, 0, 8);
        return ByteData.sublistView(truncated).getFloat64(0);
      default:
        throw EbmlContentError('Invalid IEEE-754 float length: ${header.len}');
    }
  }

  bool _readFlag(EbmlHeader header) => _readUint(header) == 1;

  int _readUint(EbmlHeader header) {
    final data = _readBuffer(header);
    return _readUIntBE(data, header.len);
  }

  String _readString(EbmlHeader header) {
    final bytes = _readBuffer(header);
    final zeroIndex = bytes.indexOf(0);
    final payload = zeroIndex >= 0 ? bytes.sublist(0, zeroIndex) : bytes;
    return utf8.decode(payload, allowMalformed: true);
  }

  Uint8List _readBuffer(EbmlHeader header) =>
      Uint8List.fromList(_tokenizer.readBytes(header.len));

  bool _isEndOfStream(TokenizerException error) =>
      error.message.startsWith('End of file') ||
      error.message.startsWith('End of data');

  int _readUIntBE(Uint8List bytes, int len) {
    if (len > 8) {
      return -1;
    }

    var value = BigInt.zero;
    for (var i = 0; i < len; i++) {
      value = (value << 8) | BigInt.from(bytes[i]);
    }
    return value.toInt();
  }
}
