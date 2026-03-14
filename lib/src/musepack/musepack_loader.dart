library;

// ignore_for_file: public_member_api_docs

import 'package:audio_metadata/src/apev2/apev2_tag_map.dart';
import 'package:audio_metadata/src/common/combined_tag_mapper.dart';
import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/matroska/matroska_tag_mapper.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/musepack/musepack_parser.dart';
import 'package:audio_metadata/src/parser_factory.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

class MusepackLoader extends ParserLoader {
  @override
  List<String> get extension => const <String>['mpc', 'mp+', 'mpk', 'mka'];

  @override
  List<String> get mimeType => const <String>[
    'audio/x-musepack',
    'audio/musepack',
    'video/x-musepack',
    'video/webm',
  ];

  @override
  bool get hasRandomAccessRequirements => true;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    final mapper = CombinedTagMapper()
      ..registerMapper('APEv2', Apev2TagMapper())
      ..registerMapper('matroska', MatroskaTagMapper());

    final metadata = MetadataCollector(mapper);
    final parser = MusepackParser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await parser.parse();
    return metadata.toAudioMetadata();
  }
}
