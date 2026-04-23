import 'dart:io';

import 'package:metadata_audio/src/native/api.dart';
import 'package:metadata_audio/src/native/frb_generated.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Symphonia picture extraction', () {
    setUpAll(RustLib.init);
    tearDownAll(RustLib.dispose);

    String sample(String relativePath) =>
        p.join(Directory.current.path, 'test', 'samples', relativePath);

    test('FLAC sample fixtures currently expose no embedded visuals', () async {
      for (final relativePath in const [
        'flac/sample.flac',
        'flac/flac-multiple-album-artists-tags.flac',
        'flac/testcase.flac',
      ]) {
        final file = File(sample(relativePath));
        if (!file.existsSync()) {
          markTestSkipped('Sample file not found: ${file.path}');
          return;
        }

        final pictures = await pocGetPictures(path: file.path);
        expect(pictures, isEmpty, reason: '$relativePath pictures');
      }
    });

    test('MP3 id3v2 fixture exposes JPEG front cover art', () async {
      final file = File(sample('mp3/id3v2.3.mp3'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final pictures = await pocGetPictures(path: file.path);

      expect(pictures, isNotEmpty);
      final picture = pictures.first;
      expect(picture.format, isNotNull);
      expect(picture.format, startsWith('image/'));
      expect(picture.data, isNotEmpty);
      expect(picture.type, 'Cover (front)');
    });

    test('other MP3 sample fixtures currently expose no APIC visuals', () async {
      for (final relativePath in const [
        'mp3/id3v1.mp3',
        'mp3/adts-0-frame.mp3',
        'mp3/issue-347.mp3',
        'mp3/no-tags.mp3',
      ]) {
        final file = File(sample(relativePath));
        if (!file.existsSync()) {
          markTestSkipped('Sample file not found: ${file.path}');
          return;
        }

        final pictures = await pocGetPictures(path: file.path);
        expect(pictures, isEmpty, reason: '$relativePath pictures');
      }
    });

    test('MP4 audiobook fixture exposes JPEG front cover art', () async {
      final file = File(sample('mp4/The Dark Forest.m4a'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final pictures = await pocGetPictures(path: file.path);

      expect(pictures, isNotEmpty);
      final picture = pictures.first;
      expect(picture.format, isNotNull);
      expect(picture.format, startsWith('image/'));
      expect(picture.data, isNotEmpty);
      expect(picture.type, 'Cover (front)');
    });

    test('MP4 short sample currently exposes no embedded visuals', () async {
      final file = File(sample('mp4/sample.m4a'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final pictures = await pocGetPictures(path: file.path);
      expect(pictures, isEmpty);
    });
  });
}
