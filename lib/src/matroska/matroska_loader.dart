library;

// ignore_for_file: public_member_api_docs

import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/matroska/matroska_parser.dart';
import 'package:metadata_audio/src/matroska/matroska_tag_mapper.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parser_factory.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class MatroskaLoader extends ParserLoader {
  @override
  List<String> get extension => const <String>[
    'mka',
    'mkv',
    'mk3d',
    'mks',
    'webm',
  ];

  @override
  List<String> get mimeType => const <String>[
    'audio/matroska',
    'video/matroska',
    'audio/webm',
    'video/webm',
  ];

  @override
  bool get hasRandomAccessRequirements => true;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    final mapper = CombinedTagMapper()
      ..registerMapper('matroska', MatroskaTagMapper());

    final metadata = MetadataCollector(mapper, observer: options.observer);

    final parser = MatroskaParser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await parser.parse();

    return metadata.toAudioMetadata();
  }
}
