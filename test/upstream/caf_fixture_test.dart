/// Fixture tests using upstream music-metadata CAF samples
/// (test/samples/caf/*), fetched from GitHub at test time and asserting the
/// same expectations as upstream `test/test-file-caf.ts`.
library;

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/caf/caf_token.dart';
import 'package:test/test.dart';

import 'upstream_fixture_loader.dart';

void main() {
  group('upstream CAF fixtures', () {
    test(
      'lpcm-be-16bit / lpcm-le-16bit: PCM stereo 16-bit 44.1kHz 0.1s',
      () async {
        for (final path in ['caf/lpcm-be-16bit.caf', 'caf/lpcm-le-16bit.caf']) {
          final bytes = await fetchUpstreamFixtureOrSkip(path);
          if (bytes.isEmpty) return;
          final metadata = await parseBytes(bytes, fileInfo: FileInfo.fromPath(path));
          expect(metadata.format.container, equals('CAF'), reason: path);
          expect(metadata.format.hasAudio, isTrue, reason: path);
          expect(metadata.format.hasVideo, isFalse, reason: path);
          expect(metadata.format.codec, equals('PCM'), reason: path);
          expect(metadata.format.lossless, isTrue, reason: path);
          expect(metadata.format.sampleRate, equals(44100), reason: path);
          expect(metadata.format.numberOfChannels, equals(2), reason: path);
          expect(metadata.format.bitsPerSample, equals(16), reason: path);
          expect(metadata.format.numberOfSamples, equals(4410), reason: path);
          expect(metadata.format.duration, closeTo(0.1, 1e-9), reason: path);
          expect(metadata.format.bitrate, closeTo(1411200, 1), reason: path);
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('ulaw / alaw codecs with expected names', () async {
      final ulawBytes = await fetchUpstreamFixtureOrSkip('caf/ulaw.caf');
      if (ulawBytes.isEmpty) return;
      final ulaw = await parseBytes(ulawBytes, fileInfo: FileInfo.fromPath('caf/ulaw.caf'));
      expect(ulaw.format.codec, equals('ITU-T G.711 mu-law'));
      expect(ulaw.format.lossless, isFalse);
      expect(ulaw.format.sampleRate, equals(8000));
      expect(ulaw.format.numberOfChannels, equals(1));
      expect(ulaw.format.bitsPerSample, equals(8));
      expect(ulaw.format.numberOfSamples, equals(800));
      expect(ulaw.format.duration, closeTo(0.1, 1e-9));
      expect(ulaw.format.bitrate, closeTo(64000, 1));

      final alawBytes = await fetchUpstreamFixtureOrSkip('caf/alaw.caf');
      if (alawBytes.isEmpty) return;
      final alaw = await parseBytes(alawBytes, fileInfo: FileInfo.fromPath('caf/alaw.caf'));
      expect(alaw.format.codec, equals('ITU-T G.711 A-law'));
      expect(alaw.format.lossless, isFalse);
      expect(alaw.format.numberOfSamples, equals(800));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('aac codec without bitsPerSample', () async {
      final bytes = await fetchUpstreamFixtureOrSkip('caf/aac.caf');
      if (bytes.isEmpty) return;
      final metadata = await parseBytes(bytes, fileInfo: FileInfo.fromPath('caf/aac.caf'));
      expect(metadata.format.codec, equals('AAC'));
      expect(metadata.format.lossless, isFalse);
      expect(metadata.format.sampleRate, equals(44100));
      expect(metadata.format.numberOfChannels, equals(2));
      expect(metadata.format.bitsPerSample, isNull);
      expect(metadata.format.numberOfSamples, equals(4410));
      expect(metadata.format.duration, closeTo(0.1, 1e-9));
      expect(metadata.format.bitrate, closeTo(53600, 1));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('ima4 codec', () async {
      final bytes = await fetchUpstreamFixtureOrSkip('caf/ima4.caf');
      if (bytes.isEmpty) return;
      final metadata = await parseBytes(bytes, fileInfo: FileInfo.fromPath('caf/ima4.caf'));
      expect(metadata.format.codec, equals('IMA4 ADPCM'));
      expect(metadata.format.lossless, isFalse);
      expect(metadata.format.sampleRate, equals(44100));
      expect(metadata.format.numberOfChannels, equals(2));
      expect(metadata.format.numberOfSamples, equals(4410));
      expect(metadata.format.duration, closeTo(0.1, 1e-9));
      expect(metadata.format.bitrate, closeTo(375360, 1));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('alac codec with numberValidFrames-driven duration', () async {
      final bytes = await fetchUpstreamFixtureOrSkip('caf/alac.caf');
      if (bytes.isEmpty) return;
      final metadata = await parseBytes(bytes, fileInfo: FileInfo.fromPath('caf/alac.caf'));
      expect(metadata.format.codec, equals('ALAC'));
      expect(metadata.format.lossless, isTrue);
      expect(metadata.format.sampleRate, equals(44100));
      expect(metadata.format.numberOfChannels, equals(2));
      expect(metadata.format.numberOfSamples, equals(4410));
      expect(metadata.format.duration, closeTo(0.1, 1e-9));
      expect(metadata.format.bitrate, closeTo(148560, 1));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('data chunk with unknown size derives duration', () async {
      final bytes = await fetchUpstreamFixtureOrSkip('caf/data-unknown-size.caf');
      if (bytes.isEmpty) return;
      // The -1 data chunk size is derived from the file size; pass it like
      // parseFile does.
      final metadata = await parseBytes(
        bytes,
        fileInfo: FileInfo(path: 'caf/data-unknown-size.caf', size: bytes.length),
      );
      expect(metadata.format.numberOfSamples, equals(512));
      expect(metadata.format.duration, closeTo(0.064, 1e-9));
      expect(metadata.format.bitrate, closeTo(64000, 1));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('unknown chunks are skipped', () async {
      final bytes = await fetchUpstreamFixtureOrSkip('caf/unknown-chunk.caf');
      if (bytes.isEmpty) return;
      final metadata = await parseBytes(bytes, fileInfo: FileInfo.fromPath('caf/unknown-chunk.caf'));
      expect(metadata.format.numberOfSamples, equals(512));
      expect(metadata.format.duration, closeTo(0.064, 1e-9));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('zero packet count falls back to constant bitrate derivation', () async {
      final bytes = await fetchUpstreamFixtureOrSkip('caf/pakt-zero-packets.caf');
      if (bytes.isEmpty) return;
      final metadata = await parseBytes(bytes, fileInfo: FileInfo.fromPath('caf/pakt-zero-packets.caf'));
      expect(metadata.format.numberOfSamples, equals(4480));
      expect(metadata.format.duration, closeTo(4480 / 22050, 1e-9));
      expect(metadata.format.bitrate, closeTo(187425, 1));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('negative valid frames are ignored', () async {
      final bytes =
          await fetchUpstreamFixtureOrSkip('caf/flac-negative-valid-frames.caf');
      if (bytes.isEmpty) return;
      final metadata =
          await parseBytes(bytes, fileInfo: FileInfo.fromPath('caf/flac-negative-valid-frames.caf'));
      expect(metadata.format.codec, equals('FLAC'));
      expect(metadata.format.lossless, isTrue);
      expect(metadata.format.numberOfSamples, isNull);
      expect(metadata.format.duration, isNull);
      expect(metadata.format.bitrate, isNull);
      expect(metadata.native['CAF'], isNotNull);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('info tags map to common and native tags', () async {
      final bytes = await fetchUpstreamFixtureOrSkip('caf/info-tags.caf');
      if (bytes.isEmpty) return;
      final metadata = await parseBytes(bytes, fileInfo: FileInfo.fromPath('caf/info-tags.caf'));
      final common = metadata.common;
      expect(common.title, equals('Fixture Piece'));
      expect(common.artist, equals('Able Baker'));
      expect(common.album, equals('The Book of Fixtures'));
      expect(common.track.no, equals(7));
      expect(common.bpm, equals(120));
      expect(common.key, equals('Cm'));
      expect(common.year, equals(2004));
      expect(common.date, equals('2004-06-01T12:00:00Z'));
      expect(common.composer, equals(['Charlie Delta']));
      expect(common.lyricist, equals(['Echo Foxtrot']));
      expect(common.genre, equals(['Jazz']));
      expect(common.copyright, equals('Copyright 2004 The CoolBandName'));
      expect(common.encodersettings, equals('Fixture Encoder v4.2'));
      expect(common.encodedby, equals('Fixture App v1.0'));
      expect(common.comment, hasLength(1));
      expect(common.comment!.single.text, equals('first note, second note'));

      // Unmapped keys stay native.
      final cafTags = metadata.native['CAF']!;
      final nominalBitRate =
          cafTags.where((tag) => tag.id == 'nominal bit rate').single;
      expect(nominalBitRate.value, equals('128 kbits'));
      final hiddenKey =
          cafTags.where((tag) => tag.id == '.hidden reserved key').single;
      expect(hiddenKey.value, equals('reserved value'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('channel descriptions are exposed as native tags', () async {
      final bytes = await fetchUpstreamFixtureOrSkip('caf/chan-descriptions.caf');
      if (bytes.isEmpty) return;
      final metadata = await parseBytes(bytes, fileInfo: FileInfo.fromPath('caf/chan-descriptions.caf'));
      final cafTags = metadata.native['CAF']!;

      final layoutTag =
          cafTags.where((tag) => tag.id == 'channelLayoutTag').single.value;
      expect(layoutTag, equals(1245190)); // kAudioChannelLayoutTag_5_1

      final layoutBitmap =
          cafTags.where((tag) => tag.id == 'channelLayoutBitmap').single.value;
      expect(layoutBitmap, equals(63));

      final descriptions = (cafTags
              .where((tag) => tag.id == 'channelLayoutDescriptions')
              .single
              .value as List)
          .cast<ChannelDescription>();
      expect(descriptions, hasLength(6));
      for (var i = 0; i < 6; i++) {
        expect(descriptions[i].channelLabel, equals(i + 1));
        expect(descriptions[i].channelFlags, equals(0));
        expect(descriptions[i].coordinates, const <double>[0, 0, 0]);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('bitmap layout keeps description channel count from desc', () async {
      final bytes = await fetchUpstreamFixtureOrSkip('caf/chan-bitmap-layout.caf');
      if (bytes.isEmpty) return;
      final metadata = await parseBytes(bytes, fileInfo: FileInfo.fromPath('caf/chan-bitmap-layout.caf'));
      expect(metadata.format.numberOfChannels, equals(4));
      final cafTags = metadata.native['CAF']!;
      expect(
        cafTags.where((tag) => tag.id == 'channelLayoutTag').single.value,
        equals(65536), // kAudioChannelLayoutTag_Quadraphonic
      );
      expect(
        cafTags.where((tag) => tag.id == 'channelLayoutBitmap').single.value,
        equals(7),
      );
      final descriptions = (cafTags
              .where((tag) => tag.id == 'channelLayoutDescriptions')
              .single
              .value as List)
          .cast<ChannelDescription>();
      expect(
        descriptions.map((d) => d.channelLabel),
        equals(<int>[1, 2, 3, 5]),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('truncated packet table is rejected', () async {
      final bytes =
          await fetchUpstreamFixtureOrSkip('caf/malformed-truncated-pakt.caf');
      if (bytes.isEmpty) return;
      await expectLater(
        parseBytes(bytes, fileInfo: FileInfo.fromPath('caf/malformed-truncated-pakt.caf')),
        throwsA(
          isA<UnexpectedFileContentError>().having(
            (e) => e.message,
            'message',
            contains(
              'Packet Table data section holds 1 byte(s) for 2 '
              'packet table entries',
            ),
          ),
        ),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
