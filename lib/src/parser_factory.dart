library;

import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/parse_error.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

/// Contract for lazily loading and invoking an audio metadata parser.
///
/// A parser loader declares which extensions and MIME types it can handle,
/// whether it requires random access, and how it parses metadata from a
/// tokenizer.
abstract class ParserLoader {
  /// File extensions this parser handles (without leading dot), for example
  /// `mp3`, `flac`.
  List<String> get extension;

  /// MIME types this parser handles, for example `audio/mpeg`.
  List<String> get mimeType;

  /// Whether this parser requires random access support from the tokenizer.
  bool get hasRandomAccessRequirements;

  /// Returns true if [tokenizer] capabilities satisfy parser requirements.
  ///
  /// By default, this enforces [hasRandomAccessRequirements] against
  /// [Tokenizer.canSeek].
  bool supports(Tokenizer tokenizer) =>
      !hasRandomAccessRequirements || tokenizer.canSeek;

  /// Parse metadata from [tokenizer] using [options].
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options);
}

/// Registry that maintains a map of parser loaders by extension and MIME type.
///
/// Provides methods to:
/// - Register parser loaders
/// - Lookup loaders by file extension
/// - Lookup loaders by MIME type
/// - List all registered extensions
class ParserRegistry {
  /// Map of file extensions (lowercase) to their parser loaders.
  final Map<String, ParserLoader> _extensionMap = {};

  /// Map of MIME types to their parser loaders.
  final Map<String, ParserLoader> _mimeTypeMap = {};

  /// Register a parser loader for its supported extensions and MIME types.
  ///
  /// The loader's extensions and MIME types are added to the registry.
  /// If an extension or MIME type is already registered, it is overwritten.
  void register(ParserLoader loader) {
    // Register by extensions (normalize to lowercase)
    for (final ext in loader.extension) {
      _extensionMap[ext.toLowerCase()] = loader;
    }

    // Register by MIME types
    for (final mimeType in loader.mimeType) {
      _mimeTypeMap[mimeType] = loader;
    }
  }

  /// Get a parser loader by file extension.
  ///
  /// Returns the registered loader for [extension], or null if no loader
  /// is registered for this extension.
  /// Extension matching is case-insensitive.
  ParserLoader? getLoader(String extension) {
    return _extensionMap[extension.toLowerCase()];
  }

  /// Get a parser loader by MIME type.
  ///
  /// Returns the registered loader for [mimeType], or null if no loader
  /// is registered for this MIME type.
  /// MIME type matching is case-sensitive.
  ParserLoader? getLoaderForMimeType(String mimeType) {
    return _mimeTypeMap[mimeType];
  }

  /// Get all registered file extensions.
  ///
  /// Returns a sorted list of all extensions that have registered loaders.
  List<String> getRegisteredExtensions() {
    return _extensionMap.keys.toList()..sort();
  }

  /// Get all registered MIME types.
  ///
  /// Returns a sorted list of all MIME types that have registered loaders.
  List<String> getRegisteredMimeTypes() {
    return _mimeTypeMap.keys.toList()..sort();
  }
}

/// Factory for selecting and retrieving appropriate parser loaders.
///
/// Implements parser selection precedence:
/// 1. MIME type (highest priority)
/// 2. File extension (second priority)
/// 3. Content sniffing (fallback)
///
/// Throws [CouldNotDetermineFileTypeError] if no parser can be determined.
class ParserFactory {
  /// Parser registry containing registered loaders.
  final ParserRegistry registry;

  /// Create a ParserFactory with the given registry.
  ParserFactory(this.registry);

  /// Select a parser loader based on FileInfo and tokenizer.
  ///
  /// Selection precedence:
  /// 1. If [fileInfo.mimeType] is set, use MIME type lookup
  /// 2. Else if [fileInfo.path] has an extension, use extension lookup
  /// 3. Else use content sniffing via [tokenizer]
  ///
  /// Throws [CouldNotDetermineFileTypeError] if no parser is found.
  ParserLoader selectParser(FileInfo fileInfo, Tokenizer tokenizer) {
    // Priority 1: MIME type
    if (fileInfo.mimeType != null && fileInfo.mimeType!.isNotEmpty) {
      final loader = registry.getLoaderForMimeType(fileInfo.mimeType!);
      if (loader != null) {
        return loader;
      }
    }

    // Priority 2: File extension
    if (fileInfo.path != null && fileInfo.path!.isNotEmpty) {
      final extension = _extractExtension(fileInfo.path!);
      if (extension != null && extension.isNotEmpty) {
        final loader = registry.getLoader(extension);
        if (loader != null) {
          return loader;
        }
      }
    }

    // Priority 3: Content sniffing (placeholder for now)
    // TODO: Implement actual content sniffing in T033
    _attemptContentSniffing(tokenizer);

    // If we reach here, no parser was found
    throw CouldNotDetermineFileTypeError(
      'Could not determine file type from MIME type, extension, or content',
    );
  }

  /// Extract file extension from a file path.
  ///
  /// Returns the extension without the leading dot, normalized to lowercase.
  /// Returns null if no extension is found.
  String? _extractExtension(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot <= 0 || lastDot == path.length - 1) {
      return null;
    }
    return path.substring(lastDot + 1).toLowerCase();
  }

  /// Placeholder for content sniffing implementation.
  ///
  /// This method peeks at the tokenizer's magic bytes to determine file type.
  /// Currently unimplemented; will be completed in T033.
  void _attemptContentSniffing(Tokenizer tokenizer) {
    // TODO: Implement content sniffing by peeking magic bytes
    // This will be implemented in task T033
  }
}
