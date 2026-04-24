library;

import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/native/api.dart';
import 'package:metadata_audio/src/parser_factory.dart';
import 'package:metadata_audio/src/symphonia/symphonia_converter.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class SymphoniaLoader extends ParserLoader {
  @override
  List<String> get extension => const <String>[
    'mp3',
    'flac',
    'mp4',
    'm4a',
    'm4b',
    'ogg',
    'oga',
    'wav',
    'aiff',
    'aif',
    'ape',
    'mkv',
    'mka',
    'wv',
  ];

  @override
  List<String> get mimeType => const <String>[
    'audio/mpeg',
    'audio/flac',
    'audio/mp4',
    'audio/x-m4a',
    'audio/ogg',
    'audio/vorbis',
    'audio/wav',
    'audio/x-wav',
    'audio/aiff',
    'audio/x-aiff',
    'audio/ape',
    'audio/x-monkeys-audio',
    'video/x-matroska',
    'audio/x-matroska',
    'audio/x-wavpack',
  ];

  @override
  bool get hasRandomAccessRequirements => false;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    if (tokenizer is FileTokenizer) {
      final path = tokenizer.fileInfo?.path;
      if (path == null || path.isEmpty) {
        return _parseFromTokenizerBytes(tokenizer);
      }

      final metadata = await parseFromPath(path: path);
      return convertFfiAudioMetadata(metadata);
    }

    if (tokenizer is BytesTokenizer) {
      return _parseFromTokenizerBytes(tokenizer);
    }

    if (tokenizer.canSeek && tokenizer.hasCompleteData) {
      return _parseFromTokenizerBytes(tokenizer);
    }

    throw UnsupportedError(
      'SymphoniaLoader requires a file path, BytesTokenizer, or a complete '
      'seekable tokenizer (got ${tokenizer.runtimeType}).',
    );
  }

  Future<AudioMetadata> _parseFromTokenizerBytes(Tokenizer tokenizer) async {
    final size = tokenizer.fileInfo?.size;
    if (size == null) {
      throw StateError('${tokenizer.runtimeType} is missing fileInfo.size');
    }

    tokenizer.seek(0);
    final bytes = tokenizer.readBytes(size);
    final metadata = await parseFromBytes(
      bytes: bytes,
      mimeHint: tokenizer.fileInfo?.mimeType,
    );
    return convertFfiAudioMetadata(metadata);
  }
}
