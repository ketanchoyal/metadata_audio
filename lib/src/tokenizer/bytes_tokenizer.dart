library;

import 'dart:typed_data';

import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

/// Tokenizer implementation for in-memory byte data
///
/// Provides random-access reading from Uint8List buffers with support for:
/// - Sequential reading (readUint8, readBytes, etc.)
/// - Random seeking (seek, canSeek = true)
/// - Peeking without advancing position
/// - Efficient in-memory byte operations
class BytesTokenizer extends Tokenizer {

  /// Create a BytesTokenizer from a Uint8List
  ///
  /// [bytes]: The byte buffer to read from
  /// [fileInfo]: Optional file information (auto-created with buffer size if not provided)
  BytesTokenizer(Uint8List bytes, {FileInfo? fileInfo})
    : _bytes = bytes,
      fileInfo = fileInfo ?? FileInfo(size: bytes.length);
  /// Underlying byte buffer
  final Uint8List _bytes;

  /// File information metadata
  @override
  final FileInfo? fileInfo;

  /// Current read position in bytes
  int _position = 0;

  @override
  bool get canSeek => true;

  @override
  int get position => _position;

  @override
  int readUint8() {
    if (_position >= _bytes.length) {
      throw TokenizerException(
        'End of data reached: attempted to read at position $_position, buffer size ${_bytes.length}',
      );
    }
    return _bytes[_position++];
  }

  @override
  int readUint16() {
    if (_position + 1 >= _bytes.length) {
      throw TokenizerException(
        'Insufficient data to read uint16: need 2 bytes at position $_position, buffer size ${_bytes.length}',
      );
    }
    final value = (_bytes[_position] << 8) | _bytes[_position + 1];
    _position += 2;
    return value;
  }

  @override
  int readUint32() {
    if (_position + 3 >= _bytes.length) {
      throw TokenizerException(
        'Insufficient data to read uint32: need 4 bytes at position $_position, buffer size ${_bytes.length}',
      );
    }
    final value =
        (_bytes[_position] << 24) |
        (_bytes[_position + 1] << 16) |
        (_bytes[_position + 2] << 8) |
        _bytes[_position + 3];
    _position += 4;
    return value;
  }

  @override
  List<int> readBytes(int length) {
    if (_position + length > _bytes.length) {
      throw TokenizerException(
        'Insufficient data to read $length bytes: need ${_position + length} bytes total, buffer size ${_bytes.length}',
      );
    }
    final result = _bytes.sublist(_position, _position + length);
    _position += length;
    return result;
  }

  @override
  int peekUint8() {
    if (_position >= _bytes.length) {
      throw TokenizerException(
        'End of data reached: attempted to peek at position $_position, buffer size ${_bytes.length}',
      );
    }
    return _bytes[_position];
  }

  @override
  List<int> peekBytes(int length) {
    if (_position + length > _bytes.length) {
      throw TokenizerException(
        'Insufficient data to peek $length bytes: need ${_position + length} bytes total, buffer size ${_bytes.length}',
      );
    }
    return _bytes.sublist(_position, _position + length);
  }

  @override
  void skip(int length) {
    if (_position + length > _bytes.length) {
      throw TokenizerException(
        'Cannot skip $length bytes: need ${_position + length} bytes total, buffer size ${_bytes.length}',
      );
    }
    _position += length;
  }

  @override
  void seek(int position) {
    if (position < 0 || position > _bytes.length) {
      throw TokenizerException(
        'Invalid seek position: $position (buffer size ${_bytes.length})',
      );
    }
    _position = position;
  }
}