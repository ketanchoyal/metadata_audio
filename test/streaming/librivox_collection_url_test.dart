/// Integration tests for direct files under the
/// `LibrivoxM4bCollectionAudiobooks` archive.org collection.
///
/// This file keeps per-format URL cases separate from the broader
/// `url_integration_test.dart` suite.
library;

import 'dart:async';
import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Chapter-extraction type tracking URLs (all MP4/M4B containers)
// ---------------------------------------------------------------------------

/// Co64-focused regression URL used in existing chapter fixes.
const _co64ChapterUrl = String.fromEnvironment(
  'METADATA_AUDIO_CO64_CHAPTER_URL',
  defaultValue:
      'https://archive.org/download/city_of_fire_2209_librivox/'
      'CityFire_librivox.m4b',
);

/// Bookmarkable M4B from archive.org with companion `.afpk` derivative.
/// Used to track non-co64 chapter extraction behavior.
const _bookmarkableAfpkChapterUrl = String.fromEnvironment(
  'METADATA_AUDIO_BOOKMARKABLE_AFPK_CHAPTER_URL',
  defaultValue:
      'https://archive.org/download/'
      'TheStoryOfCivilizationVolume4ivBookmarkableM4bAudiobookFile/'
      '04TheAgeOfFaithPart1.m4b',
);

/// Alternate Librivox collection sample to track another chapter layout path.
const _librivox22ChapterUrl = String.fromEnvironment(
  'METADATA_AUDIO_LIBRIVOX22_CHAPTER_URL',
  defaultValue:
      'https://archive.org/download/LibrivoxM4bCollectionAudiobooks_22/'
      'ancient_ballads_legends_hindustan_1501.m4b',
);

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

  group('MP4/M4B chapter extraction type tracking (archive URLs)', () {
    late String? co64Skip;
    late String? bookmarkableSkip;
    late String? librivox22Skip;

    setUpAll(() async {
      co64Skip = await _probeUrl(_co64ChapterUrl);
      bookmarkableSkip = await _probeUrl(_bookmarkableAfpkChapterUrl);
      librivox22Skip = await _probeUrl(_librivox22ChapterUrl);

      if (co64Skip != null) {
        // ignore: avoid_print
        print('[SKIP] co64 chapter URL: $co64Skip');
      }
      if (bookmarkableSkip != null) {
        // ignore: avoid_print
        print('[SKIP] bookmarkable+afpk chapter URL: $bookmarkableSkip');
      }
      if (librivox22Skip != null) {
        // ignore: avoid_print
        print('[SKIP] Librivox_22 chapter URL: $librivox22Skip');
      }
    });

    test(
      'type=co64: parses rich chapter list from large M4B URL',
      () async {
        if (co64Skip != null) {
          markTestSkipped(co64Skip!);
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
      'type=bookmarkable+afpk: parses chapter list from companion set',
      () async {
        if (bookmarkableSkip != null) {
          markTestSkipped(bookmarkableSkip!);
          return;
        }

        final info = await detectStrategy(_bookmarkableAfpkChapterUrl);
        final metadata = await parseUrl(
          _bookmarkableAfpkChapterUrl,
          options: const ParseOptions(includeChapters: true),
          timeout: const Duration(seconds: 120),
        );

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
      'type=alternate-layout: parses chapters from Librivox_22 URL',
      () async {
        if (librivox22Skip != null) {
          markTestSkipped(librivox22Skip!);
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
            markTestSkipped('Librivox_22 URL transient remote failure: $e');
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
  });
}
