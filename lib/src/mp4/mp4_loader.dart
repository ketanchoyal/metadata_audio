library;

import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/mp4/mp4_parser.dart';
import 'package:metadata_audio/src/mp4/mp4_tag_mapper.dart';
import 'package:metadata_audio/src/parser_factory.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class Mp4Loader extends ParserLoader {
  @override
  List<String> get extension => const <String>[
    'mp4',
    'm4a',
    'm4b',
    'm4p',
    'm4r',
    'm4v',
  ];

  @override
  List<String> get mimeType => const <String>[
    'audio/mp4',
    'video/mp4',
    'audio/x-m4a',
  ];

  @override
  bool get hasRandomAccessRequirements => true;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    final mapper = CombinedTagMapper()
      ..registerMapper('iTunes', Mp4TagMapper());

    final metadata = MetadataCollector(mapper, options);
    metadata.setFormat(container: 'mp4');

    final parser = Mp4Parser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await parser.parse();

    return metadata.toAudioMetadata();
  }
}
