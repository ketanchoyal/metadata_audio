library;

// ignore_for_file: public_member_api_docs

import 'package:audio_metadata/src/apev2/apev2_parser.dart';
import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/musepack/musepack_content_error.dart';
import 'package:audio_metadata/src/musepack/sv7/bit_reader.dart';
import 'package:audio_metadata/src/musepack/sv7/stream_version7.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

class MpcSv7Parser {
  MpcSv7Parser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  late BitReader _bitReader;
  var _audioLength = 0;
  double? _duration;

  Future<void> parse() async {
    final header = StreamVersion7.parseHeader(
      tokenizer.readBytes(StreamVersion7.headerLength),
    );

    if (header.signature != 'MP+') {
      throw MusepackContentError('Unexpected magic number');
    }

    metadata.setFormat(
      container: 'Musepack, SV7',
      sampleRate: header.sampleFrequency,
    );

    final numberOfSamples =
        1152 * (header.frameCount - 1) + header.lastFrameLength;
    _duration = numberOfSamples / header.sampleFrequency;
    metadata.setFormat(
      numberOfSamples: numberOfSamples,
      duration: _duration,
      numberOfChannels: header.midSideStereo || header.intensityStereo ? 2 : 1,
    );

    _bitReader = BitReader(tokenizer);

    final version = await _bitReader.read(8);
    metadata.setFormat(codec: (version / 100).toStringAsFixed(2));

    await _skipAudioData(header.frameCount);

    await Apev2Parser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    ).tryParseApeHeader();
  }

  Future<void> _skipAudioData(int frameCount) async {
    var remainingFrames = frameCount;
    while (remainingFrames-- > 0) {
      final frameLength = await _bitReader.read(20);
      _audioLength += 20 + frameLength;
      await _bitReader.ignore(frameLength);
    }

    final lastFrameLength = await _bitReader.read(11);
    _audioLength += lastFrameLength;

    if (_duration != null && _duration! > 0) {
      metadata.setFormat(bitrate: (_audioLength / _duration!).round());
    }
  }
}
