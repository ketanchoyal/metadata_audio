library;

import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

/// Scans for appending headers at the end of the audio file
///
/// When [skipPostHeaders] is false and the tokenizer supports random access,
/// this function scans the end of the file for post-headers (e.g., ID3v1 tags).
///
/// **Parameters:**
/// - `tokenizer`: The tokenizer providing access to file data
/// - `skipPostHeaders`: If true, skips the post-header scan entirely
///
/// **Behavior:**
/// - If `skipPostHeaders` is true: Returns immediately without scanning
/// - If tokenizer doesn't support seek (canSeek=false): Continues without post-scan
/// - If tokenizer supports seek: Performs post-header scan (actual detection delegated to format parsers)
///
/// **Returns:** null (placeholder for future return value if needed)
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
