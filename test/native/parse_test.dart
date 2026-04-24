import 'dart:io';

import 'package:metadata_audio/src/native/api.dart';
import 'package:metadata_audio/src/native/frb_generated.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Symphonia parseFromPath aggregation', () {
    setUpAll(RustLib.init);
    tearDownAll(RustLib.dispose);

    String sample(String relativePath) =>
        p.join(Directory.current.path, 'test', 'samples', relativePath);

    Future<void> expectParsedMetadata(
      String relativePath, {
      required String expectedContainer,
      String? expectedTitle,
      String? expectedArtist,
      String? expectedAlbum,
      Matcher? expectedAlbumMatcher,
      bool expectPictures = false,
      bool expectWarnings = false,
    }) async {
      final file = File(sample(relativePath));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFromPath(path: file.path);

      expect(metadata.format.container, expectedContainer, reason: '$relativePath container');

      if (expectedTitle != null) {
        expect(metadata.common.title, expectedTitle, reason: '$relativePath title');
      }
      if (expectedArtist != null) {
        expect(metadata.common.artist, contains(expectedArtist), reason: '$relativePath artist');
      }
      if (expectedAlbum != null) {
        expect(metadata.common.album, expectedAlbum, reason: '$relativePath album');
      }
      if (expectedAlbumMatcher != null) {
        expect(metadata.common.album, expectedAlbumMatcher, reason: '$relativePath album');
      }

      expect(metadata.native, isNotEmpty, reason: '$relativePath native tags');

      if (expectPictures) {
        expect(metadata.pictures, isNotEmpty, reason: '$relativePath pictures');
      }

      if (expectWarnings) {
        expect(metadata.warnings, isNotEmpty, reason: '$relativePath warnings');
      } else {
        expect(metadata.warnings, isEmpty, reason: '$relativePath warnings');
      }
    }

    Future<void> expectParsedMetadataFromBytes(
      String relativePath, {
      required String expectedContainer,
      String? expectedTitle,
      String? expectedArtist,
      String? expectedAlbum,
      Matcher? expectedAlbumMatcher,
      String? mimeHint,
      bool expectPictures = false,
      bool expectWarnings = false,
    }) async {
      final file = File(sample(relativePath));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFromBytes(
        bytes: file.readAsBytesSync(),
        mimeHint: mimeHint,
      );

      expect(metadata.format.container, expectedContainer, reason: '$relativePath container');

      if (expectedTitle != null) {
        expect(metadata.common.title, expectedTitle, reason: '$relativePath title');
      }
      if (expectedArtist != null) {
        expect(metadata.common.artist, contains(expectedArtist), reason: '$relativePath artist');
      }
      if (expectedAlbum != null) {
        expect(metadata.common.album, expectedAlbum, reason: '$relativePath album');
      }
      if (expectedAlbumMatcher != null) {
        expect(metadata.common.album, expectedAlbumMatcher, reason: '$relativePath album');
      }

      expect(metadata.native, isNotEmpty, reason: '$relativePath native tags');

      if (expectPictures) {
        expect(metadata.pictures, isNotEmpty, reason: '$relativePath pictures');
      }

      if (expectWarnings) {
        expect(metadata.warnings, isNotEmpty, reason: '$relativePath warnings');
      } else {
        expect(metadata.warnings, isEmpty, reason: '$relativePath warnings');
      }
    }

    test('aggregates MP3 metadata', () async {
      await expectParsedMetadata(
        'mp3/id3v2.3.mp3',
        expectedContainer: 'mp3',
        expectedTitle: 'Home',
        expectedArtist: 'Explosions In The Sky/Another/',
        expectedAlbumMatcher: startsWith('Friday Night Lights [Original'),
        expectPictures: true,
      );
    });

    test('aggregates FLAC metadata', () async {
      await expectParsedMetadata(
        'flac/sample.flac',
        expectedContainer: 'flac',
        expectedTitle: 'Mi Korasón',
        expectedArtist: 'Yasmin Levy',
        expectedAlbum: 'Sentir',
      );
    });

    test('aggregates MP4 metadata', () async {
      await expectParsedMetadata(
        'mp4/sample.m4a',
        expectedContainer: 'mp4',
        expectedTitle: 'Testcase',
        expectedArtist: 'Testcase',
        expectedAlbum: 'Testcase',
      );
    });

    test('aggregates OGG metadata', () async {
      await expectParsedMetadata(
        'ogg/vorbis.ogg',
        expectedContainer: 'ogg',
        expectedTitle: 'In Bloom',
        expectedArtist: 'Nirvana',
        expectedAlbum: 'Nevermind',
      );
    });

    group('Symphonia parseFromBytes aggregation', () {
      test('aggregates MP3 metadata from bytes', () async {
        await expectParsedMetadataFromBytes(
          'mp3/id3v2.3.mp3',
          expectedContainer: 'mp3',
          expectedTitle: 'Home',
          expectedArtist: 'Explosions In The Sky/Another/',
          expectedAlbumMatcher: startsWith('Friday Night Lights [Original'),
          expectPictures: true,
        );
      });

      test('aggregates FLAC metadata from bytes', () async {
        await expectParsedMetadataFromBytes(
          'flac/sample.flac',
          expectedContainer: 'flac',
          expectedTitle: 'Mi Korasón',
          expectedArtist: 'Yasmin Levy',
          expectedAlbum: 'Sentir',
        );
      });

      test('aggregates MP4 metadata from bytes', () async {
        await expectParsedMetadataFromBytes(
          'mp4/sample.m4a',
          expectedContainer: 'mp4',
          expectedTitle: 'Testcase',
          expectedArtist: 'Testcase',
          expectedAlbum: 'Testcase',
        );
      });

      test('aggregates OGG metadata from bytes', () async {
        await expectParsedMetadataFromBytes(
          'ogg/vorbis.ogg',
          expectedContainer: 'ogg',
          expectedTitle: 'In Bloom',
          expectedArtist: 'Nirvana',
          expectedAlbum: 'Nevermind',
          mimeHint: 'audio/ogg',
        );
      });
    });

    test('collects warnings for untagged media', () async {
      final file = File(sample('mp3/no-tags.mp3'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFromPath(path: file.path);

      expect(metadata.native, isEmpty);
      expect(metadata.warnings, isNotEmpty);
      expect(metadata.warnings, contains('no native tags found in metadata revisions'));
    });
  });
}
