library;

import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

/// Contract for lazily loading and invoking an audio metadata parser.
///
/// A parser loader declares which extensions and MIME types it can handle,
/// whether it requires random access, and how it parses metadata from a
/// tokenizer.
abstract class ParserLoader {
  /// File extensions this parser handles (without leading dot), for example
  /// `mp3`, `flac`.
  List<String> get extension;

  /// MIME types this parser handles, for example `audio/mpeg`.
  List<String> get mimeType;

  /// Whether this parser requires random access support from the tokenizer.
  bool get hasRandomAccessRequirements;

  /// Returns true if [tokenizer] capabilities satisfy parser requirements.
  ///
  /// By default, this enforces [hasRandomAccessRequirements] against
  /// [Tokenizer.canSeek].
  bool supports(Tokenizer tokenizer) =>
      !hasRandomAccessRequirements || tokenizer.canSeek;

  /// Parse metadata from [tokenizer] using [options].
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options);
}
