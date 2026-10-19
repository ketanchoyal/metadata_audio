/// Memory allocation guards for metadata parsing (upstream parity).
///
/// Mirrors upstream `lib/common/Allocation.ts` from Borewit/music-metadata.
library;

import '../model/types.dart';

/// Default maximum bytes buffered for a single metadata payload, accumulated
/// Ogg packet, or tokenizer stream lookahead. Matches upstream's
/// `defaultMaxMemoryAllocation` (64 MiB).
const _defaultMaxMemoryAllocation = 64 * 1024 * 1024;

/// Returns the validated `maxMemoryAllocation` limit for the given
/// [options].
///
/// Throws [ArgumentError] when the value is not a positive integer.
int getMaxMemoryAllocation(ParseOptions options) {
  final limit =
      options.maxMemoryAllocation ?? _defaultMaxMemoryAllocation;
  if (limit <= 0) {
    throw ArgumentError.value(
      limit,
      'maxMemoryAllocation',
      'must be a positive safe integer',
    );
  }
  return limit;
}
