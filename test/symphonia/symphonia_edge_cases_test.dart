import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/native/frb_generated.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Symphonia edge cases via public API', () {
    late Directory tempDir;
    var tempFileCounter = 0;

    setUpAll(() async {
      await RustLib.init();
      tempDir = await Directory.systemTemp.createTemp('symphonia_edge_cases_');
    });

    tearDownAll(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
      RustLib.dispose();
    });

    setUp(() {
      initializeParserFactory(createDefaultParserFactory());
    });

    test('empty file throws a file-type or format recognition error', () async {
      final file = await _writeTempFile(
        tempDir,
        'empty_${tempFileCounter++}.mp3',
        const <int>[],
      );

      await _expectReasonableSymphoniaFailure(
        () => parseFile(file.path),
        allowGenericProbeMessage: true,
      );
    });

    test(
      'unsupported random bytes throw CouldNotDetermineFileTypeError',
      () async {
        final file = await _writeTempFile(
          tempDir,
          'unsupported_${tempFileCounter++}.mp3',
          List<int>.generate(1024, (i) => i % 256),
        );

        await _expectReasonableSymphoniaFailure(
          () => parseFile(file.path),
          allowGenericProbeMessage: true,
        );
      },
    );

    test(
      'truncated MP3 either parses partially or throws a reasonable error',
      () async {
        final file = await _writeTempFile(
          tempDir,
          'truncated_${tempFileCounter++}.mp3',
          <int>[
            0xFF,
            0xFB,
            0x90,
            0x64,
            ...List<int>.generate(512, (i) => (255 - i) & 0xFF),
          ],
        );

        try {
          final metadata = await parseFile(file.path);

          expect(metadata, isA<AudioMetadata>());
          expect(metadata.quality.warnings, isA<List<ParserWarning>>());
          expect(metadata.format.container, anyOf(isNull, equals('mp3')));
        } catch (error) {
          _expectReasonableSymphoniaError(
            error,
            allowGenericProbeMessage: true,
          );
        }
      },
    );

    test('no-tags MP3 keeps title, artist, and album null', () async {
      final file = _sampleFile('mp3/no-tags.mp3');
      if (file == null) return;

      final metadata = await parseFile(file.path);

      expect(metadata.common.title, isNull);
      expect(metadata.common.artist, isNull);
      expect(metadata.common.album, isNull);
    });

    test(
      'MP4 audiobook fixture exposes cover art with default factory',
      () async {
        final file = _sampleFile('mp4/The Dark Forest.m4a');
        if (file == null) return;

        final metadata = await parseFile(
          file.path,
          options: const ParseOptions(includeChapters: true),
        );

        expect(metadata.common.picture, isNotNull);
        expect(metadata.common.picture, isNotEmpty);
        expect(metadata.common.picture!.first.format, startsWith('image/'));
        expect(metadata.common.picture!.first.data, isNotEmpty);
      },
    );
  });
}

Future<File> _writeTempFile(
  Directory directory,
  String fileName,
  List<int> bytes,
) async {
  final file = File(p.join(directory.path, fileName));
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

File? _sampleFile(String relativePath) {
  final file = File(
    p.join(Directory.current.path, 'test', 'samples', relativePath),
  );
  if (!file.existsSync()) {
    markTestSkipped('Sample file not found: ${file.path}');
    return null;
  }

  return file;
}

Future<void> _expectReasonableSymphoniaFailure(
  Future<AudioMetadata> Function() action, {
  bool allowGenericProbeMessage = false,
}) async {
  try {
    await action();
    fail('Expected parsing to fail');
  } catch (error) {
    _expectReasonableSymphoniaError(
      error,
      allowGenericProbeMessage: allowGenericProbeMessage,
    );
  }
}

void _expectReasonableSymphoniaError(
  Object error, {
  bool allowGenericProbeMessage = false,
}) {
  if (error is CouldNotDetermineFileTypeError || error is ParseError) {
    expect(error.toString(), isNotEmpty);
    return;
  }

  final message = error.toString();
  expect(message, isNotEmpty);
  if (allowGenericProbeMessage) {
    expect(
      message,
      anyOf(
        contains('Could not determine file type'),
        contains('no suitable format reader found'),
        contains('failed to probe media source stream'),
        contains('unsupported feature: core (probe)'),
      ),
    );
    return;
  }

  expect(
    message,
    anyOf(
      contains('Could not determine file type'),
      contains('no suitable format reader found'),
      contains('failed to probe media source stream'),
    ),
  );
}
