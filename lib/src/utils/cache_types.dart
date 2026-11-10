import 'dart:convert';

import 'package:metadata_audio/src/common/allocation.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/mp4/atom_token.dart';
import 'package:metadata_audio/src/utils/audio_metadata_json.dart';

/// Tracks which [ParseOptions] capabilities have been satisfied in a cached
/// [AudioMetadata] entry so subsequent parses can reuse existing data and
/// fetch only newly enabled options.
class CachedParseCoverage {
  const CachedParseCoverage({
    this.hasCovers = false,
    this.hasChapters = false,
    this.hasPostHeaders = false,
    this.hasDuration = false,
    this.mkvUseIndex = false,
    this.maxChapterCount = 1000,
    this.maxMetadataEntries = 100000,
    this.chaptersTruncated = false,
  });

  factory CachedParseCoverage.fromOptions(
    ParseOptions options,
    AudioMetadata metadata,
  ) {
    final chapterLimit = getMaxChapterCount(options);
    final chaptersCount = metadata.format.chapters?.length ?? 0;
    return CachedParseCoverage(
      hasCovers: !options.skipCovers,
      hasChapters: options.includeChapters,
      hasPostHeaders: !options.skipPostHeaders,
      hasDuration: options.duration,
      mkvUseIndex: options.mkvUseIndex,
      maxChapterCount: chapterLimit,
      maxMetadataEntries: getMaxMetadataEntries(options),
      chaptersTruncated:
          options.includeChapters && chaptersCount >= chapterLimit,
    );
  }

  factory CachedParseCoverage.fromJson(Map<String, dynamic> m) =>
      CachedParseCoverage(
        hasCovers: m['hasCovers'] as bool? ?? false,
        hasChapters: m['hasChapters'] as bool? ?? false,
        hasPostHeaders: m['hasPostHeaders'] as bool? ?? false,
        hasDuration: m['hasDuration'] as bool? ?? false,
        mkvUseIndex: m['mkvUseIndex'] as bool? ?? false,
        maxChapterCount: m['maxChapterCount'] as int? ?? 1000,
        maxMetadataEntries: m['maxMetadataEntries'] as int? ?? 100000,
        chaptersTruncated: m['chaptersTruncated'] as bool? ?? false,
      );

  /// Full coverage preset used when legacy [putMetadata] callers store raw
  /// metadata without explicit [ParseOptions].
  factory CachedParseCoverage.full() => const CachedParseCoverage(
    hasCovers: true,
    hasChapters: true,
    hasPostHeaders: true,
    hasDuration: true,
  );

  final bool hasCovers;
  final bool hasChapters;
  final bool hasPostHeaders;
  final bool hasDuration;
  final bool mkvUseIndex;
  final int maxChapterCount;
  final int maxMetadataEntries;
  final bool chaptersTruncated;

  /// Computes which newly requested [ParseOptions] are not yet satisfied by
  /// this cached entry.
  MissingParseOptions missingRequirements(
    ParseOptions options,
    AudioMetadata metadata,
  ) {
    final requestedMaxChapters = getMaxChapterCount(options);
    final requestedMaxEntries = getMaxMetadataEntries(options);

    final needChapters =
        options.includeChapters &&
        (!hasChapters ||
            (chaptersTruncated && requestedMaxChapters > maxChapterCount));
    final needCovers = !options.skipCovers && !hasCovers;
    final needPostHeaders = !options.skipPostHeaders && !hasPostHeaders;
    final needDuration =
        options.duration && !hasDuration && needsFullDurationScan(metadata);
    final needMkvFullScan =
        !options.mkvUseIndex && mkvUseIndex && isMatroskaContainer(metadata);
    final needHigherEntryLimit = requestedMaxEntries > maxMetadataEntries;

    return MissingParseOptions(
      chapters: needChapters,
      covers: needCovers,
      postHeaders: needPostHeaders,
      duration: needDuration,
      mkvFullScan: needMkvFullScan,
      higherEntryLimit: needHigherEntryLimit,
    );
  }

  /// Returns `true` when all capabilities requested by [options] are already
  /// present in this cached entry.
  bool satisfies(ParseOptions options, AudioMetadata metadata) =>
      missingRequirements(options, metadata).isEmpty;

  /// Returns the combined coverage after merging [other] into `this`.
  CachedParseCoverage merge(
    CachedParseCoverage other,
    AudioMetadata mergedMetadata,
  ) {
    final mergedHasChapters = hasChapters || other.hasChapters;
    final mergedMaxChapters = other.hasChapters
        ? (hasChapters
              ? (other.maxChapterCount > maxChapterCount
                    ? other.maxChapterCount
                    : maxChapterCount)
              : other.maxChapterCount)
        : maxChapterCount;
    final chaptersCount = mergedMetadata.format.chapters?.length ?? 0;

    return CachedParseCoverage(
      hasCovers: hasCovers || other.hasCovers,
      hasChapters: mergedHasChapters,
      hasPostHeaders: hasPostHeaders || other.hasPostHeaders,
      hasDuration: hasDuration || other.hasDuration,
      mkvUseIndex: mkvUseIndex && other.mkvUseIndex,
      maxChapterCount: mergedMaxChapters,
      maxMetadataEntries: other.maxMetadataEntries > maxMetadataEntries
          ? other.maxMetadataEntries
          : maxMetadataEntries,
      chaptersTruncated:
          mergedHasChapters && chaptersCount >= mergedMaxChapters,
    );
  }

  Map<String, dynamic> toJson() => {
    'hasCovers': hasCovers,
    'hasChapters': hasChapters,
    'hasPostHeaders': hasPostHeaders,
    'hasDuration': hasDuration,
    'mkvUseIndex': mkvUseIndex,
    'maxChapterCount': maxChapterCount,
    'maxMetadataEntries': maxMetadataEntries,
    'chaptersTruncated': chaptersTruncated,
  };

  /// Whether `options.duration = true` can produce different results from
  /// `options.duration = false` for [metadata].
  ///
  /// Only MPEG/MP3 (and Ogg without duration) alter parsing behavior based on
  /// `options.duration`; all other containers derive exact duration from headers.
  static bool needsFullDurationScan(AudioMetadata metadata) {
    final container = metadata.format.container?.toLowerCase() ?? '';
    if (container == 'mp3' || container == 'mpeg' || container == 'adts') {
      return true;
    }
    if (container == 'ogg' && metadata.format.duration == null) {
      return true;
    }
    return false;
  }

  static bool isMatroskaContainer(AudioMetadata metadata) {
    final container = metadata.format.container?.toLowerCase() ?? '';
    return container == 'matroska' ||
        container == 'webm' ||
        container.contains('matroska');
  }
}

/// Describes which capabilities are missing from a cached entry for a new
/// [ParseOptions] request.
class MissingParseOptions {
  const MissingParseOptions({
    this.chapters = false,
    this.covers = false,
    this.postHeaders = false,
    this.duration = false,
    this.mkvFullScan = false,
    this.higherEntryLimit = false,
  });

  final bool chapters;
  final bool covers;
  final bool postHeaders;
  final bool duration;
  final bool mkvFullScan;
  final bool higherEntryLimit;

  bool get isEmpty =>
      !chapters &&
      !covers &&
      !postHeaders &&
      !duration &&
      !mkvFullScan &&
      !higherEntryLimit;

  bool get isNotEmpty => !isEmpty;

  /// Builds [ParseOptions] tailored to fetch only the missing capabilities
  /// while preserving resource limits from [requested].
  ParseOptions toDeltaOptions(ParseOptions requested) => ParseOptions(
    skipCovers: !covers,
    skipPostHeaders: !postHeaders,
    includeChapters: chapters,
    duration: duration,
    maxMemoryAllocation: requested.maxMemoryAllocation,
    maxMetadataEntries: requested.maxMetadataEntries,
    maxChapterCount: requested.maxChapterCount,
    mkvUseIndex: requested.mkvUseIndex && !mkvFullScan,
  );
}

/// Serialisable sample-table snapshot for an MP4 track (chapter or audio).
class CachedMp4TrackData {
  const CachedMp4TrackData({
    required this.trackId,
    required this.timeScale,
    required this.durationUnits,
    required this.sampleSize,
    required this.sampleSizeTable,
    required this.timeToSampleTable,
    required this.sampleToChunkTable,
    required this.chunkOffsetTable,
  });

  factory CachedMp4TrackData.fromJson(Map<String, dynamic> m) =>
      CachedMp4TrackData(
        trackId: m['trackId'] as int,
        timeScale: m['timeScale'] as int?,
        durationUnits: m['durationUnits'] as int?,
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
      );

  final int trackId;
  final int? timeScale;
  final int? durationUnits;
  final int? sampleSize;
  final List<int> sampleSizeTable;
  final List<SttsEntry> timeToSampleTable;
  final List<StscEntry> sampleToChunkTable;
  final List<int> chunkOffsetTable;

  Map<String, dynamic> toJson() => {
    'trackId': trackId,
    'timeScale': timeScale,
    'durationUnits': durationUnits,
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
  };
}

/// Cached MP4 chapter table hints so enabling `includeChapters: true` on a
/// subsequent run can resolve chapters with minimal or zero extra calls.
class CachedMp4ChapterInfo {
  const CachedMp4ChapterInfo({
    required this.hasChapterSource,
    this.chplPayload,
    this.chapterTrack,
    this.referencedTrack,
  });

  factory CachedMp4ChapterInfo.fromJson(Map<String, dynamic> m) {
    final chplRaw = m['chplPayload'] as String?;
    return CachedMp4ChapterInfo(
      hasChapterSource: m['hasChapterSource'] as bool? ?? false,
      chplPayload: chplRaw == null ? null : base64Decode(chplRaw),
      chapterTrack: m['chapterTrack'] == null
          ? null
          : CachedMp4TrackData.fromJson(
              m['chapterTrack'] as Map<String, dynamic>,
            ),
      referencedTrack: m['referencedTrack'] == null
          ? null
          : CachedMp4TrackData.fromJson(
              m['referencedTrack'] as Map<String, dynamic>,
            ),
    );
  }

  final bool hasChapterSource;
  final List<int>? chplPayload;
  final CachedMp4TrackData? chapterTrack;
  final CachedMp4TrackData? referencedTrack;

  Map<String, dynamic> toJson() => {
    'hasChapterSource': hasChapterSource,
    if (chplPayload != null) 'chplPayload': base64Encode(chplPayload!),
    if (chapterTrack != null) 'chapterTrack': chapterTrack!.toJson(),
    if (referencedTrack != null) 'referencedTrack': referencedTrack!.toJson(),
  };
}

/// Format-specific byte-location hints cached alongside [AudioMetadata] to
/// enable targeted incremental fetches when new [ParseOptions] are turned on.
class CachedParseHints {
  const CachedParseHints({
    this.fileSize,
    this.id3v2Size,
    this.moovOffset,
    this.moovSize,
    this.mp4Chapters,
  });

  factory CachedParseHints.fromJson(Map<String, dynamic> m) => CachedParseHints(
    fileSize: m['fileSize'] as int?,
    id3v2Size: m['id3v2Size'] as int?,
    moovOffset: m['moovOffset'] as int?,
    moovSize: m['moovSize'] as int?,
    mp4Chapters: m['mp4Chapters'] == null
        ? null
        : CachedMp4ChapterInfo.fromJson(
            m['mp4Chapters'] as Map<String, dynamic>,
          ),
  );

  final int? fileSize;
  final int? id3v2Size;
  final int? moovOffset;
  final int? moovSize;
  final CachedMp4ChapterInfo? mp4Chapters;

  CachedParseHints merge(CachedParseHints? other) {
    if (other == null) return this;
    return CachedParseHints(
      fileSize: other.fileSize ?? fileSize,
      id3v2Size: other.id3v2Size ?? id3v2Size,
      moovOffset: other.moovOffset ?? moovOffset,
      moovSize: other.moovSize ?? moovSize,
      mp4Chapters: other.mp4Chapters ?? mp4Chapters,
    );
  }

  Map<String, dynamic> toJson() => {
    if (fileSize != null) 'fileSize': fileSize,
    if (id3v2Size != null) 'id3v2Size': id3v2Size,
    if (moovOffset != null) 'moovOffset': moovOffset,
    if (moovSize != null) 'moovSize': moovSize,
    if (mp4Chapters != null) 'mp4Chapters': mp4Chapters!.toJson(),
  };
}

/// Complete cached metadata record stored under a single source key.
class CachedMetadataEntry {
  const CachedMetadataEntry({
    required this.metadata,
    required this.coverage,
    this.hints,
  });

  static CachedMetadataEntry? fromJson(Map<String, dynamic> m) {
    final metaRaw = m['data'];
    if (metaRaw is! Map<String, dynamic>) return null;
    final meta = audioMetadataFromJson(metaRaw);
    if (meta == null) return null;

    final coverageRaw = m['coverage'];
    final coverage = coverageRaw is Map<String, dynamic>
        ? CachedParseCoverage.fromJson(coverageRaw)
        : CachedParseCoverage.full();

    final hintsRaw = m['hints'];
    final hints = hintsRaw is Map<String, dynamic>
        ? CachedParseHints.fromJson(hintsRaw)
        : null;

    return CachedMetadataEntry(
      metadata: meta,
      coverage: coverage,
      hints: hints,
    );
  }

  final AudioMetadata metadata;
  final CachedParseCoverage coverage;
  final CachedParseHints? hints;

  Map<String, dynamic> toJson() => {
    'data': audioMetadataToJson(metadata),
    'coverage': coverage.toJson(),
    if (hints != null) 'hints': hints!.toJson(),
  };
}
