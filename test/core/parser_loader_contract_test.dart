import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/parser_factory.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

class MockTokenizer implements Tokenizer {
  MockTokenizer({required this.canSeek});

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

class TestParserLoader extends ParserLoader {
  TestParserLoader({
    required this.extension,
    required this.mimeType,
    required this.hasRandomAccessRequirements,
  });

  @override
  final List<String> extension;

  @override
  final List<String> mimeType;

  @override
  final bool hasRandomAccessRequirements;

  bool parseWasCalled = false;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    parseWasCalled = true;
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

void main() {
  group('ParserLoader Contract', () {
    test('extension and mimeType are list properties', () {
      final loader = TestParserLoader(
        extension: ['mp3', 'mpeg'],
        mimeType: ['audio/mpeg'],
        hasRandomAccessRequirements: false,
      );

      expect(loader.extension, equals(['mp3', 'mpeg']));
      expect(loader.mimeType, equals(['audio/mpeg']));
      expect(loader.extension, isA<List<String>>());
      expect(loader.mimeType, isA<List<String>>());
    });

    test('supports() returns true when random access is not required', () {
      final loader = TestParserLoader(
        extension: ['mp3'],
        mimeType: ['audio/mpeg'],
        hasRandomAccessRequirements: false,
      );

      final nonSeekableTokenizer = MockTokenizer(canSeek: false);
      expect(loader.supports(nonSeekableTokenizer), isTrue);
    });

    test(
      'supports() returns false when random access is required but unavailable',
      () {
        final loader = TestParserLoader(
          extension: ['flac'],
          mimeType: ['audio/flac'],
          hasRandomAccessRequirements: true,
        );

        final nonSeekableTokenizer = MockTokenizer(canSeek: false);
        expect(loader.supports(nonSeekableTokenizer), isFalse);
      },
    );

    test(
      'supports() returns true when random access is required and available',
      () {
        final loader = TestParserLoader(
          extension: ['flac'],
          mimeType: ['audio/flac'],
          hasRandomAccessRequirements: true,
        );

        final seekableTokenizer = MockTokenizer(canSeek: true);
        expect(loader.supports(seekableTokenizer), isTrue);
      },
    );

    test('parse() can be implemented and invoked', () async {
      final loader = TestParserLoader(
        extension: ['mp3'],
        mimeType: ['audio/mpeg'],
        hasRandomAccessRequirements: false,
      );

      final metadata = await loader.parse(
        MockTokenizer(canSeek: true),
        const ParseOptions(),
      );

      expect(loader.parseWasCalled, isTrue);
      expect(metadata, isA<AudioMetadata>());
    });
  });
}
