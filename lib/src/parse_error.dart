library;

/// Base exception class for all parsing errors.
///
/// This is the parent class for all music metadata parsing exceptions.
/// Specific error types extend this class to provide more detailed
/// error information.
abstract class ParseError implements Exception {
  /// Creates a new [ParseError] with the given [message].
  ParseError(this.message);

  /// The error message describing what went wrong
  final String message;

  /// The name of the specific error type
  String get name;

  @override
  String toString() => '$name: $message';
}

/// Error thrown when the file type cannot be determined.
///
/// This error occurs when the parser is unable to identify the file type
/// from its extension, magic bytes, or other identifying information.
class CouldNotDetermineFileTypeError extends ParseError {
  /// Creates a new [CouldNotDetermineFileTypeError] with the given
  /// [message].
  CouldNotDetermineFileTypeError(super.message);

  @override
  String get name => 'CouldNotDetermineFileTypeError';
}

/// Error thrown when the detected file type is not supported.
///
/// This error occurs when the file type is successfully identified,
/// but the parser does not have support for that particular format.
class UnsupportedFileTypeError extends ParseError {
  /// Creates a new [UnsupportedFileTypeError] with the given [message].
  UnsupportedFileTypeError(super.message);

  @override
  String get name => 'UnsupportedFileTypeError';
}

/// Error thrown when file content does not match the expected format.
///
/// This error occurs when the file content doesn't conform to the
/// expected structure for the detected file type. This typically indicates
/// file corruption or an incorrect file type identification.
class UnexpectedFileContentError extends ParseError {
  /// Creates a new [UnexpectedFileContentError] with the given [fileType]
  /// and [message].
  UnexpectedFileContentError(this.fileType, super.message);

  /// The file type that was expected
  final String fileType;

  @override
  String get name => 'UnexpectedFileContentError';

  @override
  String toString() => '$name (FileType: $fileType): $message';
}

/// Error thrown when a specific field cannot be decoded.
///
/// This error occurs when the parser encounters a field or tag that
/// cannot be properly decoded. This might happen due to invalid encoding,
/// malformed data, or unsupported field formats.
class FieldDecodingError extends ParseError {
  /// Creates a new [FieldDecodingError] with the given [message].
  FieldDecodingError(super.message);

  @override
  String get name => 'FieldDecodingError';
}

/// Error thrown for internal parser bugs.
///
/// This error indicates an unexpected condition within the parser itself
/// that should not occur during normal operation. This typically indicates
/// a bug in the parser implementation.
class InternalParserError extends ParseError {
  /// Creates a new [InternalParserError] with the given [message].
  InternalParserError(super.message);

  @override
  String get name => 'InternalParserError';
}
