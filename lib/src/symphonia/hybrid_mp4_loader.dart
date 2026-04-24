library;

import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/mp4/mp4_loader.dart';
import 'package:metadata_audio/src/parser_factory.dart';
import 'package:metadata_audio/src/symphonia/symphonia_loader.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class HybridMp4Loader extends ParserLoader {
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
    final rustMetadata = await SymphoniaLoader().parse(tokenizer, options);
    if (!options.includeChapters) {
      return rustMetadata;
    }

    tokenizer.seek(0);
    final dartMetadata = await Mp4Loader().parse(tokenizer, options);

    return AudioMetadata(
      format: _mergeFormat(rustMetadata.format, dartMetadata.format),
      native: rustMetadata.native,
      common: rustMetadata.common,
      quality: _mergeQuality(rustMetadata.quality, dartMetadata.quality),
    );
  }

  Format _mergeFormat(Format rustFormat, Format dartFormat) => Format(
      container: rustFormat.container,
      tagTypes: rustFormat.tagTypes,
      duration: rustFormat.duration,
      bitrate: rustFormat.bitrate,
      sampleRate: rustFormat.sampleRate,
      bitsPerSample: rustFormat.bitsPerSample,
      tool: rustFormat.tool,
      codec: rustFormat.codec,
      codecProfile: rustFormat.codecProfile,
      lossless: rustFormat.lossless,
      numberOfChannels: rustFormat.numberOfChannels,
      numberOfSamples: rustFormat.numberOfSamples,
      audioMD5: rustFormat.audioMD5,
      chapters: dartFormat.chapters,
      creationTime: rustFormat.creationTime,
      modificationTime: rustFormat.modificationTime,
      trackGain: rustFormat.trackGain,
      trackPeakLevel: rustFormat.trackPeakLevel,
      albumGain: rustFormat.albumGain,
      hasAudio: rustFormat.hasAudio,
      hasVideo: rustFormat.hasVideo,
      trackInfo: rustFormat.trackInfo,
    );

  QualityInformation _mergeQuality(
    QualityInformation rustQuality,
    QualityInformation dartQuality,
  ) => QualityInformation(
      warnings: <ParserWarning>[
        ...rustQuality.warnings,
        ...dartQuality.warnings,
      ],
    );
}
