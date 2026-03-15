import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/mpeg/mpeg_loader.dart';
import 'package:test/test.dart';

void main() {
  group('Regression non-ASCII characters', () {
    setUp(() {
      final registry = ParserRegistry()..register(MpegLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('preserves UTF-8 accented characters in ID3 text frames', () async {
      const title = 'Beyoncé - Halo (Acoustic Café) - Cliché';
      const artist = 'Sigur Rós - Jónsi';

      final frames = <int>[
        ..._buildTextFrame('TIT2', title),
        ..._buildTextFrame('TPE1', artist),
      ];

      final metadata = await parseBytes(
        Uint8List.fromList(_buildId3Tag(frames)),
        fileInfo: const FileInfo(path: 'non-ascii.mp3', mimeType: 'audio/mpeg'),
      );

      expect(metadata.common.title, equals(title));
      expect(metadata.common.artist, equals(artist));
    });
  });
}

List<int> _buildTextFrame(String id, String value) {
  final payload = <int>[0x03, ...utf8.encode(value)];
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
