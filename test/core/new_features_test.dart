import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/apev2/apev2_tag_map.dart';
import 'package:metadata_audio/src/asf/asf_tag_map.dart';
import 'package:test/test.dart';

void main() {
  group('New upstream-parity features', () {
    test('content sniffing detects common container types from bytes', () async {
      final cases = <String, String>{
        'test/samples/mp3/id3v2.3.mp3': 'MPEG',
        'test/samples/flac/sample.flac': 'FLAC',
        'test/samples/ogg/vorbis.ogg': 'Ogg',
      };
      for (final entry in cases.entries) {
        final bytes = File(entry.key).readAsBytesSync();
        final metadata = await parseBytes(bytes);
        expect(
          metadata.format.container,
          equals(entry.value),
          reason: entry.key,
        );
      }
    });

    test('getSupportedMimeTypes includes core and x- variants', () {
      final types = getSupportedMimeTypes();
      expect(types, contains('audio/mpeg'));
      expect(types, contains('audio/x-mpeg'));
      expect(types, contains('audio/flac'));
    });

    test('parseFile rejects directories with NotRegularFileError', () async {
      await expectLater(
        () => parseFile(Directory.systemTemp.path),
        throwsA(isA<NotRegularFileError>()),
      );
    });

    test('parseFile still throws FileSystemException for missing files',
        () async {
      await expectLater(
        () => parseFile('/no/such/file.mp3'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('TrackType constants match serialized track types', () async {
      // Ensure the constant is usable wherever a track type string is expected.
      expect(TrackType.audio, equals('audio'));
      expect(TrackType.video, equals('video'));
    });

    test('containerDuration and overallBitrate are consistent', () async {
      final file = File('test/samples/mp3/id3v2.3.mp3');
      final metadata = await parseFile(file.path);
      final format = metadata.format;

      expect(format.containerDuration, isNotNull);
      expect(format.duration, isNotNull);
      expect(format.containerDuration, equals(format.duration));

      expect(format.overallBitrate, isNotNull);
      final expected = file.lengthSync() * 8 / format.duration!;
      expect(format.overallBitrate, closeTo(expected, expected * 0.01));
    });

    test('Vorbis comments map DESCRIPTION and LABEL', () async {
      final metadata = await parseFile('test/samples/ogg/vorbis.ogg');
      expect(metadata.common.comment, isNotNull);
      expect(metadata.common.label, contains('Geffen Records'));
    });

    test('ParseOptions defaults match upstream', () {
      const options = ParseOptions();
      expect(options.mkvUseIndex, isFalse);
    });

    test('Format.copyWith preserves and overrides fields', () {
      const original = Format(container: 'mp3', duration: 10.0);
      final updated = original.copyWith(overallBitrate: 128000);
      expect(updated.container, equals('mp3'));
      expect(updated.duration, equals(10.0));
      expect(updated.overallBitrate, equals(128000));
    });

    test('Ogg unknown granule positions do not break parsing', () async {
      final metadata = await parseFile('test/samples/ogg/vorbis.ogg');
      expect(metadata.format.container, equals('Ogg'));
      expect(metadata.format.duration, isNotNull);
    });

    test('APEv2 Date maps to common date', () {
      final mapper = Apev2TagMapper();
      final mapped = mapper.mapTags({'Date': '2024-01-02'});
      expect(mapped['date'], equals('2024-01-02'));
    });

    test('ASF POPULARIMETER maps to rating', () {
      final mapper = AsfTagMapper();
      final mapped = mapper.mapTags({'POPULARIMETER': '50'});
      expect(mapped['rating'], isNotNull);
    });

    group('Simulated network parsing (local files)', () {
      test('parses MP4 chapters from bytes', () async {
        final bytes = File('test/samples/mp4/video_chapters.mp4').readAsBytesSync();
        final metadata = await parseBytes(
          bytes,
          options: const ParseOptions(includeChapters: true),
        );
        expect(metadata.format.chapters, isNotNull);
        expect(metadata.format.chapters, isNotEmpty);
      });

      test('parses M4B metadata from bytes', () async {
        final bytes = File('test/samples/mp4/issue_mvhd_v1.m4b').readAsBytesSync();
        final metadata = await parseBytes(bytes);
        expect(metadata.format.container, isNotNull);
      });

      test('parses MP3 metadata from bytes', () async {
        final bytes = File('test/samples/mp3/id3v2.3.mp3').readAsBytesSync();
        final metadata = await parseBytes(bytes);
        expect(metadata.common.title, isNotNull);
      });
    });
  });
}