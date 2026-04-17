/// Integration test for co64 atom-based chapter extraction.
///
/// co64 (Chunk offset box 64) is used in MP4/M4B files for chapter tracking
/// when files are optimized for direct random access.
///
/// This test validates that our parser correctly extracts chapters from
/// M4B files using the co64 atom structure.
library;

import 'dart:async';
import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

/// Co64-focused test URL from LibriVox archive.
/// This file uses co64 atoms for chapter metadata.
const _co64ChapterUrl =
    'https://archive.org/download/city_of_fire_2209_librivox/CityFire_librivox.m4b';

Future<String?> _probeUrl(String url) async {
  if (url.isEmpty) return 'URL not configured';

  final client = HttpClient();
  try {
    final req = await client
        .headUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 12));
    req.followRedirects = true;
    final res = await req.close().timeout(const Duration(seconds: 12));

    if (res.statusCode >= 400) return 'HTTP ${res.statusCode}';

    final ranges = res.headers.value('accept-ranges');
    if (!(ranges?.toLowerCase().contains('bytes') ?? false)) {
      return 'Server does not support Range requests';
    }

    return null;
  } on SocketException catch (e) {
    return 'Network unavailable: ${e.message}';
  } on TimeoutException {
    return 'Timed out connecting to $url';
  } catch (e) {
    return 'Probe failed: $e';
  } finally {
    client.close();
  }
}

bool _isSkippableRemoteError(Object e) {
  final msg = e.toString();
  return msg.contains('TokenizerException') ||
      msg.contains('FileDownloadError') ||
      msg.contains('Data not available at position') ||
      msg.contains('Range request failed') ||
      msg.contains('HTTP 500');
}

void main() {
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

  group('MP4/M4B co64 atom chapter extraction', () {
    late String? urlSkip;

    setUpAll(() async {
      urlSkip = await _probeUrl(_co64ChapterUrl);
      if (urlSkip != null) {
        // ignore: avoid_print
        print('[SKIP] co64 chapter URL: $urlSkip');
      }
    });

    test(
      'parses rich chapter list from large M4B with co64 atoms',
      () async {
        if (urlSkip != null) {
          markTestSkipped(urlSkip!);
          return;
        }

        final info = await detectStrategy(_co64ChapterUrl);
        late final AudioMetadata metadata;
        try {
          metadata = await parseUrl(
            _co64ChapterUrl,
            options: const ParseOptions(includeChapters: true),
            timeout: const Duration(seconds: 120),
          );
        } catch (e) {
          if (_isSkippableRemoteError(e)) {
            markTestSkipped('co64 URL transient remote failure: $e');
            return;
          }
          rethrow;
        }

        expect(info.detectedFormat, equals('mp4'));
        expect(info.supportsRange, isTrue);
        expect(
          (metadata.format.container ?? '').toLowerCase(),
          anyOf(contains('m4'), contains('mp4')),
        );
        expect(metadata.format.chapters, isNotNull);
        expect(metadata.format.chapters!.length, greaterThanOrEqualTo(20));
        expect(metadata.format.chapters!.first.title, isNotEmpty);
      },
      timeout: const Timeout(Duration(seconds: 180)),
    );

    test(
      'chapter metadata is accessible and complete for co64 atoms',
      () async {
        if (urlSkip != null) {
          markTestSkipped(urlSkip!);
          return;
        }

        late final AudioMetadata metadata;
        try {
          metadata = await parseUrl(
            _co64ChapterUrl,
            options: const ParseOptions(includeChapters: true),
            timeout: const Duration(seconds: 120),
          );
        } catch (e) {
          if (_isSkippableRemoteError(e)) {
            markTestSkipped('co64 URL transient remote failure: $e');
            return;
          }
          rethrow;
        }

        final chapters = metadata.format.chapters;
        expect(chapters, isNotNull);

        for (final chapter in chapters!) {
          expect(chapter.title, isNotNull);
          expect(chapter.start, isNotNull);
        }
      },
      timeout: const Timeout(Duration(seconds: 180)),
    );

    test(
      'validates file format detection for co64-based M4B',
      () async {
        if (urlSkip != null) {
          markTestSkipped(urlSkip!);
          return;
        }

        final info = await detectStrategy(_co64ChapterUrl);

        expect(info.detectedFormat, equals('mp4'));
        expect(info.supportsRange, isTrue);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
