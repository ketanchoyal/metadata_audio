library;

import 'package:audio_metadata/src/apev2/apev2_tag_map.dart';
import 'package:audio_metadata/src/common/combined_tag_mapper.dart';
import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/parser_factory.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';
import 'package:audio_metadata/src/wavpack/wavpack_parser.dart';

class WavPackLoader extends ParserLoader {
  @override
  List<String> get extension => const <String>['wv', 'wvp'];

  @override
  List<String> get mimeType => const <String>['audio/wavpack'];

  @override
  bool get hasRandomAccessRequirements => true;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    final mapper = CombinedTagMapper()
      ..registerMapper('APEv2', Apev2TagMapper());

    final metadata = MetadataCollector(mapper);
    final parser = WavPackParser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await parser.parse();

    return metadata.toAudioMetadata();
  }
}
