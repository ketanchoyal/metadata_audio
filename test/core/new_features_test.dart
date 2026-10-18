import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

void main() {
  group('New upstream-parity features', () {
    test('content sniffing parses bytes without path or MIME type', () async {
      final bytes = File('test/samples/mp3/id3v2.3.mp3').readAsBytesSync();
      final metadata = await parseBytes(bytes);
      expect(metadata.format.container, equals('MPEG'));
    });

    test('getSupportedMimeTypes returns supported types', () {
      final types = getSupportedMimeTypes();
      expect(types, isNotEmpty);
      expect(types, contains('audio/mpeg'));
    });

    test('parseFile rejects directories with NotRegularFileError', () async {
      await expectLater(
        () => parseFile(Directory.systemTemp.path),
        throwsA(isA<NotRegularFileError>()),
      );
    });

    test('TrackType constants are available', () {
      expect(TrackType.audio, equals('audio'));
      expect(TrackType.video, equals('video'));
    });

    test('containerDuration and overallBitrate are populated when possible',
        () async {
      final metadata = await parseFile('test/samples/mp3/id3v2.3.mp3');
      expect(metadata.format.containerDuration, isNotNull);
      expect(metadata.format.overallBitrate, isNotNull);
    });
  });
}