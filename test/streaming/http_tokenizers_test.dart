import 'package:audio_metadata/audio_metadata.dart';
import 'package:audio_metadata/src/aiff/aiff_loader.dart';
import 'package:audio_metadata/src/flac/flac_loader.dart';
import 'package:audio_metadata/src/mp4/mp4_loader.dart';
import 'package:audio_metadata/src/mpeg/mpeg_loader.dart';
import 'package:audio_metadata/src/ogg/ogg_loader.dart';
import 'package:audio_metadata/src/wav/wave_loader.dart';
import 'package:test/test.dart';

/// Tests for the three HTTP tokenizers and smart parseUrl function.
///
/// NOTE: These tests require a real HTTP URL to test against.
/// Set [testUrl] below to a large audio file URL (300MB+) that supports
/// HTTP Range requests, or leave empty to skip these tests.
void main() {
  group('HTTP Tokenizers', () {
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

    // Configuration: Set to your own test URL or leave empty to skip
    // Example: 'https://example.com/large-audio.m4a'
    const testUrl = '';
    final hasTestUrl = testUrl.isNotEmpty;

    group('Strategy Detection', () {
      test(
        'detects strategy for large file',
        () async {
          final info = await detectStrategy(testUrl);

          print('');
          print('=== Strategy Detection ===');
          print('File: 323MB M4A');
          print('Detected strategy: ${info.strategy}');
          print('File size: ${info.fileSize} bytes');
          print('Range support: ${info.supportsRange}');
          print('');

          expect(info.fileSize, greaterThan(300 * 1024 * 1024));
          expect(info.supportsRange, isTrue);
        },
        skip: hasTestUrl ? false : 'No test URL configured',
        timeout: const Timeout(Duration(seconds: 10)),
      );
    });

    group('Smart parseUrl with auto-selection', () {
      test(
        'auto-selects best strategy for large file',
        () async {
          ParseStrategy? selectedStrategy;
          String? reason;

          final metadata = await parseUrl(
            testUrl,
            timeout: const Duration(seconds: 30),
            onStrategySelected: (strategy, r) {
              selectedStrategy = strategy;
              reason = r;
            },
          );

          print('');
          print('=== Smart parseUrl ===');
          print('Selected strategy: $selectedStrategy');
          print('Reason: $reason');
          print('Format: ${metadata.format.container}');
          print('Codec: ${metadata.format.codec}');
          print('Duration: ${metadata.format.duration?.toStringAsFixed(2)}s');
          print('');

          expect(selectedStrategy, isNotNull);
          expect(metadata.format.container, contains('M4A'));
        },
        skip: hasTestUrl ? false : 'No test URL configured',
        timeout: const Timeout(Duration(seconds: 60)),
      );
    });

    group('Explicit strategies', () {
      test('fullDownload strategy works', () async {
        // Skip this test as it would download 323MB
        print('Skipping fullDownload test (would download large file)');
        expect(true, isTrue);
      }, skip: 'Skipped to avoid large download');

      test(
        'headerOnly strategy works',
        () async {
          final metadata = await parseUrl(
            testUrl,
            timeout: const Duration(seconds: 30),
            strategy: ParseStrategy.headerOnly,
          );

          print('');
          print('=== Header-Only Strategy ===');
          print('Format: ${metadata.format.container}');
          print('Codec: ${metadata.format.codec}');
          print('');

          expect(metadata.format.container, contains('M4A'));
        },
        skip: hasTestUrl ? false : 'No test URL configured',
        timeout: const Timeout(Duration(seconds: 60)),
      );

      test(
        'randomAccess strategy works',
        () async {
          final metadata = await parseUrl(
            testUrl,
            timeout: const Duration(seconds: 30),
            strategy: ParseStrategy.randomAccess,
          );

          print('');
          print('=== Random Access Strategy ===');
          print('Format: ${metadata.format.container}');
          print('Codec: ${metadata.format.codec}');
          print('');

          expect(metadata.format.container, contains('M4A'));
        },
        skip: hasTestUrl ? false : 'No test URL configured',
        timeout: const Timeout(Duration(seconds: 60)),
      );
    });

    group('Tokenizer classes', () {
      test(
        'HttpTokenizer creates successfully',
        () async {
          // Skip to avoid large download
          print('Skipping HttpTokenizer test (would download large file)');
          expect(true, isTrue);
        },
        skip: 'Skipped to avoid large download',
      );

      test(
        'RangeTokenizer creates and parses',
        () async {
          final tokenizer = await RangeTokenizer.fromUrl(testUrl);

          print('');
          print('=== RangeTokenizer ===');
          print('Header size: ${tokenizer.headerSize} bytes');
          print('Total size: ${tokenizer.totalSize} bytes');
          print('');

          expect(tokenizer.headerSize, greaterThan(0));
          expect(tokenizer.totalSize, greaterThan(300 * 1024 * 1024));

          tokenizer.close();
        },
        skip: hasTestUrl ? false : 'No test URL configured',
        timeout: const Timeout(Duration(seconds: 30)),
      );

      test(
        'RandomAccessTokenizer creates',
        () async {
          final tokenizer = await RandomAccessTokenizer.fromUrl(testUrl);

          print('');
          print('=== RandomAccessTokenizer ===');
          print('Can seek: ${tokenizer.canSeek}');
          print('Total size: ${tokenizer.fileInfo?.size}');
          print('');

          expect(tokenizer.canSeek, isTrue);

          tokenizer.close();
        },
        skip: hasTestUrl ? false : 'No test URL configured',
        timeout: const Timeout(Duration(seconds: 30)),
      );
    });
  });
}
