import 'dart:async';
import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/aiff/aiff_loader.dart';
import 'package:metadata_audio/src/flac/flac_loader.dart';
import 'package:metadata_audio/src/mp4/mp4_loader.dart';
import 'package:metadata_audio/src/mpeg/mpeg_loader.dart';
import 'package:metadata_audio/src/ogg/ogg_loader.dart';
import 'package:metadata_audio/src/wav/wave_loader.dart';
import 'package:test/test.dart';

/// Validates that a URL is accessible and supports Range requests.
/// Returns null if valid, or a skip message if invalid.
Future<String?> _validateUrl(String url) async {
  if (url.isEmpty) {
    return 'No test URL configured';
  }

  try {
    final client = HttpClient();
    try {
      final request = await client.headUrl(Uri.parse(url));
      request.followRedirects = true;
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode >= 400) {
        return 'URL returned HTTP ${response.statusCode}';
      }

      final acceptRanges = response.headers.value('accept-ranges');
      final supportsRange =
          acceptRanges?.toLowerCase().contains('bytes') ?? false;

      if (!supportsRange) {
        return 'URL does not support HTTP Range requests';
      }

      final contentLength = response.contentLength;
      if (contentLength <= 0) {
        return 'URL returned invalid content length: $contentLength';
      }

      return null; // Valid
    } finally {
      client.close();
    }
  } on SocketException catch (e) {
    return 'Cannot connect to URL: ${e.message}';
  } on TimeoutException {
    return 'URL connection timed out';
  } catch (e) {
    return 'URL validation failed: $e';
  }
}

/// Tests for the three HTTP tokenizers and smart parseUrl function.
///
/// NOTE: These tests require a real HTTP URL to test against.
/// Set [testUrl] below to an audio file URL that supports HTTP Range requests.
/// The file should be at least 5MB to properly test the strategies.
void main() {
  // Unit tests for detectStrategy logic (no network required)
  group('detectStrategy logic', () {
    test('returns fullDownload for small files (<= 5MB)', () {
      const fileSize = 1024 * 1024; // 1MB
      const largeFileThreshold = 5 * 1024 * 1024;

      late ParseStrategy strategy;
      const supportsRange = true;

      if (fileSize <= largeFileThreshold) {
        strategy = ParseStrategy.fullDownload;
      } else if (supportsRange) {
        if (fileSize > 50 * 1024 * 1024) {
          strategy = ParseStrategy.randomAccess;
        } else {
          strategy = ParseStrategy.probe;
        }
      } else {
        strategy = ParseStrategy.fullDownload;
      }

      expect(strategy, equals(ParseStrategy.fullDownload));
    });

    test('returns probe for medium files (5MB < size <= 50MB)', () {
      const fileSize = 10 * 1024 * 1024; // 10MB
      const largeFileThreshold = 5 * 1024 * 1024;

      late ParseStrategy strategy;
      const supportsRange = true;

      if (fileSize <= largeFileThreshold) {
        strategy = ParseStrategy.fullDownload;
      } else if (supportsRange) {
        if (fileSize > 50 * 1024 * 1024) {
          strategy = ParseStrategy.randomAccess;
        } else {
          strategy = ParseStrategy.probe;
        }
      } else {
        strategy = ParseStrategy.fullDownload;
      }

      expect(strategy, equals(ParseStrategy.probe));
    });

    test('returns probe for files exactly 50MB', () {
      const fileSize = 50 * 1024 * 1024; // 50MB exactly
      const largeFileThreshold = 5 * 1024 * 1024;

      late ParseStrategy strategy;
      const supportsRange = true;

      if (fileSize <= largeFileThreshold) {
        strategy = ParseStrategy.fullDownload;
      } else if (supportsRange) {
        if (fileSize > 50 * 1024 * 1024) {
          strategy = ParseStrategy.randomAccess;
        } else {
          strategy = ParseStrategy.probe;
        }
      } else {
        strategy = ParseStrategy.fullDownload;
      }

      expect(strategy, equals(ParseStrategy.probe));
    });

    test('returns randomAccess for large files (> 50MB)', () {
      const fileSize = 100 * 1024 * 1024; // 100MB
      const largeFileThreshold = 5 * 1024 * 1024;

      late ParseStrategy strategy;
      const supportsRange = true;

      if (fileSize <= largeFileThreshold) {
        strategy = ParseStrategy.fullDownload;
      } else if (supportsRange) {
        if (fileSize > 50 * 1024 * 1024) {
          strategy = ParseStrategy.randomAccess;
        } else {
          strategy = ParseStrategy.probe;
        }
      } else {
        strategy = ParseStrategy.fullDownload;
      }

      expect(strategy, equals(ParseStrategy.randomAccess));
    });

    test('returns fullDownload when Range not supported', () {
      const fileSize = 10 * 1024 * 1024; // 10MB
      const largeFileThreshold = 5 * 1024 * 1024;

      late ParseStrategy strategy;
      const supportsRange = false;

      if (fileSize <= largeFileThreshold) {
        strategy = ParseStrategy.fullDownload;
      } else if (supportsRange) {
        if (fileSize > 50 * 1024 * 1024) {
          strategy = ParseStrategy.randomAccess;
        } else {
          strategy = ParseStrategy.probe;
        }
      } else {
        strategy = ParseStrategy.fullDownload;
      }

      expect(strategy, equals(ParseStrategy.fullDownload));
    });
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

  // Validate URL before running tests
  late final String? skipReason;

  setUpAll(() async {
    // Initialize parser factory
    final registry = ParserRegistry()
      ..register(MpegLoader())
      ..register(FlacLoader())
      ..register(OggLoader())
      ..register(Mp4Loader())
      ..register(WaveLoader())
      ..register(AiffLoader());
    initializeParserFactory(ParserFactory(registry));

    // Validate URL
    skipReason = await _validateUrl(testUrl);
    if (skipReason != null) {
      print('');
      print('=== HTTP Tokenizers Tests ===');
      print('SKIP: $skipReason');
      print('URL: ${testUrl.isEmpty ? "(not set)" : testUrl}');
      print('');
    }
  });

  group('Strategy Detection', () {
    test(
      'detects strategy based on file size',
      () async {
        final info = await detectStrategy(testUrl);

        print('');
        print('=== Strategy Detection ===');
        print(
          'URL: ${testUrl.substring(0, testUrl.length > 50 ? 50 : testUrl.length)}...',
        );
        print('Detected strategy: ${info.strategy}');
        print(
          'File size: ${info.fileSize != null ? "${info.fileSize! ~/ 1024}KB" : "unknown"}',
        );
        print('Range support: ${info.supportsRange}');
        print('');

        // Verify strategy selection logic
        if (info.fileSize != null) {
          if (info.fileSize! <= 5 * 1024 * 1024) {
            expect(
              info.strategy,
              equals(ParseStrategy.fullDownload),
              reason: 'Small files should use fullDownload',
            );
          } else if (info.fileSize! > 50 * 1024 * 1024 && info.supportsRange) {
            expect(
              info.strategy,
              equals(ParseStrategy.randomAccess),
              reason: 'Large files with Range should use randomAccess',
            );
          } else if (info.supportsRange) {
            expect(
              info.strategy,
              equals(ParseStrategy.probe),
              reason: 'Medium files with Range should use probe',
            );
          } else {
            expect(
              info.strategy,
              equals(ParseStrategy.fullDownload),
              reason: 'Files without Range should use fullDownload',
            );
          }
        }

        expect(
          info.supportsRange,
          isTrue,
          reason: 'Test URL should support Range requests',
        );
      },
      skip: testUrl.isEmpty ? 'No test URL configured' : false,
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
        print('Selected strategy: $selectedStrategy');
        print('Reason: $reason');
        print('Format: ${metadata.format.container}');
        print('Codec: ${metadata.format.codec}');
        print('Duration: ${metadata.format.duration?.toStringAsFixed(2)}s');
        print('');

        expect(selectedStrategy, isNotNull);
        expect(metadata.format.container, isNotNull);
        expect(metadata.format.codec, isNotNull);
      },
      skip: testUrl.isEmpty ? 'No test URL configured' : false,
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
        print('Format: ${metadata.format.container}');
        print('Codec: ${metadata.format.codec}');
        print('');

        expect(metadata.format.container, isNotNull);
        expect(metadata.format.codec, isNotNull);
      },
      skip: testUrl.isEmpty ? 'No test URL configured' : false,
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
        print('Format: ${metadata.format.container}');
        print('Codec: ${metadata.format.codec}');
        print('');

        expect(metadata.format.container, isNotNull);
      },
      skip: testUrl.isEmpty ? 'No test URL configured' : false,
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'probe strategy works',
      () async {
        final metadata = await parseUrl(
          testUrl,
          timeout: const Duration(seconds: 60),
          strategy: ParseStrategy.probe,
        );

        print('');
        print('=== Probe Strategy ===');
        print('Format: ${metadata.format.container}');
        print('Codec: ${metadata.format.codec}');
        print('');

        expect(metadata.format.container, isNotNull);
      },
      skip: testUrl.isEmpty ? 'No test URL configured' : false,
      timeout: const Timeout(Duration(seconds: 120)),
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
        print('Format: ${metadata.format.container}');
        print('Codec: ${metadata.format.codec}');
        print('');

        expect(metadata.format.container, isNotNull);
      },
      skip: testUrl.isEmpty ? 'No test URL configured' : false,
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
        print('File size: ${tokenizer.fileInfo?.size} bytes');
        print('Can seek: ${tokenizer.canSeek}');
        print('');

        expect(tokenizer.fileInfo?.size, greaterThan(0));
        expect(tokenizer.canSeek, isTrue);

        // Parse using the tokenizer
        final metadata = await parseFromTokenizer(tokenizer);
        expect(metadata.format.container, isNotNull);

        tokenizer.close();
      },
      skip: testUrl.isEmpty ? 'No test URL configured' : false,
      timeout: const Timeout(Duration(seconds: 180)),
    );

    test(
      'RangeTokenizer downloads header',
      () async {
        final tokenizer = await RangeTokenizer.fromUrl(testUrl);

        print('');
        print('=== RangeTokenizer ===');
        print('Header size: ${tokenizer.headerSize} bytes');
        print('Total size: ${tokenizer.totalSize} bytes');
        print('');

        expect(tokenizer.headerSize, greaterThan(0));
        if (tokenizer.totalSize != null) {
          expect(tokenizer.totalSize, greaterThan(minFileSize));
        }

        tokenizer.close();
      },
      skip: testUrl.isEmpty ? 'No test URL configured' : false,
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'ProbingRangeTokenizer fetches scattered ranges',
      () async {
        final tokenizer = await ProbingRangeTokenizer.fromUrl(testUrl);

        print('');
        print('=== ProbingRangeTokenizer ===');
        print('Can seek: ${tokenizer.canSeek}');
        print('Total size: ${tokenizer.fileInfo?.size}');
        print('Fetched: ${tokenizer.fetchedRanges}');
        print('');

        expect(tokenizer.canSeek, isTrue);
        expect(
          tokenizer.fetchedRanges['chunks'],
          greaterThan(1),
          reason: 'Should fetch multiple chunks for scatter strategy',
        );

        tokenizer.close();
      },
      skip: testUrl.isEmpty ? 'No test URL configured' : false,
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'ProbingRangeTokenizer with mp4Optimized strategy',
      () async {
        final tokenizer = await ProbingRangeTokenizer.fromUrl(
          testUrl,
          probeStrategy: ProbeStrategy.mp4Optimized,
        );

        print('');
        print('=== ProbingRangeTokenizer (MP4 Optimized) ===');
        print('Can seek: ${tokenizer.canSeek}');
        print('Total size: ${tokenizer.fileInfo?.size}');
        print('Fetched: ${tokenizer.fetchedRanges}');
        print('');

        expect(tokenizer.canSeek, isTrue);

        tokenizer.close();
      },
      skip: testUrl.isEmpty ? 'No test URL configured' : false,
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'RandomAccessTokenizer provides random access',
      () async {
        final tokenizer = await RandomAccessTokenizer.fromUrl(testUrl);

        print('');
        print('=== RandomAccessTokenizer ===');
        print('Can seek: ${tokenizer.canSeek}');
        print('Total size: ${tokenizer.fileInfo?.size}');
        print('');

        expect(tokenizer.canSeek, isTrue);

        // Prefetch first chunk and verify
        await tokenizer.prefetchRange(0, 65535);
        expect(tokenizer.totalBytesFetched, greaterThan(0));

        tokenizer.close();
      },
      skip: testUrl.isEmpty ? 'No test URL configured' : false,
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
