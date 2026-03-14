import 'dart:typed_data';

import 'package:audio_metadata/audio_metadata.dart';
import 'package:test/test.dart';

void main() {
  group('Regression unparseable/no metadata input', () {
    setUp(() {
      initializeParserFactory(ParserFactory(ParserRegistry()));
    });

    test(
      'throws CouldNotDetermineFileTypeError for random non-audio bytes',
      () async {
        final bytes = Uint8List.fromList(<int>[
          0x13,
          0x37,
          0xCA,
          0xFE,
          0xBA,
          0xBE,
          0x00,
          0x42,
        ]);

        await expectLater(
          () =>
              parseBytes(bytes, fileInfo: const FileInfo(path: 'garbage.bin')),
          throwsA(isA<CouldNotDetermineFileTypeError>()),
        );
      },
    );
  });
}
