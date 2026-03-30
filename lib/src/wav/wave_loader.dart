library;

import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/id3v2/id3v2_tag_map.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parser_factory.dart';
import 'package:metadata_audio/src/riff/riff_info_tag_map.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:metadata_audio/src/wav/wave_parser.dart';

class WaveLoader extends ParserLoader {
  @override
  List<String> get extension => const <String>['wav', 'wave'];

  @override
  List<String> get mimeType => const <String>[
    'audio/wav',
    'audio/x-wav',
    'audio/wave',
  ];

  @override
  bool get hasRandomAccessRequirements => true;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    final mapper = CombinedTagMapper()
      ..registerMapper('exif', RiffInfoTagMapper())
      ..registerMapper('ID3v2.2', Id3v2TagMapper())
      ..registerMapper('ID3v2.3', Id3v2TagMapper())
      ..registerMapper('ID3v2.4', Id3v2TagMapper());

    final metadata = MetadataCollector(mapper, options);

    final parser = WaveParser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await parser.parse();

    return metadata.toAudioMetadata();
  }
}
