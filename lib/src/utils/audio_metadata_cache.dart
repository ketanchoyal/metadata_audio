import 'dart:convert';
import 'dart:io';

import 'package:metadata_audio/src/mp4/atom_token.dart';
import 'package:metadata_audio/src/mp4/mp4_parser.dart';

/// A disk-backed cache for parsed MP4/M4B audio-track metadata.
///
/// Stores [CachedAudioTrack] entries in the OS temp directory under
/// `metadata_audio_cache/`. The OS can evict these files at any time;
/// [clearCache] removes them explicitly.
///
/// **Cache key**: A sanitised version of the source URL/path, so the
/// same file is never re-parsed within the same or subsequent app runs.
class AudioMetadataCache {
  AudioMetadataCache._();

  static const String _cacheDir = 'metadata_audio_cache';
  static const String _cacheVersion = '1';

  // In-memory cache (simple map – sufficient for typical audiobook usage).
  static final Map<String, CachedAudioTrack> _memCache = {};

  /// Returns the directory where cache files are written.
  static Directory get _dir => Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}$_cacheDir',
      );

  // ── public API ─────────────────────────────────────────────────────────────

  /// Reads a cached [CachedAudioTrack] for [url], or `null` if absent /
  /// expired / corrupt.
  static Future<CachedAudioTrack?> get(String url) async {
    final key = _keyFor(url);

    // 1. Memory hit
    if (_memCache.containsKey(key)) return _memCache[key];

    // 2. Disk hit
    final file = File(
      '${_dir.path}${Platform.pathSeparator}$key.json',
    );
    if (!file.existsSync()) return null;

    try {
      final raw = await file.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['v'] != _cacheVersion) {
        await file.delete();
        return null;
      }
      final entry = CachedAudioTrack.fromJson(map);
      _memCache[key] = entry;
      return entry;
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
    _memCache[key] = entry;

    try {
      await _dir.create(recursive: true);
      final file = File(
        '${_dir.path}${Platform.pathSeparator}$key.json',
      );
      final map = entry.toJson();
      map['v'] = _cacheVersion;
      map['url'] = url;
      await file.writeAsString(jsonEncode(map));
    } on Object catch (_) {
      // Non-fatal: caching is best-effort.
    }
  }

  /// Evicts a single entry from memory and disk for [url].
  static Future<void> evict(String url) async {
    final key = _keyFor(url);
    _memCache.remove(key);
    final file = File(
      '${_dir.path}${Platform.pathSeparator}$key.json',
    );
    if (file.existsSync()) {
      try {
        await file.delete();
      } on Object catch (_) {}
    }
  }

  /// Deletes **all** cached metadata files and clears the in-memory cache.
  ///
  /// Call this when the user explicitly triggers "Clear Cache" in the UI.
  static Future<void> clearCache() async {
    _memCache.clear();
    final dir = _dir;
    if (dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } on Object catch (_) {}
    }
  }

  /// Returns the total size of all cache files on disk in bytes.
  ///
  /// Returns `0` if the cache directory does not yet exist.
  static int getCacheSize() {
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
  });

  /// Builds a [CachedAudioTrack] from a live [Mp4TrackInfo] plus the
  /// internal sample tables that are only available on [Mp4Parser].
  factory CachedAudioTrack.fromParser({
    required Mp4TrackInfo trackInfo,
    required List<StscEntry> sampleToChunkTable,
    required List<int> chunkOffsetTable,
  }) =>
      CachedAudioTrack(
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
      );

  factory CachedAudioTrack.fromJson(Map<String, dynamic> m) =>
      CachedAudioTrack(
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
        rawStsdBox: m['rawStsdBox'] == null
            ? null
            : (m['rawStsdBox'] as List<dynamic>).map((e) => e as int).toList(),
      );

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
      };
}
