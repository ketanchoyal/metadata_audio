import 'package:metadata_audio/src/id3v2/id3v2_loader.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:test/test.dart';

import 'id3_test_utils.dart';

void main() {
  group('ID3v2.2 parser', () {
    test('parses TT2 title and maps to common title', () async {
      final titleFrame = buildId3v22Frame('TT2', [
        0x00,
        ...'Song v2.2'.codeUnits,
      ]);
      final tag = buildId3Tag(
        majorVersion: 2,
        revision: 0,
        flags: 0x00,
        payload: titleFrame,
      );

      final loader = Id3v2Loader();
      final tokenizer = MockTokenizer(
        data: tag,
        fileInfo: const FileInfo(path: 'song.mp3', size: 1024),
      );

      final metadata = await loader.parse(tokenizer, const ParseOptions());

      expect(metadata.native['ID3v2.2'], isNotNull);
      expect(metadata.native['ID3v2.2']!.single.id, equals('TT2'));
      expect(metadata.native['ID3v2.2']!.single.value, equals(['Song v2.2']));
      expect(metadata.common.title, equals('Song v2.2'));
    });
  });
}
