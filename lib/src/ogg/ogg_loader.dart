library;

import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/ogg/ogg_parser.dart';
import 'package:metadata_audio/src/ogg/vorbis/vorbis_tag_map.dart';
import 'package:metadata_audio/src/parser_factory.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

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
    final mapper = CombinedTagMapper()
      ..registerMapper('vorbis', VorbisTagMapper());
    final metadata = MetadataCollector(mapper, observer: options.observer);
    metadata.setFormat(container: 'Ogg');

    final parser = OggParser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await parser.parse();

    return metadata.toAudioMetadata();
  }
}
