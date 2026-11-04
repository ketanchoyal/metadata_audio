/// Memory allocation guards for metadata parsing.
library;

import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parse_error.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

/// Default maximum bytes buffered for a single metadata payload, accumulated
/// Ogg packet, or tokenizer stream lookahead (64 MiB).
const defaultMaxMemoryAllocation = 64 * 1024 * 1024;
const _defaultMaxMemoryAllocation = defaultMaxMemoryAllocation;

/// Default limit for entries in an individual decoded list or table (100,000).
const defaultMaxMetadataEntries = 100000;
const _defaultMaxMetadataEntries = defaultMaxMetadataEntries;

/// Default maximum number of chapters returned by supported chapter parsers (1,000).
const defaultMaxChapterCount = 1000;
const _defaultMaxChapterCount = defaultMaxChapterCount;

/// Chunk size used for bounded reading (64 KiB).
const readChunkSize = 64 * 1024;

/// Factory function type for constructing exceptions thrown when an allocation fails validation.
typedef AllocationErrorFactory = Exception Function(String message);

/// Default exception factory producing an [UnexpectedFileContentError].
Exception defaultAllocationError(String message) =>
    UnexpectedFileContentError('metadata', message);

/// Check untrusted lengths before allocating, including accumulated stream payloads.
///
/// Throws an error from [makeError] (defaulting to [UnexpectedFileContentError])
/// if [length] is negative or exceeds [options.maxMemoryAllocation].
void validateAllocation(
  int length,
  ParseOptions options, [
  AllocationErrorFactory makeError = defaultAllocationError,
]) {
  if (length < 0) {
    throw makeError('Invalid allocation size: $length');
  }
  final limit = getMaxMemoryAllocation(options);
  if (length > limit) {
    throw makeError(
      'Metadata size $length exceeds allocation limit $limit (buffering limit)',
    );
  }
}

/// Reads [length] bytes from [tokenizer] after validating the allocation size
/// against [options.maxMemoryAllocation] and verifying sufficient bytes remain.
List<int> readBuffer(
  Tokenizer tokenizer,
  int length,
  ParseOptions options, [
  AllocationErrorFactory makeError = defaultAllocationError,
]) {
  validateAllocation(length, options, makeError);
  final fileInfoSize = tokenizer.fileInfo?.size;
  if (fileInfoSize != null && length > fileInfoSize - tokenizer.position) {
    throw TokenizerException(
      'End of file reached: requested $length bytes at position ${tokenizer.position}, total size $fileInfoSize',
    );
  }
  return tokenizer.readBytes(length);
}

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
/// byte-buffer limits.
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
