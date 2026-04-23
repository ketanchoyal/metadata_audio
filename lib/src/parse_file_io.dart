/// IO platform implementation of parseFile.
///
/// This file is used on platforms where dart:io is available (VM, Flutter).
/// On web platforms, [parse_file_web.dart] is used instead.
library;

import 'package:metadata_audio/src/core_impl.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';

/// Parse audio metadata from a file path.
///
/// Opens the file, creates a tokenizer, and delegates to parseFromTokenizer.
///
/// **Parameters:**
/// - `path`: File path to parse
/// - `options`: Parse options (optional, defaults to standard options)
///
/// **Throws:**
/// - `FileSystemException`: If file cannot be opened or read
/// - `TokenizerException`: If tokenizer operations fail
/// - `CouldNotDetermineFileTypeError`: If file format cannot be determined
/// - `UnrecognizedFormatError`: If format is recognized but parsing fails
Future<AudioMetadata> parseFile(String path, {ParseOptions? options}) async {
  final tokenizer = FileTokenizer.fromPath(path);
  try {
    return await parseFromTokenizer(tokenizer, options: options);
  } finally {
    tokenizer.close();
  }
}