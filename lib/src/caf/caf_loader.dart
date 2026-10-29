/// CAF (Core Audio File) loader, ported from upstream
/// `lib/caf/CafLoader.ts` (Borewit/music-metadata).
library;

import 'package:metadata_audio/src/caf/caf_parser.dart';
import 'package:metadata_audio/src/caf/caf_tag_map.dart';
import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parser_factory.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class CafLoader extends ParserLoader {
  @override
  List<String> get extension => const <String>['caf', 'caff'];

  @override
  List<String> get mimeType => const <String>['audio/caf', 'application/caf'];

  @override
  bool get hasRandomAccessRequirements => false;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    final mapper = CombinedTagMapper()
      ..registerMapper('CAF', CafTagMapper());

    final metadata = MetadataCollector(mapper, options);

    final parser = CafParser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await parser.parse();

    return metadata.toAudioMetadata();
  }
}
