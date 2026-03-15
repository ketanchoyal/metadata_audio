import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/mpeg/mpeg_loader.dart';
import 'package:test/test.dart';

void main() {
  group('Regression unknown encoding fallback', () {
    setUp(() {
      final registry = ParserRegistry()..register(MpegLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('falls back to UTF-8 for non-standard encoding byte', () async {
      final payload = <int>[0x09, ...utf8.encode('Fallback Title')];
      final frame = _buildRawFrame('TIT2', payload);

      final metadata = await parseBytes(
        Uint8List.fromList(_buildId3Tag(frame)),
        fileInfo: const FileInfo(
          path: 'unknown-encoding.mp3',
          mimeType: 'audio/mpeg',
        ),
      );

      expect(metadata.common.title, equals('Fallback Title'));
    });
  });
}

List<int> _buildRawFrame(String id, List<int> payload) => <int>[
  ...id.codeUnits,
  (payload.length >> 24) & 0xFF,
  (payload.length >> 16) & 0xFF,
  (payload.length >> 8) & 0xFF,
  payload.length & 0xFF,
  0x00,
  0x00,
  ...payload,
];

List<int> _buildId3Tag(List<int> frame) {
  final size = frame.length;
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
    ...frame,
  ];
}
