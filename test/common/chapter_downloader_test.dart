import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/mp4/atom_token.dart';
import 'package:metadata_audio/src/utils/m4a_muxer.dart';
import 'package:test/test.dart';

import '../id3/id3_test_utils.dart';

void main() {
  group('ChapterDownloader', () {
    late String originalFilePath;
    late String tempM4aPath;
    late String tempAacPath;
    late Directory testCacheDir;

    setUpAll(() async {
      testCacheDir = await Directory.systemTemp.createTemp(
        'metadata_audio_chapter_cache_',
      );
      AudioMetadataCache.overrideDirForTesting = testCacheDir;
      originalFilePath =
          '${Directory.current.path}/test/samples/mp4/video_chapters.mp4';
      tempM4aPath =
          '${Directory.current.path}/test/common/playable_chapter_1_temp.m4a';
      tempAacPath =
          '${Directory.current.path}/test/common/playable_chapter_1_temp.aac';
    });

    tearDownAll(() async {
      AudioMetadataCache.overrideDirForTesting = null;
      if (testCacheDir.existsSync()) {
        await testCacheDir.delete(recursive: true);
      }
    });

    tearDown(() async {
      for (final path in [tempM4aPath, tempAacPath]) {
        final f = File(path);
        if (await f.exists()) {
          await f.delete();
        }
      }
    });

    test(
      'extracts a chapter directly to a playable standalone M4A container file',
      () async {
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
        expect(
          bytes.sublist(8, 12),
          equals([0x4D, 0x34, 0x41, 0x20]),
        ); // 'M4A '

        // Verify metadata parser can parse the generated M4A file
        final parsed = await parseFile(tempM4aPath);
        expect(parsed.format.container, startsWith('M4A'));
        expect(parsed.format.hasAudio, isTrue);
        expect(parsed.format.duration, closeTo(2.0, 0.1));
      },
    );

    test(
      'extracts a chapter directly to a playable standalone ADTS AAC file when .aac requested',
      () async {
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
        final raf = await aacFile.open();
        try {
          final firstBytes = await raf.read(7);
          expect(firstBytes[0], equals(0xFF));
          expect(firstBytes[1] & 0xF0, equals(0xF0)); // Syncword check
          expect(
            firstBytes[1] & 0x01,
            equals(0x01),
          ); // Protection absent check (1)
        } finally {
          await raf.close();
        }
      },
    );

    test('extracts a chapter from an MP3 file without tags', () async {
      final mp3Path = '${Directory.current.path}/test/samples/mp3/no-tags.mp3';
      final tempMp3Path =
          '${Directory.current.path}/test/common/temp_no_tags.mp3';
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

    test(
      'extracts a chapter from an MP3 file with ID3v2 tags (skipping tags)',
      () async {
        final mp3Path =
            '${Directory.current.path}/test/samples/mp3/id3v2.3.mp3';
        final tempMp3Path =
            '${Directory.current.path}/test/common/temp_id3v2.mp3';
        final file = File(mp3Path);
        expect(await file.exists(), isTrue);

        final result = await ChapterDownloader.downloadChapter(
          originalUrl: mp3Path,
          chapterStartMs: 100,
          chapterEndMs: 600,
          outputPath: tempMp3Path,
          includeMetadata: false,
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
      },
    );

    test(
      'preserves original ID3v2 metadata in sliced MP3 chapter by default',
      () async {
        final mp3Path =
            '${Directory.current.path}/test/samples/mp3/id3v2.3.mp3';
        final tempMp3Path =
            '${Directory.current.path}/test/common/temp_id3v2_with_meta.mp3';

        final original = await parseFile(mp3Path);

        final result = await ChapterDownloader.downloadChapter(
          originalUrl: mp3Path,
          chapterStartMs: 100,
          chapterEndMs: 600,
          outputPath: tempMp3Path,
        );

        expect(result.isSuccess, isTrue);
        final tempFile = File(tempMp3Path);
        expect(await tempFile.exists(), isTrue);

        final bytes = await tempFile.readAsBytes();
        // Starts with 'ID3' tag
        expect(bytes.sublist(0, 3), equals([0x49, 0x44, 0x33]));

        final sliced = await parseFile(tempMp3Path);
        expect(sliced.common.title, equals(original.common.title));
        expect(sliced.common.artist, equals(original.common.artist));
        expect(sliced.common.album, equals(original.common.album));
        expect(sliced.common.year, equals(original.common.year));
        expect(sliced.common.genre, equals(original.common.genre));
        expect(
          sliced.common.picture?.length ?? 0,
          equals(original.common.picture?.length ?? 0),
        );

        await tempFile.delete();
      },
    );

    test(
      'preserves original M4A/M4B metadata and cover art in sliced M4A chapter',
      () async {
        await ChapterDownloader.clearCache();
        final sampleM4a =
            '${Directory.current.path}/test/samples/mp4/sample.m4a';
        final tempMetaM4a =
            '${Directory.current.path}/test/common/playable_chapter_meta_temp.m4a';

        final original = await parseFile(sampleM4a);
        final durationMs = ((original.format.duration ?? 2.0) * 1000).round();

        final result = await ChapterDownloader.downloadChapter(
          originalUrl: sampleM4a,
          chapterStartMs: 0,
          chapterEndMs: durationMs,
          outputPath: tempMetaM4a,
        );

        expect(result.isSuccess, isTrue);
        final sliced = await parseFile(
          tempMetaM4a,
          options: const ParseOptions(includeChapters: true),
        );
        expect(sliced.format.container, startsWith('M4A'));
        expect(sliced.common.title, equals(original.common.title));
        expect(sliced.common.artist, equals(original.common.artist));
        expect(sliced.common.album, equals(original.common.album));
        expect(sliced.common.genre, equals(original.common.genre));
        expect(
          sliced.common.picture?.length ?? 0,
          equals(original.common.picture?.length ?? 0),
        );
        if (original.common.picture != null &&
            original.common.picture!.isNotEmpty) {
          expect(
            sliced.common.picture!.first.data,
            equals(original.common.picture!.first.data),
          );
        }
        // Whole-book chapter list (chpl) is not copied as chapters of single slice
        expect(sliced.format.chapters, isNull);

        await File(tempMetaM4a).delete();
        await ChapterDownloader.clearCache();
      },
    );

    test(
      'supports fallback AudioMetadata when source container lacks udta box',
      () async {
        await ChapterDownloader.clearCache();
        final tempFallbackM4a =
            '${Directory.current.path}/test/common/playable_chapter_fallback_temp.m4a';

        // Seed a cached audio track without rawUdtaBox/rawMetaBox (as if parsed
        // from an MP4 lacking udta/meta) to verify fallback metadata muxing.
        final parsed = await parseFile(originalFilePath);
        expect(parsed.format.hasAudio, isTrue);

        const customMeta = AudioMetadata(
          format: Format(container: 'mp4'),
          native: {},
          common: CommonTags(
            track: TrackNo(no: 2, of: 10),
            disk: TrackNo(no: 1, of: 1),
            movementIndex: TrackNo(),
            title: 'Chapter 2: The Journey',
            artist: 'Author Name',
            album: 'Audiobook Title',
            year: 2025,
          ),
          quality: QualityInformation(),
        );

        // First populate cache from original file, then replace cached entry
        // with metadataChecked=true and null udta/meta boxes.
        final seedResult = await ChapterDownloader.downloadChapter(
          originalUrl: originalFilePath,
          chapterStartMs: 0,
          chapterEndMs: 2000,
          outputPath: tempM4aPath,
        );
        expect(seedResult.isSuccess, isTrue);
        final seeded = await AudioMetadataCache.get(originalFilePath);
        expect(seeded, isNotNull);

        await AudioMetadataCache.put(
          originalFilePath,
          CachedAudioTrack(
            trackId: seeded!.trackId,
            timeScale: seeded.timeScale,
            sampleRate: seeded.sampleRate,
            numberOfChannels: seeded.numberOfChannels,
            sampleSize: seeded.sampleSize,
            sampleSizeTable: seeded.sampleSizeTable,
            timeToSampleTable: seeded.timeToSampleTable,
            sampleToChunkTable: seeded.sampleToChunkTable,
            chunkOffsetTable: seeded.chunkOffsetTable,
            rawStsdBox: seeded.rawStsdBox,
            metadataChecked: true,
          ),
        );

        final result = await ChapterDownloader.downloadChapter(
          originalUrl: originalFilePath,
          chapterStartMs: 0,
          chapterEndMs: 2000,
          outputPath: tempFallbackM4a,
          metadata: customMeta,
        );

        expect(result.isSuccess, isTrue);
        final sliced = await parseFile(tempFallbackM4a);
        expect(sliced.common.title, equals('Chapter 2: The Journey'));
        expect(sliced.common.artist, equals('Author Name'));
        expect(sliced.common.album, equals('Audiobook Title'));
        expect(sliced.common.track.no, equals(2));
        expect(sliced.common.track.of, equals(10));

        await File(tempFallbackM4a).delete();
        await ChapterDownloader.clearCache();
      },
    );

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

    test(
      'AudioMetadataCache saves, retrieves, and clears cached track metadata',
      () async {
        await AudioMetadataCache.clearCache();
        expect(AudioMetadataCache.getCacheSize(), equals(0));

        const testUrl = 'https://example.com/audiobook_cache_test.m4b';
        expect(await AudioMetadataCache.get(testUrl), isNull);

        const track = CachedAudioTrack(
          trackId: 1,
          timeScale: 44100,
          sampleRate: 44100,
          numberOfChannels: 2,
          sampleSize: 1024,
          sampleSizeTable: [1024, 1024],
          timeToSampleTable: [SttsEntry(count: 2, duration: 1024)],
          sampleToChunkTable: [StscEntry(firstChunk: 1, samplesPerChunk: 2)],
          chunkOffsetTable: [1000],
          rawStsdBox: [0, 0, 0, 8, 115, 116, 115, 100],
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
      },
    );

    test(
      'ChapterDownloader caches metadata and reuses it on subsequent chapter downloads',
      () async {
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
        final tempM4aPath2 =
            '${Directory.current.path}/test/common/playable_chapter_2_temp.m4a';
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
      },
    );

    group('Playability and full metadata preservation', () {
      Future<bool> hasTool(String name) async {
        final res = await Process.run('which', [name]);
        return res.exitCode == 0;
      }

      Future<void> verifyPlayableWithSystemTools(
        String filePath, {
        required String expectedCodec,
        required double minDurationSec,
        Map<String, String>? expectedFfprobeTags,
      }) async {
        if (await hasTool('ffmpeg')) {
          final decode = await Process.run('ffmpeg', [
            '-v',
            'error',
            '-i',
            filePath,
            '-f',
            'null',
            '-',
          ]);
          expect(
            decode.exitCode,
            equals(0),
            reason: 'ffmpeg failed to decode $filePath: ${decode.stderr}',
          );
          expect(
            (decode.stderr as String).trim(),
            isEmpty,
            reason: 'ffmpeg reported decode errors for $filePath',
          );
        }

        if (await hasTool('ffprobe')) {
          final probe = await Process.run('ffprobe', [
            '-v',
            'error',
            '-show_format',
            '-show_streams',
            '-of',
            'json',
            filePath,
          ]);
          expect(probe.exitCode, equals(0));
          final json = jsonDecode(probe.stdout as String) as Map<String, dynamic>;
          final streams = (json['streams'] as List).cast<Map<String, dynamic>>();
          final audioStreams = streams
              .where((s) => s['codec_type'] == 'audio')
              .toList();
          expect(audioStreams, isNotEmpty);
          expect(audioStreams.first['codec_name'], equals(expectedCodec));

          final format = json['format'] as Map<String, dynamic>;
          final duration = double.tryParse('${format['duration'] ?? ''}');
          expect(duration, isNotNull);
          expect(duration!, greaterThanOrEqualTo(minDurationSec));

          if (expectedFfprobeTags != null) {
            final tags = (format['tags'] as Map<String, dynamic>?) ?? const {};
            final lowerTags = {
              for (final e in tags.entries) e.key.toLowerCase(): '${e.value}',
            };
            for (final expected in expectedFfprobeTags.entries) {
              expect(
                lowerTags[expected.key.toLowerCase()],
                equals(expected.value),
                reason: 'ffprobe missing/mismatched tag ${expected.key}',
              );
            }
          }
        }

        if (Platform.isMacOS && await hasTool('afinfo')) {
          final afinfo = await Process.run('afinfo', [filePath]);
          expect(
            afinfo.exitCode,
            equals(0),
            reason: 'afinfo failed for $filePath: ${afinfo.stderr}',
          );
        }
      }

      test(
        'sliced M4A chapter from richly tagged M4B is playable and preserves all metadata + cover art',
        () async {
          if (!await hasTool('ffmpeg')) {
            markTestSkipped('ffmpeg not installed');
            return;
          }

          final tmpDir = await Directory.systemTemp.createTemp(
            'chapter_m4b_playability_',
          );
          try {
            final coverPath = '${tmpDir.path}/cover.png';
            final m4bPath = '${tmpDir.path}/audiobook.m4b';
            final chaptersMetaPath = '${tmpDir.path}/ffmeta.txt';
            final sliced1Path = '${tmpDir.path}/chapter_1.m4a';
            final sliced2Path = '${tmpDir.path}/chapter_2.m4a';

            // Generate a tiny valid PNG cover via ffmpeg.
            final coverGen = await Process.run('ffmpeg', [
              '-y',
              '-f',
              'lavfi',
              '-i',
              'color=c=blue:s=32x32:d=1',
              '-frames:v',
              '1',
              coverPath,
            ]);
            expect(coverGen.exitCode, equals(0));

            await File(chaptersMetaPath).writeAsString(
              ';FFMETADATA1\n'
              'title=The Great Audiobook\n'
              'artist=Jane Author\n'
              'album=Chronicles Series\n'
              'album_artist=Jane Author\n'
              'genre=Audiobook\n'
              'date=2025\n'
              'composer=Studio Narrator\n'
              'comment=Unabridged Edition\n'
              'track=1/3\n'
              'disc=1/2\n'
              '[CHAPTER]\n'
              'TIMEBASE=1/1000\n'
              'START=0\n'
              'END=2000\n'
              'title=Chapter 1: Beginning\n'
              '[CHAPTER]\n'
              'TIMEBASE=1/1000\n'
              'START=2000\n'
              'END=4000\n'
              'title=Chapter 2: Middle\n',
            );

            // Generate 4s playable AAC M4B with chapters, metadata, and cover art.
            final genM4b = await Process.run('ffmpeg', [
              '-y',
              '-f',
              'lavfi',
              '-i',
              'sine=frequency=440:duration=4',
              '-i',
              coverPath,
              '-i',
              chaptersMetaPath,
              '-map',
              '0:a',
              '-map',
              '1:v',
              '-map_metadata',
              '2',
              '-map_chapters',
              '2',
              '-c:a',
              'aac',
              '-b:a',
              '96k',
              '-c:v',
              'png',
              '-disposition:v:0',
              'attached_pic',
              '-f',
              'mp4',
              m4bPath,
            ]);
            expect(
              genM4b.exitCode,
              equals(0),
              reason: 'ffmpeg m4b generation failed: ${genM4b.stderr}',
            );

            final originalMeta = await parseFile(
              m4bPath,
              options: const ParseOptions(includeChapters: true),
            );
            expect(originalMeta.format.chapters, hasLength(2));
            expect(originalMeta.common.picture, hasLength(1));

            // Test slicing via remote HTTP server (verifying both download +
            // cache reuse across chapters 1 and 2).
            final m4bBytes = await File(m4bPath).readAsBytes();
            final server = await _RangeHttpServer.start(m4bBytes, '/book.m4b');
            try {
              await ChapterDownloader.clearCache();

              final res1 = await ChapterDownloader.downloadChapter(
                originalUrl: server.url,
                chapterStartMs: 0,
                chapterEndMs: 2000,
                outputPath: sliced1Path,
              );
              expect(res1.isSuccess, isTrue, reason: res1.error);

              // Second chapter reuses CachedAudioTrack (with cached udta/cover).
              final res2 = await ChapterDownloader.downloadChapter(
                originalUrl: server.url,
                chapterStartMs: 2000,
                chapterEndMs: 4000,
                outputPath: sliced2Path,
              );
              expect(res2.isSuccess, isTrue, reason: res2.error);

              for (final slicedPath in [sliced1Path, sliced2Path]) {
                await verifyPlayableWithSystemTools(
                  slicedPath,
                  expectedCodec: 'aac',
                  minDurationSec: 1.5,
                  expectedFfprobeTags: const {
                    'title': 'The Great Audiobook',
                    'artist': 'Jane Author',
                    'album': 'Chronicles Series',
                    'album_artist': 'Jane Author',
                    'genre': 'Audiobook',
                    'composer': 'Studio Narrator',
                    'comment': 'Unabridged Edition',
                  },
                );

                final slicedMeta = await parseFile(
                  slicedPath,
                  options: const ParseOptions(includeChapters: true),
                );
                expect(slicedMeta.common.title, equals(originalMeta.common.title));
                expect(
                  slicedMeta.common.artist,
                  equals(originalMeta.common.artist),
                );
                expect(slicedMeta.common.album, equals(originalMeta.common.album));
                expect(
                  slicedMeta.common.albumartist,
                  equals(originalMeta.common.albumartist),
                );
                expect(slicedMeta.common.genre, equals(originalMeta.common.genre));
                expect(slicedMeta.common.year, equals(originalMeta.common.year));
                expect(
                  slicedMeta.common.composer,
                  equals(originalMeta.common.composer),
                );
                expect(
                  slicedMeta.common.track.no,
                  equals(originalMeta.common.track.no),
                );
                expect(
                  slicedMeta.common.track.of,
                  equals(originalMeta.common.track.of),
                );
                expect(
                  slicedMeta.common.disk.no,
                  equals(originalMeta.common.disk.no),
                );
                expect(
                  slicedMeta.common.picture?.length,
                  equals(originalMeta.common.picture?.length),
                );
                expect(
                  slicedMeta.common.picture!.first.data,
                  equals(originalMeta.common.picture!.first.data),
                );
              }
            } finally {
              await server.close();
            }
          } finally {
            await ChapterDownloader.clearCache();
            if (tmpDir.existsSync()) {
              await tmpDir.delete(recursive: true);
            }
          }
        },
      );

      test(
        'sliced MP3 chapter is playable, preserves ID3v2/ID3v1/APIC metadata, and strips CHAP/CTOC',
        () async {
          if (!await hasTool('ffmpeg')) {
            markTestSkipped('ffmpeg not installed');
            return;
          }

          final tmpDir = await Directory.systemTemp.createTemp(
            'chapter_mp3_playability_',
          );
          try {
            final coverPath = '${tmpDir.path}/cover.jpg';
            final rawMp3Path = '${tmpDir.path}/raw.mp3';
            final taggedMp3Path = '${tmpDir.path}/audiobook.mp3';
            final slicedMp3Path = '${tmpDir.path}/chapter_1.mp3';

            final coverGen = await Process.run('ffmpeg', [
              '-y',
              '-f',
              'lavfi',
              '-i',
              'color=c=red:s=32x32:d=1',
              '-frames:v',
              '1',
              coverPath,
            ]);
            expect(coverGen.exitCode, equals(0));
            final coverBytes = await File(coverPath).readAsBytes();

            // Generate 3s of valid MPEG audio frames.
            final genMp3 = await Process.run('ffmpeg', [
              '-y',
              '-f',
              'lavfi',
              '-i',
              'sine=frequency=523.25:duration=3',
              '-c:a',
              'libmp3lame',
              '-b:a',
              '128k',
              rawMp3Path,
            ]);
            expect(
              genMp3.exitCode,
              equals(0),
              reason: 'ffmpeg mp3 generation failed: ${genMp3.stderr}',
            );

            final rawMp3Bytes = await File(rawMp3Path).readAsBytes();
            // Strip any ffmpeg-generated ID3 tag so we control exact ID3v2+CHAP+ID3v1.
            var audioStart = 0;
            if (rawMp3Bytes.length >= 10 &&
                rawMp3Bytes[0] == 0x49 &&
                rawMp3Bytes[1] == 0x44 &&
                rawMp3Bytes[2] == 0x33) {
              final sz =
                  ((rawMp3Bytes[6] & 0x7F) << 21) |
                  ((rawMp3Bytes[7] & 0x7F) << 14) |
                  ((rawMp3Bytes[8] & 0x7F) << 7) |
                  (rawMp3Bytes[9] & 0x7F);
              audioStart = 10 + sz;
            }
            final mpegFrames = rawMp3Bytes.sublist(audioStart);

            final chap1 = buildId3v23Frame('CHAP', [
              ...utf8.encode('ch1'),
              0x00,
              0, 0, 0, 0,
              0, 0, 0x05, 0xDC, // 1500ms
              0xFF, 0xFF, 0xFF, 0xFF,
              0xFF, 0xFF, 0xFF, 0xFF,
              ...buildId3v23Frame('TIT2', [0x00, ...latin1.encode('Ch 1')]),
            ]);
            final id3v2 = buildId3Tag(
              majorVersion: 3,
              revision: 0,
              flags: 0x00,
              payload: [
                ...buildId3v23Frame('TIT2', [
                  0x03,
                  ...utf8.encode('MP3 Audiobook'),
                ]),
                ...buildId3v23Frame('TPE1', [
                  0x03,
                  ...utf8.encode('MP3 Author'),
                ]),
                ...buildId3v23Frame('TALB', [
                  0x03,
                  ...utf8.encode('MP3 Series'),
                ]),
                ...buildId3v23Frame('TCON', [
                  0x03,
                  ...utf8.encode('Audiobook'),
                ]),
                ...buildId3v23Frame('TYER', [0x03, ...utf8.encode('2024')]),
                // Whole-file duration & custom chapter XML that must be stripped
                ...buildId3v23Frame('TLEN', [0x00, ...ascii.encode('36000000')]),
                ...buildId3v23Frame('TXXX', [
                  0x00,
                  ...ascii.encode('OverDrive MediaMarkers'),
                  0x00,
                  ...ascii.encode('<Markers><Marker><Name>Ch1</Name></Marker></Markers>'),
                ]),
                ...buildId3v23Frame('APIC', [
                  0x00,
                  ...ascii.encode('image/jpeg'),
                  0x00,
                  0x03,
                  0x00,
                  ...coverBytes,
                ]),
                ...chap1,
              ],
            );

            // Trailing ID3v1 tag (128 bytes)
            final id3v1 = List<int>.filled(128, 0);
            id3v1.setRange(0, 3, 'TAG'.codeUnits);
            id3v1.setRange(3, 12, 'V1 Title!'.codeUnits);
            id3v1.setRange(97, 108, 'V1 Comment!'.codeUnits);

            await File(taggedMp3Path).writeAsBytes([
              ...id3v2,
              ...mpegFrames,
              ...id3v1,
            ]);

            final originalMeta = await parseFile(
              taggedMp3Path,
              options: const ParseOptions(includeChapters: true),
            );
            expect(originalMeta.format.chapters, hasLength(1));

            final res = await ChapterDownloader.downloadChapter(
              originalUrl: taggedMp3Path,
              chapterStartMs: 0,
              chapterEndMs: 1500,
              outputPath: slicedMp3Path,
            );
            expect(res.isSuccess, isTrue, reason: res.error);

            await verifyPlayableWithSystemTools(
              slicedMp3Path,
              expectedCodec: 'mp3',
              minDurationSec: 1,
              expectedFfprobeTags: const {
                'title': 'MP3 Audiobook',
                'artist': 'MP3 Author',
                'album': 'MP3 Series',
                'genre': 'Audiobook',
              },
            );

            final slicedMeta = await parseFile(
              slicedMp3Path,
              options: const ParseOptions(includeChapters: true),
            );
            expect(slicedMeta.common.title, equals('MP3 Audiobook'));
            expect(slicedMeta.common.artist, equals('MP3 Author'));
            expect(slicedMeta.common.album, equals('MP3 Series'));
            expect(slicedMeta.common.year, equals(2024));
            expect(slicedMeta.common.genre, equals(['Audiobook']));
            // ID3v1 comment preserved
            expect(
              slicedMeta.native['ID3v1']?.any(
                (t) => t.id == 'comment' && t.value == 'V1 Comment!',
              ),
              isTrue,
            );
            // APIC image preserved
            final apic = slicedMeta.native['ID3v2.3']?.firstWhere(
              (t) => t.id == 'APIC',
            );
            expect(
              (apic?.value as Picture?)?.data,
              equals(coverBytes),
            );
            // Original full-book CHAP/CTOC, TLEN, and MediaMarkers stripped from slice
            expect(slicedMeta.format.chapters, isNull);
            final v23 = slicedMeta.native['ID3v2.3'] ?? const <Tag>[];
            expect(v23.any((t) => t.id == 'TLEN'), isFalse);
            expect(v23.any((t) => t.id == 'CHAP'), isFalse);
            expect(
              v23.any((t) => t.id.startsWith('TXXX') && '${t.id}:${t.value}'.contains('MediaMarkers')),
              isFalse,
            );
          } finally {
            if (tmpDir.existsSync()) {
              await tmpDir.delete(recursive: true);
            }
          }
        },
      );

      test(
        'M4aMuxer.sanitizeUdtaForSlice strips chpl, pgap, iTunSMPB, and OverDrive MediaMarkers while keeping covr and title',
        () async {
          List<int> u32(int v) => [
            (v >> 24) & 0xFF,
            (v >> 16) & 0xFF,
            (v >> 8) & 0xFF,
            v & 0xFF,
          ];
          List<int> atom(String name, List<int> payload) => [
            ...u32(8 + payload.length),
            ...latin1.encode(name),
            ...payload,
          ];
          List<int> dataAtom(int type, List<int> val) => atom('data', [
            0,
            (type >> 16) & 0xFF,
            (type >> 8) & 0xFF,
            type & 0xFF,
            0, 0, 0, 0,
            ...val,
          ]);
          List<int> customAtom(String name, String val) => atom('----', [
            ...atom('mean', [0, 0, 0, 0, ...ascii.encode('com.apple.iTunes')]),
            ...atom('name', [0, 0, 0, 0, ...ascii.encode(name)]),
            ...dataAtom(1, utf8.encode(val)),
          ]);

          final ilst = atom('ilst', [
            ...atom('©nam', dataAtom(1, utf8.encode('Book Title'))),
            ...atom('covr', dataAtom(13, [0xFF, 0xD8, 0xFF, 0xD9])),
            ...atom('pgap', dataAtom(21, [1])),
            ...customAtom('iTunSMPB', '00000000 00000840 00000180 0000000012345678'),
            ...customAtom('OverDrive MediaMarkers', '<Markers/>'),
          ]);
          final meta = atom('meta', [0, 0, 0, 0, ...ilst]);
          final chpl = atom('chpl', List<int>.filled(16, 0));
          final udta = atom('udta', [...meta, ...chpl]);

          final sanitized = M4aMuxer.sanitizeUdtaForSlice(udta);
          expect(sanitized, isNotNull);

          final m4a = M4aMuxer.buildM4a(
            rawStsdBox: atom('stsd', [
              0, 0, 0, 0, ...u32(1),
              ...atom('mp4a', List<int>.filled(28, 0)),
            ]),
            sampleSizes: const [4],
            timeScale: 44100,
            sampleDuration: 1024,
            rawAudioData: Uint8List.fromList([0, 0, 0, 0]),
            rawUdtaBox: sanitized,
          );

          final parsed = await parseBytes(m4a);
          expect(parsed.common.title, equals('Book Title'));
          expect(parsed.common.picture, hasLength(1));
          expect(parsed.common.picture!.first.data, equals([0xFF, 0xD8, 0xFF, 0xD9]));
          expect(parsed.common.gapless, isNull);
          final iTunes = parsed.native['iTunes'] ?? const <Tag>[];
          expect(iTunes.any((t) => t.id.contains('iTunSMPB')), isFalse);
          expect(iTunes.any((t) => t.id.contains('MediaMarkers')), isFalse);
          expect(iTunes.any((t) => t.id == 'pgap'), isFalse);
        },
      );

      test(
        'extractChapterBytes slices MP4/M4A and MP3 in memory while preserving cover art and stripping chapters',
        () async {
          final cover = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

          // 1a. MP4 with chapters -> M4A in-memory slice strips original chapters
          final mp4Bytes = await File(originalFilePath).readAsBytes();
          final mp4Slice = await ChapterDownloader.extractChapterBytes(
            sourceBytes: mp4Bytes,
            chapterStartMs: 0,
            chapterEndMs: 2000,
            fileName: 'video_chapters.mp4',
          );
          expect(mp4Slice.isSuccess, isTrue, reason: mp4Slice.error);
          expect(mp4Slice.extension, equals('m4a'));
          expect(mp4Slice.mimeType, equals('audio/mp4'));
          final parsedMp4Slice = await parseBytes(
            mp4Slice.bytes!,
            options: const ParseOptions(includeChapters: true),
          );
          expect(parsedMp4Slice.format.chapters, isNull);

          // 1b. M4A with cover art & tags -> M4A in-memory slice preserves them
          final m4aPath =
              '${Directory.current.path}/test/samples/mp4/sample.m4a';
          final m4aBytes = await File(m4aPath).readAsBytes();
          final originalM4a = await parseBytes(m4aBytes);
          final m4aSlice = await ChapterDownloader.extractChapterBytes(
            sourceBytes: m4aBytes,
            chapterStartMs: 0,
            chapterEndMs: ((originalM4a.format.duration ?? 2.0) * 1000).round(),
            fileName: 'sample.m4a',
          );
          expect(m4aSlice.isSuccess, isTrue, reason: m4aSlice.error);
          final parsedM4aSlice = await parseBytes(
            m4aSlice.bytes!,
            options: const ParseOptions(includeChapters: true),
          );
          expect(parsedM4aSlice.common.title, equals(originalM4a.common.title));
          expect(
            parsedM4aSlice.common.picture?.length ?? 0,
            equals(originalM4a.common.picture?.length ?? 0),
          );
          expect(parsedM4aSlice.format.chapters, isNull);

          // 2. MP3 -> MP3 in-memory slice (MPEG1 Layer III 128kbps 44.1kHz = 417 B/frame)
          final singleMpegFrame = <int>[
            0xFF,
            0xFB,
            0x90,
            0x00,
            ...List<int>.filled(413, 0xAA),
          ];
          final mpegFrames = <int>[
            for (var i = 0; i < 60; i++) ...singleMpegFrame,
          ];
          final chap1 = buildId3v23Frame('CHAP', [
            ...ascii.encode('ch1'), 0x00,
            0, 0, 0, 0, 0, 0, 5, 0xDC,
            0, 0, 0, 0, 0, 0, 0, 100,
            ...buildId3v23Frame('TIT2', [0x00, ...latin1.encode('Ch 1')]),
          ]);
          final id3v2 = buildId3Tag(
            majorVersion: 3,
            revision: 0,
            flags: 0x00,
            payload: [
              ...buildId3v23Frame('TIT2', [0x03, ...utf8.encode('Web MP3')]),
              ...buildId3v23Frame('TLEN', [0x00, ...ascii.encode('999999')]),
              ...buildId3v23Frame('APIC', [
                0x00,
                ...ascii.encode('image/jpeg'),
                0x00,
                0x03,
                0x00,
                ...cover,
              ]),
              ...chap1,
            ],
          );
          final mp3Bytes = Uint8List.fromList([...id3v2, ...mpegFrames]);
          final mp3Slice = await ChapterDownloader.extractChapterBytes(
            sourceBytes: mp3Bytes,
            chapterStartMs: 0,
            chapterEndMs: 1200,
            fileName: 'book.mp3',
          );
          expect(mp3Slice.isSuccess, isTrue, reason: mp3Slice.error);
          expect(mp3Slice.extension, equals('mp3'));
          expect(mp3Slice.mimeType, equals('audio/mpeg'));
          final parsedMp3Slice = await parseBytes(
            mp3Slice.bytes!,
            options: const ParseOptions(includeChapters: true),
          );
          expect(parsedMp3Slice.common.title, equals('Web MP3'));
          final mp3Apic = parsedMp3Slice.native['ID3v2.3']?.firstWhere(
            (t) => t.id == 'APIC',
          );
          expect((mp3Apic?.value as Picture?)?.data, equals(cover));
          expect(parsedMp3Slice.format.chapters, isNull);
          expect(
            parsedMp3Slice.native['ID3v2.3']?.any((t) => t.id == 'TLEN') ??
                false,
            isFalse,
          );

          // 3. Unsupported bytes fail cleanly
          final unsupported = await ChapterDownloader.extractChapterBytes(
            sourceBytes: Uint8List.fromList(ascii.encode('fLaC0000')),
            chapterStartMs: 0,
            chapterEndMs: 1000,
            fileName: 'song.flac',
          );
          expect(unsupported.isSuccess, isFalse);
          expect(unsupported.error, isNotEmpty);
        },
      );
    });
  });
}

class _RangeHttpServer {
  _RangeHttpServer._(this._server, this._bytes, this._path);

  final HttpServer _server;
  final Uint8List _bytes;
  final String _path;

  String get url => 'http://127.0.0.1:${_server.port}$_path';

  static Future<_RangeHttpServer> start(List<int> bytes, String path) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = _RangeHttpServer._(
      server,
      Uint8List.fromList(bytes),
      path,
    );
    unawaited(instance._serve());
    return instance;
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mp4');

      if (request.method == 'HEAD') {
        request.response.contentLength = _bytes.length;
        await request.response.close();
        continue;
      }

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parts = rangeHeader.substring(6).split('-');
        final start = int.parse(parts[0]).clamp(0, _bytes.length - 1);
        final end = parts.length > 1 && parts[1].isNotEmpty
            ? int.parse(parts[1]).clamp(0, _bytes.length - 1)
            : _bytes.length - 1;
        final safeEnd = end < start ? start : end;
        final slice = _bytes.sublist(start, safeEnd + 1);
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$safeEnd/${_bytes.length}',
        );
        request.response.contentLength = slice.length;
        request.response.add(slice);
        await request.response.close();
        continue;
      }

      request.response.contentLength = _bytes.length;
      request.response.add(_bytes);
      await request.response.close();
    }
  }

  Future<void> close() => _server.close(force: true);
}
