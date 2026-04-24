import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/native/frb_generated.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Symphonia e2e via public API', () {
    setUpAll(RustLib.init);
    tearDownAll(RustLib.dispose);

    setUp(() {
      initializeParserFactory(createDefaultParserFactory());
    });

    test('parseFile parses MP3 sample with normalized metadata', () async {
      final file = _sampleFile('mp3/id3v2.3.mp3');
      if (file == null) return;

      final metadata = await parseFile(file.path);
      _expectCoreMetadata(metadata, container: 'mp3', expectTags: true);
    });

    test('parseFile parses FLAC sample with normalized metadata', () async {
      final file = _sampleFile('flac/sample.flac');
      if (file == null) return;

      final metadata = await parseFile(file.path);
      _expectCoreMetadata(metadata, container: 'flac', expectTags: true);
    });

    test('parseFile parses MP4 sample with normalized metadata', () async {
      final file = _sampleFile('mp4/sample.m4a');
      if (file == null) return;

      final metadata = await parseFile(file.path);
      _expectCoreMetadata(metadata, container: 'mp4', expectTags: true);
    });

    test('parseFile includes MP4 chapters when requested', () async {
      final file = _sampleFile('mp4/sample.m4a');
      if (file == null) return;

      final metadata = await parseFile(
        file.path,
        options: const ParseOptions(includeChapters: true),
      );

      _expectCoreMetadata(metadata, container: 'mp4', expectTags: true);
      expect(metadata.format.chapters, isNotNull);
      expect(metadata.format.chapters, isNotEmpty);
    });

    test('parseFile parses OGG sample with normalized metadata', () async {
      final file = _sampleFile('ogg/vorbis.ogg');
      if (file == null) return;

      final metadata = await parseFile(file.path);
      _expectCoreMetadata(metadata, container: 'ogg', expectTags: true);
    });

    test('parseFile parses WAV sample with normalized metadata', () async {
      final file = _sampleFile('wav/issue-819.wav');
      if (file == null) return;

      final metadata = await parseFile(file.path);
      _expectCoreMetadata(metadata, container: 'wav');
    });

    test('parseFile parses AIFF sample with normalized metadata', () async {
      final file = _sampleFile('aiff/sample.aiff');
      if (file == null) return;

      final metadata = await parseFile(file.path);
      _expectCoreMetadata(metadata, container: 'aiff', expectTags: true);
    });

    test('parseBytes parses MP3 sample with default factory', () async {
      final file = _sampleFile('mp3/id3v2.3.mp3');
      if (file == null) return;

      final metadata = await parseBytes(
        await file.readAsBytes(),
        fileInfo: _bytesFileInfo(file),
      );

      _expectCoreMetadata(metadata, container: 'mp3', expectTags: true);
    });

    test('parseBytes parses FLAC sample with default factory', () async {
      final file = _sampleFile('flac/sample.flac');
      if (file == null) return;

      final metadata = await parseBytes(
        await file.readAsBytes(),
        fileInfo: _bytesFileInfo(file),
      );

      _expectCoreMetadata(metadata, container: 'flac', expectTags: true);
    });

    test('parseFile reports empty native tags and warnings for no-tags MP3', () async {
      final file = _sampleFile('mp3/no-tags.mp3');
      if (file == null) return;

      final metadata = await parseFile(file.path);

      expect(metadata.format.container, equals('mp3'));
      expect(metadata.native, isEmpty);
      expect(metadata.quality.warnings, isA<List<ParserWarning>>());
      expect(metadata.quality.warnings, isNotEmpty);
    });
  });
}

FileInfo _bytesFileInfo(File file) {
  final base = FileInfo.fromPath(file.path);
  return FileInfo(path: base.path, size: file.lengthSync());
}

File? _sampleFile(String relativePath) {
  final file = File(p.join(Directory.current.path, 'test', 'samples', relativePath));
  if (!file.existsSync()) {
    markTestSkipped('Sample file not found: ${file.path}');
    return null;
  }

  return file;
}

void _expectCoreMetadata(
  AudioMetadata metadata, {
  required String container,
  bool expectTags = false,
}) {
  expect(metadata.format.container, isNotNull);
  expect(metadata.format.container, equals(container));
  expect(metadata.format.codec, isNotNull);
  expect(metadata.format.duration, isNotNull);
  expect(metadata.format.duration, greaterThan(0));
  expect(metadata.format.sampleRate, isNotNull);
  expect(metadata.format.sampleRate, greaterThan(0));
  expect(metadata.quality.warnings, isA<List<ParserWarning>>());

  if (expectTags) {
    expect(metadata.common.title, isNotNull);
    expect(metadata.common.artist, isNotNull);
    expect(metadata.native, isNotEmpty);
  }
}
