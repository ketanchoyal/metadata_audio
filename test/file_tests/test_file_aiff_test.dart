import 'dart:io';

import 'package:audio_metadata/audio_metadata.dart';
import 'package:audio_metadata/src/aiff/aiff_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('AIFF file parsing (real samples)', () {
    setUp(() {
      final registry = ParserRegistry()..register(AiffLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('parses sample.aiff (Beth Hart & Joe Bonamassa)', () async {
      final file = File(p.join(samplePath, 'aiff', 'sample.aiff'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found');
        return;
      }

      final metadata = await parseFile(file.path);

      checkFormat(metadata.format, container: 'AIFF', codec: 'PCM');

      // Should have ID3v2.4 tags
      expect(metadata.native.containsKey('ID3v2.4'), isTrue);

      // Check metadata
      expect(metadata.common.title, equals('Sinner\'s Prayer'));
      expect(metadata.common.artist, contains('Beth Hart'));
      expect(metadata.common.album, equals('Don\'t Explain'));
    });
  });
}
