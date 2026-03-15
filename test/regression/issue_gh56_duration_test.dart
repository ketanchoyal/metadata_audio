import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/mpeg/mpeg_loader.dart';
import 'package:test/test.dart';

void main() {
  group('Regression GH-56 (CBR duration)', () {
    setUp(() {
      final registry = ParserRegistry()..register(MpegLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('calculates CBR duration from frame count and file size', () async {
      final frames = <int>[];
      for (var i = 0; i < 12; i++) {
        frames.addAll(_buildMpegFrame());
      }

      final metadata = await parseBytes(
        Uint8List.fromList(frames),
        fileInfo: FileInfo(path: 'gh56.mp3', size: frames.length),
        options: const ParseOptions(duration: true),
      );

      expect(metadata.format.codecProfile, equals('CBR'));
      expect(metadata.format.numberOfSamples, equals(12 * 1152));
      expect(metadata.format.duration, closeTo(12 * 1152 / 44100, 0.01));
    });
  });
}

List<int> _buildMpegFrame({int bitrateIndex = 9}) {
  const sampleRate = 44100;
  const samplesPerFrame = 1152;
  final bitrateKbps = _bitrateFromIndex(bitrateIndex);
  final bitrate = bitrateKbps * 1000;
  final frameLength = (samplesPerFrame / 8.0 * bitrate / sampleRate).floor();

  final header = <int>[0xFF, 0xFB, (bitrateIndex << 4), 0x40];
  final payload = List<int>.filled(frameLength - 4, 0);
  return <int>[...header, ...payload];
}

int _bitrateFromIndex(int index) {
  const table = <int, int>{
    1: 32,
    2: 40,
    3: 48,
    4: 56,
    5: 64,
    6: 80,
    7: 96,
    8: 112,
    9: 128,
    10: 160,
    11: 192,
    12: 224,
    13: 256,
    14: 320,
  };
  return table[index] ?? 128;
}
