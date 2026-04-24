import 'dart:io';

import 'package:metadata_audio/src/native/api.dart';
import 'package:metadata_audio/src/native/frb_generated.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Symphonia metadata POC', () {
    setUpAll(RustLib.init);

    tearDownAll(RustLib.dispose);

    String sample(String relativePath) =>
        p.join(Directory.current.path, 'test', 'samples', relativePath);

    Future<void> expectBasicMetadata(
      String relativePath, {
      String? expectedTitle,
      String? expectedArtist,
      String? expectedAlbum,
      String? expectedAlbumPrefix,
      int? expectedChapterCount,
    }) async {
      final metadata = await pocParseFile(path: sample(relativePath));

      expect(metadata.container, isNotNull, reason: '$relativePath container');
      expect(metadata.container, isNotEmpty, reason: '$relativePath container');
      expect(metadata.codec, isNotNull, reason: '$relativePath codec');
      expect(metadata.codec, isNotEmpty, reason: '$relativePath codec');
      expect(metadata.durationSecs, isNotNull, reason: '$relativePath duration');
      expect(metadata.durationSecs!, greaterThan(0), reason: '$relativePath duration');
      expect(metadata.chapterCount, greaterThanOrEqualTo(0), reason: '$relativePath chapter count');

      if (expectedTitle != null) {
        expect(metadata.title, equals(expectedTitle), reason: '$relativePath title');
        expect(metadata.artist, contains(expectedArtist), reason: '$relativePath artist');
        expect(expectedAlbum, isNotNull, reason: '$relativePath expected album');
        if (expectedAlbumPrefix != null) {
          expect(
            metadata.album,
            startsWith(expectedAlbumPrefix),
            reason: '$relativePath album',
          );
        } else {
          expect(metadata.album, equals(expectedAlbum), reason: '$relativePath album');
        }
        expect(
          metadata.nativeTagCount,
          greaterThan(0),
          reason: '$relativePath nativeTagCount',
        );
      }

      if (expectedChapterCount != null) {
        expect(
          metadata.chapterCount,
          equals(expectedChapterCount),
          reason: '$relativePath chapterCount',
        );
      }
    }

    test('parses MP3 metadata from file', () async {
      await expectBasicMetadata(
        'mp3/id3v2.3.mp3',
        expectedTitle: 'Home',
        expectedArtist: 'Explosions In The Sky',
        expectedAlbum: 'Friday Night Lights [Original Movie Soundtrack]',
        expectedAlbumPrefix: 'Friday Night Lights [Original',
      );
    });

    test('parses FLAC metadata from file', () async {
      await expectBasicMetadata(
        'flac/sample.flac',
        expectedTitle: 'Mi Korasón',
        expectedArtist: 'Yasmin Levy',
        expectedAlbum: 'Sentir',
      );
    });

    test('parses MP4 metadata from file', () async {
      await expectBasicMetadata(
        'mp4/sample.m4a',
        expectedChapterCount: 0,
      );
    });

    test('parses OGG metadata from file', () async {
      await expectBasicMetadata('ogg/vorbis.ogg');
    });

    group('returns native tags', () {
      Future<void> expectNativeTags(
        String relativePath, {
        required List<String> expectedKeys,
        List<String> forbiddenKeys = const [],
      }) async {
        final tags = await pocGetNativeTags(path: sample(relativePath));

        expect(tags, isNotEmpty, reason: '$relativePath tags');

        final keys = tags.map((tag) => tag.key).toList();
        for (final key in expectedKeys) {
          expect(keys, contains(key), reason: '$relativePath missing $key');
        }

        for (final key in forbiddenKeys) {
          expect(keys, isNot(contains(key)), reason: '$relativePath should not contain $key');
        }

        expect(keys.where((key) => key.isEmpty), isEmpty, reason: '$relativePath empty raw keys');
      }

      test('mp4 exposes reconstructed atom keys', () async {
        await expectNativeTags(
          'mp4/sample.m4a',
          expectedKeys: ['©nam', '©alb', '©ART'],
          forbiddenKeys: [''],
        );
      });

      test('mp3 exposes raw ID3 frame ids', () async {
        await expectNativeTags(
          'mp3/id3v2.3.mp3',
          expectedKeys: ['TIT2', 'TALB', 'TPE1'],
        );
      });

      test('flac exposes vorbis comment keys', () async {
        await expectNativeTags(
          'flac/sample.flac',
          expectedKeys: ['TITLE', 'ARTIST', 'ALBUM'],
        );
      });
    });
  });
}
