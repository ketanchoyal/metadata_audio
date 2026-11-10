import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/mp4/atom_token.dart';
import 'package:metadata_audio/src/mp4/mp4_parser.dart';
import 'package:metadata_audio/src/utils/cache_types.dart';

/// A persistent cache for parsed audio metadata and MP4/M4B audio track tables.
///
/// On platforms with file system access (native IO), entries are stored in
/// the OS temporary directory under `metadata_audio_cache/` without keeping
/// parsed objects in memory.
/// On platforms without file system access (such as web), an in-memory cache
/// is used instead with bounded size.
class AudioMetadataCache {
  AudioMetadataCache._();

  static const bool _hasIoEnvironment = bool.fromEnvironment('dart.library.io');

  /// Override whether IO is available, primarily for testing web behavior.
  @visibleForTesting
  static bool? overrideHasIoForTesting;

  /// Override the disk cache directory path, primarily to isolate parallel
  /// test suites that call [clearCache].
  @visibleForTesting
  static Directory? overrideDirForTesting;

  /// Whether IO operations (file system access) are available.
  static bool get hasIo => overrideHasIoForTesting ?? _hasIoEnvironment;

  /// When true, metadata caching is globally enabled across all parse calls
  /// (`parseFile`, `parseUrl`, `parseBytes`, `parseStream`, and
  /// `parseFromTokenizer`), even when [ParseOptions.useCache] is `false`.
  ///
  /// Defaults to `true` when the `METADATA_CACHE_ENABLED=1` environment
  /// variable is set on IO platforms.
  static bool enabled =
      _hasIoEnvironment &&
      Platform.environment['METADATA_CACHE_ENABLED'] == '1';

  static const String _cacheDir = 'metadata_audio_cache';
  static const String _cacheVersion = '5';

  // In-memory cache used ONLY when IO is unavailable (e.g. web).
  static final Map<String, CachedAudioTrack> _memCache = {};
  static final Map<String, CachedMetadataEntry> _metaMemCache = {};

  /// Maximum number of in-memory cached entries when in web/memory mode.
  static const int maxMemoryCacheEntries = 100;

  @visibleForTesting
  static int get memCacheSize => _memCache.length;

  @visibleForTesting
  static int get metaMemCacheSize => _metaMemCache.length;

  /// Returns the directory where cache files are written.
  static Directory get _dir {
    if (!hasIo) {
      throw UnsupportedError('IO is not available on this platform');
    }
    return overrideDirForTesting ??
        Directory(
          '${Directory.systemTemp.path}${Platform.pathSeparator}$_cacheDir',
        );
  }

  // ── public API ─────────────────────────────────────────────────────────────

  /// Reads a cached [CachedAudioTrack] for [url], or `null` if absent /
  /// expired / corrupt.
  static Future<CachedAudioTrack?> get(String url) async {
    final key = _keyFor(url);

    // In-memory cache for web/no-IO platforms
    if (!hasIo) {
      return _memCache[key];
    }

    // Disk cache for IO platforms (no in-memory caching)
    final file = File('${_dir.path}${Platform.pathSeparator}$key.json');
    if (!file.existsSync()) return null;

    try {
      final raw = await file.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['v'] != _cacheVersion) {
        await file.delete();
        return null;
      }
      return CachedAudioTrack.fromJson(map);
    } on Object catch (_) {
      // Corrupt file – delete and ignore.
      try {
        await file.delete();
      } on Object catch (_) {}
      return null;
    }
  }

  /// Writes [entry] to the cache for [url].
  static Future<void> put(String url, CachedAudioTrack entry) async {
    final key = _keyFor(url);

    // In-memory cache for web/no-IO platforms
    if (!hasIo) {
      _memCache[key] = entry;
      if (_memCache.length > maxMemoryCacheEntries) {
        _memCache.remove(_memCache.keys.first);
      }
      return;
    }

    // Disk cache for IO platforms (no in-memory caching)
    try {
      await _dir.create(recursive: true);
      final file = File('${_dir.path}${Platform.pathSeparator}$key.json');
      final map = entry.toJson();
      map['v'] = _cacheVersion;
      map['url'] = url;
      await file.writeAsString(jsonEncode(map));
    } on Object catch (_) {
      // Non-fatal: caching is best-effort.
    }
  }

  // ── general metadata cache (all formats) ───────────────────────────────

  /// Reads a cached [CachedMetadataEntry] (metadata + option coverage + hints)
  /// for [key], or `null` if absent/corrupt.
  static Future<CachedMetadataEntry?> getEntry(String key) async {
    final fileKey = _keyFor(key);

    // In-memory cache for web/no-IO platforms
    if (!hasIo) {
      return _metaMemCache[fileKey];
    }

    // Disk cache for IO platforms (no in-memory caching)
    final file = File(
      '${_dir.path}${Platform.pathSeparator}${fileKey}_meta.json',
    );
    if (!file.existsSync()) return null;
    try {
      final raw = await file.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['v'] != _cacheVersion) {
        await file.delete();
        return null;
      }
      final entry = CachedMetadataEntry.fromJson(map);
      if (entry == null) {
        await file.delete();
        return null;
      }
      return entry;
    } on Object catch (_) {
      try {
        await file.delete();
      } on Object catch (_) {}
      return null;
    }
  }

  /// Writes [entry] (metadata + option coverage + hints) to the cache for [key].
  static Future<void> putEntry(
    String key,
    CachedMetadataEntry entry, {
    int? maxMemoryAllocation,
  }) async {
    // Guard against excessive memory/disk use by capping cache payload
    // based on maxMemoryAllocation (default: 64 MiB).
    final maxAlloc = maxMemoryAllocation ?? (64 * 1024 * 1024);
    final payload = <String, dynamic>{
      'v': _cacheVersion,
      'key': key,
      ...entry.toJson(),
    };
    final encoded = jsonEncode(payload);
    if (encoded.length > maxAlloc) {
      return;
    }

    final fileKey = _keyFor(key);

    // In-memory cache for web/no-IO platforms
    if (!hasIo) {
      _metaMemCache[fileKey] = entry;
      if (_metaMemCache.length > maxMemoryCacheEntries) {
        _metaMemCache.remove(_metaMemCache.keys.first);
      }
      return;
    }

    // Disk cache for IO platforms (no in-memory caching)
    try {
      await _dir.create(recursive: true);
      final file = File(
        '${_dir.path}${Platform.pathSeparator}${fileKey}_meta.json',
      );
      await file.writeAsString(encoded);
    } on Object catch (_) {}
  }

  /// Reads a cached [AudioMetadata] for [key], or `null` if absent/corrupt.
  static Future<AudioMetadata?> getMetadata(String key) async =>
      (await getEntry(key))?.metadata;

  /// Writes [metadata] to the cache for [key].
  static Future<void> putMetadata(
    String key,
    AudioMetadata metadata, {
    int? maxMemoryAllocation,
  }) => putEntry(
    key,
    CachedMetadataEntry(
      metadata: metadata,
      coverage: CachedParseCoverage.full(),
    ),
    maxMemoryAllocation: maxMemoryAllocation,
  );

  /// Evicts a single entry from memory and disk for [urlOrKey].
  static Future<void> evict(String urlOrKey) async {
    final key = _keyFor(urlOrKey);
    _memCache.remove(key);
    _metaMemCache.remove(key);

    if (hasIo) {
      final trackFile = File('${_dir.path}${Platform.pathSeparator}$key.json');
      if (trackFile.existsSync()) {
        try {
          await trackFile.delete();
        } on Object catch (_) {}
      }
      final metaFile = File(
        '${_dir.path}${Platform.pathSeparator}${key}_meta.json',
      );
      if (metaFile.existsSync()) {
        try {
          await metaFile.delete();
        } on Object catch (_) {}
      }
    }
  }

  /// Deletes **all** cached metadata files and clears the in-memory cache.
  static Future<void> clearCache() async {
    _memCache.clear();
    _metaMemCache.clear();
    if (hasIo) {
      final dir = _dir;
      if (dir.existsSync()) {
        try {
          await dir.delete(recursive: true);
        } on Object catch (_) {}
      }
    }
  }

  /// Returns the total size of all cache files on disk in bytes.
  ///
  /// Returns `0` if in web mode or if the cache directory does not exist.
  static int getCacheSize() {
    if (!hasIo) return 0;
    final dir = _dir;
    if (!dir.existsSync()) return 0;
    var total = 0;
    for (final entity in dir.listSync()) {
      if (entity is File) {
        try {
          total += entity.lengthSync();
        } on Object catch (_) {}
      }
    }
    return total;
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  /// Converts a URL/path to a safe file-system key (max 200 chars).
  static String _keyFor(String url) {
    // Simple hash – avoids path-separator and special chars.
    var hash = 0;
    for (var i = 0; i < url.length; i++) {
      hash = (hash * 31 + url.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    // Also embed a sanitised suffix for readability in the file system.
    final sanitised = url
        .replaceAll(RegExp('[^a-zA-Z0-9._-]'), '_')
        .substring(url.length > 60 ? url.length - 60 : 0);
    return '${hash}_$sanitised';
  }
}

// ─── Cached data model ───────────────────────────────────────────────────────

/// A serialisable snapshot of an MP4 audio track's sample tables,
/// sufficient to map chapter timestamps to byte offsets without re-parsing.
class CachedAudioTrack {
  const CachedAudioTrack({
    required this.trackId,
    required this.timeScale,
    required this.sampleRate,
    required this.numberOfChannels,
    required this.sampleSize,
    required this.sampleSizeTable,
    required this.timeToSampleTable,
    required this.sampleToChunkTable,
    required this.chunkOffsetTable,
    this.rawStsdBox,
    this.rawUdtaBox,
    this.rawMetaBox,
    this.metadataChecked = false,
  });

  /// Builds a [CachedAudioTrack] from a live [Mp4TrackInfo] plus the
  /// internal sample tables that are only available on [Mp4Parser].
  factory CachedAudioTrack.fromParser({
    required Mp4TrackInfo trackInfo,
    required List<StscEntry> sampleToChunkTable,
    required List<int> chunkOffsetTable,
    List<int>? rawUdtaBox,
    List<int>? rawMetaBox,
    bool metadataChecked = false,
  }) => CachedAudioTrack(
    trackId: trackInfo.trackId,
    timeScale: trackInfo.timeScale,
    sampleRate: trackInfo.sampleRate,
    numberOfChannels: trackInfo.numberOfChannels,
    sampleSize: trackInfo.sampleSize,
    sampleSizeTable: List<int>.unmodifiable(trackInfo.sampleSizeTable),
    timeToSampleTable: List<SttsEntry>.unmodifiable(
      trackInfo.timeToSampleTable,
    ),
    sampleToChunkTable: List<StscEntry>.unmodifiable(sampleToChunkTable),
    chunkOffsetTable: List<int>.unmodifiable(chunkOffsetTable),
    rawStsdBox: trackInfo.rawStsdBox != null
        ? List<int>.unmodifiable(trackInfo.rawStsdBox!)
        : null,
    rawUdtaBox: rawUdtaBox != null ? List<int>.unmodifiable(rawUdtaBox) : null,
    rawMetaBox: rawMetaBox != null ? List<int>.unmodifiable(rawMetaBox) : null,
    metadataChecked: metadataChecked,
  );

  factory CachedAudioTrack.fromJson(Map<String, dynamic> m) => CachedAudioTrack(
    trackId: m['trackId'] as int,
    timeScale: m['timeScale'] as int?,
    sampleRate: m['sampleRate'] as int?,
    numberOfChannels: m['numberOfChannels'] as int?,
    sampleSize: m['sampleSize'] as int?,
    sampleSizeTable: (m['sampleSizeTable'] as List<dynamic>)
        .map((e) => e as int)
        .toList(),
    timeToSampleTable: (m['timeToSampleTable'] as List<dynamic>)
        .map(
          (e) => SttsEntry(
            count: (e as Map<String, dynamic>)['count'] as int,
            duration: e['duration'] as int,
          ),
        )
        .toList(),
    sampleToChunkTable: (m['sampleToChunkTable'] as List<dynamic>)
        .map(
          (e) => StscEntry(
            firstChunk: (e as Map<String, dynamic>)['firstChunk'] as int,
            samplesPerChunk: e['samplesPerChunk'] as int,
          ),
        )
        .toList(),
    chunkOffsetTable: (m['chunkOffsetTable'] as List<dynamic>)
        .map((e) => e as int)
        .toList(),
    rawStsdBox: _decodeBytes(m['rawStsdBox']),
    rawUdtaBox: _decodeBytes(m['rawUdtaBox']),
    rawMetaBox: _decodeBytes(m['rawMetaBox']),
    metadataChecked: m['metadataChecked'] as bool? ?? false,
  );

  static List<int>? _decodeBytes(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) return base64Decode(raw);
    if (raw is List) return raw.map((e) => e as int).toList();
    return null;
  }

  /// The MP4 track ID (usually 1 or 2).
  final int trackId;

  /// Audio timescale (e.g. 44100).
  final int? timeScale;

  /// Audio sample rate in Hz.
  final int? sampleRate;

  /// Number of audio channels.
  final int? numberOfChannels;

  /// Uniform sample size (0 when variable – see [sampleSizeTable]).
  final int? sampleSize;

  /// Per-sample sizes from the `stsz` box.
  final List<int> sampleSizeTable;

  /// Time-to-sample run-length table from the `stts` box.
  final List<SttsEntry> timeToSampleTable;

  /// Sample-to-chunk table from the `stsc` box.
  final List<StscEntry> sampleToChunkTable;

  /// Chunk-byte-offset table from the `stco`/`co64` box.
  final List<int> chunkOffsetTable;

  /// Raw `stsd` box bytes, used to build standalone M4A containers.
  final List<int>? rawStsdBox;

  /// Raw `udta` box bytes (excluding `chpl`), used to preserve original
  /// iTunes/MP4 metadata and cover art in sliced chapter `.m4a` files.
  final List<int>? rawUdtaBox;

  /// Raw top-level `moov.meta` box bytes (when present outside `udta`).
  final List<int>? rawMetaBox;

  /// Whether metadata boxes (`udta`/`meta`) were already checked/captured
  /// without skipping cover art.
  final bool metadataChecked;

  // ── sample index & byte offset lookup ──────────────────────────────────────

  /// Converts a time offset (in track [timeScale] units) to a
  /// 0-based sample index.
  int? getSampleIndexForTime(int timeOffset) {
    if (timeToSampleTable.isEmpty) {
      return null;
    }

    var remainingTime = timeOffset;
    var sampleIndex = 0;

    for (final entry in timeToSampleTable) {
      if (remainingTime <= 0) {
        return sampleIndex;
      }

      final sampleDuration = entry.duration;
      if (sampleDuration <= 0) {
        return null;
      }

      final maxSamplesToConsume = entry.count;
      final samplesNeeded = remainingTime ~/ sampleDuration;

      if (samplesNeeded < maxSamplesToConsume) {
        return sampleIndex + samplesNeeded;
      }

      sampleIndex += maxSamplesToConsume;
      remainingTime -= maxSamplesToConsume * sampleDuration;
    }

    return sampleIndex;
  }

  /// Converts a 0-based sample index to the absolute file byte offset
  /// of that sample.
  int? getByteOffsetForSample(int targetSampleIndex) {
    if (chunkOffsetTable.isEmpty || sampleToChunkTable.isEmpty) {
      return null;
    }

    var currentSampleIndex = 0;
    var currentChunkId = 1;
    var chunkIndexInTable = 0;
    var samplesPerChunk = sampleToChunkTable[0].samplesPerChunk;

    while (true) {
      final nextRunFirstChunk =
          (chunkIndexInTable + 1 < sampleToChunkTable.length)
          ? sampleToChunkTable[chunkIndexInTable + 1].firstChunk
          : chunkOffsetTable.length + 1;

      final chunksInRun = nextRunFirstChunk - currentChunkId;
      final totalSamplesInRun = chunksInRun * samplesPerChunk;

      if (targetSampleIndex < currentSampleIndex + totalSamplesInRun) {
        final relativeSampleIndex = targetSampleIndex - currentSampleIndex;
        final chunkOffsetInRun = relativeSampleIndex ~/ samplesPerChunk;
        final sampleOffsetInChunk = relativeSampleIndex % samplesPerChunk;

        final targetChunkId = currentChunkId + chunkOffsetInRun;
        if (targetChunkId - 1 >= chunkOffsetTable.length) return null;

        final chunkByteOffset = chunkOffsetTable[targetChunkId - 1];
        var sampleByteOffset = 0;
        final firstSampleInChunkIndex =
            currentSampleIndex + chunkOffsetInRun * samplesPerChunk;

        for (var i = 0; i < sampleOffsetInChunk; i++) {
          final idx = firstSampleInChunkIndex + i;
          if (sampleSize != null && sampleSize! > 0) {
            sampleByteOffset += sampleSize!;
          } else if (idx < sampleSizeTable.length) {
            sampleByteOffset += sampleSizeTable[idx];
          }
        }
        return chunkByteOffset + sampleByteOffset;
      }

      currentSampleIndex += totalSamplesInRun;
      currentChunkId = nextRunFirstChunk;
      chunkIndexInTable++;
      if (chunkIndexInTable >= sampleToChunkTable.length) break;
      samplesPerChunk = sampleToChunkTable[chunkIndexInTable].samplesPerChunk;
    }

    return null;
  }

  // ── serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'trackId': trackId,
    'timeScale': timeScale,
    'sampleRate': sampleRate,
    'numberOfChannels': numberOfChannels,
    'sampleSize': sampleSize,
    'sampleSizeTable': sampleSizeTable,
    'timeToSampleTable': timeToSampleTable
        .map((e) => {'count': e.count, 'duration': e.duration})
        .toList(),
    'sampleToChunkTable': sampleToChunkTable
        .map(
          (e) => {
            'firstChunk': e.firstChunk,
            'samplesPerChunk': e.samplesPerChunk,
          },
        )
        .toList(),
    'chunkOffsetTable': chunkOffsetTable,
    'rawStsdBox': rawStsdBox,
    if (rawUdtaBox != null) 'rawUdtaBox': base64Encode(rawUdtaBox!),
    if (rawMetaBox != null) 'rawMetaBox': base64Encode(rawMetaBox!),
    'metadataChecked': metadataChecked,
  };
}
