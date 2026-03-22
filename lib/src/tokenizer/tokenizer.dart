library;

import 'package:metadata_audio/src/model/types.dart';

/// Exception thrown when attempting an unsupported operation on a tokenizer
class TokenizerException implements Exception {
  /// Create a TokenizerException
  TokenizerException(this.message);

  /// Error message
  final String message;

  @override
  String toString() => 'TokenizerException: $message';
}

/// Abstract base class for tokenizers that read and parse binary audio data
///
/// Tokenizers provide a sequential or random-access interface for reading
/// bytes from audio data sources. They expose capabilities (peek, seek)
/// to determine what operations are supported.
///
/// Corresponds to the tokenizer contract in the upstream music-metadata library.
abstract class Tokenizer {
  /// File information metadata about the source
  ///
  /// May be null for streams or in-memory data without file context.
  FileInfo? get fileInfo;

  /// Current position in the stream (in bytes)
  ///
  /// For sequential tokenizers, this advances with each read.
  /// For random-access tokenizers, this is the current seek position.
  int get position;

  /// Whether this tokenizer supports random access (seek operations)
  ///
  /// When true, [seek] can be used to move to arbitrary positions.
  /// When false, [seek] will throw [TokenizerException].
  bool get canSeek;

  /// Read a single byte (unsigned 8-bit integer) and advance position
  ///
  /// Throws [TokenizerException] if at end of data.
  int readUint8();

  /// Read 2 bytes (unsigned 16-bit integer, big-endian) and advance position
  ///
  /// Throws [TokenizerException] if fewer than 2 bytes available.
  int readUint16();

  /// Read 4 bytes (unsigned 32-bit integer, big-endian) and advance position
  ///
  /// Throws [TokenizerException] if fewer than 4 bytes available.
  int readUint32();

  /// Read N bytes and advance position
  ///
  /// Returns a list of exactly [length] bytes.
  /// Throws [TokenizerException] if fewer than [length] bytes available.
  List<int> readBytes(int length);

  /// Peek at a single byte (unsigned 8-bit integer) without advancing position
  ///
  /// Throws [TokenizerException] if at end of data.
  int peekUint8();

  /// Peek at N bytes without advancing position
  ///
  /// Returns a list of exactly [length] bytes at current position.
  /// Throws [TokenizerException] if fewer than [length] bytes available.
  List<int> peekBytes(int length);

  /// Skip N bytes forward (advance position)
  ///
  /// Equivalent to reading and discarding [length] bytes.
  /// Throws [TokenizerException] if fewer than [length] bytes available.
  void skip(int length);

  /// Seek to an absolute position
  ///
  /// Throws [TokenizerException] if [canSeek] is false.
  /// Throws [TokenizerException] if [position] is negative or beyond data end.
  void seek(int position);
}
