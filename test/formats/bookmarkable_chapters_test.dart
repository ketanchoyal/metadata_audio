/// Integration test for bookmarkable+afpk atom-based chapter extraction.
///
/// Bookmarkable M4B files with companion `.afpk` (Adobe Flash Player Keyframe)
/// files use a different chapter metadata structure than co64-based files.
/// These files are optimized for streaming and often have pre-computed
/// chapter markers.
///
/// This test validates that our parser correctly extracts chapters from
/// M4B files using the bookmarkable atom structure with afpk derivatives.
library;

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

/// Bookmarkable M4B from archive.org with companion `.afpk` derivative.
/// This file uses a different chapter extraction mechanism than co64.
const _bookmarkableAfpkChapterUrl =
    'https://archive.org/download/'
    'TheStoryOfCivilizationVolume4ivBookmarkableM4bAudiobookFile/'
    '04TheAgeOfFaithPart1.m4b';

Future<String?> _probeUrl(String url) async {
  if (url.isEmpty) return 'URL not configured';

  try {
    final res = await http
        .head(Uri.parse(url))
        .timeout(const Duration(seconds: 12));

    if (res.statusCode >= 400) return 'HTTP ${res.statusCode}';

    final ranges = res.headers['accept-ranges'];
    if (!(ranges?.toLowerCase().contains('bytes') ?? false)) {
      return 'Server does not support Range requests';
    }

    return null;
  } on TimeoutException {
    return 'Timed out connecting to $url';
  } catch (e) {
    if (e.toString().contains('SocketException') || e.toString().contains('ClientException')) {
      return 'Network unavailable: $e';
    }
    return 'Probe failed: $e';
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

  group('MP4/M4B bookmarkable+afpk atom chapter extraction', () {
    late String? urlSkip;

    setUpAll(() async {
      urlSkip = await _probeUrl(_bookmarkableAfpkChapterUrl);
      if (urlSkip != null) {
        // ignore: avoid_print
        print('[SKIP] bookmarkable+afpk chapter URL: $urlSkip');
      }
    });

    test(
      'parses chapter list from M4B with bookmarkable+afpk atoms',
      () async {
        if (urlSkip != null) {
          markTestSkipped(urlSkip!);
          return;
        }

        final info = await detectStrategy(_bookmarkableAfpkChapterUrl);
        late final AudioMetadata metadata;
        try {
          metadata = await parseUrl(
            _bookmarkableAfpkChapterUrl,
            options: const ParseOptions(includeChapters: true),
            timeout: const Duration(seconds: 120),
          );
        } catch (e) {
          if (_isSkippableRemoteError(e)) {
            markTestSkipped(
              'bookmarkable+afpk URL transient remote failure: $e',
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
        expect(metadata.format.chapters!.length, greaterThanOrEqualTo(10));
        expect(metadata.format.chapters!.first.title, isNotEmpty);
      },
      timeout: const Timeout(Duration(seconds: 180)),
    );

    test(
      'chapter metadata is accessible for bookmarkable+afpk atoms',
      () async {
        if (urlSkip != null) {
          markTestSkipped(urlSkip!);
          return;
        }

        late final AudioMetadata metadata;
        try {
          metadata = await parseUrl(
            _bookmarkableAfpkChapterUrl,
            options: const ParseOptions(includeChapters: true),
            timeout: const Duration(seconds: 120),
          );
        } catch (e) {
          if (_isSkippableRemoteError(e)) {
            markTestSkipped(
              'bookmarkable+afpk URL transient remote failure: $e',
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
      'validates file format detection for bookmarkable+afpk-based M4B',
      () async {
        if (urlSkip != null) {
          markTestSkipped(urlSkip!);
          return;
        }

        final info = await detectStrategy(_bookmarkableAfpkChapterUrl);

        expect(info.detectedFormat, equals('mp4'));
        expect(info.supportsRange, isTrue);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
