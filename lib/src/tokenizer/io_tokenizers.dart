library;

import 'dart:io';

import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

// Re-export BytesTokenizer for backward compatibility.
// New code should import bytes_tokenizer.dart directly.
export 'bytes_tokenizer.dart' show BytesTokenizer;

/// Tokenizer implementation for file-based audio data using dart:io
///
/// Provides random-access reading from files with support for:
/// - Sequential reading (readUint8, readBytes, etc.)
/// - Random seeking (seek, canSeek = true)
/// - Peeking without advancing position
/// - Efficient RandomAccessFile operations
class FileTokenizer extends Tokenizer {

  /// Create a FileTokenizer from a file path
  ///
  /// Throws [FileSystemException] if file doesn't exist or can't be opened
  /// Throws [TokenizerException] if file size can't be determined
  FileTokenizer.fromPath(String filePath)
    : _file = File(filePath).openSync(),
      fileInfo = _createFileInfo(filePath) {
    _validateFile();
  }

  /// Create a FileTokenizer from a File object
  ///
  /// Throws [FileSystemException] if file can't be opened
  /// Throws [TokenizerException] if file size can't be determined
  FileTokenizer.fromFile(File file)
    : _file = file.openSync(),
      fileInfo = _createFileInfo(file.path) {
    _validateFile();
  }
  /// Underlying file handle for random access operations
  final RandomAccessFile _file;

  /// File information metadata
  @override
  final FileInfo? fileInfo;

  /// Current read position in bytes
  int _position = 0;

  /// Cache for peek operations (single byte)
  int? _peekedByte;

  /// Flag indicating if a byte has been peeked
  bool _hasPeekedByte = false;

  /// Close the underlying file handle
  ///
  /// After closing, all operations will fail.
  void close() {
    _file.closeSync();
  }

  @override
  int get position => _position;

  @override
  bool get canSeek => true;

  @override
  int readUint8() {
    if (_hasPeekedByte) {
      _hasPeekedByte = false;
      final byte = _peekedByte!;
      _position++;
      _peekedByte = null;
      return byte;
    }

    if (_isEOF) {
      throw TokenizerException('End of file reached');
    }

    try {
      _file.setPositionSync(_position);
      final byte = _file.readByteSync();
      _position++;
      return byte;
    } on FileSystemException catch (e) {
      throw TokenizerException('Failed to read byte: $e');
    }
  }

  @override
  int readUint16() {
    final byte1 = readUint8();
    final byte2 = readUint8();
    return (byte1 << 8) | byte2;
  }

  @override
  int readUint32() {
    final byte1 = readUint8();
    final byte2 = readUint8();
    final byte3 = readUint8();
    final byte4 = readUint8();
    return (byte1 << 24) | (byte2 << 16) | (byte3 << 8) | byte4;
  }

  @override
  List<int> readBytes(int length) {
    if (length < 0) {
      throw TokenizerException('Cannot read negative number of bytes');
    }

    if (length == 0) {
      return [];
    }

    final result = <int>[];

    // If we have a peeked byte and length > 0, use it
    if (_hasPeekedByte) {
      result.add(_peekedByte!);
      _hasPeekedByte = false;
      _peekedByte = null;
      _position++;

      if (result.length == length) {
        return result;
      }
    }

    // Read remaining bytes
    final remaining = length - result.length;
    if (_position + remaining > _fileSize) {
      throw TokenizerException(
        'Not enough bytes available: requested $length, '
        'only ${_fileSize - _position + result.length} available',
      );
    }

    try {
      _file.setPositionSync(_position);
      final bytes = _file.readSync(remaining);
      _position += bytes.length;
      result.addAll(bytes);
    } on FileSystemException catch (e) {
      throw TokenizerException('Failed to read bytes: $e');
    }

    return result;
  }

  @override
  int peekUint8() {
    if (_hasPeekedByte) {
      return _peekedByte!;
    }

    if (_isEOF) {
      throw TokenizerException('End of file reached');
    }

    try {
      _file.setPositionSync(_position);
      final byte = _file.readByteSync();
      _peekedByte = byte;
      _hasPeekedByte = true;
      return byte;
    } on FileSystemException catch (e) {
      throw TokenizerException('Failed to peek byte: $e');
    }
  }

  @override
  List<int> peekBytes(int length) {
    if (length < 0) {
      throw TokenizerException('Cannot peek negative number of bytes');
    }

    if (length == 0) {
      return [];
    }

    if (_position + length > _fileSize) {
      throw TokenizerException(
        'Not enough bytes available for peek: requested $length, '
        'only ${_fileSize - _position} available',
      );
    }

    try {
      _file.setPositionSync(_position);
      final bytes = _file.readSync(length);
      return bytes;
    } on FileSystemException catch (e) {
      throw TokenizerException('Failed to peek bytes: $e');
    }
  }

  @override
  void skip(int length) {
    if (length < 0) {
      throw TokenizerException('Cannot skip negative number of bytes');
    }

    if (length == 0) {
      return;
    }

    var remaining = length;
    if (_hasPeekedByte && remaining > 0) {
      _hasPeekedByte = false;
      _peekedByte = null;
      _position++;
      remaining--;
    }

    if (_position + remaining > _fileSize) {
      throw TokenizerException(
        'Cannot skip $length bytes: '
        'only ${_fileSize - _position} bytes available',
      );
    }

    _position += remaining;
  }

  @override
  void seek(int newPosition) {
    if (newPosition < 0 || newPosition > _fileSize) {
      throw TokenizerException(
        'Invalid seek position: $newPosition (file size: $_fileSize)',
      );
    }

    _position = newPosition;
    _hasPeekedByte = false;
    _peekedByte = null;
  }

  /// Create FileInfo from file path
  static FileInfo? _createFileInfo(String filePath) {
    try {
      final file = File(filePath);
      final stat = file.statSync();
      return FileInfo(
        path: filePath,
        size: stat.size,
        mimeType: _guessMimeType(filePath),
      );
    } on FileSystemException {
      // If we can't get file stats, return minimal info
      return FileInfo(path: filePath);
    }
  }

  /// Guess MIME type from file extension
  static String? _guessMimeType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    const mimeTypes = {
      'mp3': 'audio/mpeg',
      'flac': 'audio/flac',
      'ogg': 'audio/ogg',
      'mp4': 'audio/mp4',
      'wav': 'audio/wav',
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
      'opus': 'audio/opus',
      'wma': 'audio/x-ms-wma',
      'ape': 'audio/x-ape',
    };
    return mimeTypes[ext];
  }

  /// Validate file is readable and get size
  void _validateFile() {
    try {
      _file.lengthSync();
    } on FileSystemException catch (e) {
      _file.closeSync();
      throw TokenizerException('Cannot read file: $e');
    }
  }

  /// Get the total file size in bytes
  int get _fileSize {
    try {
      return _file.lengthSync();
    } on FileSystemException catch (e) {
      throw TokenizerException('Cannot determine file size: $e');
    }
  }

  /// Check if current position is at end of file
  bool get _isEOF => _position >= _fileSize;
}


