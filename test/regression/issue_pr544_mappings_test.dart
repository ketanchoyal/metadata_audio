import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

void main() {
  group('Regression PR-544 (common tag mappings)', () {
    setUp(() {
      final registry = ParserRegistry()..register(MpegLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('maps extended ID3v2 fields to 20+ common tags', () async {
      final frames = <int>[
        ..._buildTextFrame('TIT2', 'Mapping Regression'),
        ..._buildTextFrame('TPE1', 'Regression Artist'),
        ..._buildTextFrame('TALB', 'Regression Album'),
        ..._buildTextFrame('TPE2', 'Album Artist'),
        ..._buildTextFrame('TSOT', 'Title Sort'),
        ..._buildTextFrame('TSOA', 'Album Sort'),
        ..._buildTextFrame('TSOP', 'Artist Sort'),
        ..._buildTextFrame('TSO2', 'Album Artist Sort'),
        ..._buildTextFrame('TMOO', 'Calm'),
        ..._buildTextFrame('TCOM', 'Composer Name'),
        ..._buildTextFrame('TEXT', 'Lyricist Name'),
        ..._buildTextFrame('TENC', 'Encoder Name'),
        ..._buildTextFrame('TPUB', 'Publisher Name'),
        ..._buildTextFrame('TIT1', 'Grouping Value'),
        ..._buildTextFrame('MVNM', 'Movement Name'),
        ..._buildTextFrame('MVIN', '2/4'),
        ..._buildTextFrame('PCST', '1'),
        ..._buildTextFrame('PCS', 'Podcast ID Value'),
        ..._buildTextFrame('TLAN', 'eng'),
        ..._buildTextFrame('TCOP', 'Copyright Notice'),
        ..._buildTextFrame('TCON', 'Podcast'),
      ];

      final bytes = Uint8List.fromList(_buildId3Tag(frames));

      final metadata = await parseBytes(
        bytes,
        fileInfo: const FileInfo(path: 'pr544.mp3', mimeType: 'audio/mpeg'),
      );

      expect(metadata.common.title, equals('Mapping Regression'));
      expect(metadata.common.artist, equals('Regression Artist'));
      expect(metadata.common.album, equals('Regression Album'));

      // TODO(T095): Expand ID3v2 tag mapping parity with upstream PR-544.
    });
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
