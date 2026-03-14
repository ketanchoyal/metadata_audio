import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/parse_error.dart';
import 'package:audio_metadata/src/parser_factory.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

class TestParserLoader extends ParserLoader {
  TestParserLoader({
    required this.extension,
    required this.mimeType,
    this.hasRandomAccessRequirements = false,
  });

  @override
  final List<String> extension;

  @override
  final List<String> mimeType;

  @override
  final bool hasRandomAccessRequirements;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    return const AudioMetadata(
      format: Format(),
      native: {},
      common: CommonTags(
        track: TrackNo(),
        disk: TrackNo(),
        movementIndex: TrackNo(),
      ),
      quality: QualityInformation(),
    );
  }
}

class MockTokenizer implements Tokenizer {
  MockTokenizer({this.canSeek = true});

  @override
  final bool canSeek;

  @override
  FileInfo? get fileInfo => null;

  @override
  int get position => 0;

  @override
  int peekUint8() => throw UnimplementedError();

  @override
  List<int> peekBytes(int length) => throw UnimplementedError();

  @override
  int readUint8() => throw UnimplementedError();

  @override
  int readUint16() => throw UnimplementedError();

  @override
  int readUint32() => throw UnimplementedError();

  @override
  List<int> readBytes(int length) => throw UnimplementedError();

  @override
  void seek(int position) => throw UnimplementedError();

  @override
  void skip(int length) => throw UnimplementedError();
}

void main() {
  group('ParserFactory - Selection Precedence', () {
    late ParserRegistry registry;
    late ParserFactory factory;
    late TestParserLoader mp3Loader;
    late TestParserLoader flacLoader;
    late TestParserLoader oggLoader;

    setUp(() {
      registry = ParserRegistry();
      factory = ParserFactory(registry);

      // Create test loaders for different formats
      mp3Loader = TestParserLoader(
        extension: ['mp3', 'mpeg'],
        mimeType: ['audio/mpeg'],
      );

      flacLoader = TestParserLoader(
        extension: ['flac'],
        mimeType: ['audio/flac'],
      );

      oggLoader = TestParserLoader(
        extension: ['ogg', 'oga'],
        mimeType: ['audio/ogg', 'application/ogg'],
      );

      // Register loaders
      registry.register(mp3Loader);
      registry.register(flacLoader);
      registry.register(oggLoader);
    });

    test('Priority 1: MIME type selection (audio/mpeg)', () {
      final fileInfo = FileInfo(
        path: '/path/to/file.unknown',
        mimeType: 'audio/mpeg',
      );

      final loader = factory.selectParser(fileInfo, MockTokenizer());
      expect(loader, same(mp3Loader));
    });

    test('Priority 1: MIME type selection (audio/flac)', () {
      final fileInfo = FileInfo(
        path: '/path/to/file.unknown',
        mimeType: 'audio/flac',
      );

      final loader = factory.selectParser(fileInfo, MockTokenizer());
      expect(loader, same(flacLoader));
    });

    test('Priority 1: MIME type overrides extension', () {
      final fileInfo = FileInfo(
        path: '/path/to/file.mp3',
        mimeType: 'audio/flac', // Different MIME type
      );

      final loader = factory.selectParser(fileInfo, MockTokenizer());
      expect(loader, same(flacLoader)); // Should use MIME, not extension
    });

    test('Priority 2: Extension selection when MIME type is missing', () {
      final fileInfo = FileInfo(
        path: '/path/to/file.flac',
        mimeType: null, // No MIME type
      );

      final loader = factory.selectParser(fileInfo, MockTokenizer());
      expect(loader, same(flacLoader));
    });

    test('Priority 2: Extension selection with .mp3 extension', () {
      final fileInfo = FileInfo(path: '/path/to/audio.mp3', mimeType: null);

      final loader = factory.selectParser(fileInfo, MockTokenizer());
      expect(loader, same(mp3Loader));
    });

    test('Priority 2: Extension selection with alternative extension', () {
      final fileInfo = FileInfo(path: '/path/to/audio.mpeg', mimeType: null);

      final loader = factory.selectParser(fileInfo, MockTokenizer());
      expect(loader, same(mp3Loader));
    });

    test('Priority 2: Extension selection is case-insensitive', () {
      final fileInfo = FileInfo(path: '/path/to/audio.FLAC', mimeType: null);

      final loader = factory.selectParser(fileInfo, MockTokenizer());
      expect(loader, same(flacLoader));
    });

    test('Priority 2: Handle multiple MIME types for same loader', () {
      final fileInfo = FileInfo(
        path: '/path/to/file.unknown',
        mimeType: 'application/ogg', // Second MIME type for OGG loader
      );

      final loader = factory.selectParser(fileInfo, MockTokenizer());
      expect(loader, same(oggLoader));
    });

    test('Error: No parser found when MIME and path are missing', () {
      final fileInfo = FileInfo(path: null, mimeType: null);

      expect(
        () => factory.selectParser(fileInfo, MockTokenizer()),
        throwsA(isA<CouldNotDetermineFileTypeError>()),
      );
    });

    test('Error: No parser found for unknown MIME type', () {
      final fileInfo = FileInfo(
        path: '/path/to/file.unknown',
        mimeType: 'audio/unknown',
      );

      expect(
        () => factory.selectParser(fileInfo, MockTokenizer()),
        throwsA(isA<CouldNotDetermineFileTypeError>()),
      );
    });

    test('Error: No parser found for unknown extension', () {
      final fileInfo = FileInfo(path: '/path/to/file.xyz', mimeType: null);

      expect(
        () => factory.selectParser(fileInfo, MockTokenizer()),
        throwsA(isA<CouldNotDetermineFileTypeError>()),
      );
    });

    test('Error: No parser found for file with no extension', () {
      final fileInfo = FileInfo(
        path: '/path/to/filename_without_extension',
        mimeType: null,
      );

      expect(
        () => factory.selectParser(fileInfo, MockTokenizer()),
        throwsA(isA<CouldNotDetermineFileTypeError>()),
      );
    });

    test('Error: No parser found for file ending with dot', () {
      final fileInfo = FileInfo(path: '/path/to/filename.', mimeType: null);

      expect(
        () => factory.selectParser(fileInfo, MockTokenizer()),
        throwsA(isA<CouldNotDetermineFileTypeError>()),
      );
    });

    test('Error message indicates what information was checked', () {
      final fileInfo = FileInfo(
        path: '/path/to/file.unknown',
        mimeType: 'audio/unknown',
      );

      expect(
        () => factory.selectParser(fileInfo, MockTokenizer()),
        throwsA(
          isA<CouldNotDetermineFileTypeError>().having(
            (e) => e.message,
            'message',
            contains('MIME type'),
          ),
        ),
      );
    });

    test('Extension extraction handles paths with multiple dots', () {
      final fileInfo = FileInfo(
        path: '/path/to/archive.tar.flac',
        mimeType: null,
      );

      final loader = factory.selectParser(fileInfo, MockTokenizer());
      expect(loader, same(flacLoader)); // Should extract 'flac'
    });

    test('Empty MIME type string is treated as missing', () {
      final fileInfo = FileInfo(
        path: '/path/to/file.flac',
        mimeType: '', // Empty string
      );

      final loader = factory.selectParser(fileInfo, MockTokenizer());
      expect(loader, same(flacLoader)); // Should fall through to extension
    });

    test('Empty path string is treated as missing', () {
      final fileInfo = FileInfo(
        path: '', // Empty string
        mimeType: 'audio/flac',
      );

      final loader = factory.selectParser(fileInfo, MockTokenizer());
      expect(loader, same(flacLoader));
    });
  });
}
