/// Fixture tests for RIFF LIST/INFO character encoding using upstream
/// music-metadata samples (`test/samples/wav/cest_*.wav`), fetched from
/// GitHub at test time and asserting the same expectations as upstream
/// `test/test-file-wav.ts`.
library;

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

import 'upstream_fixture_loader.dart';

void main() {
  group('upstream CSET fixtures', () {
    test('latin1 variants decode as ISO 8859-1', () async {
      for (final path in [
        'wav/cest_latin1-default.wav',
        'wav/cest_latin1-zero.wav',
        'wav/cest_latin1-explicit.wav',
      ]) {
        final bytes = await fetchUpstreamFixtureOrSkip(path);
        if (bytes.isEmpty) return;
        final metadata = await parseBytes(bytes, fileInfo: FileInfo.fromPath(path));
        expect(metadata.common.title, equals('Mötley'), reason: path);
        expect(metadata.common.artist, equals('Björk'), reason: path);
        expect(metadata.format.sampleRate, equals(8000), reason: path);
        expect(metadata.format.numberOfSamples, equals(800), reason: path);
        expect(metadata.format.duration, equals(0.1), reason: path);
        expect(
          metadata.quality.warnings.any((w) => w.message.contains('CSET')),
          isFalse,
          reason: path,
        );
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('windows-1252 code page decodes the euro sign', () async {
      for (final path in [
        'wav/cest_windows1252.wav',
        'wav/cest_windows1252-after-info.wav',
      ]) {
        final bytes = await fetchUpstreamFixtureOrSkip(path);
        if (bytes.isEmpty) return;
        final metadata = await parseBytes(bytes, fileInfo: FileInfo.fromPath(path));
        expect(metadata.common.title, equals('“Mötley” – 10 €'), reason: path);
        expect(metadata.common.artist, equals('Björk'), reason: path);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('utf-8 via CSET 65001 after INFO chunk', () async {
      final bytes = await fetchUpstreamFixtureOrSkip('wav/cest_utf8-after-info.wav');
      if (bytes.isEmpty) return;
      final metadata = await parseBytes(bytes, fileInfo: FileInfo.fromPath('wav/cest_utf8-after-info.wav'));
      expect(metadata.common.title, equals('音楽 – Mötley'));
      expect(metadata.common.artist, equals('Björk'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('unsupported code page 1251 omits tags with a warning', () async {
      final bytes = await fetchUpstreamFixtureOrSkip('wav/cest_unsupported1251.wav');
      if (bytes.isEmpty) return;
      final metadata = await parseBytes(bytes, fileInfo: FileInfo.fromPath('wav/cest_unsupported1251.wav'));
      expect(metadata.common.title, isNull);
      expect(metadata.native['exif'], isNull);
      expect(
        metadata.quality.warnings.any(
          (w) =>
              w.message ==
              'Unsupported RIFF CSET code page: 1251; LIST/INFO tags will be '
              'omitted',
        ),
        isTrue,
      );
      expect(metadata.format.numberOfSamples, equals(800));
      expect(metadata.format.duration, equals(0.1));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('CSET chunk smaller than 8 bytes is rejected', () async {
      final bytes = await fetchUpstreamFixtureOrSkip('wav/cest_truncated-cset.wav');
      if (bytes.isEmpty) return;
      await expectLater(
        parseBytes(bytes, fileInfo: FileInfo.fromPath('wav/cest_truncated-cset.wav')),
        throwsA(
          isA<UnexpectedFileContentError>().having(
            (e) => e.message,
            'message',
            contains('CSET chunk must contain at least 8 bytes'),
          ),
        ),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
