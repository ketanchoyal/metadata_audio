library;

/// Metadata event observer callback type
///
/// Called with incremental metadata updates during parsing
typedef MetadataObserver = void Function(MetadataEvent event);

/// Information about the audio file being parsed
///
/// Corresponds to the FileInfo concept used for parsing hints
class FileInfo {
  /// File path of the audio file
  final String? path;

  /// MIME type hint for the audio file
  ///
  /// Example: 'audio/mpeg', 'audio/flac'
  final String? mimeType;

  /// File size in bytes
  final int? size;

  /// Source URL if the audio data comes from a stream or remote source
  final String? url;

  /// Create FileInfo from file metadata
  const FileInfo({this.path, this.mimeType, this.size, this.url});

  /// Create FileInfo from a local file path
  factory FileInfo.fromPath(String path) => FileInfo(path: path);

  /// Create FileInfo from a URL
  factory FileInfo.fromUrl(String url) => FileInfo(url: url);

  /// Create FileInfo with MIME type hint
  factory FileInfo.withMimeType(String? path, String mimeType) =>
      FileInfo(path: path, mimeType: mimeType);
}

/// Options for parsing audio metadata
///
/// Controls parsing behavior and what metadata to extract
class ParseOptions {
  /// Skip reading cover art / picture tags
  ///
  /// Default: false
  final bool skipCovers;

  /// Skip searching for headers after initial metadata
  ///
  /// Useful for streaming scenarios
  /// Default: false
  final bool skipPostHeaders;

  /// Include chapter information if available
  ///
  /// Default: false
  final bool includeChapters;

  /// Calculate/parse duration information
  ///
  /// May require parsing the entire file
  /// Default: false
  final bool duration;

  /// Observer callback for incremental metadata updates
  ///
  /// Called as metadata is discovered during parsing
  final MetadataObserver? observer;

  /// Create ParseOptions with custom parsing configuration
  const ParseOptions({
    this.skipCovers = false,
    this.skipPostHeaders = false,
    this.includeChapters = false,
    this.duration = false,
    this.observer,
  });

  /// Create ParseOptions with all parsing enabled
  factory ParseOptions.all({MetadataObserver? observer}) =>
      ParseOptions(includeChapters: true, duration: true, observer: observer);

  /// Create ParseOptions for minimal parsing (fast mode)
  factory ParseOptions.minimal() =>
      const ParseOptions(skipCovers: true, skipPostHeaders: true);

  /// Create ParseOptions for metadata-only parsing
  factory ParseOptions.metadataOnly() =>
      const ParseOptions(skipPostHeaders: true);
}

/// Event representing a metadata change during parsing
class MetadataEvent {
  /// Create a metadata event
  const MetadataEvent();
}
