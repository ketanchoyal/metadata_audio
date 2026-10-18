import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
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
  });
}