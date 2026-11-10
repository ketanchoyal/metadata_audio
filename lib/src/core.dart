library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/src/aiff/aiff_loader.dart';
import 'package:metadata_audio/src/apev2/apev2_loader.dart';
import 'package:metadata_audio/src/asf/asf_loader.dart';
import 'package:metadata_audio/src/caf/caf_loader.dart';
import 'package:metadata_audio/src/common/allocation.dart';
import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/dsdiff/dsdiff_loader.dart';
import 'package:metadata_audio/src/dsf/dsf_loader.dart';
import 'package:metadata_audio/src/flac/flac_loader.dart';
import 'package:metadata_audio/src/id3v1/id3v1_parser.dart';
import 'package:metadata_audio/src/id3v1/id3v1_tag_map.dart';
import 'package:metadata_audio/src/id3v2/id3v2_loader.dart';
import 'package:metadata_audio/src/id3v2/id3v2_parser.dart';
import 'package:metadata_audio/src/id3v2/id3v2_tag_map.dart';
import 'package:metadata_audio/src/matroska/matroska_loader.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/mp4/mp4_loader.dart';
import 'package:metadata_audio/src/mp4/mp4_parser.dart';
import 'package:metadata_audio/src/mpeg/mpeg_loader.dart';
import 'package:metadata_audio/src/musepack/musepack_loader.dart';
import 'package:metadata_audio/src/ogg/ogg_loader.dart';
import 'package:metadata_audio/src/parse_error.dart';
import 'package:metadata_audio/src/parser_factory.dart';
import 'package:metadata_audio/src/tokenizer/http_tokenizers.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:metadata_audio/src/utils/audio_metadata_cache.dart';
import 'package:metadata_audio/src/utils/audio_metadata_merge.dart';
import 'package:metadata_audio/src/utils/cache_types.dart';
import 'package:metadata_audio/src/wav/wave_loader.dart';
import 'package:metadata_audio/src/wavpack/wavpack_loader.dart';

export 'package:metadata_audio/src/aiff/aiff_loader.dart';
export 'package:metadata_audio/src/apev2/apev2_loader.dart';
export 'package:metadata_audio/src/asf/asf_loader.dart';
export 'package:metadata_audio/src/caf/caf_loader.dart';
export 'package:metadata_audio/src/dsdiff/dsdiff_loader.dart';
export 'package:metadata_audio/src/dsf/dsf_loader.dart';
export 'package:metadata_audio/src/flac/flac_loader.dart';
export 'package:metadata_audio/src/id3v2/id3v2_loader.dart';
export 'package:metadata_audio/src/matroska/matroska_dtd.dart';
export 'package:metadata_audio/src/matroska/matroska_loader.dart';
export 'package:metadata_audio/src/matroska/matroska_parser.dart';
export 'package:metadata_audio/src/matroska/matroska_tag_mapper.dart';
export 'package:metadata_audio/src/model/types.dart';
export 'package:metadata_audio/src/mp4/mp4_loader.dart';
export 'package:metadata_audio/src/mpeg/mpeg_loader.dart';
export 'package:metadata_audio/src/musepack/musepack_loader.dart';
export 'package:metadata_audio/src/ogg/ogg_loader.dart';
export 'package:metadata_audio/src/parse_error.dart';
export 'package:metadata_audio/src/parser_factory.dart';
export 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
export 'package:metadata_audio/src/tokenizer/tokenizer.dart';
export 'package:metadata_audio/src/wav/wave_loader.dart';
export 'package:metadata_audio/src/wavpack/wavpack_loader.dart';

export 'tokenizer/http_tokenizers.dart'
    show
        FileDownloadError,
        HttpTokenizer,
        ParseStrategy,
        ProbeStrategy,
        ProbingRangeTokenizer,
        RandomAccessTokenizer,
        RangeTokenizer,
        StrategyInfo,
        detectStrategy,
        parseUrl;

// Global parser factory instance
ParserFactory? _parserFactory;
bool _isInitialized = false;

/// Whether metadata caching is globally enabled across all parse calls.
///
/// Mirrors [AudioMetadataCache.enabled].
bool get cacheEnabled => AudioMetadataCache.enabled;

/// Globally enables or disables metadata caching across all parse calls.
///
/// When `true`, `parseFile`, `parseUrl`, `parseBytes`, `parseStream`, and
/// `parseFromTokenizer` cache and reuse parsed metadata by source URL/path
/// (even when [ParseOptions.useCache] is `false`).
// ignore: avoid_positional_boolean_parameters
set cacheEnabled(bool enabled) {
  AudioMetadataCache.enabled = enabled;
}

/// Initialize the parser factory for public API entrypoints.
///
/// This must be called before using parseFile, parseBytes, parseStream, or parseBuffer.
/// If not called explicitly, a default factory with all format loaders will be created
/// automatically on first use.
///
/// **Example:**
/// ```dart
/// // Option 1: Use default factory (automatic)
/// final metadata = await parseFile('music.mp3'); // Auto-initializes
///
/// // Option 2: Custom initialization
/// final registry = ParserRegistry()
///   ..register(MpegLoader())
///   ..register(FlacLoader());
/// initializeParserFactory(ParserFactory(registry));
/// final metadata = await parseFile('music.mp3');
/// ```
void initializeParserFactory(ParserFactory factory) {
  _parserFactory = factory;
  _isInitialized = true;
}

/// Create a default ParserFactory with all format loaders registered.
///
/// This registers loaders for all supported formats:
/// - MP3/MPEG (ID3v1, ID3v2)
/// - FLAC
/// - MP4/M4A
/// - OGG (Vorbis, Opus, Speex)
/// - WAV
/// - AIFF
/// - ASF/WMA
/// - APE
/// - Matroska/MKV
/// - Musepack
/// - WavPack
/// - DSD (DSF, DSDIFF)
ParserFactory createDefaultParserFactory() {
  final registry = ParserRegistry()
    ..register(FlacLoader())
    ..register(Mp4Loader())
    ..register(OggLoader())
    ..register(WaveLoader())
    ..register(AiffLoader())
    ..register(AsfLoader())
    ..register(Apev2Loader())
    ..register(MatroskaLoader())
    ..register(MusepackLoader())
    ..register(WavPackLoader())
    ..register(DsfLoader())
    ..register(DsdiffLoader())
    ..register(CafLoader())
    ..register(Id3v2Loader())
    ..register(MpegLoader());

  return ParserFactory(registry);
}

/// Ensures the parser factory is initialized.
///
/// If not already initialized, creates and sets a default factory
/// with all format loaders registered.
void _ensureInitialized() {
  if (!_isInitialized) {
    _parserFactory = createDefaultParserFactory();
    _isInitialized = true;
  }
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
  final effectiveOptions = options ?? const ParseOptions();
  final maxAllocation = getMaxMemoryAllocation(effectiveOptions);
  getMaxMetadataEntries(effectiveOptions);
  getMaxChapterCount(effectiveOptions);

  final entityType = await FileSystemEntity.type(path);
  if (entityType != FileSystemEntityType.notFound &&
      entityType != FileSystemEntityType.file) {
    throw NotRegularFileError('Not a regular file: $path');
  }

  final tokenizer = FileTokenizer.fromPath(path, maxBufferSize: maxAllocation);
  try {
    return await parseFromTokenizer(tokenizer, options: effectiveOptions);
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
  final effectiveOptions = options ?? const ParseOptions();
  final maxAllocation = getMaxMemoryAllocation(effectiveOptions);
  getMaxMetadataEntries(effectiveOptions);
  getMaxChapterCount(effectiveOptions);

  final tokenizer = BytesTokenizer(
    bytes,
    fileInfo: fileInfo,
    maxBufferSize: maxAllocation,
  );
  return parseFromTokenizer(tokenizer, options: effectiveOptions);
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
  final effectiveOptions = options ?? const ParseOptions();
  final maxAllocation = getMaxMemoryAllocation(effectiveOptions);
  final chunks = <int>[];
  await for (final chunk in stream) {
    if (chunks.length + chunk.length > maxAllocation) {
      throw TokenizerException(
        'Stream size exceeds maxMemoryAllocation ($maxAllocation bytes)',
      );
    }
    chunks.addAll(chunk);
  }
  return parseBytes(
    Uint8List.fromList(chunks),
    fileInfo: fileInfo,
    options: effectiveOptions,
  );
}

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
  // Ensure parser factory is initialized (auto-initialize if needed)
  _ensureInitialized();

  options ??= const ParseOptions();

  // Validate resource limits up front.
  final maxBufferSize = getMaxMemoryAllocation(options);
  getMaxMetadataEntries(options);
  getMaxChapterCount(options);

  final cacheKey = resolveCacheKey(tokenizer, options);
  if (cacheKey.isNotEmpty) {
    final cachedEntry = await AudioMetadataCache.getEntry(cacheKey);
    if (cachedEntry != null) {
      if (cachedEntry.coverage.satisfies(options, cachedEntry.metadata)) {
        final view = applyParseOptionsView(cachedEntry.metadata, options);
        if (options.observer != null) {
          emitCachedMetadataEvents(view, options.observer!);
        }
        return view;
      }

      // Partial cache hit: fetch only what is needed for newly enabled options
      // and merge with the cached metadata.
      final updatedEntry = await _resolveIncrementalFromTokenizer(
        tokenizer: tokenizer,
        cachedEntry: cachedEntry,
        requestedOptions: options,
        maxBufferSize: maxBufferSize,
      );
      await AudioMetadataCache.putEntry(
        cacheKey,
        updatedEntry,
        maxMemoryAllocation: maxBufferSize,
      );
      final view = applyParseOptionsView(updatedEntry.metadata, options);
      if (options.observer != null) {
        emitCachedMetadataEvents(view, options.observer!);
      }
      return view;
    }
  }

  final (:metadata, :hints) = await parseFromTokenizerWithHints(
    tokenizer,
    options: options,
  );

  // Persist to general metadata cache if opted in.
  if (cacheKey.isNotEmpty) {
    final entry = CachedMetadataEntry(
      metadata: metadata,
      coverage: CachedParseCoverage.fromOptions(options, metadata),
      hints: hints,
    );
    await AudioMetadataCache.putEntry(
      cacheKey,
      entry,
      maxMemoryAllocation: maxBufferSize,
    );
  }

  return metadata;
}

/// Executes an uncached parse from [tokenizer] and returns both the finalized
/// [AudioMetadata] and any [CachedParseHints] produced by the parser.
Future<({AudioMetadata metadata, CachedParseHints? hints})>
parseFromTokenizerWithHints(
  Tokenizer tokenizer, {
  required ParseOptions options,
}) async {
  _ensureInitialized();

  // Get file info from tokenizer, or create minimal info if not available
  final fileInfo = tokenizer.fileInfo ?? const FileInfo();

  // Apply allocation cap to tokenizers that support it.
  final maxBufferSize = getMaxMemoryAllocation(options);
  getMaxMetadataEntries(options);
  getMaxChapterCount(options);
  if (tokenizer is FileTokenizer) {
    tokenizer.maxBufferSize = maxBufferSize;
  } else if (tokenizer is BytesTokenizer) {
    tokenizer.maxBufferSize = maxBufferSize;
  } else if (tokenizer is HttpBasedTokenizer) {
    tokenizer.maxBufferSize = maxBufferSize;
  }

  // Select appropriate parser based on file info and tokenizer
  final parser = _parserFactory!.selectParser(fileInfo, tokenizer);

  // Verify parser supports tokenizer capabilities
  if (!parser.supports(tokenizer)) {
    throw const UnsupportedFileTypeError(
      'Parser requires random access, but tokenizer does not support seeking',
    );
  }

  // Parse metadata using selected parser
  final parsed = parser is HintProvidingParserLoader
      ? await parser.parseWithHints(tokenizer, options)
      : (metadata: await parser.parse(tokenizer, options), hints: null);
  final metadata = parsed.metadata;

  // Scan for post-headers if applicable
  await scanPostHeaders(tokenizer, options);

  // Finalize container-level duration/bitrate information when possible.
  final fileSize = tokenizer.fileInfo?.size;
  final result = finalizeContainerFormat(metadata, fileSize: fileSize);
  final hints =
      parsed.hints ??
      (fileSize != null ? CachedParseHints(fileSize: fileSize) : null);

  return (metadata: result, hints: hints);
}

/// Applies container-level `containerDuration` and `overallBitrate` fallbacks.
AudioMetadata finalizeContainerFormat(
  AudioMetadata metadata, {
  int? fileSize,
}) {
  final baseDuration =
      metadata.format.containerDuration ?? metadata.format.duration;
  var overallBitrate = metadata.format.overallBitrate;
  if (overallBitrate == null &&
      fileSize != null &&
      baseDuration != null &&
      baseDuration > 0) {
    overallBitrate = fileSize * 8 / baseDuration;
  }
  final containerDuration = metadata.format.containerDuration ?? baseDuration;

  if (containerDuration != metadata.format.containerDuration ||
      overallBitrate != metadata.format.overallBitrate) {
    final updatedFormat = metadata.format.copyWith(
      containerDuration: containerDuration,
      overallBitrate: overallBitrate,
    );
    return AudioMetadata(
      format: updatedFormat,
      native: metadata.native,
      common: metadata.common,
      quality: metadata.quality,
    );
  }
  return metadata;
}

Future<CachedMetadataEntry> _resolveIncrementalFromTokenizer({
  required Tokenizer tokenizer,
  required CachedMetadataEntry cachedEntry,
  required ParseOptions requestedOptions,
  required int maxBufferSize,
}) async {
  final missing = cachedEntry.coverage.missingRequirements(
    requestedOptions,
    cachedEntry.metadata,
  );
  final hints = cachedEntry.hints;
  final container = cachedEntry.metadata.format.container?.toLowerCase() ?? '';
  final isMpeg = container == 'mp3' || container == 'mpeg' || container == 'adts';
  final isMp4 =
      container.contains('mp4') ||
      container.contains('m4a') ||
      container.contains('m4b') ||
      container.contains('qt') ||
      container.contains('isom');

  // 1. Targeted MP4 chapter-only resolution using cached chapter track / chpl.
  if (missing.chapters &&
      !missing.covers &&
      !missing.duration &&
      !missing.higherEntryLimit &&
      !missing.mkvFullScan &&
      isMp4 &&
      hints?.mp4Chapters != null) {
    final mp4Chap = hints!.mp4Chapters!;
    if (!mp4Chap.hasChapterSource ||
        mp4Chap.chplPayload != null ||
        tokenizer.canSeek) {
      final resolved = await Mp4Parser.resolveChaptersFromCache(
        chapterInfo: mp4Chap,
        tokenizer: tokenizer,
        options: requestedOptions,
        fileDuration: cachedEntry.metadata.format.duration,
      );
      final mergedFormat = Format(
        container: cachedEntry.metadata.format.container,
        tagTypes: cachedEntry.metadata.format.tagTypes,
        duration: cachedEntry.metadata.format.duration,
        bitrate: cachedEntry.metadata.format.bitrate,
        sampleRate: cachedEntry.metadata.format.sampleRate,
        bitsPerSample: cachedEntry.metadata.format.bitsPerSample,
        tool: cachedEntry.metadata.format.tool,
        codec: cachedEntry.metadata.format.codec,
        codecProfile: cachedEntry.metadata.format.codecProfile,
        lossless: cachedEntry.metadata.format.lossless,
        numberOfChannels: cachedEntry.metadata.format.numberOfChannels,
        numberOfSamples: cachedEntry.metadata.format.numberOfSamples,
        audioMD5: cachedEntry.metadata.format.audioMD5,
        chapters: resolved.chapters,
        creationTime: cachedEntry.metadata.format.creationTime,
        modificationTime: cachedEntry.metadata.format.modificationTime,
        trackGain: cachedEntry.metadata.format.trackGain,
        trackPeakLevel: cachedEntry.metadata.format.trackPeakLevel,
        albumGain: cachedEntry.metadata.format.albumGain,
        hasAudio: cachedEntry.metadata.format.hasAudio,
        hasVideo: cachedEntry.metadata.format.hasVideo,
        trackInfo: cachedEntry.metadata.format.trackInfo,
        containerDuration: cachedEntry.metadata.format.containerDuration,
        overallBitrate: cachedEntry.metadata.format.overallBitrate,
      );
      final merged = AudioMetadata(
        format: mergedFormat,
        native: cachedEntry.metadata.native,
        common: cachedEntry.metadata.common,
        quality: QualityInformation(
          warnings: [
            ...cachedEntry.metadata.quality.warnings,
            ...resolved.warnings,
          ],
        ),
      );
      final updatedCoverage = cachedEntry.coverage.merge(
        CachedParseCoverage(
          hasChapters: true,
          hasPostHeaders: missing.postHeaders,
          maxChapterCount: getMaxChapterCount(requestedOptions),
        ),
        merged,
      );
      return CachedMetadataEntry(
        metadata: merged,
        coverage: updatedCoverage,
        hints: hints,
      );
    }
  }

  // 2. Post-headers only on non-MPEG formats requires no extra reads.
  if (missing.postHeaders &&
      !missing.chapters &&
      !missing.covers &&
      !missing.duration &&
      !missing.higherEntryLimit &&
      !missing.mkvFullScan &&
      !isMpeg) {
    return CachedMetadataEntry(
      metadata: cachedEntry.metadata,
      coverage: cachedEntry.coverage.merge(
        const CachedParseCoverage(hasPostHeaders: true),
        cachedEntry.metadata,
      ),
      hints: hints,
    );
  }

  // 3. Targeted ID3v1 post-header scan on seekable MPEG tokenizer.
  final fileSize = hints?.fileSize ?? tokenizer.fileInfo?.size;
  if (missing.postHeaders &&
      !missing.chapters &&
      !missing.covers &&
      !missing.duration &&
      !missing.higherEntryLimit &&
      !missing.mkvFullScan &&
      isMpeg &&
      tokenizer.canSeek &&
      fileSize != null &&
      fileSize >= 128) {
    final mapper = CombinedTagMapper()
      ..registerMapper('ID3v1', Id3v1TagMapper());
    final collector = MetadataCollector(mapper, requestedOptions);
    final id3v1 = Id3v1Parser(metadata: collector, tokenizer: tokenizer);
    await id3v1.parse();
    final deltaMeta = collector.toAudioMetadata();
    final merged = mergeAudioMetadata(
      existing: cachedEntry.metadata,
      delta: deltaMeta,
      preferExistingCommon: true,
    );
    return CachedMetadataEntry(
      metadata: merged,
      coverage: cachedEntry.coverage.merge(
        const CachedParseCoverage(hasPostHeaders: true),
        merged,
      ),
      hints: hints,
    );
  }

  // 4. Targeted ID3v2 header-only delta on seekable MPEG tokenizer.
  if ((missing.chapters || missing.covers) &&
      !missing.postHeaders &&
      !missing.duration &&
      !missing.higherEntryLimit &&
      !missing.mkvFullScan &&
      isMpeg &&
      hints?.id3v2Size != null &&
      tokenizer.canSeek) {
    final id3v2Size = hints!.id3v2Size!;
    if (id3v2Size == 0) {
      return CachedMetadataEntry(
        metadata: cachedEntry.metadata,
        coverage: cachedEntry.coverage.merge(
          CachedParseCoverage(
            hasChapters: missing.chapters,
            hasCovers: missing.covers,
            maxChapterCount: getMaxChapterCount(requestedOptions),
          ),
          cachedEntry.metadata,
        ),
        hints: hints,
      );
    }
    tokenizer.seek(0);
    final headerBytes = Uint8List.fromList(tokenizer.readBytes(id3v2Size));
    final headerTokenizer = BytesTokenizer(
      headerBytes,
      fileInfo: tokenizer.fileInfo,
      maxBufferSize: maxBufferSize,
    );
    final deltaOpts = missing.toDeltaOptions(requestedOptions);
    final mapper = CombinedTagMapper()
      ..registerMapper('ID3v2.2', Id3v2TagMapper())
      ..registerMapper('ID3v2.3', Id3v2TagMapper())
      ..registerMapper('ID3v2.4', Id3v2TagMapper());
    final collector = MetadataCollector(mapper, deltaOpts);
    await Id3v2Parser(
      metadata: collector,
      tokenizer: headerTokenizer,
      options: deltaOpts,
    ).parse();
    final merged = mergeAudioMetadata(
      existing: cachedEntry.metadata,
      delta: collector.toAudioMetadata(),
      replaceChapters: missing.chapters,
      replaceCovers: missing.covers,
    );
    return CachedMetadataEntry(
      metadata: merged,
      coverage: cachedEntry.coverage.merge(
        CachedParseCoverage.fromOptions(deltaOpts, merged),
        merged,
      ),
      hints: hints,
    );
  }

  // 5. General delta parse for any remaining format/option combination.
  final deltaOptions = (missing.higherEntryLimit || missing.mkvFullScan)
      ? requestedOptions
      : missing.toDeltaOptions(requestedOptions);
  if (tokenizer.canSeek && tokenizer.position != 0) {
    tokenizer.seek(0);
  }
  final (:metadata, hints: newHints) = await parseFromTokenizerWithHints(
    tokenizer,
    options: deltaOptions,
  );
  final merged = mergeAudioMetadata(
    existing: cachedEntry.metadata,
    delta: metadata,
    replaceChapters: missing.chapters || missing.higherEntryLimit,
    replaceCovers: missing.covers || missing.higherEntryLimit,
    replaceDuration: missing.duration || missing.higherEntryLimit,
  );
  final mergedHints = (hints ?? const CachedParseHints()).merge(newHints);
  final updatedCoverage = cachedEntry.coverage.merge(
    CachedParseCoverage.fromOptions(deltaOptions, metadata),
    merged,
  );
  return CachedMetadataEntry(
    metadata: merged,
    coverage: updatedCoverage,
    hints: mergedHints,
  );
}

/// Resolves the cache key for [tokenizer] when caching is enabled, or returns
/// `''` if caching is disabled / no source identifier is available.
///
/// The key uses only the explicit [ParseOptions.cacheKey] or the source
/// URL/path (never [ParseOptions] flags), enabling incremental reuse across
/// different option sets.
String resolveCacheKey(Tokenizer tokenizer, ParseOptions options) {
  if (options.cacheKey != null && options.cacheKey!.isNotEmpty) {
    return options.cacheKey!;
  }
  if (!options.useCache && !AudioMetadataCache.enabled) {
    return '';
  }
  final info = tokenizer.fileInfo;
  if (info?.url != null && info!.url!.isNotEmpty) {
    return 'url:${info.url}';
  }
  if (info?.path != null && info!.path!.isNotEmpty) {
    return 'path:${info.path}';
  }
  return '';
}

/// Resolves the cache key for a remote [url] when caching is enabled, or
/// returns `''` if caching is disabled.
String resolveUrlCacheKey(String url, ParseOptions options) {
  if (options.cacheKey != null && options.cacheKey!.isNotEmpty) {
    return options.cacheKey!;
  }
  if (!options.useCache && !AudioMetadataCache.enabled) {
    return '';
  }
  return 'url:$url';
}

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
/// **Returns:** `Map<String, List<dynamic>>` where keys are tag IDs
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

/// Return a list of supported MIME-types.
List<String> getSupportedMimeTypes() {
  _ensureInitialized();
  return _parserFactory!.getSupportedMimeTypes();
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
