library;

import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/dsdiff/dsdiff_parser.dart';
import 'package:metadata_audio/src/id3v2/id3v2_tag_map.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parser_factory.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class DsdiffLoader extends ParserLoader {
  @override
  List<String> get extension => const <String>['dff'];

  @override
  List<String> get mimeType => const <String>['audio/dsf', 'audio/dsd'];

  @override
  bool get hasRandomAccessRequirements => false;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    final mapper = CombinedTagMapper()
      ..registerMapper('ID3v2.2', Id3v2TagMapper())
      ..registerMapper('ID3v2.3', Id3v2TagMapper())
      ..registerMapper('ID3v2.4', Id3v2TagMapper());

    final metadata = MetadataCollector(mapper);
    final parser = DsdiffParser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await parser.parse();

    return metadata.toAudioMetadata();
  }
}
