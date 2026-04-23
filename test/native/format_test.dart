import 'dart:io';

import 'package:metadata_audio/src/native/api.dart';
import 'package:metadata_audio/src/native/frb_generated.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Symphonia format/format-info extraction', () {
    setUpAll(RustLib.init);
    tearDownAll(RustLib.dispose);

    String sample(String relativePath) =>
        p.join(Directory.current.path, 'test', 'samples', relativePath);

    Future<void> expectFormat(
      String relativePath, {
      required String expectedContainer,
      required String expectedCodec,
      required int expectedSampleRate,
      required int expectedChannels,
      required bool expectedLossless,
      Matcher? durationMatcher,
    }) async {
      final file = File(sample(relativePath));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final format = await pocGetFormat(path: sample(relativePath));

      expect(format.container, expectedContainer, reason: '$relativePath container');
      expect(format.codec, expectedCodec, reason: '$relativePath codec');
      expect(format.sampleRate, expectedSampleRate, reason: '$relativePath sample rate');
      expect(
        format.numberOfChannels,
        expectedChannels,
        reason: '$relativePath channels',
      );
      expect(format.lossless, expectedLossless, reason: '$relativePath lossless');
      expect(format.duration, isNotNull, reason: '$relativePath duration present');
      expect(
        format.duration,
        durationMatcher ?? greaterThan(0),
        reason: '$relativePath duration',
      );
      expect(format.hasAudio, isTrue, reason: '$relativePath hasAudio');
      expect(format.hasVideo, anyOf(isFalse, isNull), reason: '$relativePath hasVideo');
      expect(format.tagTypes, isNotEmpty, reason: '$relativePath tag types');
      expect(format.numberOfSamples, isNotNull, reason: '$relativePath sample frames');
    }

    test('extracts MP3 format info', () async {
      await expectFormat(
        'mp3/id3v2.3.mp3',
        expectedContainer: 'mp3',
        expectedCodec: 'MPEG 1 Layer 3',
        expectedSampleRate: 44100,
        expectedChannels: 2,
        expectedLossless: false,
      );
    });

    test('extracts FLAC format info', () async {
      await expectFormat(
        'flac/sample.flac',
        expectedContainer: 'flac',
        expectedCodec: 'FLAC',
        expectedSampleRate: 44100,
        expectedChannels: 2,
        expectedLossless: true,
      );
    });

    test('extracts MP4 format info with normalized container', () async {
      final file = File(sample('mp4/sample.m4a'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final format = await pocGetFormat(path: file.path);

      expect(format.container, 'mp4');
      expect(format.codec, 'MPEG-4/AAC');
      expect(format.sampleRate, 44100);
      expect(format.numberOfChannels, 1);
      expect(format.lossless, false);
      expect(format.duration, closeTo(1.02, 0.1));
      expect(format.tool, isNotNull);
      expect(format.tagTypes, contains('isomp4'));
      expect(format.hasAudio, isTrue);
      expect(format.hasVideo, isFalse);
    });

    test('extracts OGG format info', () async {
      await expectFormat(
        'ogg/vorbis.ogg',
        expectedContainer: 'ogg',
        expectedCodec: 'Vorbis I',
        expectedSampleRate: 44100,
        expectedChannels: 2,
        expectedLossless: false,
      );
    });
  });
}
