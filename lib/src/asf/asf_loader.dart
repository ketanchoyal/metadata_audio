library;

import 'package:metadata_audio/src/asf/asf_parser.dart';
import 'package:metadata_audio/src/asf/asf_tag_map.dart';
import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parser_factory.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class AsfLoader extends ParserLoader {
  @override
  List<String> get extension => const <String>['asf', 'wma', 'wmv'];

  @override
  List<String> get mimeType => const <String>[
    'audio/x-ms-wma',
    'audio/x-ms-asf',
    'video/x-ms-asf',
    'application/vnd.ms-asf',
    'audio/ms-wma',
    'video/ms-wmv',
    'audio/ms-asf',
    'video/ms-asf',
  ];

  @override
  bool get hasRandomAccessRequirements => false;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    final mapper = CombinedTagMapper()..registerMapper('asf', AsfTagMapper());

    final metadata = MetadataCollector(mapper);
    final parser = AsfParser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );

    await parser.parse();
    return metadata.toAudioMetadata();
  }
}
