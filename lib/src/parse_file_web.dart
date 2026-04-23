/// Web platform stub for parseFile.
///
/// On web platforms, file system access is not available.
/// Use [parseBytes] or [parseUrl] instead.
library;

import 'package:metadata_audio/src/model/types.dart';

/// Parse audio metadata from a file path.
///
/// **Not available on web platforms.**
/// Throws [UnsupportedError] when called on web.
/// Use [parseBytes] or [parseUrl] instead.
///
/// **Example (IO only):**
/// ```dart
/// final metadata = await parseFile('music.mp3');
/// ```
Future<AudioMetadata> parseFile(String path, {ParseOptions? options}) async {
  throw UnsupportedError(
    'parseFile() is not supported on web platform. '
    'Use parseBytes() or parseUrl() instead.',
  );
}