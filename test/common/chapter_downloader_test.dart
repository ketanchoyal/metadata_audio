import 'dart:io';
import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

void main() {
  group('ChapterDownloader', () {
    late String originalFilePath;
    late String tempAacPath;

    setUpAll(() {
      originalFilePath = '${Directory.current.path}/test/samples/mp4/The Dark Forest.m4a';
      tempAacPath = '${Directory.current.path}/test/common/playable_chapter_1_temp.aac';
    });

    tearDown(() async {
      final aacFile = File(tempAacPath);
      if (await aacFile.exists()) {
        await aacFile.delete();
      }
    });

    test('extracts a chapter directly to a playable standalone ADTS AAC file', () async {
      final originalFile = File(originalFilePath);
      expect(await originalFile.exists(), isTrue);

      // Chapter 1 of The Dark Forest: 52036ms to 1943017ms
      const startMs = 52036;
      const endMs = 1943017;

      final result = await ChapterDownloader.downloadChapter(
        originalUrl: originalFilePath,
        chapterStartMs: startMs,
        chapterEndMs: endMs,
        outputPath: tempAacPath,
      );

      expect(result.isSuccess, isTrue);
      expect(result.outputPath, equals(tempAacPath));
      expect(result.error, isNull);

      final aacFile = File(result.outputPath!);
      expect(await aacFile.exists(), isTrue);

      // The file size should be equal to sum of chapter sample sizes + 7 bytes header per sample
      // Let's read first few bytes to verify it starts with a valid ADTS syncword (0xFFF)
      final raf = await aacFile.open(mode: FileMode.read);
      try {
        final firstBytes = await raf.read(7);
        expect(firstBytes[0], equals(0xFF));
        expect(firstBytes[1] & 0xF0, equals(0xF0)); // Syncword check
        expect(firstBytes[1] & 0x01, equals(0x01)); // Protection absent check (1)
      } finally {
        await raf.close();
      }
    });

    test('returns failure for non-existent local file', () async {
      final result = await ChapterDownloader.downloadChapter(
        originalUrl: '/non/existent/file.m4b',
        chapterStartMs: 0,
        chapterEndMs: 1000,
        outputPath: tempAacPath,
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
      expect(result.outputPath, isNull);
    });
  });
}
