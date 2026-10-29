/// Fixture test asserting `format.trackInfo` for Ogg/Theora, mirroring
/// upstream music-metadata's OggParser per-stream track behaviour.
library;

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

import 'upstream_fixture_loader.dart';

void main() {
  group('upstream Ogg trackInfo fixtures', () {
    test('short.ogv exposes Theora video and Vorbis audio tracks', () async {
      final bytes = await fetchUpstreamFixtureOrSkip('ogg/short.ogv');
      if (bytes.isEmpty) return;
      final metadata = await parseBytes(
        bytes,
        fileInfo: FileInfo.fromPath('ogg/short.ogv'),
      );

      final video = metadata.format.trackInfo.firstWhere(
        (t) => t.type == 'video',
      );
      expect(video.codecName, equals('Theora'));
      expect(video.video?.pixelWidth, equals(640));
      expect(video.video?.pixelHeight, equals(480));
      expect(video.video?.frameRate, closeTo(30, 1e-6));

      final audio = metadata.format.trackInfo.firstWhere(
        (t) => t.type == 'audio',
      );
      expect(audio.codecName, equals('Vorbis I'));
      expect(audio.audio?.samplingFrequency, equals(44100));
      expect(audio.audio?.channels, equals(2));
      expect(audio.duration, closeTo(5.76, 0.01));
      expect(audio.bitrate, greaterThan(0));
    });
  });
}
