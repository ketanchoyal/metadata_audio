import 'dart:async';

import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/mp4/mp4_parser.dart';
import 'package:metadata_audio/src/mp4/mp4_tag_mapper.dart';
import 'package:metadata_audio/src/parser_factory.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:metadata_audio/src/utils/audio_metadata_cache.dart';
import 'package:metadata_audio/src/utils/cache_types.dart';

class Mp4Loader extends ParserLoader with HintProvidingParserLoader {
  @override
  List<String> get extension => const <String>[
    'mp4',
    'm4a',
    'm4b',
    'm4p',
    'm4r',
    'm4v',
    'mov',
  ];

  @override
  List<String> get mimeType => const <String>[
    'audio/mp4',
    'video/mp4',
    'audio/x-m4a',
    'video/quicktime',
  ];

  @override
  bool get hasRandomAccessRequirements => true;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async =>
      (await parseWithHints(tokenizer, options)).metadata;

  @override
  Future<({AudioMetadata metadata, CachedParseHints? hints})> parseWithHints(
    Tokenizer tokenizer,
    ParseOptions options,
  ) async {
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

    final source = tokenizer.fileInfo?.url ?? tokenizer.fileInfo?.path;
    if (source != null && source.isNotEmpty) {
      final audioTrack = parser
          .getTrackInfos()
          .where((t) => t.isAudio)
          .firstOrNull;
      if (audioTrack != null) {
        final stsc = parser.getSampleToChunkTable(audioTrack.trackId) ?? [];
        final stco = parser.getChunkOffsetTable(audioTrack.trackId) ?? [];
        final hasCompleteSampleTables =
            stco.isNotEmpty &&
            stsc.isNotEmpty &&
            audioTrack.timeToSampleTable.isNotEmpty &&
            ((audioTrack.sampleSize ?? 0) > 0 ||
                audioTrack.sampleSizeTable.isNotEmpty);
        if (hasCompleteSampleTables) {
          final cached = CachedAudioTrack.fromParser(
            trackInfo: audioTrack,
            sampleToChunkTable: stsc,
            chunkOffsetTable: stco,
            rawUdtaBox: parser.rawUdtaBox,
            rawMetaBox: parser.rawMetaBox,
            metadataChecked: !options.skipCovers,
          );
          unawaited(AudioMetadataCache.put(source, cached));
        }
      }
    }

    final hints = CachedParseHints(
      fileSize: tokenizer.fileInfo?.size,
      moovOffset: parser.moovOffset,
      moovSize: parser.moovSize,
      mp4Chapters: parser.getCachedChapterInfo(),
    );

    return (metadata: metadata.toAudioMetadata(), hints: hints);
  }
}
