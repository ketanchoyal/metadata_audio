import 'dart:io';
import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/mp4/atom_token.dart';
import 'package:test/test.dart';

void main() {
  group('ChapterDownloader', () {
    late String originalFilePath;
    late String tempM4aPath;
    late String tempAacPath;

    setUpAll(() {
      originalFilePath = '${Directory.current.path}/test/samples/mp4/video_chapters.mp4';
      tempM4aPath = '${Directory.current.path}/test/common/playable_chapter_1_temp.m4a';
      tempAacPath = '${Directory.current.path}/test/common/playable_chapter_1_temp.aac';
    });

    tearDown(() async {
      for (final path in [tempM4aPath, tempAacPath]) {
        final f = File(path);
        if (await f.exists()) {
          await f.delete();
        }
      }
    });

    test('extracts a chapter directly to a playable standalone M4A container file', () async {
      final originalFile = File(originalFilePath);
      expect(await originalFile.exists(), isTrue);

      // Chapter 1 of video_chapters.mp4: 0ms to 2000ms
      const startMs = 0;
      const endMs = 2000;

      final result = await ChapterDownloader.downloadChapter(
        originalUrl: originalFilePath,
        chapterStartMs: startMs,
        chapterEndMs: endMs,
        outputPath: tempM4aPath,
      );

      expect(result.isSuccess, isTrue);
      expect(result.outputPath, equals(tempM4aPath));
      expect(result.error, isNull);

      final m4aFile = File(result.outputPath!);
      expect(await m4aFile.exists(), isTrue);

      // Verify the generated M4A file starts with ftyp and M4A brand
      final bytes = await m4aFile.readAsBytes();
      expect(bytes.length, greaterThan(100));
      // ftyp box
      expect(bytes.sublist(4, 8), equals([0x66, 0x74, 0x79, 0x70])); // 'ftyp'
      expect(bytes.sublist(8, 12), equals([0x4D, 0x34, 0x41, 0x20])); // 'M4A '

      // Verify metadata parser can parse the generated M4A file
      final parsed = await parseFile(tempM4aPath);
      expect(parsed.format.container, startsWith('M4A'));
      expect(parsed.format.hasAudio, isTrue);
      expect(parsed.format.duration, closeTo(2.0, 0.1));
    });

    test('extracts a chapter directly to a playable standalone ADTS AAC file when .aac requested', () async {
      final originalFile = File(originalFilePath);
      expect(await originalFile.exists(), isTrue);

      // Chapter 1 of sample.m4a: 0ms to 2000ms
      const startMs = 0;
      const endMs = 2000;

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

    test('extracts a chapter from an MP3 file without tags', () async {
      final mp3Path = '${Directory.current.path}/test/samples/mp3/no-tags.mp3';
      final tempMp3Path = '${Directory.current.path}/test/common/temp_no_tags.mp3';
      final file = File(mp3Path);
      expect(await file.exists(), isTrue);

      final result = await ChapterDownloader.downloadChapter(
        originalUrl: mp3Path,
        chapterStartMs: 0,
        chapterEndMs: 1000,
        outputPath: tempMp3Path,
      );

      expect(result.isSuccess, isTrue);
      expect(result.outputPath, equals(tempMp3Path));
      expect(result.error, isNull);

      final tempFile = File(tempMp3Path);
      expect(await tempFile.exists(), isTrue);

      // Verify that the output MP3 starts with MPEG frame syncword (0xFF)
      final bytes = await tempFile.readAsBytes();
      expect(bytes.length, greaterThan(0));
      expect(bytes[0], equals(0xFF));
      expect(bytes[1] & 0xE0, equals(0xE0));

      await tempFile.delete();
    });

    test('extracts a chapter from an MP3 file with ID3v2 tags (skipping tags)', () async {
      final mp3Path = '${Directory.current.path}/test/samples/mp3/id3v2.3.mp3';
      final tempMp3Path = '${Directory.current.path}/test/common/temp_id3v2.mp3';
      final file = File(mp3Path);
      expect(await file.exists(), isTrue);

      final result = await ChapterDownloader.downloadChapter(
        originalUrl: mp3Path,
        chapterStartMs: 100,
        chapterEndMs: 600,
        outputPath: tempMp3Path,
      );

      expect(result.isSuccess, isTrue);
      expect(result.outputPath, equals(tempMp3Path));
      expect(result.error, isNull);

      final tempFile = File(tempMp3Path);
      expect(await tempFile.exists(), isTrue);

      // Verify that the output MP3 starts with MPEG frame syncword (0xFF)
      final bytes = await tempFile.readAsBytes();
      expect(bytes.length, greaterThan(0));
      expect(bytes[0], equals(0xFF));
      expect(bytes[1] & 0xE0, equals(0xE0));

      await tempFile.delete();
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

    test('AudioMetadataCache saves, retrieves, and clears cached track metadata', () async {
      await AudioMetadataCache.clearCache();
      expect(AudioMetadataCache.getCacheSize(), equals(0));

      const testUrl = 'https://example.com/audiobook_cache_test.m4b';
      expect(await AudioMetadataCache.get(testUrl), isNull);

      final track = CachedAudioTrack(
        trackId: 1,
        timeScale: 44100,
        sampleRate: 44100,
        numberOfChannels: 2,
        sampleSize: 1024,
        sampleSizeTable: [1024, 1024],
        timeToSampleTable: const [SttsEntry(count: 2, duration: 1024)],
        sampleToChunkTable: const [StscEntry(firstChunk: 1, samplesPerChunk: 2)],
        chunkOffsetTable: const [1000],
        rawStsdBox: const [0, 0, 0, 8, 115, 116, 115, 100],
      );

      await AudioMetadataCache.put(testUrl, track);

      final retrieved = await AudioMetadataCache.get(testUrl);
      expect(retrieved, isNotNull);
      expect(retrieved!.trackId, equals(1));
      expect(retrieved.timeScale, equals(44100));
      expect(retrieved.sampleRate, equals(44100));
      expect(retrieved.numberOfChannels, equals(2));
      expect(retrieved.getSampleIndexForTime(1024), equals(1));
      expect(retrieved.getByteOffsetForSample(0), equals(1000));
      expect(retrieved.getByteOffsetForSample(1), equals(2024));

      expect(AudioMetadataCache.getCacheSize(), greaterThan(0));

      await AudioMetadataCache.clearCache();
      expect(await AudioMetadataCache.get(testUrl), isNull);
      expect(AudioMetadataCache.getCacheSize(), equals(0));
    });

    test('ChapterDownloader caches metadata and reuses it on subsequent chapter downloads', () async {
      await ChapterDownloader.clearCache();

      // First chapter download parses file and populates cache
      final result1 = await ChapterDownloader.downloadChapter(
        originalUrl: originalFilePath,
        chapterStartMs: 0,
        chapterEndMs: 2000,
        outputPath: tempM4aPath,
      );
      expect(result1.isSuccess, isTrue);

      // Verify cache now holds metadata for this file
      final cachedTrack = await AudioMetadataCache.get(originalFilePath);
      expect(cachedTrack, isNotNull);
      expect(cachedTrack!.timeScale, isNotNull);

      // Second chapter download reuses cache directly
      final tempM4aPath2 = '${Directory.current.path}/test/common/playable_chapter_2_temp.m4a';
      final result2 = await ChapterDownloader.downloadChapter(
        originalUrl: originalFilePath,
        chapterStartMs: 2000,
        chapterEndMs: 4000,
        outputPath: tempM4aPath2,
      );
      expect(result2.isSuccess, isTrue);

      final f2 = File(tempM4aPath2);
      expect(await f2.exists(), isTrue);
      await f2.delete();
      await ChapterDownloader.clearCache();
    });
  });
}
