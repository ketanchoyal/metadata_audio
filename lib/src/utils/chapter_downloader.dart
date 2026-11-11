import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/id3v2/id3v2_parser.dart';
import 'package:metadata_audio/src/id3v2/id3v2_tag_map.dart';
import 'package:metadata_audio/src/mp4/mp4_parser.dart';
import 'package:metadata_audio/src/mpeg/mpeg_parser.dart';
import 'package:metadata_audio/src/mpeg/xing_tag.dart';
import 'package:metadata_audio/src/utils/m4a_muxer.dart';

/// The current phase of the chapter download process.
enum ChapterDownloadPhase {
  /// Connecting to the source (remote URL or local file).
  connecting,

  /// Parsing the MP4/M4B container structure.
  analyzing,

  /// Resolving chapter timestamps to audio sample boundaries.
  resolvingSamples,

  /// Downloading the raw audio payload (remote) or reading it (local).
  downloading,

  /// Wrapping samples with ADTS headers and writing the output file.
  writing,
}

/// The result of a [ChapterDownloader.downloadChapter] operation.
class ChapterDownloadResult {
  const ChapterDownloadResult._({
    required this.isSuccess,
    this.outputPath,
    this.error,
  });

  /// Creates a successful result with the given [outputPath].
  const ChapterDownloadResult.success(String outputPath)
    : this._(isSuccess: true, outputPath: outputPath);

  /// Creates a failed result with the given [error] message.
  const ChapterDownloadResult.failure(String error)
    : this._(isSuccess: false, error: error);

  /// Whether the download completed successfully.
  final bool isSuccess;

  /// The output file path on success, `null` on failure.
  final String? outputPath;

  /// A human-readable error message on failure, `null` on success.
  final String? error;
}

/// The result of an in-memory [ChapterDownloader.extractChapterBytes] operation.
class ChapterBytesResult {
  const ChapterBytesResult._({
    required this.isSuccess,
    this.bytes,
    this.extension,
    this.mimeType,
    this.error,
  });

  /// Creates a successful result with extracted file [bytes], container
  /// [extension] (without leading dot), and [mimeType].
  const ChapterBytesResult.success({
    required Uint8List bytes,
    required String extension,
    required String mimeType,
  }) : this._(
         isSuccess: true,
         bytes: bytes,
         extension: extension,
         mimeType: mimeType,
       );

  /// Creates a failed result with the given [error] message.
  const ChapterBytesResult.failure(String error)
    : this._(isSuccess: false, error: error);

  /// Whether the extraction succeeded.
  final bool isSuccess;

  /// The extracted standalone chapter bytes on success, `null` on failure.
  final Uint8List? bytes;

  /// The output file extension without leading dot (`'m4a'`, `'aac'`, `'mp3'`).
  final String? extension;

  /// The MIME type of [bytes] (`'audio/mp4'`, `'audio/aac'`, `'audio/mpeg'`).
  final String? mimeType;

  /// A human-readable error message on failure, `null` on success.
  final String? error;
}

/// A utility class for downloading playable chapter files
/// from audiobook range requests.
class ChapterDownloader {
  ChapterDownloader._();

  /// Downloads or extracts a specific MP4/M4B audiobook chapter
  /// directly to [outputPath] as a playable standalone M4A (or AAC) file.
  ///
  /// On the **first call** for a given URL the MP4 container is parsed in
  /// full and the audio-track metadata is stored to the OS temp directory
  /// (`AudioMetadataCache`). Subsequent calls reuse that cache, skipping
  /// the parse step entirely – even across app restarts.
  ///
  /// This extracts the audio track sample boundaries using
  /// [Mp4Parser], downloads or reads only the specific sample range
  /// for the chapter, and packages the raw AAC samples into a standard
  /// standalone `.m4a` container (compatible with Chromecast, ExoPlayer,
  /// AVPlayer, and standard media players). If [outputPath] explicitly
  /// ends with `.aac`, legacy ADTS framing is used instead.
  ///
  /// For MP3 files, extracts the exact MPEG frame range without re-encoding.
  ///
  /// Returns a [ChapterDownloadResult] indicating success or failure.
  ///
  /// [originalUrl] can be a remote URL or a local file path.
  /// [chapterStartMs] / [chapterEndMs] are chapter boundaries in ms.
  /// [outputPath] is the destination (`.m4a` appended if extension omitted
  /// for MP4 sources).
  /// [httpClient] is an optional custom [HttpClient] for remote URLs.
  /// [onProgress] is called with 0.0–1.0 during the download phase.
  /// [onPhase] is called with a [ChapterDownloadPhase] enum value
  /// each time the operation transitions to a new phase.
  /// [parallelChunks] controls the number of parallel HTTP
  /// connections for remote downloads (default: 4).
  /// [includeMetadata] copies all metadata tags and cover art from the
  /// original file into the sliced chapter output (default: `true`).
  /// [metadata] supplies fallback metadata for `.m4a` output if the original
  /// container had no raw `udta`/`meta` box.
  static Future<ChapterDownloadResult> downloadChapter({
    required String originalUrl,
    required int chapterStartMs,
    required int chapterEndMs,
    required String outputPath,
    HttpClient? httpClient,
    void Function(double progress)? onProgress,
    void Function(ChapterDownloadPhase phase)? onPhase,
    int parallelChunks = 4,
    bool includeMetadata = true,
    AudioMetadata? metadata,
  }) async {
    try {
      final isRemote =
          originalUrl.startsWith('http://') ||
          originalUrl.startsWith('https://');

      var isMp3 =
          originalUrl.toLowerCase().endsWith('.mp3') ||
          originalUrl.toLowerCase().contains('.mp3?') ||
          originalUrl.toLowerCase().contains('/mp3/');

      if (!isMp3 && isRemote) {
        try {
          final strategyInfo = await detectStrategy(originalUrl);
          if (strategyInfo.detectedFormat == 'mpeg') {
            isMp3 = true;
          }
        } catch (_) {}
      }

      if (!isMp3 && !isRemote) {
        try {
          final file = File(originalUrl);
          final raf = await file.open();
          try {
            final magic = await raf.read(4);
            if (magic.length >= 3 &&
                magic[0] == 0x49 &&
                magic[1] == 0x44 &&
                magic[2] == 0x33) {
              isMp3 = true;
            } else if (magic.length >= 2 &&
                magic[0] == 0xFF &&
                (magic[1] & 0xE0) == 0xE0) {
              isMp3 = true;
            }
          } finally {
            await raf.close();
          }
        } catch (_) {}
      }

      var finalPath = outputPath;
      final wantsAac = finalPath.toLowerCase().endsWith('.aac');
      if (isMp3) {
        if (!finalPath.toLowerCase().endsWith('.mp3')) {
          finalPath += '.mp3';
        }
      } else {
        if (!wantsAac &&
            !finalPath.toLowerCase().endsWith('.m4a') &&
            !finalPath.toLowerCase().endsWith('.mp4')) {
          finalPath += '.m4a';
        }
      }

      if (isMp3) {
        return await _downloadMp3Chapter(
          originalUrl: originalUrl,
          chapterStartMs: chapterStartMs,
          chapterEndMs: chapterEndMs,
          outputPath: finalPath,
          isRemote: isRemote,
          httpClient: httpClient,
          onProgress: onProgress,
          onPhase: onPhase,
          parallelChunks: parallelChunks,
          includeMetadata: includeMetadata,
        );
      }

      return await _downloadMp4Chapter(
        originalUrl: originalUrl,
        chapterStartMs: chapterStartMs,
        chapterEndMs: chapterEndMs,
        finalPath: finalPath,
        wantsAac: wantsAac,
        isRemote: isRemote,
        httpClient: httpClient,
        onProgress: onProgress,
        onPhase: onPhase,
        parallelChunks: parallelChunks,
        includeMetadata: includeMetadata,
        fallbackMetadata: metadata,
      );
    } catch (e) {
      return ChapterDownloadResult.failure(e.toString());
    }
  }

  /// Extracts a standalone playable chapter or time range in memory from
  /// [sourceBytes] without writing to the local file system.
  ///
  /// Ideal for browser/web environments (using Blob downloads) or in-memory
  /// audio pipelines. Supports MP4/M4B/M4A/MOV containers (producing `.m4a`
  /// by default, or `.aac` when [wantsAac] is `true`) and MP3 files (producing
  /// `.mp3`).
  ///
  /// When [includeMetadata] is `true` (default), safe tags and cover art are
  /// preserved in the output while whole-file chapters, total durations, and
  /// file-wide seek tables are stripped.
  static Future<ChapterBytesResult> extractChapterBytes({
    required Uint8List sourceBytes,
    required int chapterStartMs,
    required int chapterEndMs,
    String? fileName,
    bool wantsAac = false,
    void Function(double progress)? onProgress,
    void Function(ChapterDownloadPhase phase)? onPhase,
    bool includeMetadata = true,
    AudioMetadata? metadata,
  }) async {
    try {
      if (sourceBytes.isEmpty) {
        return const ChapterBytesResult.failure('Source bytes are empty.');
      }

      onPhase?.call(ChapterDownloadPhase.connecting);

      final isMp3 = _isMp3Bytes(
        sourceBytes,
        fileName: fileName,
        metadata: metadata,
      );

      final tokenizer = BytesTokenizer(
        sourceBytes,
        fileInfo: FileInfo(size: sourceBytes.length),
      );

      if (isMp3) {
        final slice = await _extractMp3SliceBytes(
          tokenizer: tokenizer,
          chapterStartMs: chapterStartMs,
          chapterEndMs: chapterEndMs,
          includeMetadata: includeMetadata,
          readPayloadRange: (startByte, endByte) async {
            if (startByte < 0 || endByte > sourceBytes.length) {
              throw RangeError('Requested MP3 slice out of bounds.');
            }
            onProgress?.call(1);
            return Uint8List.sublistView(sourceBytes, startByte, endByte);
          },
          onPhase: onPhase,
        );
        if (slice.error != null || slice.bytes == null) {
          return ChapterBytesResult.failure(
            slice.error ?? 'Failed to extract MP3 chapter bytes.',
          );
        }
        return ChapterBytesResult.success(
          bytes: slice.bytes!,
          extension: 'mp3',
          mimeType: 'audio/mpeg',
        );
      }

      if (!_looksLikeMp4Container(
        sourceBytes,
        fileName: fileName,
        metadata: metadata,
      )) {
        return const ChapterBytesResult.failure(
          'Chapter extraction only supports MP4/M4A/M4B/MOV and MP3 audio.',
        );
      }

      onPhase?.call(ChapterDownloadPhase.analyzing);
      final parsed = await _parseMp4Track(
        tokenizer,
        includeMetadata: includeMetadata,
      );
      if (parsed.error != null || parsed.track == null) {
        return ChapterBytesResult.failure(
          parsed.error ?? 'Could not parse MP4 audio track.',
        );
      }

      final slice = await _buildMp4ChapterBytes(
        cached: parsed.track!,
        chapterStartMs: chapterStartMs,
        chapterEndMs: chapterEndMs,
        wantsAac: wantsAac,
        includeMetadata: includeMetadata,
        fallbackMetadata: metadata,
        readPayloadRange: (rangeStart, rangeEnd) async {
          if (rangeStart < 0 || rangeEnd > sourceBytes.length) {
            throw RangeError('Requested MP4 slice out of bounds.');
          }
          onProgress?.call(1);
          return Uint8List.sublistView(sourceBytes, rangeStart, rangeEnd);
        },
        onPhase: onPhase,
      );
      if (slice.error != null || slice.bytes == null) {
        return ChapterBytesResult.failure(
          slice.error ?? 'Failed to build MP4 chapter bytes.',
        );
      }
      return ChapterBytesResult.success(
        bytes: slice.bytes!,
        extension: wantsAac ? 'aac' : 'm4a',
        mimeType: wantsAac ? 'audio/aac' : 'audio/mp4',
      );
    } catch (e) {
      return ChapterBytesResult.failure(e.toString());
    }
  }

  static bool _isMp3Bytes(
    Uint8List sourceBytes, {
    String? fileName,
    AudioMetadata? metadata,
  }) {
    final container = metadata?.format.container?.toUpperCase();
    if (container == 'MPEG' || container == 'MP3') return true;
    final lowerName = fileName?.toLowerCase() ?? '';
    if (lowerName.endsWith('.mp3')) return true;
    if (sourceBytes.length >= 3 &&
        sourceBytes[0] == 0x49 &&
        sourceBytes[1] == 0x44 &&
        sourceBytes[2] == 0x33) {
      return true;
    }
    if (!_looksLikeMp4Container(
          sourceBytes,
          fileName: fileName,
          metadata: metadata,
        ) &&
        sourceBytes.length >= 4 &&
        sourceBytes[0] == 0xFF &&
        (sourceBytes[1] & 0xE0) == 0xE0 &&
        !MpegFrameHeader.isAdtsHeader(sourceBytes.sublist(0, 4)) &&
        MpegFrameHeader.parse(sourceBytes.sublist(0, 4)) != null) {
      return true;
    }
    return false;
  }

  static bool _looksLikeMp4Container(
    Uint8List sourceBytes, {
    String? fileName,
    AudioMetadata? metadata,
  }) {
    final container = metadata?.format.container?.toLowerCase() ?? '';
    if (container.contains('mp4') ||
        container.contains('m4a') ||
        container.contains('m4b') ||
        container.contains('quicktime') ||
        container.contains('isom')) {
      return true;
    }
    final lowerName = fileName?.toLowerCase() ?? '';
    if (lowerName.endsWith('.m4a') ||
        lowerName.endsWith('.m4b') ||
        lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.mov')) {
      return true;
    }
    if (sourceBytes.length >= 8) {
      final boxType = String.fromCharCodes(sourceBytes.sublist(4, 8));
      if (boxType == 'ftyp' ||
          boxType == 'moov' ||
          boxType == 'mdat' ||
          boxType == 'free' ||
          boxType == 'wide' ||
          boxType == 'skip') {
        return true;
      }
    }
    return false;
  }

  /// Clears all cached audiobook metadata written to the OS temp directory.
  ///
  /// Call this when the user explicitly triggers "Clear Cache" in the UI.
  /// The OS may also evict the cache at any time on its own.
  static Future<void> clearCache() => AudioMetadataCache.clearCache();

  /// Returns the total size of cached metadata files on disk in bytes.
  static int getCacheSize() => AudioMetadataCache.getCacheSize();

  // ── MP4/M4B chapter extraction ─────────────────────────────────────────────

  static Future<ChapterDownloadResult> _downloadMp4Chapter({
    required String originalUrl,
    required int chapterStartMs,
    required int chapterEndMs,
    required String finalPath,
    required bool wantsAac,
    required bool isRemote,
    required int parallelChunks,
    required bool includeMetadata,
    AudioMetadata? fallbackMetadata,
    HttpClient? httpClient,
    void Function(double progress)? onProgress,
    void Function(ChapterDownloadPhase phase)? onPhase,
  }) async {
    onPhase?.call(ChapterDownloadPhase.connecting);

    // ── 1. Resolve audio-track metadata (cache-first) ─────────────────────
    var cached = await AudioMetadataCache.get(originalUrl);

    final needsSampleTables =
        cached != null &&
        (cached.timeToSampleTable.isEmpty ||
            cached.chunkOffsetTable.isEmpty ||
            cached.sampleToChunkTable.isEmpty ||
            ((cached.sampleSize ?? 0) == 0 && cached.sampleSizeTable.isEmpty));

    final needsMetadataRefresh =
        cached != null &&
        includeMetadata &&
        !wantsAac &&
        !cached.metadataChecked &&
        cached.rawUdtaBox == null &&
        cached.rawMetaBox == null;

    if (cached == null || needsSampleTables || needsMetadataRefresh) {
      // Slow path: parse the container and populate the cache.
      final Tokenizer tokenizer;
      if (isRemote) {
        tokenizer = await RandomAccessTokenizer.fromUrl(originalUrl);
      } else {
        final file = File(originalUrl);
        if (!file.existsSync()) {
          return ChapterDownloadResult.failure(
            'Original local file not found at $originalUrl',
          );
        }
        tokenizer = FileTokenizer.fromFile(file);
      }

      try {
        onPhase?.call(ChapterDownloadPhase.analyzing);
        final parsed = await _parseMp4Track(
          tokenizer,
          includeMetadata: includeMetadata,
        );
        if (parsed.error != null || parsed.track == null) {
          return ChapterDownloadResult.failure(
            parsed.error ?? 'No audio track found in the original audiobook.',
          );
        }
        cached = parsed.track!;

        // Persist to disk asynchronously (non-blocking).
        unawaited(AudioMetadataCache.put(originalUrl, cached));
      } finally {
        if (isRemote) {
          (tokenizer as RandomAccessTokenizer).close();
        } else {
          (tokenizer as FileTokenizer).close();
        }
      }
    }

    final slice = await _buildMp4ChapterBytes(
      cached: cached,
      chapterStartMs: chapterStartMs,
      chapterEndMs: chapterEndMs,
      wantsAac: wantsAac,
      includeMetadata: includeMetadata,
      fallbackMetadata: fallbackMetadata,
      readPayloadRange: (rangeStart, rangeEnd) {
        final downloadSize = rangeEnd - rangeStart;
        if (isRemote) {
          return _downloadRangeParallel(
            url: originalUrl,
            rangeStart: rangeStart,
            totalSize: downloadSize,
            parallelChunks: parallelChunks,
            httpClient: httpClient,
            onProgress: onProgress,
          );
        }
        return _readLocalFileRange(
          originalUrl,
          rangeStart,
          rangeEnd,
          downloadSize,
          onProgress,
        );
      },
      onPhase: onPhase,
    );

    if (slice.error != null || slice.bytes == null) {
      return ChapterDownloadResult.failure(
        slice.error ?? 'Could not build MP4 chapter output.',
      );
    }

    await File(finalPath).writeAsBytes(slice.bytes!);
    return ChapterDownloadResult.success(finalPath);
  }

  static Future<({CachedAudioTrack? track, String? error})> _parseMp4Track(
    Tokenizer tokenizer, {
    required bool includeMetadata,
  }) async {
    final parseOpts = ParseOptions(
      includeChapters: true,
      skipCovers: !includeMetadata,
    );
    final mapper = CombinedTagMapper();
    final collector = MetadataCollector(mapper, parseOpts);
    final parser = Mp4Parser(
      metadata: collector,
      tokenizer: tokenizer,
      options: parseOpts,
      collectSampleTables: true,
    );
    await parser.parse();

    final tracks = parser.getTrackInfos();
    final audioTrack = tracks.where((t) => t.isAudio).firstOrNull;
    if (audioTrack == null) {
      return (
        track: null,
        error: 'No audio track found in the original audiobook.',
      );
    }

    final stsc = parser.getSampleToChunkTable(audioTrack.trackId) ?? [];
    final stco = parser.getChunkOffsetTable(audioTrack.trackId) ?? [];

    final cached = CachedAudioTrack.fromParser(
      trackInfo: audioTrack,
      sampleToChunkTable: stsc,
      chunkOffsetTable: stco,
      rawUdtaBox: parser.rawUdtaBox,
      rawMetaBox: parser.rawMetaBox,
      metadataChecked: includeMetadata,
    );
    return (track: cached, error: null);
  }

  static Future<({Uint8List? bytes, String? error})> _buildMp4ChapterBytes({
    required CachedAudioTrack cached,
    required int chapterStartMs,
    required int chapterEndMs,
    required bool wantsAac,
    required bool includeMetadata,
    required Future<Uint8List> Function(int rangeStart, int rangeEnd)
    readPayloadRange,
    AudioMetadata? fallbackMetadata,
    void Function(ChapterDownloadPhase phase)? onPhase,
  }) async {
    // ── 2. Map chapter timestamps → sample indices & byte offsets ─────────
    onPhase?.call(ChapterDownloadPhase.resolvingSamples);

    final timeScale = cached.timeScale ?? 1000;
    final startOffsetUnits = (chapterStartMs * timeScale) ~/ 1000;
    final endOffsetUnits = (chapterEndMs * timeScale) ~/ 1000;

    final startSampleIndex = cached.getSampleIndexForTime(startOffsetUnits);
    final endSampleIndex = cached.getSampleIndexForTime(endOffsetUnits);

    if (startSampleIndex == null || endSampleIndex == null) {
      return (
        bytes: null,
        error: 'Could not map chapter timestamps to audio samples.',
      );
    }

    final startByteOffset = cached.getByteOffsetForSample(startSampleIndex);
    if (startByteOffset == null) {
      return (
        bytes: null,
        error: 'Could not resolve starting byte offset for chapter.',
      );
    }

    final lastSampleIndex = endSampleIndex - 1;
    final lastSampleByteOffset = cached.getByteOffsetForSample(lastSampleIndex);
    if (lastSampleByteOffset == null) {
      return (
        bytes: null,
        error: 'Could not resolve ending byte offset for chapter.',
      );
    }

    int lastSampleSize;
    if (cached.sampleSize != null && cached.sampleSize! > 0) {
      lastSampleSize = cached.sampleSize!;
    } else if (lastSampleIndex < cached.sampleSizeTable.length) {
      lastSampleSize = cached.sampleSizeTable[lastSampleIndex];
    } else {
      return (bytes: null, error: 'Could not resolve ending sample size.');
    }

    final rangeStart = startByteOffset;
    final rangeEnd = lastSampleByteOffset + lastSampleSize;
    final downloadSize = rangeEnd - rangeStart;

    if (downloadSize <= 0) {
      return (
        bytes: null,
        error: 'Chapter does not contain any audio samples.',
      );
    }

    // ── 3. Fetch raw payload bytes ────────────────────────────────────────
    onPhase?.call(ChapterDownloadPhase.downloading);
    final payloadBytes = await readPayloadRange(rangeStart, rangeEnd);

    // ── 4. Write output bytes ─────────────────────────────────────────────
    onPhase?.call(ChapterDownloadPhase.writing);

    final sampleRate = cached.sampleRate ?? 44100;
    final channels = cached.numberOfChannels ?? 2;
    final samplingFreqIndex = _getSamplingFrequencyIndex(sampleRate);

    if (!wantsAac && cached.rawStsdBox != null) {
      // Build standalone Chromecast-ready M4A file
      final sampleSizes = <int>[];
      final rawAudioBuilder = BytesBuilder(copy: false);

      for (var i = startSampleIndex; i < endSampleIndex; i++) {
        final sampleOffset = cached.getByteOffsetForSample(i);
        if (sampleOffset == null) break;
        final relativeOffset = sampleOffset - rangeStart;

        int size;
        if (cached.sampleSize != null && cached.sampleSize! > 0) {
          size = cached.sampleSize!;
        } else if (i < cached.sampleSizeTable.length) {
          size = cached.sampleSizeTable[i];
        } else {
          break;
        }

        if (relativeOffset + size > payloadBytes.length) break;

        sampleSizes.add(size);
        rawAudioBuilder.add(
          payloadBytes.sublist(relativeOffset, relativeOffset + size),
        );
      }

      final sampleDuration = cached.timeToSampleTable.isNotEmpty
          ? cached.timeToSampleTable.first.duration
          : 1024;

      var rawUdtaBox = includeMetadata ? cached.rawUdtaBox : null;
      final rawMetaBox = includeMetadata ? cached.rawMetaBox : null;
      if (includeMetadata &&
          rawUdtaBox == null &&
          rawMetaBox == null &&
          fallbackMetadata != null) {
        rawUdtaBox = M4aMuxer.buildUdtaFromMetadata(fallbackMetadata);
      }

      final m4aBytes = M4aMuxer.buildM4a(
        rawStsdBox: cached.rawStsdBox!,
        sampleSizes: sampleSizes,
        timeScale: timeScale,
        sampleDuration: sampleDuration > 0 ? sampleDuration : 1024,
        rawAudioData: rawAudioBuilder.takeBytes(),
        rawUdtaBox: rawUdtaBox,
        rawMetaBox: rawMetaBox,
      );

      return (bytes: m4aBytes, error: null);
    }

    // Legacy ADTS-wrapped output
    final outputBuilder = BytesBuilder();
    for (var i = startSampleIndex; i < endSampleIndex; i++) {
      final sampleOffset = cached.getByteOffsetForSample(i);
      if (sampleOffset == null) break;
      final relativeOffset = sampleOffset - rangeStart;

      int size;
      if (cached.sampleSize != null && cached.sampleSize! > 0) {
        size = cached.sampleSize!;
      } else if (i < cached.sampleSizeTable.length) {
        size = cached.sampleSizeTable[i];
      } else {
        break;
      }

      if (relativeOffset + size > payloadBytes.length) break;

      outputBuilder.add(
        _buildAdtsHeader(
          profile: 1, // AAC-LC
          samplingFrequencyIndex: samplingFreqIndex,
          channelConfig: channels,
          frameLength: size + 7,
        ),
      );
      outputBuilder.add(
        payloadBytes.sublist(relativeOffset, relativeOffset + size),
      );
    }

    return (bytes: outputBuilder.takeBytes(), error: null);
  }

  static Future<Uint8List> _readLocalFileRange(
    String path,
    int rangeStart,
    int rangeEnd,
    int totalSize,
    void Function(double progress)? onProgress,
  ) async {
    final localFile = File(path);
    final builder = BytesBuilder(copy: false);
    var readBytes = 0;
    await for (final chunk in localFile.openRead(rangeStart, rangeEnd)) {
      builder.add(chunk);
      readBytes += chunk.length;
      if (onProgress != null && totalSize > 0) {
        onProgress((readBytes / totalSize).clamp(0.0, 1.0));
      }
    }
    return builder.takeBytes();
  }

  static const int _maxRetries = 5;

  /// Downloads a byte range using parallel HTTP connections.
  ///
  /// Splits the total range into [parallelChunks] segments and downloads
  /// them concurrently. Staggers chunk start requests slightly to reduce
  /// the risk of triggering CDN / Cloudflare 429 rate limits.
  ///
  /// If the server responds with HTTP 429 (Too Many Requests), automatically
  /// retries with exponential backoff (respecting `Retry-After`). If parallel
  /// chunking triggers persistent rate limiting, automatically falls back to
  /// a sequential single-range request.
  static Future<Uint8List> _downloadRangeParallel({
    required String url,
    required int rangeStart,
    required int totalSize,
    required int parallelChunks,
    HttpClient? httpClient,
    void Function(double progress)? onProgress,
  }) async {
    // Don't bother parallelising tiny payloads
    const minChunkSize = 256 * 1024; // 256 KB
    var numChunks = parallelChunks.clamp(1, 8);
    if (totalSize < minChunkSize * 2) {
      numChunks = 1;
    } else if (totalSize ~/ numChunks < minChunkSize) {
      numChunks = totalSize ~/ minChunkSize;
      if (numChunks < 1) numChunks = 1;
    }

    final client = httpClient ?? HttpClient();
    final shouldCloseClient = httpClient == null;

    try {
      if (numChunks <= 1) {
        return await _downloadSingleRangeWithRetry(
          client: client,
          url: url,
          rangeStart: rangeStart,
          rangeEnd: rangeStart + totalSize - 1,
          onProgress: onProgress,
        );
      }

      final chunkSize = totalSize ~/ numChunks;
      final downloadedPerChunk = List<int>.filled(numChunks, 0);

      try {
        final futures = List<Future<Uint8List>>.generate(numChunks, (i) async {
          // Stagger chunk starts slightly (100ms) to avoid simultaneous bursts
          if (i > 0) {
            await Future<void>.delayed(Duration(milliseconds: 100 * i));
          }
          final start = rangeStart + (i * chunkSize);
          final end = (i == numChunks - 1)
              ? rangeStart + totalSize - 1
              : start + chunkSize - 1;
          final expectedChunkSize = end - start + 1;

          return _downloadSingleRangeWithRetry(
            client: client,
            url: url,
            rangeStart: start,
            rangeEnd: end,
            onProgress: (chunkProgress) {
              downloadedPerChunk[i] = (expectedChunkSize * chunkProgress)
                  .round();
              if (onProgress != null) {
                final totalDownloaded = downloadedPerChunk.fold<int>(
                  0,
                  (a, b) => a + b,
                );
                onProgress((totalDownloaded / totalSize).clamp(0.0, 1.0));
              }
            },
          );
        });

        final results = await Future.wait(futures);
        final combined = BytesBuilder(copy: false);
        for (final chunk in results) {
          combined.add(chunk);
        }
        return combined.takeBytes();
      } on Object catch (e) {
        // If parallel downloading triggered rate limiting (HTTP 429) or
        // connection resets, fall back to a single sequential download.
        final msg = e.toString().toLowerCase();
        if (msg.contains('429') || msg.contains('too many requests')) {
          onProgress?.call(0);
          return await _downloadSingleRangeWithRetry(
            client: client,
            url: url,
            rangeStart: rangeStart,
            rangeEnd: rangeStart + totalSize - 1,
            onProgress: onProgress,
          );
        }
        rethrow;
      }
    } finally {
      if (shouldCloseClient) client.close();
    }
  }

  /// Downloads a single byte range with automatic retry on HTTP 429
  /// (Too Many Requests) using exponential backoff.
  static Future<Uint8List> _downloadSingleRangeWithRetry({
    required HttpClient client,
    required String url,
    required int rangeStart,
    required int rangeEnd,
    void Function(double progress)? onProgress,
    int attempt = 0,
  }) async {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('User-Agent', 'metadata_audio/0.9.4');
    request.headers.set('Range', 'bytes=$rangeStart-$rangeEnd');
    final response = await request.close();

    if (response.statusCode == 429) {
      await response.drain<void>();

      if (attempt >= _maxRetries) {
        throw HttpException(
          'Server returned HTTP 429 (Too Many Requests) after '
          '$_maxRetries retries for bytes=$rangeStart-$rangeEnd',
        );
      }

      var delaySec = 1 << attempt; // 1, 2, 4, 8, 16 seconds
      final retryAfter = response.headers.value('retry-after');
      if (retryAfter != null) {
        final parsed = int.tryParse(retryAfter.trim());
        if (parsed != null && parsed > 0) {
          delaySec = parsed;
        }
      }

      await Future<void>.delayed(Duration(seconds: delaySec));
      return _downloadSingleRangeWithRetry(
        client: client,
        url: url,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        onProgress: onProgress,
        attempt: attempt + 1,
      );
    }

    if (response.statusCode >= 400) {
      await response.drain<void>();
      throw HttpException(
        'Failed to download chunk: HTTP ${response.statusCode} '
        'for bytes=$rangeStart-$rangeEnd',
      );
    }

    final expectedSize = rangeEnd - rangeStart + 1;
    final builder = BytesBuilder(copy: false);
    var received = 0;

    await for (final chunk in response) {
      builder.add(chunk);
      received += chunk.length;
      onProgress?.call((received / expectedSize).clamp(0.0, 1.0));
    }

    return builder.takeBytes();
  }

  static List<int> _buildAdtsHeader({
    required int profile,
    required int samplingFrequencyIndex,
    required int channelConfig,
    required int frameLength,
  }) {
    final header = Uint8List(7);
    header[0] = 0xFF;
    header[1] = 0xF1;
    header[2] =
        ((profile & 3) << 6) |
        ((samplingFrequencyIndex & 0x0F) << 2) |
        ((channelConfig >> 2) & 1);
    header[3] = ((channelConfig & 3) << 6) | ((frameLength >> 11) & 3);
    header[4] = (frameLength >> 3) & 0xFF;
    header[5] = ((frameLength & 7) << 5) | 0x1F;
    header[6] = 0xFC;
    return header;
  }

  static int _getSamplingFrequencyIndex(int sampleRate) {
    switch (sampleRate) {
      case 96000:
        return 0;
      case 88200:
        return 1;
      case 64000:
        return 2;
      case 48000:
        return 3;
      case 44100:
        return 4;
      case 32000:
        return 5;
      case 24000:
        return 6;
      case 22050:
        return 7;
      case 16000:
        return 8;
      case 12000:
        return 9;
      case 11025:
        return 10;
      case 8000:
        return 11;
      case 7350:
        return 12;
      default:
        return 4;
    }
  }

  static Future<ChapterDownloadResult> _downloadMp3Chapter({
    required String originalUrl,
    required int chapterStartMs,
    required int chapterEndMs,
    required String outputPath,
    required bool isRemote,
    required bool includeMetadata,
    HttpClient? httpClient,
    void Function(double progress)? onProgress,
    void Function(ChapterDownloadPhase phase)? onPhase,
    int parallelChunks = 4,
  }) async {
    final Tokenizer tokenizer;
    onPhase?.call(ChapterDownloadPhase.connecting);
    if (isRemote) {
      tokenizer = await RandomAccessTokenizer.fromUrl(originalUrl);
    } else {
      final file = File(originalUrl);
      if (!await file.exists()) {
        return ChapterDownloadResult.failure(
          'Original local file not found at $originalUrl',
        );
      }
      tokenizer = FileTokenizer.fromFile(file);
    }

    try {
      final slice = await _extractMp3SliceBytes(
        tokenizer: tokenizer,
        chapterStartMs: chapterStartMs,
        chapterEndMs: chapterEndMs,
        includeMetadata: includeMetadata,
        readPayloadRange: (startByte, endByte) {
          final downloadSize = endByte - startByte;
          if (isRemote) {
            return _downloadRangeParallel(
              url: originalUrl,
              rangeStart: startByte,
              totalSize: downloadSize,
              parallelChunks: parallelChunks,
              httpClient: httpClient,
              onProgress: onProgress,
            );
          }
          return _readLocalFileRange(
            originalUrl,
            startByte,
            endByte,
            downloadSize,
            onProgress,
          );
        },
        onPhase: onPhase,
      );

      if (slice.error != null || slice.bytes == null) {
        return ChapterDownloadResult.failure(
          slice.error ?? 'Could not build MP3 chapter output.',
        );
      }

      await File(outputPath).writeAsBytes(slice.bytes!);
      return ChapterDownloadResult.success(outputPath);
    } catch (e) {
      return ChapterDownloadResult.failure(e.toString());
    } finally {
      if (isRemote) {
        (tokenizer as RandomAccessTokenizer).close();
      } else {
        (tokenizer as FileTokenizer).close();
      }
    }
  }

  static Future<({Uint8List? bytes, String? error})> _extractMp3SliceBytes({
    required Tokenizer tokenizer,
    required int chapterStartMs,
    required int chapterEndMs,
    required bool includeMetadata,
    required Future<Uint8List> Function(int startByte, int endByte)
    readPayloadRange,
    void Function(ChapterDownloadPhase phase)? onPhase,
  }) async {
    onPhase?.call(ChapterDownloadPhase.analyzing);
    final mpegOffset = await _findMpegAudioOffset(tokenizer);

    final header = await _findFirstMpegFrame(tokenizer, mpegOffset);
    if (header == null) {
      return (
        bytes: null,
        error: 'Could not parse first MPEG frame header in MP3 file.',
      );
    }

    final xingInfo = await _findXingHeader(tokenizer, header, mpegOffset);

    List<int>? id3v2Bytes;
    List<int>? id3v1Bytes;
    final fileSize = tokenizer.fileInfo?.size;

    if (includeMetadata) {
      if (mpegOffset > 0) {
        if (tokenizer is HttpBasedTokenizer) {
          await tokenizer.prefetchRange(0, mpegOffset);
        }
        tokenizer.seek(0);
        final rawId3v2 = tokenizer.readBytes(mpegOffset);
        id3v2Bytes = await _sanitizeId3v2ForSlice(rawId3v2);
      }

      if (fileSize != null && fileSize >= 128) {
        try {
          if (tokenizer is HttpBasedTokenizer) {
            await tokenizer.prefetchRange(fileSize - 128, fileSize);
          }
          tokenizer.seek(fileSize - 128);
          final tail = tokenizer.readBytes(128);
          if (tail.length == 128 &&
              tail[0] == 0x54 && // 'T'
              tail[1] == 0x41 && // 'A'
              tail[2] == 0x47) {
            // 'G'
            id3v1Bytes = tail;
          }
        } catch (_) {}
      }
    }

    onPhase?.call(ChapterDownloadPhase.resolvingSamples);
    int startByte;
    int endByte;

    final frameDurationMs = (header.samplesPerFrame * 1000) / header.sampleRate;
    if (xingInfo != null &&
        xingInfo.toc != null &&
        xingInfo.streamSize != null &&
        xingInfo.numFrames != null) {
      final totalDurationMs =
          (xingInfo.numFrames! * header.samplesPerFrame * 1000) /
          header.sampleRate;

      final startPercent = (chapterStartMs / totalDurationMs) * 100;
      final endPercent = (chapterEndMs / totalDurationMs) * 100;

      final startOffsetNormalized = _interpolateToc(
        xingInfo.toc!,
        startPercent,
      );
      final endOffsetNormalized = _interpolateToc(xingInfo.toc!, endPercent);

      startByte =
          mpegOffset +
          ((startOffsetNormalized / 256.0) * xingInfo.streamSize!).round();
      endByte =
          mpegOffset +
          ((endOffsetNormalized / 256.0) * xingInfo.streamSize!).round();
    } else {
      final startFrame = chapterStartMs ~/ frameDurationMs;
      final endFrame = (chapterEndMs / frameDurationMs).ceil();
      startByte = mpegOffset + startFrame * header.frameLength;
      endByte = mpegOffset + endFrame * header.frameLength;
    }

    final audioEndLimit = (fileSize != null && id3v1Bytes != null)
        ? fileSize - 128
        : fileSize;
    if (audioEndLimit != null) {
      startByte = startByte.clamp(mpegOffset, audioEndLimit);
      endByte = endByte.clamp(mpegOffset, audioEndLimit);
    }

    if (xingInfo != null && startByte == mpegOffset) {
      startByte = (startByte + header.frameLength).clamp(
        mpegOffset,
        audioEndLimit ?? (startByte + header.frameLength),
      );
    }

    final downloadSize = endByte - startByte;
    if (downloadSize <= 0) {
      return (bytes: null, error: 'Calculated download byte size is zero.');
    }

    onPhase?.call(ChapterDownloadPhase.downloading);
    final payloadBytes = await readPayloadRange(startByte, endByte);

    onPhase?.call(ChapterDownloadPhase.writing);

    // Find the first valid MPEG frame syncword (verified by the following
    // frame boundary when available) to align the start cleanly.
    var alignedStart = 0;
    while (alignedStart < payloadBytes.length - 4) {
      if (payloadBytes[alignedStart] == 0xFF &&
          (payloadBytes[alignedStart + 1] & 0xE0) == 0xE0) {
        final sync = payloadBytes.sublist(alignedStart, alignedStart + 4);
        if (!MpegFrameHeader.isAdtsHeader(sync)) {
          final candidate = MpegFrameHeader.parse(sync);
          if (candidate != null && candidate.frameLength > 0) {
            final nextOffset = alignedStart + candidate.frameLength;
            if (nextOffset + 4 > payloadBytes.length) {
              break;
            }
            final nextSync = payloadBytes.sublist(nextOffset, nextOffset + 4);
            if (nextSync[0] == 0xFF &&
                (nextSync[1] & 0xE0) == 0xE0 &&
                !MpegFrameHeader.isAdtsHeader(nextSync) &&
                MpegFrameHeader.parse(nextSync) != null) {
              break;
            }
          }
        }
      }
      alignedStart++;
    }

    // Walk complete MPEG frames from alignedStart to trim any truncated
    // trailing frame.
    var alignedEnd = alignedStart;
    while (alignedEnd + 4 <= payloadBytes.length) {
      final sync = payloadBytes.sublist(alignedEnd, alignedEnd + 4);
      if (sync[0] != 0xFF ||
          (sync[1] & 0xE0) != 0xE0 ||
          MpegFrameHeader.isAdtsHeader(sync)) {
        break;
      }
      final frame = MpegFrameHeader.parse(sync);
      if (frame == null || frame.frameLength <= 0) {
        break;
      }
      if (alignedEnd + frame.frameLength > payloadBytes.length) {
        break;
      }
      alignedEnd += frame.frameLength;
    }

    final slicedBytes = alignedEnd > alignedStart
        ? payloadBytes.sublist(alignedStart, alignedEnd)
        : (alignedStart < payloadBytes.length
              ? payloadBytes.sublist(alignedStart)
              : payloadBytes);

    if (includeMetadata && (id3v2Bytes != null || id3v1Bytes != null)) {
      final out = BytesBuilder(copy: false);
      if (id3v2Bytes != null) out.add(id3v2Bytes);
      out.add(slicedBytes);
      if (id3v1Bytes != null) out.add(id3v1Bytes);
      return (bytes: out.takeBytes(), error: null);
    }
    return (bytes: slicedBytes, error: null);
  }

  static const Set<String> _unsafeId3v23V24Frames = <String>{
    'CHAP', // Whole-file chapter markers & offsets
    'CTOC', // Whole-file table of contents
    'TLEN', // Whole-file duration in ms (misleads players on sliced chapters)
    'SYLT', // Synchronized lyrics tied to original file timestamps
    'ETCO', // Event timing codes tied to original file timestamps
    'MLLT', // MPEG location lookup table tied to original file bytes
    'SYTC', // Synchronized tempo codes tied to original file timestamps
    'ASPI', // Audio seek point index tied to original file bytes
    'SEEK', // Next tag offset in original file
    'RBUF', // Buffer size hint for original stream
  };

  static const Set<String> _unsafeId3v22Frames = <String>{
    'TLE', // ID3v2.2 TLEN
    'SLT', // ID3v2.2 SYLT
    'ETC', // ID3v2.2 ETCO
    'MLL', // ID3v2.2 MLLT
    'STC', // ID3v2.2 SYTC
    'BUF', // ID3v2.2 RBUF
  };

  /// Sanitizes an ID3v2 tag for a standalone sliced MP3 chapter: removes
  /// chapter frames (`CHAP`/`CTOC`), whole-file duration (`TLEN`/`TLE`),
  /// seek/offset tables (`MLLT`, `ASPI`, `SEEK`), and time-synced frames
  /// (`SYLT`, `ETCO`, `SYTC`), while always retaining cover art (`APIC`/`PIC`)
  /// and safe descriptive tags.
  static Future<List<int>?> _sanitizeId3v2ForSlice(List<int> rawTag) async {
    if (rawTag.length < 10) return null;
    if (rawTag[0] != 0x49 || rawTag[1] != 0x44 || rawTag[2] != 0x33) {
      return null;
    }
    final major = rawTag[3];
    final flags = rawTag[5];
    final hasUnsync = (flags & 0x80) != 0;
    final hasExtHeader = (flags & 0x40) != 0;
    final hasFooter = (flags & 0x10) != 0;
    final tagSize =
        ((rawTag[6] & 0x7F) << 21) |
        ((rawTag[7] & 0x7F) << 14) |
        ((rawTag[8] & 0x7F) << 7) |
        (rawTag[9] & 0x7F);

    if (major == 2 && !hasUnsync && 10 + tagSize == rawTag.length) {
      final keptFrames = BytesBuilder(copy: false);
      var offset = 10;
      var strippedAny = false;
      while (offset + 6 <= rawTag.length) {
        if (rawTag[offset] == 0 &&
            rawTag[offset + 1] == 0 &&
            rawTag[offset + 2] == 0) {
          break;
        }
        final frameId = String.fromCharCodes(
          rawTag.sublist(offset, offset + 3),
        );
        final frameLen =
            ((rawTag[offset + 3] & 0xFF) << 16) |
            ((rawTag[offset + 4] & 0xFF) << 8) |
            (rawTag[offset + 5] & 0xFF);
        final totalFrameLen = 6 + frameLen;
        if (frameLen < 0 || offset + totalFrameLen > rawTag.length) {
          return _rebuildSafeId3v23Tag(rawTag);
        }
        if (_unsafeId3v22Frames.contains(frameId)) {
          strippedAny = true;
        } else {
          keptFrames.add(rawTag.sublist(offset, offset + totalFrameLen));
        }
        offset += totalFrameLen;
      }
      if (!strippedAny) return rawTag;
      final body = keptFrames.takeBytes();
      if (body.isEmpty) return null;
      return _wrapId3v2Header(rawTag.sublist(0, 6), body);
    }

    if ((major == 3 || major == 4) &&
        !hasUnsync &&
        !hasExtHeader &&
        !hasFooter &&
        10 + tagSize == rawTag.length) {
      final keptFrames = BytesBuilder(copy: false);
      var offset = 10;
      var strippedAny = false;

      while (offset + 10 <= rawTag.length) {
        if (rawTag[offset] == 0 &&
            rawTag[offset + 1] == 0 &&
            rawTag[offset + 2] == 0 &&
            rawTag[offset + 3] == 0) {
          break;
        }
        final frameId = String.fromCharCodes(
          rawTag.sublist(offset, offset + 4),
        );
        final frameLen = major == 4
            ? ((rawTag[offset + 4] & 0x7F) << 21) |
                  ((rawTag[offset + 5] & 0x7F) << 14) |
                  ((rawTag[offset + 6] & 0x7F) << 7) |
                  (rawTag[offset + 7] & 0x7F)
            : ((rawTag[offset + 4] & 0xFF) << 24) |
                  ((rawTag[offset + 5] & 0xFF) << 16) |
                  ((rawTag[offset + 6] & 0xFF) << 8) |
                  (rawTag[offset + 7] & 0xFF);
        final totalFrameLen = 10 + frameLen;
        if (frameLen < 0 || offset + totalFrameLen > rawTag.length) {
          return _rebuildSafeId3v23Tag(rawTag);
        }
        final isUnsafe =
            _unsafeId3v23V24Frames.contains(frameId) ||
            (frameId == 'TXXX' &&
                _isUnsafeTxxxFrame(rawTag, offset + 10, frameLen));
        if (isUnsafe) {
          strippedAny = true;
        } else {
          keptFrames.add(rawTag.sublist(offset, offset + totalFrameLen));
        }
        offset += totalFrameLen;
      }

      if (!strippedAny) return rawTag;
      final body = keptFrames.takeBytes();
      if (body.isEmpty) return null;
      return _wrapId3v2Header(rawTag.sublist(0, 6), body);
    }

    // Fallback for unsynchronised, extended-header, footer, or concatenated
    // ID3v2 tags: parse safely and rebuild a clean ID3v2.3 tag containing
    // cover art and safe metadata without any chapter/duration/seek frames.
    return _rebuildSafeId3v23Tag(rawTag);
  }

  static bool _isUnsafeTxxxFrame(List<int> buf, int start, int len) {
    if (len < 2) return false;
    final encoding = buf[start];
    final pos = start + 1;
    final end = start + len;
    if (encoding == 1 || encoding == 2) {
      // UTF-16: look for 0x00 0x00 on 2-byte boundary
      var descEnd = end;
      for (var i = pos; i + 1 < end; i += 2) {
        if (buf[i] == 0 && buf[i + 1] == 0) {
          descEnd = i;
          break;
        }
      }
      final rawDesc = buf.sublist(pos, descEnd);
      final desc = latin1
          .decode(rawDesc.where((b) => b != 0).toList())
          .trim()
          .toLowerCase();
      return _isUnsafeCustomDesc(desc);
    }
    var descEnd = end;
    for (var i = pos; i < end; i++) {
      if (buf[i] == 0) {
        descEnd = i;
        break;
      }
    }
    final desc = utf8
        .decode(buf.sublist(pos, descEnd), allowMalformed: true)
        .trim()
        .toLowerCase();
    return _isUnsafeCustomDesc(desc);
  }

  static bool _isUnsafeCustomDesc(String desc) =>
      desc == 'itunsmpb' ||
      desc == 'itunpgap' ||
      desc.contains('chapter') ||
      desc.contains('mediamarkers');

  static List<int> _wrapId3v2Header(List<int> headerPrefix6, List<int> body) {
    final newSize = body.length;
    final out = Uint8List(10 + newSize);
    out.setRange(0, 6, headerPrefix6);
    out[6] = (newSize >> 21) & 0x7F;
    out[7] = (newSize >> 14) & 0x7F;
    out[8] = (newSize >> 7) & 0x7F;
    out[9] = newSize & 0x7F;
    out.setRange(10, 10 + newSize, body);
    return out;
  }

  static Future<List<int>?> _rebuildSafeId3v23Tag(List<int> rawTag) async {
    try {
      final mapper = CombinedTagMapper()
        ..registerMapper('ID3v2.2', Id3v2TagMapper())
        ..registerMapper('ID3v2.3', Id3v2TagMapper())
        ..registerMapper('ID3v2.4', Id3v2TagMapper());
      const opts = ParseOptions();
      final collector = MetadataCollector(mapper, opts);
      await Id3v2Parser(
        metadata: collector,
        tokenizer: BytesTokenizer(Uint8List.fromList(rawTag)),
        options: opts,
      ).parse();
      final meta = collector.toAudioMetadata();
      final c = meta.common;

      final frames = BytesBuilder(copy: false);
      void addTextFrame(String id, String? text) {
        if (text == null || text.isEmpty) return;
        // ID3v2.3 UTF-16LE with BOM (0x01) or Latin1 if pure ASCII
        final encoded = utf8.encode(text);
        final payload = <int>[0x03, ...encoded]; // ID3v2.4-style UTF-8 or v2.4
        frames.add(_buildId3v24Frame(id, payload));
      }

      addTextFrame('TIT2', c.title);
      addTextFrame('TPE1', c.artist);
      addTextFrame('TALB', c.album);
      addTextFrame('TPE2', c.albumartist);
      if (c.genre != null && c.genre!.isNotEmpty) {
        addTextFrame('TCON', c.genre!.join(', '));
      }
      addTextFrame('TDRC', c.date ?? c.year?.toString());
      if (c.composer != null && c.composer!.isNotEmpty) {
        addTextFrame('TCOM', c.composer!.join(', '));
      }
      addTextFrame('TCOP', c.copyright);

      // Retain cover art from native APIC/PIC tags or common.picture
      final pictures = <Picture>[...?c.picture];
      for (final tagList in meta.native.values) {
        for (final tag in tagList) {
          if ((tag.id == 'APIC' || tag.id == 'PIC') && tag.value is Picture) {
            final pic = tag.value as Picture;
            if (pic.data.isNotEmpty) pictures.add(pic);
          }
        }
      }
      for (final pic in pictures) {
        if (pic.data.isEmpty) continue;
        final apicPayload = BytesBuilder(copy: false)
          ..addByte(0x00) // Latin-1
          ..add(ascii.encode(pic.format))
          ..addByte(0x00)
          ..addByte(0x03) // Cover (front)
          ..addByte(0x00)
          ..add(pic.data);
        frames.add(_buildId3v24Frame('APIC', apicPayload.takeBytes()));
      }

      final body = frames.takeBytes();
      if (body.isEmpty) return null;
      return _wrapId3v2Header(const [0x49, 0x44, 0x33, 4, 0, 0], body);
    } on Object catch (_) {
      return null;
    }
  }

  static List<int> _buildId3v24Frame(String id, List<int> payload) {
    final len = payload.length;
    return <int>[
      ...ascii.encode(id),
      (len >> 21) & 0x7F,
      (len >> 14) & 0x7F,
      (len >> 7) & 0x7F,
      len & 0x7F,
      0,
      0,
      ...payload,
    ];
  }

  static Future<int> _findMpegAudioOffset(Tokenizer tokenizer) async {
    var offset = 0;
    while (true) {
      try {
        if (tokenizer is HttpBasedTokenizer) {
          await tokenizer.prefetchRange(offset, offset + 10);
        }
        final bytes = tokenizer.peekBytes(10);
        if (bytes.length < 10) break;
        final tag = String.fromCharCodes(bytes.sublist(0, 3));
        if (tag == 'ID3') {
          final sizeBytes = bytes.sublist(6, 10);
          final size =
              (sizeBytes[0] << 21) |
              (sizeBytes[1] << 14) |
              (sizeBytes[2] << 7) |
              sizeBytes[3];
          final hasFooter = (bytes[5] & 0x10) != 0;
          final totalTagSize = 10 + size + (hasFooter ? 10 : 0);
          if (tokenizer is HttpBasedTokenizer) {
            await tokenizer.prefetchRange(offset, offset + totalTagSize);
          }
          tokenizer.skip(totalTagSize);
          offset += totalTagSize;
        } else {
          break;
        }
      } catch (_) {
        break;
      }
    }
    return offset;
  }

  static Future<MpegFrameHeader?> _findFirstMpegFrame(
    Tokenizer tokenizer,
    int mpegOffset,
  ) async {
    tokenizer.seek(mpegOffset);
    var pos = mpegOffset;
    if (tokenizer is HttpBasedTokenizer) {
      await tokenizer.prefetchRange(pos, pos + 4096);
    }
    while (true) {
      try {
        final sync = tokenizer.peekBytes(4);
        if (sync.length < 4) return null;
        if (sync[0] == 0xFF && (sync[1] & 0xE0) == 0xE0) {
          if (!MpegFrameHeader.isAdtsHeader(sync)) {
            final header = MpegFrameHeader.parse(sync);
            if (header != null) return header;
          }
        }
        tokenizer.skip(1);
        pos++;
        if (pos % 4096 == 0 && tokenizer is HttpBasedTokenizer) {
          await tokenizer.prefetchRange(pos, pos + 4096);
        }
      } catch (_) {
        return null;
      }
    }
  }

  static Future<XingInfoTag?> _findXingHeader(
    Tokenizer tokenizer,
    MpegFrameHeader header,
    int mpegOffset,
  ) async {
    try {
      if (tokenizer is HttpBasedTokenizer) {
        await tokenizer.prefetchRange(
          mpegOffset,
          mpegOffset + header.frameLength,
        );
      }
      tokenizer.seek(mpegOffset);
      final frameData = tokenizer.peekBytes(header.frameLength);
      if (frameData.length < header.frameLength) return null;

      var offset = 4;
      if (header.isProtectedByCrc) {
        offset += 2;
      }

      final sideInfoLength = header.sideInformationLength;
      if (sideInfoLength == null) return null;
      offset += sideInfoLength;

      if (offset + 4 > frameData.length) return null;
      final tag = String.fromCharCodes(frameData.sublist(offset, offset + 4));
      if (tag == 'Xing' || tag == 'Info') {
        return parseXingHeader(frameData, offset + 4);
      }
    } catch (_) {}
    return null;
  }

  static double _interpolateToc(List<int> toc, double percent) {
    if (percent <= 0) return 0;
    if (percent >= 100) return 255;

    final index = percent.floor().clamp(0, 98);
    final fraction = percent - index;

    final val1 = toc[index] & 0xFF;
    final val2 = toc[index + 1] & 0xFF;

    return val1 + (val2 - val1) * fraction;
  }
}
