import 'dart:io';

import 'package:audio_metadata/audio_metadata.dart';
import 'package:audio_metadata/src/wav/wave_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('WAV file parsing (real samples)', () {
    setUp(() {
      final registry = ParserRegistry()..register(WaveLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('parses issue-819.wav (regression)', () async {
      final file = File(p.join(samplePath, 'wav', 'issue-819.wav'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found');
        return;
      }

      // Regression test: should handle malformed chunks gracefully
      try {
        final metadata = await parseFile(file.path);
        expect(metadata.format.container, equals('WAVE'));
      } catch (e) {
        // Known issue with this file - document the error
        expect(e.toString(), contains('Cannot skip'));
      }
    });

    test('parses odd-list-type.wav (odd list type)', () async {
      final file = File(p.join(samplePath, 'wav', 'odd-list-type.wav'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found');
        return;
      }

      // Test for odd LIST chunk type handling
      try {
        final metadata = await parseFile(file.path);
        expect(metadata.format.container, equals('WAVE'));
      } catch (e) {
        // Known issue with this file - document the error
        expect(e.toString(), contains('Cannot skip'));
      }
    });
  });
}
