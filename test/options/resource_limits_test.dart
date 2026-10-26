/// Tests for the `maxMetadataEntries` and `maxChapterCount` ParseOptions
/// (upstream parity, music-metadata v12.3.0 #2838 / #2837).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/common/allocation.dart';
import 'package:metadata_audio/src/core.dart';
import 'package:metadata_audio/src/id3v2/id3v2_loader.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:test/test.dart';

import '../id3/id3_test_utils.dart';

void main() {
  group('resource limit validation', () {
    test('getMaxMetadataEntries applies the default of 100,000', () {
      expect(getMaxMetadataEntries(const ParseOptions()), 100000);
    });

    test('getMaxChapterCount applies the default of 1,000', () {
      expect(getMaxChapterCount(const ParseOptions()), 1000);
    });

    test('addition', () {
      expect(
        getMaxMetadataEntries(const ParseOptions(maxMetadataEntries: 10)),
        10,
      );
      expect(getMaxChapterCount(const ParseOptions(maxChapterCount: 7)), 7);
    });

    test('rejects zero and negative limits', () {
      expect(
        () => getMaxMetadataEntries(const ParseOptions(maxMetadataEntries: 0)),
        throwsArgumentError,
      );
      expect(
        () => getMaxChapterCount(const ParseOptions(maxChapterCount: 0)),
        throwsArgumentError,
      );
      expect(
        () => getMaxMetadataEntries(const ParseOptions(maxMetadataEntries: -1)),
        throwsArgumentError,
      );
      expect(
        () => getMaxChapterCount(const ParseOptions(maxChapterCount: -1)),
        throwsArgumentError,
      );
    });

    test('parseFromTokenizer validates options up front', () async {
      final tag = buildId3Tag(
        majorVersion: 4,
        revision: 0,
        flags: 0x00,
        payload: [
          ...buildId3v24Frame('TIT2', [0x03, ...utf8.encode('Title')]),
        ],
      );

      await expectLater(
        parseFromTokenizer(
          BytesTokenizer(
            Uint8List.fromList(tag),
            fileInfo: FileInfo.fromPath('bad-options.mp3'),
          ),
          options: const ParseOptions(maxChapterCount: 0),
        ),
        throwsArgumentError,
      );
    });
  });

  group('ID3v2 frame count limit', () {
    test('throws when the frame count exceeds maxMetadataEntries', () async {
      // Two filler frames against a limit of one.
      final tag = buildId3Tag(
        majorVersion: 4,
        revision: 0,
        flags: 0x00,
        payload: [
          ...buildId3v24Frame('TIT2', [0x03, ...utf8.encode('Title')]),
          ...buildId3v24Frame('TPE1', [0x03, ...utf8.encode('Artist')]),
        ],
      );

      await expectLater(
        Id3v2Loader().parse(
          BytesTokenizer(
            Uint8List.fromList(tag),
            fileInfo: FileInfo.fromPath('frames.mp3'),
          ),
          const ParseOptions(maxMetadataEntries: 1),
        ),
        throwsA(
          predicate(
            (error) =>
                error.toString().contains('Frame count exceeds entry limit'),
            'throws Frame count exceeds entry limit',
          ),
        ),
      );
    });
  });

  group('ID3v2 chapter limit (maxChapterCount)', () {
    test('caps chapters without a CTOC, keeping the earliest ones', () async {
      final frames = <List<int>>[
        for (var i = 0; i < 5; i++)
          _buildChapFrame(i, startTime: (i + 1) * 1000),
      ];
      final tag = buildId3Tag(
        majorVersion: 4,
        revision: 0,
        flags: 0x00,
        payload: [...frames.expand((frame) => frame)],
      );

      final metadata = await Id3v2Loader().parse(
        BytesTokenizer(
          Uint8List.fromList(tag),
          fileInfo: FileInfo.fromPath('chapters.mp3'),
        ),
        const ParseOptions(includeChapters: true, maxChapterCount: 3),
      );

      expect(metadata.format.chapters, hasLength(3));
      expect(
        metadata.format.chapters!.map((chapter) => chapter.start).toList(),
        [1000, 2000, 3000],
      );
      expect(
        metadata.quality.warnings.map((warning) => warning.message),
        contains('Chapter count exceeds the 3 chapter limit'),
      );
    });

    test('orders un-CTOCed chapters by start time', () async {
      final frames = <List<int>>[
        for (final start in const [3000, 1000, 2000])
          _buildChapFrame(start ~/ 1000, startTime: start),
      ];
      final tag = buildId3Tag(
        majorVersion: 4,
        revision: 0,
        flags: 0x00,
        payload: [...frames.expand((frame) => frame)],
      );

      final metadata = await Id3v2Loader().parse(
        BytesTokenizer(
          Uint8List.fromList(tag),
          fileInfo: FileInfo.fromPath('chapters.mp3'),
        ),
        const ParseOptions(includeChapters: true),
      );

      expect(
        metadata.format.chapters!.map((chapter) => chapter.start).toList(),
        [1000, 2000, 3000],
      );
    });
  });
}

List<int> _buildChapFrame(int index, {required int startTime}) {
  final title = 'Chapter $index';
  final titleFrame = buildId3v24Frame('TIT2', [0x03, ...utf8.encode(title)]);

  final payload = <int>[
    ...ascii.encode('chap${index.toString().padLeft(4, '0')}'),
    0x00,
    ..._u32Big(startTime),
    ..._u32Big(startTime + 1000),
    ..._u32Big(0xFFFFFFFF),
    ..._u32Big(0xFFFFFFFF),
    ...titleFrame,
  ];
  return buildId3v24Frame('CHAP', payload);
}

List<int> _u32Big(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];
