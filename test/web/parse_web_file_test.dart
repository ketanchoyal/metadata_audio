@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  group('parseWebFile', () {
    late Uint8List testBytes;
    late ParserRegistry registry;

    setUp(() {
      testBytes = Uint8List.fromList([
        0x49,
        0x44,
        0x33,
        0x03,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        ...List<int>.filled(32, 0),
      ]);

      registry = ParserRegistry();
      initializeParserFactory(ParserFactory(registry));
    });

    test('reads browser File bytes and forwards file metadata', () async {
      final capturedFileInfo = <FileInfo?>[];
      final capturedOptions = <ParseOptions>[];

      registry.register(
        _MockParser(
          mimeType: const ['audio/test'],
          onParse: (tokenizer, options) async {
            capturedFileInfo.add(tokenizer.fileInfo);
            capturedOptions.add(options);
            expect(tokenizer.readBytes(testBytes.length), testBytes);
            return _createMockMetadata();
          },
        ),
      );

      final file = web.File(
        [testBytes.toJS].toJS,
        'sample.web.mp3',
        web.FilePropertyBag(type: 'audio/test'),
      );

      final metadata = await parseWebFile(
        file,
        options: const ParseOptions(includeChapters: true),
      );

      expect(metadata.common.title, 'Test Title');
      expect(capturedFileInfo.single?.path, 'sample.web.mp3');
      expect(capturedFileInfo.single?.mimeType, 'audio/test');
      expect(capturedFileInfo.single?.size, testBytes.length);
      expect(capturedOptions.single.includeChapters, isTrue);
    });

    test('normalizes empty browser MIME types to null', () async {
      final capturedFileInfo = <FileInfo?>[];

      registry.register(
        _MockParser(
          extension: const ['mp3'],
          onParse: (tokenizer, options) async {
            capturedFileInfo.add(tokenizer.fileInfo);
            return _createMockMetadata();
          },
        ),
      );

      final file = web.File([testBytes.toJS].toJS, 'sample.mp3');

      await parseWebFile(file);

      expect(capturedFileInfo.single?.path, 'sample.mp3');
      expect(capturedFileInfo.single?.mimeType, isNull);
      expect(capturedFileInfo.single?.size, testBytes.length);
    });
  });
}

AudioMetadata _createMockMetadata() => const AudioMetadata(
  format: Format(
    container: 'mp3',
    duration: 3.5,
    bitrate: 320000,
    sampleRate: 44100,
    numberOfChannels: 2,
    codec: 'MP3',
  ),
  native: {},
  common: CommonTags(
    track: TrackNo(no: 1, of: 10),
    disk: TrackNo(no: 1, of: 1),
    movementIndex: TrackNo(),
    title: 'Test Title',
    artist: 'Test Artist',
    album: 'Test Album',
  ),
  quality: QualityInformation(),
);

class _MockParser implements ParserLoader {
  _MockParser({
    this.extension = const [],
    this.mimeType = const [],
    this.hasRandomAccessRequirements = false,
    this.onParse,
  });

  @override
  final List<String> extension;

  @override
  final List<String> mimeType;

  @override
  final bool hasRandomAccessRequirements;

  final Future<AudioMetadata> Function(Tokenizer, ParseOptions)? onParse;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    if (onParse != null) {
      return onParse!(tokenizer, options);
    }

    return _createMockMetadata();
  }

  @override
  bool supports(Tokenizer tokenizer) {
    if (hasRandomAccessRequirements && !tokenizer.canSeek) {
      return false;
    }

    return true;
  }
}
