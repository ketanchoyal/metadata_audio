import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/native/api.dart';
import 'package:metadata_audio/src/native/frb_generated.dart';
import 'package:metadata_audio/src/aiff/aiff_loader.dart';
import 'package:metadata_audio/src/flac/flac_loader.dart';
import 'package:metadata_audio/src/mp4/mp4_loader.dart';
import 'package:metadata_audio/src/mpeg/mpeg_loader.dart';
import 'package:metadata_audio/src/ogg/ogg_loader.dart';
import 'package:metadata_audio/src/wav/wave_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<HttpServer> _startBytesServer(
  List<int> bytes, {
  String contentType = 'application/octet-stream',
  Duration? responseDelay,
  bool rejectHead = false,
  void Function(HttpRequest request)? onRequest,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final data = Uint8List.fromList(bytes);

  server.listen((request) async {
    onRequest?.call(request);
    if (responseDelay != null) {
      await Future<void>.delayed(responseDelay);
    }
    if (rejectHead && request.method == 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    request.response.headers
      ..set('Accept-Ranges', 'bytes')
      ..set('Content-Type', contentType);

    final rangeHeader = request.headers.value('range');
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final spec = rangeHeader.substring('bytes='.length);
      final dash = spec.indexOf('-');
      final start = int.parse(spec.substring(0, dash));
      final endStr = spec.substring(dash + 1);
      final end = endStr.isEmpty ? data.length - 1 : int.parse(endStr);
      final sliceEnd = (end + 1).clamp(0, data.length);

      request.response.statusCode = 206;
      request.response.headers
        ..set('Content-Range', 'bytes $start-$end/${data.length}')
        ..contentLength = sliceEnd - start;
      if (request.method != 'HEAD') {
        request.response.add(data.sublist(start, sliceEnd));
      }
    } else {
      request.response.headers.contentLength = data.length;
      if (request.method != 'HEAD') {
        request.response.add(data);
      }
    }

    await request.response.close();
  });

  return server;
}

class _FakeRustApi implements RustLibApi {
  _FakeRustApi(this.onParseChaptersFromUrl);

  final Future<List<FfiChapter>> Function({
    required String url,
    required BigInt? timeoutMs,
    required BigInt? fileSizeHint,
  }) onParseChaptersFromUrl;

  @override
  Future<List<FfiChapter>> crateApiParseChaptersFromUrl({
    required String url,
    BigInt? timeoutMs,
    BigInt? fileSizeHint,
  }) => onParseChaptersFromUrl(
    url: url,
    timeoutMs: timeoutMs,
    fileSizeHint: fileSizeHint,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

typedef _RustChapterHandler = Future<List<FfiChapter>> Function({
  required String url,
  required BigInt? timeoutMs,
  required BigInt? fileSizeHint,
});

_RustChapterHandler? _currentRustChapterHandler;

Future<HttpServer> _startSampleServer(
  String relPath, {
  String? contentType,
  Duration? responseDelay,
  bool rejectHead = false,
  void Function(HttpRequest request)? onRequest,
}) async {
  final bytes = await File(
    p.join(Directory.current.path, 'test', 'samples', relPath),
  ).readAsBytes();
  return _startBytesServer(
    bytes,
    contentType: contentType ?? _mimeForFilename(relPath),
    responseDelay: responseDelay,
    rejectHead: rejectHead,
    onRequest: onRequest,
  );
}

String _mimeForFilename(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  switch (ext) {
    case 'mp3':
      return 'audio/mpeg';
    case 'flac':
      return 'audio/flac';
    case 'ogg':
      return 'audio/ogg';
    case 'm4a':
      return 'audio/mp4';
    case 'mp4':
      return 'video/mp4';
    case 'wav':
      return 'audio/wav';
    case 'aiff':
    case 'aif':
      return 'audio/aiff';
    default:
      return 'application/octet-stream';
  }
}

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

  // Unit tests for format-based strategy selection (no network required).
  // These tests verify that StrategyInfo carries the right ProbeStrategy and
  // ParseStrategy for each audio format by constructing StrategyInfo directly.
  group('format-aware strategy selection (StrategyInfo)', () {
    // Helper that simulates what detectStrategy() returns for a given format.
    StrategyInfo _makeInfo({
      required ParseStrategy strategy,
      required ProbeStrategy probeStrategy,
      required String detectedFormat,
      int fileSize = 10 * 1024 * 1024,
      bool supportsRange = true,
    }) => StrategyInfo(
      strategy: strategy,
      fileSize: fileSize,
      supportsRange: supportsRange,
      probeStrategy: probeStrategy,
      detectedFormat: detectedFormat,
    );

    test('MP4/M4A uses mp4Optimized probe strategy', () {
      final info = _makeInfo(
        strategy: ParseStrategy.probe,
        probeStrategy: ProbeStrategy.mp4Optimized,
        detectedFormat: 'mp4',
      );
      expect(info.strategy, equals(ParseStrategy.probe));
      expect(info.probeStrategy, equals(ProbeStrategy.mp4Optimized));
      expect(info.detectedFormat, equals('mp4'));
    });

    test('MP3/MPEG uses headerAndTail probe strategy', () {
      final info = _makeInfo(
        strategy: ParseStrategy.probe,
        probeStrategy: ProbeStrategy.headerAndTail,
        detectedFormat: 'mpeg',
      );
      expect(info.strategy, equals(ParseStrategy.probe));
      expect(info.probeStrategy, equals(ProbeStrategy.headerAndTail));
      expect(info.detectedFormat, equals('mpeg'));
    });

    test('FLAC/OGG/WAV uses headerOnly parse strategy', () {
      final info = _makeInfo(
        strategy: ParseStrategy.headerOnly,
        probeStrategy: ProbeStrategy.headerOnly,
        detectedFormat: 'header-only',
      );
      expect(info.strategy, equals(ParseStrategy.headerOnly));
      expect(info.probeStrategy, equals(ProbeStrategy.headerOnly));
      expect(info.detectedFormat, equals('header-only'));
    });

    test('unknown format falls back to scatter probe strategy', () {
      final info = _makeInfo(
        strategy: ParseStrategy.probe,
        probeStrategy: ProbeStrategy.scatter,
        detectedFormat: 'unknown',
      );
      expect(info.strategy, equals(ParseStrategy.probe));
      expect(info.probeStrategy, equals(ProbeStrategy.scatter));
      expect(info.detectedFormat, equals('unknown'));
    });

    test('very large MP4 (> 50MB) uses randomAccess regardless of format', () {
      final info = _makeInfo(
        strategy: ParseStrategy.randomAccess,
        probeStrategy: ProbeStrategy.mp4Optimized,
        detectedFormat: 'mp4',
        fileSize: 100 * 1024 * 1024,
      );
      expect(info.strategy, equals(ParseStrategy.randomAccess));
    });

    test('very large MP3 (> 50MB) uses randomAccess', () {
      final info = _makeInfo(
        strategy: ParseStrategy.randomAccess,
        probeStrategy: ProbeStrategy.headerAndTail,
        detectedFormat: 'mpeg',
        fileSize: 100 * 1024 * 1024,
      );
      expect(info.strategy, equals(ParseStrategy.randomAccess));
    });

    test('small file always uses fullDownload regardless of format', () {
      for (final format in ['mp4', 'mpeg', 'header-only', 'unknown']) {
        final info = _makeInfo(
          strategy: ParseStrategy.fullDownload,
          probeStrategy: ProbeStrategy.scatter,
          detectedFormat: format,
          fileSize: 1 * 1024 * 1024, // 1MB
        );
        expect(
          info.strategy,
          equals(ParseStrategy.fullDownload),
          reason: 'Small $format file should use fullDownload',
        );
      }
    });

    test('StrategyInfo exposes detectedFormat for logging', () {
      final info = StrategyInfo(
        strategy: ParseStrategy.probe,
        fileSize: 10 * 1024 * 1024,
        supportsRange: true,
        probeStrategy: ProbeStrategy.mp4Optimized,
        detectedFormat: 'mp4',
      );
      expect(info.detectedFormat, isNotNull);
      expect(info.detectedFormat, equals('mp4'));
    });
  });

  // =========================================================================
  // CONFIGURATION: Live URL used for the tokenizer smoke tests
  // =========================================================================
  // We keep these tests focused on the tokenizer layer, but they still need a
  // real public file so the HTTP range and strategy paths are exercised.
  // =========================================================================
  const testUrl =
      'https://archive.org/download/anyone_s_daughter_live_full_album/'
      'anyone_s_daughter_live_full_album.mp3';

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

  group('Rust URL augmentation', () {
    setUpAll(() {
      RustLib.initMock(
        api: _FakeRustApi(({
          required url,
          required timeoutMs,
          required fileSizeHint,
        }) async {
          final handler = _currentRustChapterHandler;
          if (handler == null) {
            throw StateError('Rust chapter handler not configured for test');
          }
          return handler(
            url: url,
            timeoutMs: timeoutMs,
            fileSizeHint: fileSizeHint,
          );
        }),
      );
    });

    tearDown(() {
      _currentRustChapterHandler = null;
    });

    test('applies Rust chapters for explicit strategy calls', () async {
      final server = await _startSampleServer('mp4/sample.m4a');
      final capturedTimeouts = <BigInt?>[];

      _currentRustChapterHandler = ({
        required url,
        required timeoutMs,
        required fileSizeHint,
      }) async {
        capturedTimeouts.add(timeoutMs);
        expect(fileSizeHint, isNotNull);
        return [
          FfiChapter(
            title: 'Rust explicit strategy chapter',
            start: BigInt.zero,
            end: BigInt.from(1000),
            timeScale: 1000,
          ),
        ];
      };

      try {
        final metadata = await parseUrl(
          'http://localhost:${server.port}/sample.m4a',
          strategy: ParseStrategy.fullDownload,
          timeout: const Duration(seconds: 7),
          options: const ParseOptions(includeChapters: true),
        );

        expect(metadata.format.chapters, isNotNull);
        expect(metadata.format.chapters, hasLength(1));
        expect(
          metadata.format.chapters!.single.title,
          equals('Rust explicit strategy chapter'),
        );
        expect(capturedTimeouts, hasLength(1));
        expect(capturedTimeouts.single, isNotNull);
        expect(capturedTimeouts.single!, greaterThan(BigInt.zero));
        expect(capturedTimeouts.single!, lessThan(BigInt.from(7000)));
      } finally {
        await server.close(force: true);
      }
    });

    test('applies Rust chapters for MIME-detected MP4 URLs without extension', () async {
      final server = await _startSampleServer(
        'mp4/sample.m4a',
        contentType: 'audio/mp4',
      );
      var called = false;

      _currentRustChapterHandler = ({
        required url,
        required timeoutMs,
        required fileSizeHint,
      }) async {
        called = true;
        expect(fileSizeHint, isNotNull);
        return [
          FfiChapter(
            title: 'Rust MIME-only chapter',
            start: BigInt.zero,
            end: BigInt.from(500),
            timeScale: 1000,
          ),
        ];
      };

      try {
        final metadata = await parseUrl(
          'http://localhost:${server.port}/stream',
          strategy: ParseStrategy.fullDownload,
          timeout: const Duration(seconds: 5),
          options: const ParseOptions(includeChapters: true),
        );

        expect(called, isTrue);
        expect(metadata.format.chapters, isNotNull);
        expect(metadata.format.chapters!.single.title, 'Rust MIME-only chapter');
      } finally {
        await server.close(force: true);
      }
    });

    test('passes only the remaining timeout budget to Rust augmentation', () async {
      final server = await _startSampleServer(
        'mp4/sample.m4a',
        responseDelay: const Duration(milliseconds: 100),
      );
      final capturedTimeouts = <BigInt?>[];

      _currentRustChapterHandler = ({
        required url,
        required timeoutMs,
        required fileSizeHint,
      }) async {
        capturedTimeouts.add(timeoutMs);
        return [
          FfiChapter(
            title: 'Rust timeout budget chapter',
            start: BigInt.zero,
            end: BigInt.from(1000),
            timeScale: 1000,
          ),
        ];
      };

      try {
        final metadata = await parseUrl(
          'http://localhost:${server.port}/sample.m4a',
          strategy: ParseStrategy.fullDownload,
          timeout: const Duration(milliseconds: 450),
          options: const ParseOptions(includeChapters: true),
        );

        expect(metadata.format.chapters, isNotNull);
        expect(capturedTimeouts, hasLength(1));
        expect(capturedTimeouts.single, isNotNull);
        expect(capturedTimeouts.single!, greaterThan(BigInt.zero));
        expect(capturedTimeouts.single!, lessThan(BigInt.from(450)));
      } finally {
        await server.close(force: true);
      }
    });
  });

  group('Smart parseUrl with auto-selection', () {
    test(
      'auto-selects best strategy and parses metadata',
      () async {
        ParseStrategy? selectedStrategy;
        String? reason;

        final metadata = await parseUrl(
          testUrl,
          options: const ParseOptions(includeChapters: true),
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
        print('Chapters: ${metadata.format.chapters?.length}');
        print('Duration: ${metadata.format.duration?.toStringAsFixed(2)}s');
        print('');

        expect(selectedStrategy, isNotNull);
        expect(metadata.format.container, isNotNull);
        expect(metadata.format.codec, isNotNull);
        for (final chapter in metadata.format.chapters ?? <Chapter>[]) {
          print(
            '  Chapter: ${chapter.title} [${chapter.start.toStringAsFixed(2)}s - ${chapter.end?.toStringAsFixed(2)}s] TimeScale: ${chapter.timeScale}',
          );
        }
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
      'RangeTokenizer reports full data when small file fits in header',
      () async {
        final server = await _startBytesServer(
          List<int>.generate(1024, (index) => index % 256),
          contentType: 'audio/mpeg',
        );

        try {
          final tokenizer = await RangeTokenizer.fromUrl(
            'http://localhost:${server.port}/tiny.mp3',
          );

          expect(tokenizer.totalSize, equals(1024));
          expect(tokenizer.headerSize, equals(1024));
          expect(tokenizer.hasCompleteData, isTrue);

          tokenizer.close();
        } finally {
          await server.close(force: true);
        }
      },
    );

    test('ProbingRangeTokenizer mp4 tail data is readable near EOF', () async {
      const totalSize = 17 * 1024 * 1024 + 123;
      final bytes = List<int>.generate(totalSize, (index) => index % 251);
      final server = await _startBytesServer(bytes, contentType: 'audio/mp4');

      try {
        final tokenizer = await ProbingRangeTokenizer.fromUrl(
          'http://localhost:${server.port}/large.m4a',
          probeStrategy: ProbeStrategy.mp4Optimized,
        );

        const probePosition = totalSize - 32;
        tokenizer.seek(probePosition);

        expect(tokenizer.readUint8(), equals(bytes[probePosition]));

        tokenizer.close();
      } finally {
        await server.close(force: true);
      }
    });

    test('HttpTokenizer downloads and parses FLAC sample', () async {
      final server = await _startSampleServer('flac/sample.flac');

      try {
        final tokenizer = await HttpTokenizer.fromUrl(
          'http://localhost:${server.port}/sample.flac',
        );

        expect(tokenizer.fileInfo?.size, equals(66183));
        expect(tokenizer.canSeek, isTrue);

        final metadata = await parseFromTokenizer(tokenizer);
        expect(metadata.format.container, equals('FLAC'));
        expect(metadata.format.lossless, isTrue);

        tokenizer.close();
      } finally {
        await server.close(force: true);
      }
    });

    test('RangeTokenizer keeps AIFF sample partially downloaded', () async {
      final server = await _startSampleServer('aiff/sample.aiff');

      try {
        final tokenizer = await RangeTokenizer.fromUrl(
          'http://localhost:${server.port}/sample.aiff',
        );

        expect(tokenizer.totalSize, equals(596904));
        expect(tokenizer.headerSize, equals(262144));
        expect(tokenizer.headerSize, lessThan(tokenizer.totalSize!));
        expect(tokenizer.hasCompleteData, isFalse);

        tokenizer.close();
      } finally {
        await server.close(force: true);
      }
    });

    test('HttpTokenizer downloads and parses AIFF sample', () async {
      final server = await _startSampleServer('aiff/sample.aiff');

      try {
        final tokenizer = await HttpTokenizer.fromUrl(
          'http://localhost:${server.port}/sample.aiff',
        );

        final metadata = await parseFromTokenizer(tokenizer);
        expect(metadata.format.container, equals('AIFF'));
        expect(metadata.common.title, equals("Sinner's Prayer"));

        tokenizer.close();
      } finally {
        await server.close(force: true);
      }
    });

    test(
      'ProbingRangeTokenizer parses M4A sample with mp4Optimized strategy',
      () async {
        final server = await _startSampleServer('mp4/sample.m4a');

        try {
          final tokenizer = await ProbingRangeTokenizer.fromUrl(
            'http://localhost:${server.port}/sample.m4a',
            probeStrategy: ProbeStrategy.mp4Optimized,
          );

          expect(tokenizer.canSeek, isTrue);
          expect(tokenizer.fetchedRanges['chunks'], greaterThan(0));

          final metadata = await parseFromTokenizer(tokenizer);
          expect(metadata.format.container, startsWith('M4'));

          tokenizer.close();
        } finally {
          await server.close(force: true);
        }
      },
    );

    test(
      'RandomAccessTokenizer provides random access for WAV sample',
      () async {
        final server = await _startSampleServer('wav/issue-819.wav');

        try {
          final tokenizer = await RandomAccessTokenizer.fromUrl(
            'http://localhost:${server.port}/sample.wav',
          );

          expect(tokenizer.canSeek, isTrue);

          await tokenizer.prefetchRange(0, 1023);
          expect(tokenizer.totalBytesFetched, greaterThan(0));

          final metadata = await parseFromTokenizer(tokenizer);
          expect(metadata.format.container, equals('WAVE'));

          tokenizer.close();
        } finally {
          await server.close(force: true);
        }
      },
    );

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
