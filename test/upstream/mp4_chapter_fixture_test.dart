/// Fixture tests using upstream music-metadata MP4 chapter samples
/// (`chapters-leading.m4b`, `chapters-nero.m4b`), fetched from GitHub at test
/// time and asserting the same chapter expectations as upstream
/// `test/test-file-mp4.ts`.
///
/// The local Chapter model exposes `start` in milliseconds, so upstream's
/// `start / timeScale` (seconds) maps to `start (ms) / 1000`.
library;

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

import 'upstream_fixture_loader.dart';

void main() {
  group('upstream MP4 chapter fixtures', () {
    for (final path in [
      'mp4/chapters-leading.m4b',
      'mp4/chapters-nero.m4b',
    ]) {
      test('parses chapters of $path', () async {
        final bytes = await fetchUpstreamFixtureOrSkip(path);
        if (bytes.isEmpty) return;
        final metadata = await parseBytes(
          bytes,
          fileInfo: FileInfo.fromPath(path),
          options: const ParseOptions(includeChapters: true),
        );

        expect(metadata.format.duration, closeTo(10, 0.05), reason: path);
        expect(metadata.format.codec, equals('MPEG-4/AAC'), reason: path);

        final chapters = metadata.format.chapters;
        expect(chapters, isNotNull, reason: path);
        expect(chapters, hasLength(3), reason: path);
        expect(
          chapters!.map((c) => c.title),
          <String>['Opening Credits', 'Chapter 1', 'Chapter 2'],
          reason: path,
        );
        expect(
          chapters.map((c) => c.start).toList(),
          [equals(0), closeTo(3000, 5), closeTo(7000, 5)],
          reason: path,
        );
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });
}
