import 'dart:io';

import 'package:audio_metadata/audio_metadata.dart';
import 'package:audio_metadata/src/ogg/ogg_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('OGG file parsing (real samples)', () {
    setUp(() {
      final registry = ParserRegistry()..register(OggLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('parses vorbis.ogg', () async {
      final file = File(p.join(samplePath, 'ogg', 'vorbis.ogg'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFile(file.path);

      checkFormat(metadata.format, container: 'ogg', codec: 'Vorbis I');

      // Should have Vorbis comments
      expect(metadata.native.containsKey('vorbis'), isTrue);
    });

    test('parses opus.ogg', () async {
      final file = File(p.join(samplePath, 'ogg', 'opus.ogg'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFile(file.path);

      checkFormat(metadata.format, container: 'ogg', codec: 'Opus');
    });
  });
}
