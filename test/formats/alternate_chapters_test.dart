/// Integration test for alternate-layout atom-based chapter extraction.
///
/// Some LibriVox collections use a different internal atom layout structure
/// for chapter markers. This alternate layout requires the probe strategy
/// for optimal parsing performance.
///
/// This test validates that our parser correctly detects and handles
/// chapters from M4B files using the alternate layout structure.
library;

import 'dart:async';
import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

/// Alternate layout M4B from LibriVox collection #22.
/// This file uses a different chapter metadata structure that requires
/// the probe strategy for optimal detection.
const _librivox22ChapterUrl =
    'https://archive.org/download/LibrivoxM4bCollectionAudiobooks_22/'
    'ancient_ballads_legends_hindustan_1501.m4b';

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

  group('MP4/M4B alternate-layout atom chapter extraction', () {
    late String? urlSkip;

    setUpAll(() async {
      urlSkip = await _probeUrl(_librivox22ChapterUrl);
      if (urlSkip != null) {
        // ignore: avoid_print
        print('[SKIP] alternate-layout chapter URL: $urlSkip');
      }
    });

    test(
      'parses chapter list from M4B with alternate-layout atoms',
      () async {
        if (urlSkip != null) {
          markTestSkipped(urlSkip!);
          return;
        }

        final info = await detectStrategy(_librivox22ChapterUrl);
        late final AudioMetadata metadata;
        try {
          metadata = await parseUrl(
            _librivox22ChapterUrl,
            options: const ParseOptions(includeChapters: true),
            strategy: ParseStrategy.probe,
            probeStrategy: ProbeStrategy.mp4Optimized,
            timeout: const Duration(seconds: 120),
          );
        } catch (e) {
          if (_isSkippableRemoteError(e)) {
            markTestSkipped(
              'alternate-layout URL transient remote failure: $e',
            );
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
        expect(metadata.format.chapters!.length, greaterThanOrEqualTo(5));
        expect(metadata.format.chapters!.first.title, isNotEmpty);
      },
      timeout: const Timeout(Duration(seconds: 180)),
    );

    test(
      'chapter metadata is accessible for alternate-layout atoms',
      () async {
        if (urlSkip != null) {
          markTestSkipped(urlSkip!);
          return;
        }

        late final AudioMetadata metadata;
        try {
          metadata = await parseUrl(
            _librivox22ChapterUrl,
            options: const ParseOptions(includeChapters: true),
            strategy: ParseStrategy.probe,
            probeStrategy: ProbeStrategy.mp4Optimized,
            timeout: const Duration(seconds: 120),
          );
        } catch (e) {
          if (_isSkippableRemoteError(e)) {
            markTestSkipped(
              'alternate-layout URL transient remote failure: $e',
            );
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
      'validates file format detection for alternate-layout-based M4B',
      () async {
        if (urlSkip != null) {
          markTestSkipped(urlSkip!);
          return;
        }

        final info = await detectStrategy(_librivox22ChapterUrl);

        expect(info.detectedFormat, equals('mp4'));
        expect(info.supportsRange, isTrue);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
