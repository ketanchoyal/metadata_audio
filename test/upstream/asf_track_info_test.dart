/// Fixture test asserting `format.trackInfo` for ASF files, mirroring
/// upstream music-metadata's AsfParser stream/codec behaviour.
library;

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

import 'upstream_fixture_loader.dart';

void main() {
  group('upstream ASF trackInfo fixtures', () {
    test('asf.wma exposes one audio track from the codec list', () async {
      final bytes = await fetchUpstreamFixtureOrSkip('asf/asf.wma');
      if (bytes.isEmpty) return;
      final metadata = await parseBytes(
        bytes,
        fileInfo: FileInfo.fromPath('asf/asf.wma'),
      );

      final tracks = metadata.format.trackInfo;
      expect(tracks, hasLength(1));

      final track = tracks.single;
      expect(track.type, equals('audio'));
      expect(track.id, equals(1));
      expect(track.codecId, equals('0x0161'));
      expect(track.codecName, equals('Windows Media Audio 9.1'));
      expect(track.audio?.samplingFrequency, equals(44100));
      expect(track.audio?.channels, equals(2));
      expect(track.audio?.bitDepth, equals(16));

      // Stream Bitrate Properties records the stream bitrate.
      expect(track.bitrate, closeTo(192639, 1));

      // First audio stream also feeds the format-level statistics.
      expect(metadata.format.sampleRate, equals(44100));
      expect(metadata.format.numberOfChannels, equals(2));
      expect(metadata.format.bitsPerSample, equals(16));
    });

    test('asf-video-audio-no-codec-list.asf yields audio and video tracks '
        'without codec names', () async {
      final bytes = await fetchUpstreamFixtureOrSkip(
        'asf/asf-video-audio-no-codec-list.asf',
      );
      if (bytes.isEmpty) return;
      final metadata = await parseBytes(
        bytes,
        fileInfo: FileInfo.fromPath('asf/asf-video-audio-no-codec-list.asf'),
      );

      final tracks = metadata.format.trackInfo;
      expect(tracks, hasLength(2));

      final audio = tracks.firstWhere((t) => t.type == 'audio');
      expect(audio.id, equals(2));
      expect(audio.codecId, equals('0x0161'));
      expect(audio.codecName, isNull); // no Codec List object in the file
      expect(audio.audio?.samplingFrequency, equals(8000));
      expect(audio.audio?.channels, equals(1));

      final video = tracks.firstWhere((t) => t.type == 'video');
      expect(video.id, equals(1));
      expect(video.codecId, equals('WMV2'));
      expect(video.video?.pixelWidth, greaterThan(0));
      expect(video.video?.pixelHeight, greaterThan(0));
    });
  });
}
