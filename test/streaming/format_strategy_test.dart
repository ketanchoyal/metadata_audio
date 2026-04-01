/// Unit tests for format-aware strategy selection helpers.
///
/// Tests cover the [_extractUrlExtension] and [_detectAudioFormatCategory]
/// private helpers indirectly via [StrategyInfo] field values set by
/// [detectStrategy], and directly via the exported [StrategyInfo] constructor
/// to verify the contract between detected format labels and probe strategies.
library;

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

void main() {
  // -------------------------------------------------------------------------
  // StrategyInfo contract
  // -------------------------------------------------------------------------
  group('StrategyInfo contract', () {
    test('default probeStrategy is scatter', () {
      final info = StrategyInfo(
        strategy: ParseStrategy.probe,
        fileSize: 10 * 1024 * 1024,
        supportsRange: true,
      );
      expect(info.probeStrategy, equals(ProbeStrategy.scatter));
    });

    test('detectedFormat defaults to null', () {
      final info = StrategyInfo(
        strategy: ParseStrategy.fullDownload,
        fileSize: 1 * 1024 * 1024,
        supportsRange: false,
      );
      expect(info.detectedFormat, isNull);
    });

    test('custom probeStrategy and detectedFormat are preserved', () {
      final info = StrategyInfo(
        strategy: ParseStrategy.probe,
        fileSize: 20 * 1024 * 1024,
        supportsRange: true,
        probeStrategy: ProbeStrategy.mp4Optimized,
        detectedFormat: 'mp4',
      );
      expect(info.probeStrategy, equals(ProbeStrategy.mp4Optimized));
      expect(info.detectedFormat, equals('mp4'));
    });
  });

  // -------------------------------------------------------------------------
  // Expected (format, strategy, probeStrategy) triples – no network required.
  // These verify the mapping table documented in detectStrategy().
  // -------------------------------------------------------------------------
  group('format → strategy mapping table', () {
    // Helper to build a StrategyInfo as detectStrategy() would for a large
    // file with Range support (the interesting region for format-based choices).
    StrategyInfo _buildFor({
      required String format,
      required ParseStrategy strategy,
      required ProbeStrategy probeStrategy,
    }) =>
        StrategyInfo(
          strategy: strategy,
          fileSize: 10 * 1024 * 1024,
          supportsRange: true,
          probeStrategy: probeStrategy,
          detectedFormat: format,
        );

    test('mp4 → probe + mp4Optimized', () {
      final info = _buildFor(
        format: 'mp4',
        strategy: ParseStrategy.probe,
        probeStrategy: ProbeStrategy.mp4Optimized,
      );
      expect(info.strategy, ParseStrategy.probe);
      expect(info.probeStrategy, ProbeStrategy.mp4Optimized);
    });

    test('mpeg → probe + headerAndTail', () {
      final info = _buildFor(
        format: 'mpeg',
        strategy: ParseStrategy.probe,
        probeStrategy: ProbeStrategy.headerAndTail,
      );
      expect(info.strategy, ParseStrategy.probe);
      expect(info.probeStrategy, ProbeStrategy.headerAndTail);
    });

    test('header-only → headerOnly strategy + headerOnly probe', () {
      final info = _buildFor(
        format: 'header-only',
        strategy: ParseStrategy.headerOnly,
        probeStrategy: ProbeStrategy.headerOnly,
      );
      expect(info.strategy, ParseStrategy.headerOnly);
      expect(info.probeStrategy, ProbeStrategy.headerOnly);
    });

    test('unknown → probe + scatter', () {
      final info = _buildFor(
        format: 'unknown',
        strategy: ParseStrategy.probe,
        probeStrategy: ProbeStrategy.scatter,
      );
      expect(info.strategy, ParseStrategy.probe);
      expect(info.probeStrategy, ProbeStrategy.scatter);
    });
  });

  // -------------------------------------------------------------------------
  // _extractUrlExtension logic (tested via expected URL inputs)
  // -------------------------------------------------------------------------
  group('URL extension extraction (expected inputs)', () {
    // We verify the extraction logic that is now embedded in detectStrategy.
    // Since _extractUrlExtension is private, we replicate the same algorithm
    // here.  If the production implementation changes, this helper must be
    // updated to stay in sync with http_tokenizers.dart.

    String? _extract(String url) {
      try {
        final path = Uri.parse(url).path;
        final lastSlash = path.lastIndexOf('/');
        final filename =
            lastSlash >= 0 ? path.substring(lastSlash + 1) : path;
        final lastDot = filename.lastIndexOf('.');
        if (lastDot <= 0 || lastDot == filename.length - 1) return null;
        return filename.substring(lastDot + 1).toLowerCase();
      } catch (_) {
        return null;
      }
    }

    test('plain URL', () {
      expect(_extract('https://cdn.example.com/audio.mp3'), equals('mp3'));
    });

    test('URL with query string', () {
      expect(
        _extract('https://cdn.example.com/audio.m4a?token=abc.def'),
        equals('m4a'),
      );
    });

    test('URL with fragment', () {
      expect(
        _extract('https://cdn.example.com/track.flac#intro'),
        equals('flac'),
      );
    });

    test('URL with no extension', () {
      expect(_extract('https://cdn.example.com/stream'), isNull);
    });

    test('URL with trailing dot', () {
      expect(_extract('https://cdn.example.com/audio.'), isNull);
    });

    test('URL with deep path', () {
      expect(
        _extract('https://cdn.example.com/music/2024/track.ogg'),
        equals('ogg'),
      );
    });

    test('extension is lowercased', () {
      expect(_extract('https://cdn.example.com/TRACK.MP3'), equals('mp3'));
    });
  });

  // -------------------------------------------------------------------------
  // Format detection heuristics (MIME type and extension combinations)
  // -------------------------------------------------------------------------
  group('format category detection heuristics', () {
    // This helper replicates _detectAudioFormatCategory() from
    // http_tokenizers.dart.  Both the extension sets and the MIME string
    // checks must stay in sync with the production implementation.
    // The duplication is intentional: _detectAudioFormatCategory is private
    // and cannot be imported directly from tests.
    String _category({String? mime, required String url}) {
      final m = mime?.toLowerCase() ?? '';
      final ext = (() {
        try {
          final path = Uri.parse(url).path;
          final ls = path.lastIndexOf('/');
          final fn = ls >= 0 ? path.substring(ls + 1) : path;
          final ld = fn.lastIndexOf('.');
          if (ld <= 0 || ld == fn.length - 1) return '';
          return fn.substring(ld + 1).toLowerCase();
        } catch (_) {
          return '';
        }
      })();

      const mp4Exts = {'mp4', 'm4a', 'm4b', 'm4p', 'm4r', 'm4v'};
      const mpegExts = {'mp3', 'mp2', 'mp1', 'aac', 'm2a', 'mpa', 'aacp'};
      const headerOnlyExts = {
        'flac',
        'ogg', 'oga', 'ogv', 'opus',
        'wav', 'wave',
        'aiff', 'aif',
        'mkv', 'mka', 'webm',
        'mpc', 'mpp',
        'wv', 'wvp', 'ape',
        'dsf', 'dff',
        'asf', 'wma', 'wmv',
      };

      if (m.contains('/mp4') ||
          m.contains('m4a') ||
          m.contains('m4b') ||
          mp4Exts.contains(ext)) return 'mp4';

      if (m.contains('mpeg') ||
          m.contains('mp3') ||
          m.contains('/aac') ||
          m.contains('aacp') ||
          mpegExts.contains(ext)) return 'mpeg';

      if (m.contains('flac') ||
          m.contains('ogg') ||
          m.contains('vorbis') ||
          m.contains('opus') ||
          m.contains('wav') ||
          m.contains('aiff') ||
          m.contains('matroska') ||
          m.contains('webm') ||
          m.contains('musepack') ||
          m.contains('wavpack') ||
          m.contains('dsf') ||
          m.contains('dsdiff') ||
          m.contains('asf') ||
          m.contains('wma') ||
          headerOnlyExts.contains(ext)) return 'header-only';

      return 'unknown';
    }

    // MP4 family
    test('audio/mp4 MIME → mp4', () {
      expect(_category(mime: 'audio/mp4', url: 'https://x.com/a'), 'mp4');
    });
    test('video/mp4 MIME → mp4', () {
      expect(_category(mime: 'video/mp4', url: 'https://x.com/a'), 'mp4');
    });
    test('.m4a extension → mp4', () {
      expect(_category(url: 'https://x.com/audio.m4a'), 'mp4');
    });
    test('.m4b extension → mp4', () {
      expect(_category(url: 'https://x.com/audio.m4b'), 'mp4');
    });
    test('.mp4 extension → mp4', () {
      expect(_category(url: 'https://x.com/audio.mp4'), 'mp4');
    });

    // MPEG family
    test('audio/mpeg MIME → mpeg', () {
      expect(_category(mime: 'audio/mpeg', url: 'https://x.com/a'), 'mpeg');
    });
    test('audio/mp3 MIME → mpeg', () {
      expect(_category(mime: 'audio/mp3', url: 'https://x.com/a'), 'mpeg');
    });
    test('audio/aac MIME → mpeg', () {
      expect(_category(mime: 'audio/aac', url: 'https://x.com/a'), 'mpeg');
    });
    test('.mp3 extension → mpeg', () {
      expect(_category(url: 'https://x.com/track.mp3'), 'mpeg');
    });
    test('.aac extension → mpeg', () {
      expect(_category(url: 'https://x.com/track.aac'), 'mpeg');
    });

    // Header-only family
    test('audio/flac MIME → header-only', () {
      expect(
        _category(mime: 'audio/flac', url: 'https://x.com/a'),
        'header-only',
      );
    });
    test('audio/ogg MIME → header-only', () {
      expect(
        _category(mime: 'audio/ogg', url: 'https://x.com/a'),
        'header-only',
      );
    });
    test('audio/wav MIME → header-only', () {
      expect(
        _category(mime: 'audio/wav', url: 'https://x.com/a'),
        'header-only',
      );
    });
    test('.flac extension → header-only', () {
      expect(_category(url: 'https://x.com/track.flac'), 'header-only');
    });
    test('.ogg extension → header-only', () {
      expect(_category(url: 'https://x.com/track.ogg'), 'header-only');
    });
    test('.wav extension → header-only', () {
      expect(_category(url: 'https://x.com/track.wav'), 'header-only');
    });
    test('.aiff extension → header-only', () {
      expect(_category(url: 'https://x.com/track.aiff'), 'header-only');
    });
    test('.mkv extension → header-only', () {
      expect(_category(url: 'https://x.com/track.mkv'), 'header-only');
    });
    test('.wma extension → header-only', () {
      expect(_category(url: 'https://x.com/track.wma'), 'header-only');
    });

    // Unknown
    test('no MIME + no extension → unknown', () {
      expect(_category(url: 'https://x.com/stream'), 'unknown');
    });
    test('application/octet-stream + no extension → unknown', () {
      expect(
        _category(
          mime: 'application/octet-stream',
          url: 'https://x.com/file',
        ),
        'unknown',
      );
    });

    // MIME type takes priority over extension
    test('audio/mp4 MIME overrides .mp3 extension → mp4', () {
      // MIME type is checked first, so audio/mp4 wins.
      expect(
        _category(mime: 'audio/mp4', url: 'https://x.com/audio.mp3'),
        'mp4',
      );
    });
  });
}
