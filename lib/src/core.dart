library;

import 'dart:async';
import 'dart:typed_data';

import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/parse_error.dart';
import 'package:audio_metadata/src/parser_factory.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

export 'package:audio_metadata/src/matroska/matroska_dtd.dart';
export 'package:audio_metadata/src/matroska/matroska_loader.dart';
export 'package:audio_metadata/src/matroska/matroska_parser.dart';
export 'package:audio_metadata/src/matroska/matroska_tag_mapper.dart';
export 'package:audio_metadata/src/matroska/types.dart';
export 'package:audio_metadata/src/musepack/musepack_content_error.dart';
export 'package:audio_metadata/src/musepack/musepack_loader.dart';
export 'package:audio_metadata/src/musepack/musepack_parser.dart';
export 'package:audio_metadata/src/musepack/sv7/bit_reader.dart';
export 'package:audio_metadata/src/musepack/sv7/mpc_sv7_parser.dart';
export 'package:audio_metadata/src/musepack/sv7/stream_version7.dart';
export 'package:audio_metadata/src/musepack/sv8/mpc_sv8_parser.dart';
export 'package:audio_metadata/src/musepack/sv8/stream_version8.dart';
export 'package:audio_metadata/src/wavpack/wavpack_loader.dart';
export 'package:audio_metadata/src/wavpack/wavpack_parser.dart';

export 'tokenizer/http_tokenizers.dart'
    show
        parseUrl,
        FileDownloadError,
        ParseStrategy,
        StrategyInfo,
        detectStrategy,
        HttpTokenizer,
        RangeTokenizer,
        RandomAccessTokenizer;

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

/// Group tags by ID in a map.
///
/// Organizes a list of tags into a Map where keys are tag IDs and values
/// are lists of tag values for that ID. This is useful for accessing all
/// values of a particular tag type.
///
/// **Parameters:**
/// - `tags`: List of tags to organize
///
/// **Returns:** Map<String, List<dynamic>> where keys are tag IDs
///
/// **Example:**
/// ```dart
/// final tags = [
///   Tag(id: 'TIT2', value: 'Song Title'),
///   Tag(id: 'TPE1', value: 'Artist Name'),
///   Tag(id: 'TIT2', value: 'Alt Title'),
/// ];
/// final grouped = orderTags(tags);
/// // grouped['TIT2'] = ['Song Title', 'Alt Title']
/// // grouped['TPE1'] = ['Artist Name']
/// ```
Map<String, List<dynamic>> orderTags(List<Tag> tags) {
  final result = <String, List<dynamic>>{};
  for (final tag in tags) {
    result.putIfAbsent(tag.id, () => []).add(tag.value);
  }
  return result;
}

/// Convert normalized rating (0-1) to star rating (1-5).
///
/// Maps a normalized rating value from 0.0 to 1.0 onto a 1-5 star scale.
/// Handles null values by returning null.
///
/// **Parameters:**
/// - `normalizedRating`: Rating value in range [0.0, 1.0], or null
///
/// **Returns:** Star rating in range [1, 5] as int, or null if input is null
///
/// **Mapping:**
/// - null → null
/// - 0.0 → 1 star
/// - 0.25 → 1-2 stars (rounded)
/// - 0.5 → 2-3 stars (rounded)
/// - 0.75 → 3-4 stars (rounded)
/// - 1.0 → 5 stars
///
/// **Example:**
/// ```dart
/// ratingToStars(0.0);   // returns 1
/// ratingToStars(0.5);   // returns 3
/// ratingToStars(1.0);   // returns 5
/// ratingToStars(null);  // returns null
/// ```
int? ratingToStars(double? normalizedRating) {
  if (normalizedRating == null) {
    return null;
  }
  // Map [0, 1] to [1, 5]
  return (normalizedRating * 4 + 1).round().clamp(1, 5);
}

/// Select the best cover art from a list of pictures.
///
/// Selects the most appropriate cover image from a list of pictures.
/// Prioritizes pictures with type='Cover', falls back to the first picture,
/// or returns null if the list is empty.
///
/// **Parameters:**
/// - `pictures`: List of Picture objects, or null
///
/// **Returns:** Best Picture object, or null if list is empty/null
///
/// **Selection logic:**
/// 1. Return first picture with type='Cover' if available
/// 2. Fall back to first picture in list
/// 3. Return null if list is empty or null
///
/// **Example:**
/// ```dart
/// final pictures = [
///   Picture(format: 'image/jpeg', data: [...], type: 'Back'),
///   Picture(format: 'image/jpeg', data: [...], type: 'Cover'),
///   Picture(format: 'image/png', data: [...], type: null),
/// ];
/// final cover = selectCover(pictures);
/// // Returns the picture with type='Cover'
/// ```
Picture? selectCover(List<Picture>? pictures) {
  if (pictures == null || pictures.isEmpty) {
    return null;
  }

  // Try to find a picture with type='Cover'
  try {
    return pictures.firstWhere((p) => p.type == 'Cover');
  } catch (_) {
    // No picture with type='Cover' found, return first picture
    return pictures.isNotEmpty ? pictures.first : null;
  }
}
