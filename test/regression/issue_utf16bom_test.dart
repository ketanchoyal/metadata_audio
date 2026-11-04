import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

void main() {
  group('Regression UTF-16 BE BOM handling', () {
    setUp(() {
      final registry = ParserRegistry()..register(MpegLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('decodes UTF-16 text with big-endian BOM in text frame', () async {
      final payload = <int>[0x01, 0xFE, 0xFF, ..._utf16Be('BOM Title')];
      final frame = _buildRawFrame('TIT2', payload);

      final metadata = await parseBytes(
        Uint8List.fromList(_buildId3Tag(frame)),
        fileInfo: const FileInfo(path: 'utf16bom.mp3', mimeType: 'audio/mpeg'),
      );

      expect(metadata.common.title, equals('BOM Title'));
    });
  });
}

List<int> _utf16Be(String value) {
  final out = <int>[];
  for (final unit in value.codeUnits) {
    out
      ..add((unit >> 8) & 0xFF)
      ..add(unit & 0xFF);
  }
  return out;
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
