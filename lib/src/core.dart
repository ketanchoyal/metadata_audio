library;

import 'dart:async';
import 'dart:typed_data';

import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/parse_error.dart';
import 'package:audio_metadata/src/parser_factory.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

// Global parser factory instance (initialized by application code)
late ParserFactory _parserFactory;

/// Initialize the parser factory for public API entrypoints.
///
/// This must be called before using parseFile, parseBytes, parseStream, or parseBuffer.
/// Typically called by the application initialization code.
void initializeParserFactory(ParserFactory factory) {
  _parserFactory = factory;
}

/// Parse audio metadata from a file path.
///
/// Opens the file, creates a tokenizer, and delegates to parseFromTokenizer.
///
/// **Parameters:**
/// - `path`: File path to parse
/// - `options`: Parse options (optional, defaults to standard options)
///
/// **Throws:**
/// - `FileSystemException`: If file cannot be opened or read
/// - `TokenizerException`: If tokenizer operations fail
/// - `CouldNotDetermineFileTypeError`: If file format cannot be determined
/// - `UnrecognizedFormatError`: If format is recognized but parsing fails
///
/// **Example:**
/// ```dart
/// final metadata = await parseFile('music.mp3');
/// print(metadata.common.title);
/// ```
Future<AudioMetadata> parseFile(String path, {ParseOptions? options}) async {
  final tokenizer = FileTokenizer.fromPath(path);
  try {
    return await parseFromTokenizer(tokenizer, options: options);
  } finally {
    tokenizer.close();
  }
}

/// Parse audio metadata from a byte array.
///
/// Creates a BytesTokenizer from the bytes and delegates to parseFromTokenizer.
///
/// **Parameters:**
/// - `bytes`: Byte array containing audio data
/// - `fileInfo`: File information hint (optional)
/// - `options`: Parse options (optional)
///
/// **Throws:**
/// - `CouldNotDetermineFileTypeError`: If file format cannot be determined
/// - `UnrecognizedFormatError`: If format is recognized but parsing fails
///
/// **Example:**
/// ```dart
/// final bytes = await File('music.mp3').readAsBytes();
/// final metadata = await parseBytes(bytes);
/// print(metadata.common.artist);
/// ```
Future<AudioMetadata> parseBytes(
  Uint8List bytes, {
  FileInfo? fileInfo,
  ParseOptions? options,
}) async {
  final tokenizer = BytesTokenizer(bytes, fileInfo: fileInfo);
  return parseFromTokenizer(tokenizer, options: options);
}

/// Parse audio metadata from a stream of bytes.
///
/// Collects bytes from the stream into a buffer and delegates to parseBytes.
/// Note: This does NOT support formats requiring random access (seeking).
/// For such formats, use parseFile or parseBytes instead.
///
/// **Parameters:**
/// - `stream`: Stream of byte lists
/// - `fileInfo`: File information hint (optional)
/// - `options`: Parse options (optional)
///
/// **Throws:**
/// - `CouldNotDetermineFileTypeError`: If file format cannot be determined
/// - `UnrecognizedFormatError`: If format is recognized but parsing fails
///
/// **Example:**
/// ```dart
/// final stream = File('music.mp3').openRead();
/// final metadata = await parseStream(stream);
/// print(metadata.format.duration);
/// ```
Future<AudioMetadata> parseStream(
  Stream<List<int>> stream, {
  FileInfo? fileInfo,
  ParseOptions? options,
}) async {
  final chunks = <int>[];
  await for (final chunk in stream) {
    chunks.addAll(chunk);
  }
  return parseBytes(
    Uint8List.fromList(chunks),
    fileInfo: fileInfo,
    options: options,
  );
}

/// Deprecated: Use parseBytes instead.
///
/// This is an alias for parseBytes provided for upstream compatibility.
@deprecated
Future<AudioMetadata> parseBuffer(
  Uint8List bytes, {
  FileInfo? fileInfo,
  ParseOptions? options,
}) async => parseBytes(bytes, fileInfo: fileInfo, options: options);

/// Parse audio metadata from a tokenizer.
///
/// This is the core parsing function that all other entry points delegate to.
/// It uses the parser factory to select the appropriate parser and invoke it.
///
/// **Parameters:**
/// - `tokenizer`: Tokenizer providing access to audio data
/// - `options`: Parse options (optional, defaults to standard options)
///
/// **Throws:**
/// - `CouldNotDetermineFileTypeError`: If file format cannot be determined
/// - `UnrecognizedFormatError`: If format is recognized but parsing fails
/// - `TokenizerException`: If tokenizer operations fail
///
/// **Example:**
/// ```dart
/// final tokenizer = FileTokenizer.fromPath('music.mp3');
/// try {
///   final metadata = await parseFromTokenizer(tokenizer);
///   print(metadata.common.title);
/// } finally {
///   tokenizer.close();
/// }
/// ```
Future<AudioMetadata> parseFromTokenizer(
  Tokenizer tokenizer, {
  ParseOptions? options,
}) async {
  options ??= const ParseOptions();

  // Get file info from tokenizer, or create minimal info if not available
  final fileInfo = tokenizer.fileInfo ?? const FileInfo();

  // Select appropriate parser based on file info and tokenizer
  final parser = _parserFactory.selectParser(fileInfo, tokenizer);

  // Verify parser supports tokenizer capabilities
  if (!parser.supports(tokenizer)) {
    throw UnsupportedFileTypeError(
      'Parser requires random access, but tokenizer does not support seeking',
    );
  }

  // Parse metadata using selected parser
  final metadata = await parser.parse(tokenizer, options);

  // Scan for post-headers if applicable
  await scanPostHeaders(tokenizer, options);

  return metadata;
}

/// Scans for appending headers at the end of the audio file
///
/// When [skipPostHeaders] is false and the tokenizer supports random access,
/// this function scans the end of the file for post-headers (e.g., ID3v1 tags).
///
/// **Parameters:**
/// - `tokenizer`: The tokenizer providing access to file data
/// - `skipPostHeaders`: If true, skips the post-header scan entirely
///
/// **Behavior:**
/// - If `skipPostHeaders` is true: Returns immediately without scanning
/// - If tokenizer doesn't support seek (canSeek=false): Continues without post-scan
/// - If tokenizer supports seek: Performs post-header scan (actual detection delegated to format parsers)
///
/// **Returns:** null (placeholder for future return value if needed)
Future<void> scanPostHeaders(Tokenizer tokenizer, ParseOptions options) async {
  // Skip post-header scan if explicitly disabled
  if (options.skipPostHeaders) {
    return;
  }

  // Check if tokenizer supports random access
  if (!tokenizer.canSeek) {
    // Cannot perform post-header scan without seek capability
    return;
  }

  // Post-header scan is possible - tokenizer has random access
  // Placeholder for post-header scanning logic
  // Actual format-specific header detection (ID3v1, etc.) is delegated to format parsers
  // This ensures separation of concerns and allows each parser to define its own post-headers
}
