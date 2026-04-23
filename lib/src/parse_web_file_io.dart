/// IO platform stub for parseWebFile.
///
/// On IO platforms, browser File objects are not available.
/// Use [parseFile] instead.
library;

import 'package:metadata_audio/src/model/types.dart';

/// Parse audio metadata from a browser File object.
///
/// **Not available on IO platforms.**
/// Throws [UnsupportedError] when called on IO.
/// Use [parseFile] instead to parse from file paths.
///
/// On web platforms, this function accepts a `web.File` object
/// from the browser's File API (e.g., from `<input type="file">`
/// or drag-and-drop events).
Future<AudioMetadata> parseWebFile(Object file, {ParseOptions? options}) async {
  throw UnsupportedError(
    'parseWebFile() is not supported on IO platforms. '
    'Use parseFile() instead.',
  );
}
