import 'dart:convert';

import 'package:metadata_audio/src/id3v2/id3v2_loader.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:test/test.dart';

import 'id3_test_utils.dart';

void main() {
  group('ID3v2.3 parser', () {
    test('handles extended header and parses TIT2', () async {
      final titleFrame = buildId3v23Frame('TIT2', [
        0x00,
        ...latin1.encode('Song v2.3'),
      ]);

      final extendedHeader = <int>[0x00, 0x00, 0x00, 0x06, 0x00, 0x00];

      final tag = buildId3Tag(
        majorVersion: 3,
        revision: 0,
        flags: 0x40,
        payload: [...extendedHeader, ...titleFrame],
      );

      final loader = Id3v2Loader();
      final tokenizer = MockTokenizer(
        data: tag,
        fileInfo: const FileInfo(path: 'song.mp3', size: 2048),
      );

      final metadata = await loader.parse(tokenizer, const ParseOptions());

      expect(metadata.native['ID3v2.3'], isNotNull);
      expect(metadata.common.title, equals('Song v2.3'));
    });

    test(
      'applies tag-level unsynchronisation when frame flag is set',
      () async {
        final unsyncedPayload = <int>[0x00, 0x41, 0xFF, 0x00, 0x42];
        final titleFrame = buildId3v23Frame(
          'TIT2',
          unsyncedPayload,
          flags2: 0x02,
        );

        final tag = buildId3Tag(
          majorVersion: 3,
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

        expect(metadata.common.title, equals('A${String.fromCharCode(0xFF)}B'));
      },
    );
  });
}
