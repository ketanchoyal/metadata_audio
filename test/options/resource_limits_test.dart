/// Tests for the `maxMetadataEntries`, `maxChapterCount`, and `maxMemoryAllocation` ParseOptions.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/common/allocation.dart';
import 'package:metadata_audio/src/core.dart';
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

    test('getMaxMemoryAllocation applies the default of 64 MiB', () {
      expect(getMaxMemoryAllocation(const ParseOptions()), 67108864);
    });

    test('addition', () {
      expect(
        getMaxMetadataEntries(const ParseOptions(maxMetadataEntries: 10)),
        10,
      );
      expect(getMaxChapterCount(const ParseOptions(maxChapterCount: 7)), 7);
      expect(
        getMaxMemoryAllocation(const ParseOptions(maxMemoryAllocation: 2048)),
        2048,
      );
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
        () =>
            getMaxMemoryAllocation(const ParseOptions(maxMemoryAllocation: 0)),
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
      expect(
        () =>
            getMaxMemoryAllocation(const ParseOptions(maxMemoryAllocation: -1)),
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

  group('parseStream maxMemoryAllocation', () {
    test(
      'throws TokenizerException when stream exceeds maxMemoryAllocation',
      () async {
        final chunk1 = Uint8List(50);
        final chunk2 = Uint8List(60);
        final stream = Stream.fromIterable([chunk1, chunk2]);

        await expectLater(
          parseStream(
            stream,
            options: const ParseOptions(maxMemoryAllocation: 100),
            fileInfo: FileInfo.fromPath('test.mp3'),
          ),
          throwsA(
            isA<TokenizerException>().having(
              (e) => e.message,
              'message',
              contains('Stream size exceeds maxMemoryAllocation (100 bytes)'),
            ),
          ),
        );
      },
    );
  });

  group('validateAllocation', () {
    test('defaults to 64 MiB and permits the exact limit', () {
      expect(
        () => validateAllocation(64 * 1024 * 1024, const ParseOptions()),
        returnsNormally,
      );
      expect(
        () => validateAllocation(64 * 1024 * 1024 + 1, const ParseOptions()),
        throwsA(
          isA<UnexpectedFileContentError>().having(
            (e) => e.message,
            'message',
            contains('allocation limit'),
          ),
        ),
      );
    });

    test('rejects negative lengths', () {
      expect(
        () => validateAllocation(-1, const ParseOptions()),
        throwsA(
          isA<UnexpectedFileContentError>().having(
            (e) => e.message,
            'message',
            contains('Invalid allocation size: -1'),
          ),
        ),
      );
    });

    test('uses custom error factory when provided', () {
      expect(
        () => validateAllocation(
          100,
          const ParseOptions(maxMemoryAllocation: 50),
          FormatException.new,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Tokenizer BufferSizeError', () {
    test('BytesTokenizer throws BufferSizeError with sizes', () {
      final tokenizer = BytesTokenizer(Uint8List(128), maxBufferSize: 64);

      expect(
        () => tokenizer.readBytes(65),
        throwsA(
          isA<BufferSizeError>()
              .having((e) => e.requestedSize, 'requestedSize', 65)
              .having((e) => e.maxBufferSize, 'maxBufferSize', 64),
        ),
      );
      expect(
        () => tokenizer.peekBytes(65),
        throwsA(
          isA<BufferSizeError>()
              .having((e) => e.requestedSize, 'requestedSize', 65)
              .having((e) => e.maxBufferSize, 'maxBufferSize', 64),
        ),
      );
    });
  });

  group('Format parser allocation limits', () {
    test('ID3v2 rejects tag size exceeding maxMemoryAllocation', () async {
      final sample = Uint8List.fromList([
        0x49, 0x44, 0x33, // 'ID3'
        0x04, 0x00, // version 2.4
        0x00, // flags
        0x00, 0x00, 0x00, 0x64, // 100 bytes synchsafe
      ]);

      await expectLater(
        parseBytes(
          sample,
          fileInfo: FileInfo.fromPath('sample.mp3'),
          options: const ParseOptions(maxMemoryAllocation: 64),
        ),
        throwsA(
          isA<UnexpectedFileContentError>().having(
            (e) => e.message,
            'message',
            contains('allocation limit 64'),
          ),
        ),
      );
    });

    test('MP4 rejects atom payload exceeding maxMemoryAllocation', () async {
      // A parsed atom with length 100 and type 'ftyp'
      final sample = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x64, // length = 100
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
      ]);

      await expectLater(
        parseBytes(
          sample,
          fileInfo: const FileInfo(mimeType: 'audio/mp4'),
          options: const ParseOptions(maxMemoryAllocation: 64),
        ),
        throwsA(
          isA<UnexpectedFileContentError>().having(
            (e) => e.message,
            'message',
            contains('allocation limit 64'),
          ),
        ),
      );
    });

    test('MP4 permits skipped atom exceeding maxMemoryAllocation', () async {
      // An unparsed atom (e.g. 'free' padding) with length 100
      final sample = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x64, // length = 100
        0x66, 0x72, 0x65, 0x65, // 'free'
        ...Uint8List(92), // 92 bytes of padding
      ]);

      final metadata = await parseBytes(
        sample,
        fileInfo: const FileInfo(mimeType: 'audio/mp4'),
        options: const ParseOptions(maxMemoryAllocation: 64),
      );
      expect(metadata, isNotNull);
    });

    test('WAV rejects fmt chunk exceeding maxMemoryAllocation', () async {
      final sample = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, // 'RIFF'
        104, 0x00, 0x00, 0x00, // size = 104
        0x57, 0x41, 0x56, 0x45, // 'WAVE'
        0x66, 0x6d, 0x74, 0x20, // 'fmt '
        92, 0x00, 0x00, 0x00, // chunkSize = 92
      ]);

      await expectLater(
        parseBytes(
          sample,
          fileInfo: const FileInfo(mimeType: 'audio/wav'),
          options: const ParseOptions(maxMemoryAllocation: 64),
        ),
        throwsA(
          isA<UnexpectedFileContentError>().having(
            (e) => e.message,
            'message',
            contains('allocation limit 64'),
          ),
        ),
      );
    });

    test('AIFF rejects COMM chunk exceeding maxMemoryAllocation', () async {
      final sample = Uint8List.fromList([
        0x46, 0x4f, 0x52, 0x4d, // 'FORM'
        0x00, 0x00, 0x00, 104, // size = 104
        0x41, 0x49, 0x46, 0x46, // 'AIFF'
        0x43, 0x4f, 0x4d, 0x4d, // 'COMM'
        0x00, 0x00, 0x00, 92, // chunkSize = 92
      ]);

      await expectLater(
        parseBytes(
          sample,
          fileInfo: const FileInfo(mimeType: 'audio/aiff'),
          options: const ParseOptions(maxMemoryAllocation: 64),
        ),
        throwsA(
          isA<UnexpectedFileContentError>().having(
            (e) => e.message,
            'message',
            contains('allocation limit 64'),
          ),
        ),
      );
    });

    test('AIFF permits skipped chunk exceeding maxMemoryAllocation', () async {
      final sample = Uint8List.fromList([
        0x46, 0x4f, 0x52, 0x4d, // 'FORM'
        0x00, 0x00, 0x00, 112, // size = 112
        0x41, 0x49, 0x46, 0x46, // 'AIFF'
        0x41, 0x50, 0x50, 0x4c, // 'APPL' (unknown chunk, skipped)
        0x00, 0x00, 0x00, 100, // chunkSize = 100
        ...Uint8List(100),
      ]);

      final metadata = await parseBytes(
        sample,
        fileInfo: const FileInfo(mimeType: 'audio/aiff'),
        options: const ParseOptions(maxMemoryAllocation: 64),
      );
      expect(metadata, isNotNull);
    });

    test('FLAC permits skipped picture block when skipCovers is true', () async {
      final streamInfo = Uint8List(34);
      // Min block size = 4096 (2 bytes), Max block size = 4096 (2 bytes)
      streamInfo[0] = 0x10;
      streamInfo[1] = 0x00;
      streamInfo[2] = 0x10;
      streamInfo[3] = 0x00;
      // Sample rate = 44100 (20 bits), Channels = 2 (3 bits), BPS = 16 (5 bits)
      // 44100 = 0x0AC44; (0x0AC44 << 12) | (1 << 9) | (15 << 4)
      streamInfo[10] = (44100 >> 12) & 0xFF;
      streamInfo[11] = (44100 >> 4) & 0xFF;
      streamInfo[12] = ((44100 & 0xF) << 4) | (1 << 1) | (15 >> 4);
      streamInfo[13] = (15 & 0xF) << 4;

      final sample = Uint8List.fromList([
        0x66, 0x4C, 0x61, 0x43, // 'fLaC'
        0x00, // block type 0 (STREAMINFO), isLast = false
        0x00, 0x00, 34, // length = 34
        ...streamInfo,
        0x86, // block type 6 (PICTURE), isLast = true
        0x00, 0x00, 100, // length = 100
        ...Uint8List(100),
      ]);

      final metadata = await parseBytes(
        sample,
        fileInfo: const FileInfo(mimeType: 'audio/flac'),
        options: const ParseOptions(maxMemoryAllocation: 64, skipCovers: true),
      );
      expect(metadata.format.container, 'FLAC');
    });
  });

  group('public API option validation', () {
    test('parseBytes rejects zero and negative maxMemoryAllocation', () async {
      await expectLater(
        parseBytes(
          Uint8List(0),
          options: const ParseOptions(maxMemoryAllocation: 0),
        ),
        throwsArgumentError,
      );
      await expectLater(
        parseBytes(
          Uint8List(0),
          options: const ParseOptions(maxMemoryAllocation: -1),
        ),
        throwsArgumentError,
      );
    });

    test(
      'parseFile rejects invalid options before touching the file system',
      () async {
        await expectLater(
          parseFile(
            'non_existent.mp3',
            options: const ParseOptions(maxMemoryAllocation: 0),
          ),
          throwsArgumentError,
        );
      },
    );
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
