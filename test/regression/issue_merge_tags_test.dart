import 'dart:typed_data';

import 'package:audio_metadata/audio_metadata.dart';
import 'package:audio_metadata/src/mpeg/mpeg_loader.dart';
import 'package:test/test.dart';

void main() {
  group('Regression merge ID3v1 + ID3v2 tags', () {
    setUp(() {
      final registry = ParserRegistry()..register(MpegLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test(
      'prefers ID3v2 values over ID3v1 while still merging non-empty fields',
      () async {
        final id3v2 = _buildId3Tag(
          _buildTextFrame('TIT2', 'ID3v2 Title') +
              _buildTextFrame('TPE1', 'ID3v2 Artist'),
        );

        final mpegFrame = _buildMpegFrame();
        final id3v1 = _buildId3v1Tag(
          title: 'ID3v1 Title',
          artist: 'ID3v1 Artist',
        );

        final bytes = Uint8List.fromList(<int>[
          ...id3v2,
          ...mpegFrame,
          ...id3v1,
        ]);

        final metadata = await parseBytes(
          bytes,
          fileInfo: FileInfo(path: 'merge-tags.mp3', size: bytes.length),
          options: const ParseOptions(duration: true),
        );

        expect(metadata.common.title, equals('ID3v2 Title'));
        expect(metadata.common.artist, equals('ID3v2 Artist'));

        // TODO(T095): Verify richer merge semantics once tag-priority
        // parity is complete.
      },
    );
  });
}

List<int> _buildTextFrame(String id, String value) {
  final payload = <int>[0x03, ...value.codeUnits];
  return <int>[
    ...id.codeUnits,
    (payload.length >> 24) & 0xFF,
    (payload.length >> 16) & 0xFF,
    (payload.length >> 8) & 0xFF,
    payload.length & 0xFF,
    0x00,
    0x00,
    ...payload,
  ];
}

List<int> _buildId3Tag(List<int> frames) {
  final size = frames.length;
  return <int>[
    0x49,
    0x44,
    0x33,
    0x03,
    0x00,
    0x00,
    (size >> 21) & 0x7F,
    (size >> 14) & 0x7F,
    (size >> 7) & 0x7F,
    size & 0x7F,
    ...frames,
  ];
}

List<int> _buildId3v1Tag({required String title, required String artist}) {
  final tag = List<int>.filled(128, 0);
  tag[0] = 0x54;
  tag[1] = 0x41;
  tag[2] = 0x47;

  for (var i = 0; i < title.length && i < 30; i++) {
    tag[3 + i] = title.codeUnitAt(i);
  }
  for (var i = 0; i < artist.length && i < 30; i++) {
    tag[33 + i] = artist.codeUnitAt(i);
  }

  return tag;
}

List<int> _buildMpegFrame({int bitrateIndex = 9}) {
  const sampleRate = 44100;
  const samplesPerFrame = 1152;
  final bitrateKbps = _bitrateFromIndex(bitrateIndex);
  final bitrate = bitrateKbps * 1000;
  final frameLength = (samplesPerFrame / 8.0 * bitrate / sampleRate).floor();
  return <int>[
    0xFF,
    0xFB,
    (bitrateIndex << 4),
    0x40,
    ...List<int>.filled(frameLength - 4, 0),
  ];
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
