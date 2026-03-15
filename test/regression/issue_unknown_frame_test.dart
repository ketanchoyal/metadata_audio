import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/mpeg/mpeg_loader.dart';
import 'package:test/test.dart';

void main() {
  group('Regression unknown ID3v2 frame handling', () {
    setUp(() {
      final registry = ParserRegistry()..register(MpegLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('ignores unknown frame IDs without breaking known tags', () async {
      final knownTitleFrame = _buildTextFrame('TIT2', 'Known Title');
      final unknownFrame = _buildRawFrame('ZZZZ', <int>[
        0xDE,
        0xAD,
        0xBE,
        0xEF,
      ]);

      final metadata = await parseBytes(
        Uint8List.fromList(
          _buildId3Tag(<int>[...unknownFrame, ...knownTitleFrame]),
        ),
        fileInfo: const FileInfo(
          path: 'unknown-frame.mp3',
          mimeType: 'audio/mpeg',
        ),
      );

      expect(metadata.common.title, equals('Known Title'));
      expect(metadata.native['ID3v2.3'], isNotNull);
      expect(
        metadata.native['ID3v2.3']!.where((tag) => tag.id == 'ZZZZ'),
        isEmpty,
      );
    });
  });
}

List<int> _buildTextFrame(String id, String value) {
  final payload = <int>[0x03, ...value.codeUnits];
  return _buildRawFrame(id, payload);
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
