import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
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

      final metadata = await parseFile(
        file.path,
        options: const ParseOptions(includeChapters: true),
      );

      checkFormat(metadata.format, container: 'M4A/isom/iso2');

      // Should have iTunes atoms
      expect(metadata.native.containsKey('iTunes'), isTrue);

      // Verify chapters
      expect(metadata.format.chapters, isNotNull);
      expect(metadata.format.chapters!.length, 3);
      expect(metadata.format.chapters![0].title, 'Chapter 1');
      expect(metadata.format.chapters![0].start, 1023);
      expect(metadata.format.chapters![1].title, 'Chapter 2');
      expect(metadata.format.chapters![1].start, 1023);
      expect(metadata.format.chapters![2].title, 'Chapter 3');
      expect(metadata.format.chapters![2].start, 1023);
    });
  });
}
