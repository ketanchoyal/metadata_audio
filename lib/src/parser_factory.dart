library;

import 'dart:typed_data';

import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parse_error.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

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
  ParserLoader? getLoader(String extension) => _extensionMap[extension.toLowerCase()];

  /// Get a parser loader by MIME type.
  ///
  /// Returns the registered loader for [mimeType], or null if no loader
  /// is registered for this MIME type.
  /// MIME type matching is case-sensitive.
  ParserLoader? getLoaderForMimeType(String mimeType) => _mimeTypeMap[mimeType];

  /// Get all registered file extensions.
  ///
  /// Returns a sorted list of all extensions that have registered loaders.
  List<String> getRegisteredExtensions() => _extensionMap.keys.toList()..sort();

  /// Get all registered MIME types.
  ///
  /// Returns a sorted list of all MIME types that have registered loaders.
  List<String> getRegisteredMimeTypes() => _mimeTypeMap.keys.toList()..sort();

  /// Returns a list of supported MIME-types.
  ///
  /// Includes `x-` prefixed variants for each registered MIME type, matching
  /// upstream `music-metadata` behaviour.
  List<String> getSupportedMimeTypes() {
    final mimeTypeSet = <String>{};
    for (final mimeType in _mimeTypeMap.keys) {
      mimeTypeSet.add(mimeType);
      mimeTypeSet.add(mimeType.replaceFirst('/', '/x-'));
    }
    final result = mimeTypeSet.toList()..sort();
    return result;
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

  /// Create a ParserFactory with the given registry.
  ParserFactory(this.registry);
  /// Parser registry containing registered loaders.
  final ParserRegistry registry;

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

    // Priority 3: Content sniffing via magic bytes
    final sniffed = _sniffParser(tokenizer);
    if (sniffed != null) {
      return sniffed;
    }

    // If we reach here, no parser was found
    throw CouldNotDetermineFileTypeError(
      'Could not determine file type from MIME type, extension, or content',
    );
  }

  /// Returns a list of supported MIME-types.
  List<String> getSupportedMimeTypes() => registry.getSupportedMimeTypes();

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

  /// Attempt to determine a parser by inspecting magic bytes.
  ///
  /// Returns the registered loader matching the detected MIME type, or null
  /// when the content cannot be identified.
  ParserLoader? _sniffParser(Tokenizer tokenizer) {
    final bytes = _peekAvailableBytes(tokenizer);
    if (bytes.isEmpty) {
      return null;
    }

    final mimeType = _detectMimeType(bytes);
    if (mimeType == null) {
      return null;
    }

    return registry.getLoaderForMimeType(mimeType);
  }

  /// Read as many leading bytes as the tokenizer can provide without
  /// advancing its position.
  Uint8List _peekAvailableBytes(Tokenizer tokenizer) {
    const candidateSizes = <int>[4096, 1024, 256, 64, 16, 8, 4, 1];
    for (final size in candidateSizes) {
      try {
        return Uint8List.fromList(tokenizer.peekBytes(size));
      } catch (_) {
        // Try a smaller read.
      }
    }
    return Uint8List(0);
  }

  /// Best-effort MIME type detection from leading magic bytes.
  String? _detectMimeType(Uint8List bytes) {
    if (bytes.length >= 4) {
      // EBML / Matroska / WebM
      if (bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3) {
        return 'audio/matroska';
      }
      // FLAC
      if (bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43) {
        return 'audio/flac';
      }
      // Ogg
      if (bytes[0] == 0x4F && bytes[1] == 0x67 && bytes[2] == 0x67 && bytes[3] == 0x53) {
        return 'audio/ogg';
      }
      // WAV / RIFF
      if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
          bytes.length >= 12 &&
          bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45) {
        return 'audio/wav';
      }
      // AIFF
      if (bytes[0] == 0x46 && bytes[1] == 0x4F && bytes[2] == 0x52 && bytes[3] == 0x4D &&
          bytes.length >= 12 &&
          (bytes[8] == 0x41 && bytes[9] == 0x49 && bytes[10] == 0x46 && bytes[11] == 0x46)) {
        return 'audio/aiff';
      }
      // ASF
      if (bytes.length >= 16 &&
          bytes[0] == 0x30 && bytes[1] == 0x26 && bytes[2] == 0xB2 && bytes[3] == 0x75 &&
          bytes[4] == 0x8E && bytes[5] == 0x66 && bytes[6] == 0xCF && bytes[7] == 0x11) {
        return 'audio/x-ms-asf';
      }
      // MP4 / QuickTime (ftyp at offset 4)
      if (bytes.length >= 8 &&
          bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
        return 'audio/mp4';
      }
      // APE
      if ((bytes[0] == 0x4D && bytes[1] == 0x41 && bytes[2] == 0x43 && bytes[3] == 0x20) ||
          (bytes.length >= 8 &&
              bytes[0] == 0x41 && bytes[1] == 0x50 && bytes[2] == 0x45 && bytes[3] == 0x54 &&
              bytes[4] == 0x41 && bytes[5] == 0x47 && bytes[6] == 0x45 && bytes[7] == 0x58)) {
        return 'audio/ape';
      }
      // Musepack SV8
      if (bytes[0] == 0x4D && bytes[1] == 0x50 && bytes[2] == 0x43 && bytes[3] == 0x4B) {
        return 'audio/musepack';
      }
      // WavPack
      if (bytes[0] == 0x77 && bytes[1] == 0x76 && bytes[2] == 0x70 && bytes[3] == 0x6B) {
        return 'audio/wavpack';
      }
      // DSF
      if (bytes[0] == 0x44 && bytes[1] == 0x53 && bytes[2] == 0x44 && bytes[3] == 0x20) {
        return 'audio/dsf';
      }
      // DSDIFF
      if (bytes[0] == 0x46 && bytes[1] == 0x52 && bytes[2] == 0x4D && bytes[3] == 0x38) {
        return 'audio/dsd';
      }
      // ID3v2 tag
      if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
        return 'audio/mpeg';
      }
    }

    // MPEG frame sync (MP3 / ADTS)
    if (bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
      return 'audio/mpeg';
    }

    return null;
  }
}
