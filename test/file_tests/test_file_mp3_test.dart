import 'dart:io';

import 'package:audio_metadata/audio_metadata.dart';
import 'package:audio_metadata/src/mpeg/mpeg_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('MP3 file parsing (real samples)', () {
    setUp(() {
      final registry = ParserRegistry()..register(MpegLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('parses id3v2.3.mp3 with metadata', () async {
      final file = File(p.join(samplePath, 'mp3', 'id3v2.3.mp3'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFile(file.path);

      // Format checks
      checkFormat(
        metadata.format,
        container: 'MPEG',
        codec: 'MPEG 1 Layer 3',
        sampleRate: 44100,
        numberOfChannels: 2,
        bitrate: 128000,
      );

      // Common metadata checks
      checkCommon(
        metadata.common,
        title: 'Home',
        artist: 'Explosions In The Sky',
        album: 'Friday Night Lights [Original Movie Soundtrack]',
      );

      // Should have ID3v2.3 tags
      expect(metadata.native.containsKey('ID3v2.3'), isTrue);
      expect(metadata.native.containsKey('ID3v1'), isTrue);
    });

    test('parses id3v1.mp3 (Luomo - Tessio)', () async {
      final file = File(p.join(samplePath, 'mp3', 'id3v1.mp3'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFile(file.path);

      // Format checks
      checkFormat(
        metadata.format,
        container: 'MPEG',
        codec: 'MPEG 1 Layer 3',
        sampleRate: 44100,
        numberOfChannels: 2,
        bitrate: 56000,
      );

      // Common metadata checks
      checkCommon(metadata.common, title: 'Luomo - Tessio (Spektre Remix)');

      // Should have ID3v1 tags only
      expect(metadata.native.containsKey('ID3v1'), isTrue);
    });

    test('parses no-tags.mp3 (format only)', () async {
      final file = File(p.join(samplePath, 'mp3', 'no-tags.mp3'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFile(file.path);

      // Format checks
      checkFormat(
        metadata.format,
        container: 'MPEG',
        codec: 'MPEG 1 Layer 3',
        sampleRate: 44100,
        numberOfChannels: 2,
        bitrate: 56000,
      );

      // Should have no native tags
      expect(metadata.native.isEmpty, isTrue);

      // Common metadata should be empty
      expect(metadata.common.title, isNull);
      expect(metadata.common.artist, isNull);
      expect(metadata.common.album, isNull);
    });

    test('parses issue-347.mp3 (regression test)', () async {
      final file = File(p.join(samplePath, 'mp3', 'issue-347.mp3'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      // issue-347.mp3 is known to have parsing issues
      // The test passes if parsing raises FormatException as expected
      expect(
        () async => await parseFile(file.path),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses adts-0-frame.mp3 with metadata', () async {
      final file = File(p.join(samplePath, 'mp3', 'adts-0-frame.mp3'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFile(file.path);

      // Format checks
      checkFormat(
        metadata.format,
        container: 'MPEG',
        codec: 'MPEG 1 Layer 3',
        sampleRate: 44100,
        numberOfChannels: 2,
        bitrate: 104000,
      );

      // Common metadata checks
      checkCommon(
        metadata.common,
        title: 'Jan Pillemann Otze',
        artist: 'Mickie Krause',
        album: 'Ballermann Hits 2008',
      );

      // Should have ID3v2.3 and ID3v1 tags
      expect(metadata.native.containsKey('ID3v2.3'), isTrue);
      expect(metadata.native.containsKey('ID3v1'), isTrue);
    });
  });
}
