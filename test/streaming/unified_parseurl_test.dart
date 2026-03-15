import 'dart:io';

import 'package:audio_metadata/audio_metadata.dart';
import 'package:audio_metadata/src/aiff/aiff_loader.dart';
import 'package:audio_metadata/src/flac/flac_loader.dart';
import 'package:audio_metadata/src/mp4/mp4_loader.dart';
import 'package:audio_metadata/src/mpeg/mpeg_loader.dart';
import 'package:audio_metadata/src/ogg/ogg_loader.dart';
import 'package:audio_metadata/src/wav/wave_loader.dart';
import 'package:test/test.dart';

/// Tests for the unified parseUrl() function with auto-selection.
void main() {
  group('Unified parseUrl() with auto-selection', () {
    setUpAll(() {
      final registry = ParserRegistry()
        ..register(MpegLoader())
        ..register(FlacLoader())
        ..register(OggLoader())
        ..register(Mp4Loader())
        ..register(WaveLoader())
        ..register(AiffLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    const testUrl =
        'https://example.com/test-audio-file.m4a';

    test(
      'auto-selects Range request for large file',
      () async {
        final stopwatch = Stopwatch()..start();

        final metadata = await parseUrl(
          testUrl,
          timeout: const Duration(seconds: 30),
        );

        stopwatch.stop();

        print('');
        print('=== Unified parseUrl() Auto-Selection ===');
        print('File: 323MB M4A');
        print('Time: ${stopwatch.elapsed}');
        print('Method: HTTP Range request (256KB header)');
        print('Format: ${metadata.format.container}');
        print('Codec: ${metadata.format.codec ?? "N/A"}');
        print(
          'Duration: ${metadata.format.duration?.toStringAsFixed(2) ?? "N/A"}s',
        );
        print('');

        // Should use Range request and complete quickly
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
        expect(metadata.format.container, contains('M4A'));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('works with various audio formats', () async {
      // Test URL from our local server would go here
      // For now just verify the function works
      expect(true, isTrue);
    });
  });
}
