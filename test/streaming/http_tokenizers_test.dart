import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/aiff/aiff_loader.dart';
import 'package:metadata_audio/src/flac/flac_loader.dart';
import 'package:metadata_audio/src/mp4/mp4_loader.dart';
import 'package:metadata_audio/src/mpeg/mpeg_loader.dart';
import 'package:metadata_audio/src/ogg/ogg_loader.dart';
import 'package:metadata_audio/src/wav/wave_loader.dart';
import 'package:test/test.dart';

/// Tests for the three HTTP tokenizers and smart parseUrl function.
///
/// NOTE: These tests require a real HTTP URL to test against.
/// Set [testUrl] below to an audio file URL that supports HTTP Range requests.
/// The file should be at least 5MB to properly test the strategies.
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

    // =========================================================================
    // CONFIGURATION: Set your test URL here
    // =========================================================================
    // Example URLs that work well for testing:
    // - Google Drive direct download (if public)
    // - GitHub raw file URLs
    // - Your own server with Range support
    //
    // Requirements:
    // - Must support HTTP Range requests (Accept-Ranges: bytes)
    // - Should be at least 5MB to test strategy selection
    // - Must be accessible without authentication
    // =========================================================================
    const testUrl = '';

    // Minimum file size for strategy tests (5MB)
    const minFileSize = 5 * 1024 * 1024;

    final hasTestUrl = testUrl.isNotEmpty;

    group('Strategy Detection', () {
      test(
        'detects strategy based on file size',
        () async {
          final info = await detectStrategy(testUrl);

          print('');
          print('=== Strategy Detection ===');
          print('URL: \$testUrl');
          print('Detected strategy: \${info.strategy}');
          print('File size: \${info.fileSize != null ? "\${info.fileSize! ~/ 1024}KB" : "unknown"}');
          print('Range support: \${info.supportsRange}');
          print('');

          // Verify strategy selection logic
          if (info.fileSize != null) {
            if (info.fileSize! <= 5 * 1024 * 1024) {
              expect(info.strategy, equals(ParseStrategy.fullDownload),
                  reason: 'Small files should use fullDownload');
            } else if (info.fileSize! > 50 * 1024 * 1024 && info.supportsRange) {
              expect(info.strategy, equals(ParseStrategy.randomAccess),
                  reason: 'Large files with Range should use randomAccess');
            } else if (info.supportsRange) {
              expect(info.strategy, equals(ParseStrategy.headerOnly),
                  reason: 'Medium files with Range should use headerOnly');
            } else {
              expect(info.strategy, equals(ParseStrategy.fullDownload),
                  reason: 'Files without Range should use fullDownload');
            }
          }

          expect(info.supportsRange, isTrue,
              reason: 'Test URL should support Range requests');
        },
        skip: hasTestUrl ? false : 'No test URL configured',
        timeout: const Timeout(Duration(seconds: 15)),
      );
    });

    group('Smart parseUrl with auto-selection', () {
      test(
        'auto-selects best strategy and parses metadata',
        () async {
          ParseStrategy? selectedStrategy;
          String? reason;

          final metadata = await parseUrl(
            testUrl,
            timeout: const Duration(seconds: 60),
            onStrategySelected: (strategy, r) {
              selectedStrategy = strategy;
              reason = r;
            },
          );

          print('');
          print('=== Smart parseUrl ===');
          print('Selected strategy: \$selectedStrategy');
          print('Reason: \$reason');
          print('Format: \${metadata.format.container}');
          print('Codec: \${metadata.format.codec}');
          print('Duration: \${metadata.format.duration?.toStringAsFixed(2)}s');
          print('');

          expect(selectedStrategy, isNotNull);
          expect(metadata.format.container, isNotNull);
          expect(metadata.format.codec, isNotNull);
        },
        skip: hasTestUrl ? false : 'No test URL configured',
        timeout: const Timeout(Duration(seconds: 120)),
      );
    });

    group('Explicit strategies', () {
      test(
        'fullDownload strategy works',
        () async {
          final metadata = await parseUrl(
            testUrl,
            timeout: const Duration(seconds: 60),
            strategy: ParseStrategy.fullDownload,
          );

          print('');
          print('=== Full Download Strategy ===');
          print('Format: \${metadata.format.container}');
          print('Codec: \${metadata.format.codec}');
          print('');

          expect(metadata.format.container, isNotNull);
          expect(metadata.format.codec, isNotNull);
        },
        skip: hasTestUrl ? false : 'No test URL configured',
        timeout: const Timeout(Duration(seconds: 180)),
      );

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
          print('Format: \${metadata.format.container}');
          print('Codec: \${metadata.format.codec}');
          print('');

          expect(metadata.format.container, isNotNull);
        },
        skip: hasTestUrl ? false : 'No test URL configured',
        timeout: const Timeout(Duration(seconds: 60)),
      );

      test(
        'randomAccess strategy works',
        () async {
          final metadata = await parseUrl(
            testUrl,
            timeout: const Duration(seconds: 60),
            strategy: ParseStrategy.randomAccess,
          );

          print('');
          print('=== Random Access Strategy ===');
          print('Format: \${metadata.format.container}');
          print('Codec: \${metadata.format.codec}');
          print('');

          expect(metadata.format.container, isNotNull);
        },
        skip: hasTestUrl ? false : 'No test URL configured',
        timeout: const Timeout(Duration(seconds: 120)),
      );
    });

    group('Tokenizer classes', () {
      test(
        'HttpTokenizer downloads and parses',
        () async {
          final tokenizer = await HttpTokenizer.fromUrl(testUrl);
          
          print('');
          print('=== HttpTokenizer ===');
          print('File size: \${tokenizer.fileInfo?.size} bytes');
          print('Can seek: \${tokenizer.canSeek}');
          print('');

          expect(tokenizer.fileInfo?.size, greaterThan(0));
          expect(tokenizer.canSeek, isTrue);

          // Parse using the tokenizer
          final metadata = await parseFromTokenizer(tokenizer);
          expect(metadata.format.container, isNotNull);

          tokenizer.close();
        },
        skip: hasTestUrl ? false : 'No test URL configured',
        timeout: const Timeout(Duration(seconds: 180)),
      );

      test(
        'RangeTokenizer downloads header',
        () async {
          final tokenizer = await RangeTokenizer.fromUrl(testUrl);

          print('');
          print('=== RangeTokenizer ===');
          print('Header size: \${tokenizer.headerSize} bytes');
          print('Total size: \${tokenizer.totalSize} bytes');
          print('');

          expect(tokenizer.headerSize, greaterThan(0));
          if (tokenizer.totalSize != null) {
            expect(tokenizer.totalSize, greaterThan(minFileSize));
          }

          tokenizer.close();
        },
        skip: hasTestUrl ? false : 'No test URL configured',
        timeout: const Timeout(Duration(seconds: 60)),
      );

      test(
        'RandomAccessTokenizer provides random access',
        () async {
          final tokenizer = await RandomAccessTokenizer.fromUrl(testUrl);

          print('');
          print('=== RandomAccessTokenizer ===');
          print('Can seek: \${tokenizer.canSeek}');
          print('Total size: \${tokenizer.fileInfo?.size}');
          print('');

          expect(tokenizer.canSeek, isTrue);

          // Prefetch first chunk and verify
          await tokenizer.prefetchRange(0, 65535);
          expect(tokenizer.totalBytesFetched, greaterThan(0));

          tokenizer.close();
        },
        skip: hasTestUrl ? false : 'No test URL configured',
        timeout: const Timeout(Duration(seconds: 60)),
      );
    });
  });
}
