library;

import 'package:metadata_audio/src/apev2/apev2_tag_map.dart';
import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parser_factory.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:metadata_audio/src/wavpack/wavpack_parser.dart';

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

    final metadata = MetadataCollector(mapper, options);
    final parser = WavPackParser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await parser.parse();

    return metadata.toAudioMetadata();
  }
}
