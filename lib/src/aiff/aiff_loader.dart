library;

import 'package:metadata_audio/src/aiff/aiff_parser.dart';
import 'package:metadata_audio/src/aiff/aiff_tag_map.dart';
import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/id3v2/id3v2_tag_map.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parser_factory.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class AiffLoader extends ParserLoader {
  @override
  List<String> get extension => const <String>['aiff', 'aif', 'aifc'];

  @override
  List<String> get mimeType => const <String>[
    'audio/aiff',
    'audio/x-aiff',
    'sound/aiff',
  ];

  @override
  bool get hasRandomAccessRequirements => true;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    final mapper = CombinedTagMapper()
      ..registerMapper('AIFF', AiffTagMapper())
      ..registerMapper('ID3v2.2', Id3v2TagMapper())
      ..registerMapper('ID3v2.3', Id3v2TagMapper())
      ..registerMapper('ID3v2.4', Id3v2TagMapper());

    final metadata = MetadataCollector(mapper, observer: options.observer);
    final parser = AiffParser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await parser.parse();

    return metadata.toAudioMetadata();
  }
}
