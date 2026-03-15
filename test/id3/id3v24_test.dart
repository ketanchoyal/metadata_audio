import 'dart:convert';

import 'package:metadata_audio/src/id3v2/id3v2_loader.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:test/test.dart';

import 'id3_test_utils.dart';

void main() {
  group('ID3v2.4 parser', () {
    test('parses CHAP + CTOC into format.chapters', () async {
      final chapterTitleFrame = buildId3v24Frame('TIT2', [
        0x03,
        ...utf8.encode('Intro'),
      ]);

      final chapterData = <int>[
        ...ascii.encode('ch1'),
        0x00,
        // startTime
        0x00,
        0x00,
        0x00,
        0x00,
        // endTime = 5000
        0x00,
        0x00,
        0x13,
        0x88,
        // startOffset / endOffset = undefined
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        ...chapterTitleFrame,
      ];

      final chapFrame = buildId3v24Frame('CHAP', chapterData);

      final tocData = <int>[
        ...ascii.encode('toc'),
        0x00,
        0x03,
        0x01,
        ...ascii.encode('ch1'),
        0x00,
      ];

      final tocFrame = buildId3v24Frame('CTOC', tocData);

      final tag = buildId3Tag(
        majorVersion: 4,
        revision: 0,
        flags: 0x00,
        payload: [...chapFrame, ...tocFrame],
      );

      final loader = Id3v2Loader();
      final tokenizer = MockTokenizer(
        data: tag,
        fileInfo: const FileInfo(path: 'chapters.mp3', size: 4096),
      );

      final metadata = await loader.parse(
        tokenizer,
        const ParseOptions(includeChapters: true),
      );

      expect(metadata.native['ID3v2.4'], isNotNull);
      expect(
        metadata.native['ID3v2.4']!.map((tag) => tag.id),
        contains('CHAP'),
      );
      expect(
        metadata.native['ID3v2.4']!.map((tag) => tag.id),
        contains('CTOC'),
      );
      final chapTag = metadata.native['ID3v2.4']!.firstWhere(
        (tag) => tag.id == 'CHAP',
      );
      final tocTag = metadata.native['ID3v2.4']!.firstWhere(
        (tag) => tag.id == 'CTOC',
      );
      expect(chapTag.value.label, equals('ch1'));
      expect(tocTag.value.childElementIds, equals(['ch1']));
      expect(metadata.format.chapters, isNotNull);
      expect(metadata.format.chapters!.length, equals(1));
      expect(metadata.format.chapters!.single.id, equals('ch1'));
      expect(metadata.format.chapters!.single.title, equals('Intro'));
      expect(metadata.format.chapters!.single.start, equals(0));
      expect(metadata.format.chapters!.single.end, equals(5000));
    });

    test('loader registers mp3 extension and mpeg mime type', () {
      final loader = Id3v2Loader();

      expect(loader.extension, contains('mp3'));
      expect(loader.mimeType, contains('audio/mpeg'));
      expect(loader.hasRandomAccessRequirements, isFalse);
    });
  });
}
