library;

import 'package:audio_metadata/src/common/combined_tag_mapper.dart';
import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/dsf/dsf_parser.dart';
import 'package:audio_metadata/src/id3v2/id3v2_tag_map.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/parser_factory.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

class DsfLoader extends ParserLoader {
  @override
  List<String> get extension => const <String>['dsf'];

  @override
  List<String> get mimeType => const <String>['audio/dsf'];

  @override
  bool get hasRandomAccessRequirements => false;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    final mapper = CombinedTagMapper()
      ..registerMapper('ID3v2.2', Id3v2TagMapper())
      ..registerMapper('ID3v2.3', Id3v2TagMapper())
      ..registerMapper('ID3v2.4', Id3v2TagMapper());

    final metadata = MetadataCollector(mapper);
    final parser = DsfParser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await parser.parse();

    return metadata.toAudioMetadata();
  }
}
