/// Web platform implementation for parsing audio metadata from browser files.
///
/// Provides [parseWebFile] which accepts `web.File` objects from
/// file pickers, drag-and-drop, or other browser file APIs.
///
/// On IO platforms, this function is replaced by a stub that throws
/// [UnsupportedError]. Use [parseFile] on IO platforms instead.
library;

import 'dart:js_interop';

import 'package:metadata_audio/src/core_impl.dart';
import 'package:web/web.dart' as web;

/// Parse audio metadata from a browser [web.File] object.
///
/// This is the recommended way to parse audio files on web platforms.
/// Use it with file picker results, drag-and-drop events, or any other
/// browser API that provides [web.File] objects.
///
/// The function reads the entire file into memory using [web.File.arrayBuffer],
/// then delegates to [parseBytes] for parsing.
///
/// **Parameters:**
/// - `file`: A [web.File] object from the browser (e.g., from `<input type="file">`
///   or drag-and-drop event). Pass the native `web.File` directly.
/// - `options`: Parse options (optional)
///
/// **Throws:**
/// - `CouldNotDetermineFileTypeError`: If file format cannot be determined
/// - `UnrecognizedFormatError`: If format is recognized but parsing fails
///
/// **Example (with package:web):**
/// ```dart
/// import 'dart:js_interop';
/// import 'package:web/web.dart' as web;
/// import 'package:metadata_audio/metadata_audio.dart';
///
/// void setupFileInput() {
///   final input = document.getElementById('file-input') as web.HTMLInputElement;
///   input.onchange = ((web.Event e) {
///     final file = (e.target as web.HTMLInputElement).files!.item(0)!;
///     final metadata = await parseWebFile(file);
///     print('Title: ${metadata.common.title}');
///   }).toJS;
/// }
/// ```
///
/// **Example (with file_picker in Flutter Web):**
/// ```dart
/// import 'package:file_picker/file_picker.dart';
/// import 'package:metadata_audio/metadata_audio.dart';
///
/// final result = await FilePicker.platform.pickFiles(type: FileType.audio);
/// if (result != null) {
///   final bytes = result.files.single.bytes!;
///   final metadata = await parseBytes(
///     bytes,
///     fileInfo: FileInfo(path: result.files.single.name),
///   );
/// }
/// ```
Future<AudioMetadata> parseWebFile(Object file, {ParseOptions? options}) async {
  final webFile = file as web.File;

  // Read the entire file into memory
  final arrayBuffer = await webFile.arrayBuffer().toDart;
  final bytes = arrayBuffer.toDart.asUint8List();

  // Build FileInfo from web.File properties
  // web.File.name and web.File.type return Dart String (not JSString)
  // web.File.size returns Dart int (not JSNumber)
  final fileInfo = FileInfo(
    path: webFile.name,
    mimeType: webFile.type.isEmpty ? null : webFile.type,
    size: webFile.size,
  );

  return parseBytes(bytes, fileInfo: fileInfo, options: options);
}
