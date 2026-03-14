import 'dart:io';

import 'package:audio_metadata/audio_metadata.dart';
import 'package:audio_metadata/src/flac/flac_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('FLAC file parsing (real samples)', () {
    setUp(() {
      final registry = ParserRegistry()..register(FlacLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('parses sample.flac (Yasmin Levy)', () async {
      final file = File(p.join(samplePath, 'flac', 'sample.flac'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFile(file.path);

      checkFormat(
        metadata.format,
        container: 'flac',
        codec: 'FLAC',
        lossless: true,
      );

      // Should have Vorbis comments
      expect(metadata.native.containsKey('vorbis'), isTrue);

      // Check metadata
      checkCommon(
        metadata.common,
        title: 'Mi Korasón',
        artist: 'Yasmin Levy',
        album: 'Sentir',
        albumartist: 'Yasmin Levy',
      );
    });

    test('parses flac-multiple-album-artists-tags.flac', () async {
      final file = File(
        p.join(samplePath, 'flac', 'flac-multiple-album-artists-tags.flac'),
      );
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFile(file.path);

      checkFormat(metadata.format, container: 'flac', codec: 'FLAC');

      // Check metadata
      checkCommon(
        metadata.common,
        title: 'Test Track',
        artist: 'Artist Two',
        album: 'Test Album',
        albumartist: 'Album Artist Two',
      );
    });

    test('parses testcase.flac (rating)', () async {
      final file = File(p.join(samplePath, 'flac', 'testcase.flac'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFile(file.path);

      checkFormat(
        metadata.format,
        container: 'flac',
        codec: 'FLAC',
        lossless: true,
      );

      // Check metadata
      checkCommon(
        metadata.common,
        title: 'Testcase',
        artist: 'Testcase',
        album: 'Testcase',
      );
    });
  });
}
