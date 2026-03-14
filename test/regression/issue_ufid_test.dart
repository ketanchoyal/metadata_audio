import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata/audio_metadata.dart';
import 'package:audio_metadata/src/mpeg/mpeg_loader.dart';
import 'package:test/test.dart';

void main() {
  group('Regression UFID frame parsing', () {
    setUp(() {
      final registry = ParserRegistry()..register(MpegLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('extracts UFID owner and identifier payload', () async {
      final ufidPayload = <int>[
        ...ascii.encode('http://musicbrainz.org'),
        0x00,
        0x12,
        0x34,
        0x56,
        0x78,
      ];

      final bytes = Uint8List.fromList(
        _buildId3Tag(_buildRawFrame('UFID', ufidPayload)),
      );

      final metadata = await parseBytes(
        bytes,
        fileInfo: const FileInfo(path: 'ufid.mp3', mimeType: 'audio/mpeg'),
      );

      expect(metadata.native['ID3v2.3'], isNotNull);
      final ufidTags = metadata.native['ID3v2.3']!.where(
        (tag) => tag.id == 'UFID',
      );
      expect(ufidTags, isNotEmpty);

      final ufidValue = ufidTags.first.value as Map<String, dynamic>;
      expect(ufidValue['owner'], equals('http://musicbrainz.org'));
      expect(ufidValue['identifier'], equals([0x12, 0x34, 0x56, 0x78]));
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
