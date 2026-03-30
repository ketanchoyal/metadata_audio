library;

import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/flac/flac_parser.dart';
import 'package:metadata_audio/src/flac/flac_vorbis_tag_map.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parser_factory.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class FlacLoader extends ParserLoader {
  @override
  List<String> get extension => const <String>['flac'];

  @override
  List<String> get mimeType => const <String>['audio/flac', 'audio/x-flac'];

  @override
  bool get hasRandomAccessRequirements => true;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    final mapper = CombinedTagMapper()
      ..registerMapper('vorbis', FlacVorbisTagMapper());

    final metadata = MetadataCollector(mapper, options);
    metadata.setFormat(container: 'FLAC');

    final parser = FlacParser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await parser.parse();

    return metadata.toAudioMetadata();
  }
}
