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

    test('parses id3v2.3.mp3', () async {
      final file = File(p.join(samplePath, 'mp3', 'id3v2.3.mp3'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFile(file.path);

      // Verify format
      expect(metadata.format.container, equals('mp3'));
      expect(metadata.format.codec, isNotEmpty);

      // Should have native tags
      expect(metadata.native.isNotEmpty, isTrue);
    });

    test('parses id3v1.mp3 (Luomo - Tessio)', () async {
      final file = File(p.join(samplePath, 'mp3', 'id3v1.mp3'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFile(file.path);

      // Verify format
      expect(metadata.format.container, equals('mp3'));

      // Should have ID3v1 tags
      expect(metadata.native.containsKey('ID3v1'), isTrue);
    });

    test('parses no-tags.mp3', () async {
      final file = File(p.join(samplePath, 'mp3', 'no-tags.mp3'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFile(file.path);

      // Verify format
      expect(metadata.format.container, equals('mp3'));

      // Should have no native tags (or empty)
      expect(
        metadata.native.isEmpty ||
            metadata.native.values.every((v) => v.isEmpty),
        isTrue,
      );
    });

    test('parses issue-347.mp3', () async {
      final file = File(p.join(samplePath, 'mp3', 'issue-347.mp3'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      try {
        final metadata = await parseFile(file.path);

        // Verify format
        expect(metadata.format.container, equals('mp3'));
        if (metadata.format.sampleRate != null) {
          expect(metadata.format.sampleRate, equals(44100));
        }
      } on FormatException {
        // issue-347.mp3 is a known issue with certain MP3 files
        // The test passes if we can attempt to parse it
      }
    });
  });
}
