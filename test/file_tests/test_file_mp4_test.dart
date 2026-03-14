import 'dart:io';

import 'package:audio_metadata/audio_metadata.dart';
import 'package:audio_metadata/src/mp4/mp4_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('MP4/M4A file parsing (real samples)', () {
    setUp(() {
      final registry = ParserRegistry()..register(Mp4Loader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('parses sample.m4a', () async {
      final file = File(p.join(samplePath, 'mp4', 'sample.m4a'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFile(file.path);

      checkFormat(metadata.format, container: 'M4A/isom/iso2');

      // Should have iTunes atoms
      expect(metadata.native.containsKey('iTunes'), isTrue);
    });
  });
}
