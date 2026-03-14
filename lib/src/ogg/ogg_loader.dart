library;

import 'package:audio_metadata/src/common/combined_tag_mapper.dart';
import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/ogg/ogg_parser.dart';
import 'package:audio_metadata/src/parser_factory.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

class OggLoader extends ParserLoader {
  @override
  List<String> get extension => const <String>['ogg', 'oga', 'ogv'];

  @override
  List<String> get mimeType => const <String>[
    'audio/ogg',
    'application/ogg',
    'audio/vorbis',
  ];

  @override
  bool get hasRandomAccessRequirements => false;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    final metadata = MetadataCollector(CombinedTagMapper());
    metadata.setFormat(container: 'ogg');

    final parser = OggParser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await parser.parse();

    return metadata.toAudioMetadata();
  }
}
