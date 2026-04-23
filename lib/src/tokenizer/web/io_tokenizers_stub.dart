/// Web platform stub for FileTokenizer.
///
/// FileTokenizer is not available on web because dart:io is not available.
/// Use [BytesTokenizer] or HTTP-based tokenizers instead.
library;

import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

/// Stub for FileTokenizer on web platform.
///
/// All methods throw [UnsupportedError] because file system access
/// is not available on web. Use [BytesTokenizer] or HTTP-based
/// tokenizers ([HttpTokenizer], [RangeTokenizer], etc.) instead.
class FileTokenizer extends Tokenizer {
  /// Not available on web platform.
  ///
  /// Throws [UnsupportedError]. Use [BytesTokenizer] or HTTP-based
  /// tokenizers instead.
  // ignore: avoid_unused_constructor_parameters
  factory FileTokenizer.fromPath(String filePath) {
    throw UnsupportedError(
      'FileTokenizer is not available on web platform. '
      'Use BytesTokenizer or HTTP-based tokenizers instead.',
    );
  }

  /// Not available on web platform.
  ///
  /// Throws [UnsupportedError]. Use [BytesTokenizer] or HTTP-based
  /// tokenizers instead.
  // ignore: avoid_unused_constructor_parameters
  factory FileTokenizer.fromFile(dynamic file) {
    throw UnsupportedError(
      'FileTokenizer is not available on web platform. '
      'Use BytesTokenizer or HTTP-based tokenizers instead.',
    );
  }

  @override
  final FileInfo? fileInfo = null;

  @override
  int get position =>
      throw UnsupportedError('FileTokenizer is not available on web platform.');

  @override
  bool get canSeek => true;

  @override
  int readUint8() =>
      throw UnsupportedError('FileTokenizer is not available on web platform.');

  @override
  int readUint16() =>
      throw UnsupportedError('FileTokenizer is not available on web platform.');

  @override
  int readUint32() =>
      throw UnsupportedError('FileTokenizer is not available on web platform.');

  @override
  List<int> readBytes(int length) =>
      throw UnsupportedError('FileTokenizer is not available on web platform.');

  @override
  int peekUint8() =>
      throw UnsupportedError('FileTokenizer is not available on web platform.');

  @override
  List<int> peekBytes(int length) =>
      throw UnsupportedError('FileTokenizer is not available on web platform.');

  @override
  void skip(int length) =>
      throw UnsupportedError('FileTokenizer is not available on web platform.');

  @override
  void seek(int position) =>
      throw UnsupportedError('FileTokenizer is not available on web platform.');
}
