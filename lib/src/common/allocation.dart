/// Memory allocation guards for metadata parsing (upstream parity).
///
/// Mirrors upstream `lib/common/Allocation.ts` from Borewit/music-metadata.
library;

import '../model/types.dart';

/// Default maximum bytes buffered for a single metadata payload, accumulated
/// Ogg packet, or tokenizer stream lookahead. Matches upstream's
/// `defaultMaxMemoryAllocation` (64 MiB).
const _defaultMaxMemoryAllocation = 64 * 1024 * 1024;

/// Default limit for entries in an individual decoded list or table.
///
/// Matches upstream's `defaultMaxMetadataEntries` (100,000).
const _defaultMaxMetadataEntries = 100000;

/// Default maximum number of chapters returned by supported chapter parsers.
///
/// Matches upstream's `defaultMaxChapterCount` (1,000).
const _defaultMaxChapterCount = 1000;

/// Returns the validated `maxMemoryAllocation` limit for the given
/// [options].
///
/// Throws [ArgumentError] when the value is not a positive integer.
int getMaxMemoryAllocation(ParseOptions options) {
  final limit = options.maxMemoryAllocation ?? _defaultMaxMemoryAllocation;
  if (limit <= 0) {
    throw ArgumentError.value(
      limit,
      'maxMemoryAllocation',
      'must be a positive safe integer',
    );
  }
  return limit;
}

/// Returns the validated `maxMetadataEntries` limit for the given [options].
///
/// Limits entries in an individual decoded list or table, independently of
/// byte-buffer limits. Mirrors upstream `getMaxMetadataEntries`.
///
/// Throws [ArgumentError] when the value is not a positive integer.
int getMaxMetadataEntries(ParseOptions options) {
  final limit = options.maxMetadataEntries ?? _defaultMaxMetadataEntries;
  if (limit <= 0) {
    throw ArgumentError.value(
      limit,
      'maxMetadataEntries',
      'must be a positive safe integer',
    );
  }
  return limit;
}

/// Returns the validated `maxChapterCount` limit for the given [options].
///
/// Maximum number of chapters returned by supported chapter parsers.
/// Mirrors upstream `getMaxChapterCount`.
///
/// Throws [ArgumentError] when the value is not a positive integer.
int getMaxChapterCount(ParseOptions options) {
  final limit = options.maxChapterCount ?? _defaultMaxChapterCount;
  if (limit <= 0) {
    throw ArgumentError.value(
      limit,
      'maxChapterCount',
      'must be a positive safe integer',
    );
  }
  return limit;
}
