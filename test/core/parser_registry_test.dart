import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parser_factory.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

class MockTokenizer implements Tokenizer {
  @override
  bool get hasCompleteData => true;
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

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async => const AudioMetadata(
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

void main() {
  group('ParserRegistry', () {
    late ParserRegistry registry;

    setUp(() {
      registry = ParserRegistry();
    });

    test('registers a parser by extension', () {
      final loader = TestParserLoader(
        extension: ['mp3', 'mpeg'],
        mimeType: ['audio/mpeg'],
        hasRandomAccessRequirements: false,
      );

      registry.register(loader);

      expect(registry.getLoader('mp3'), equals(loader));
      expect(registry.getLoader('mpeg'), equals(loader));
    });

    test('extension lookup is case-insensitive', () {
      final loader = TestParserLoader(
        extension: ['mp3'],
        mimeType: ['audio/mpeg'],
        hasRandomAccessRequirements: false,
      );

      registry.register(loader);

      expect(registry.getLoader('mp3'), equals(loader));
      expect(registry.getLoader('MP3'), equals(loader));
      expect(registry.getLoader('Mp3'), equals(loader));
    });

    test('registers a parser by MIME type', () {
      final loader = TestParserLoader(
        extension: ['mp3'],
        mimeType: ['audio/mpeg'],
        hasRandomAccessRequirements: false,
      );

      registry.register(loader);

      expect(registry.getLoaderForMimeType('audio/mpeg'), equals(loader));
    });

    test('returns null when no loader found for extension', () {
      expect(registry.getLoader('unknown'), isNull);
    });

    test('returns null when no loader found for MIME type', () {
      expect(registry.getLoaderForMimeType('audio/unknown'), isNull);
    });

    test('getRegisteredExtensions returns sorted list', () {
      final loader1 = TestParserLoader(
        extension: ['mp3', 'mpeg'],
        mimeType: ['audio/mpeg'],
        hasRandomAccessRequirements: false,
      );

      final loader2 = TestParserLoader(
        extension: ['flac'],
        mimeType: ['audio/flac'],
        hasRandomAccessRequirements: false,
      );

      registry.register(loader1);
      registry.register(loader2);

      final extensions = registry.getRegisteredExtensions();
      // Verify it's sorted
      expect(extensions, equals(extensions..sort()));
      // Verify it contains all expected extensions
      expect(extensions, containsAll(['flac', 'mpeg', 'mp3']));
    });

    test('getRegisteredMimeTypes returns sorted list', () {
      final loader1 = TestParserLoader(
        extension: ['mp3'],
        mimeType: ['audio/mpeg'],
        hasRandomAccessRequirements: false,
      );

      final loader2 = TestParserLoader(
        extension: ['flac'],
        mimeType: ['audio/flac'],
        hasRandomAccessRequirements: false,
      );

      registry.register(loader1);
      registry.register(loader2);

      final mimeTypes = registry.getRegisteredMimeTypes();
      // Verify it's sorted
      expect(mimeTypes, equals(mimeTypes..sort()));
      // Verify it contains all expected MIME types
      expect(mimeTypes, containsAll(['audio/flac', 'audio/mpeg']));
    });

    test('overwrites existing extension mapping when registering twice', () {
      final loader1 = TestParserLoader(
        extension: ['mp3'],
        mimeType: ['audio/mpeg'],
        hasRandomAccessRequirements: false,
      );

      final loader2 = TestParserLoader(
        extension: ['mp3'],
        mimeType: ['audio/mpeg-v2'],
        hasRandomAccessRequirements: true,
      );

      registry.register(loader1);
      expect(registry.getLoader('mp3'), equals(loader1));

      registry.register(loader2);
      expect(registry.getLoader('mp3'), equals(loader2));
    });

    test('registers multiple loaders with different extensions', () {
      final mp3Loader = TestParserLoader(
        extension: ['mp3', 'mpeg'],
        mimeType: ['audio/mpeg'],
        hasRandomAccessRequirements: false,
      );

      final flacLoader = TestParserLoader(
        extension: ['flac'],
        mimeType: ['audio/flac'],
        hasRandomAccessRequirements: false,
      );

      final wavLoader = TestParserLoader(
        extension: ['wav', 'wave'],
        mimeType: ['audio/wav', 'audio/wave'],
        hasRandomAccessRequirements: false,
      );

      registry.register(mp3Loader);
      registry.register(flacLoader);
      registry.register(wavLoader);

      expect(registry.getLoader('mp3'), equals(mp3Loader));
      expect(registry.getLoader('flac'), equals(flacLoader));
      expect(registry.getLoader('wav'), equals(wavLoader));
      expect(registry.getLoader('wave'), equals(wavLoader));

      expect(registry.getLoaderForMimeType('audio/mpeg'), equals(mp3Loader));
      expect(registry.getLoaderForMimeType('audio/flac'), equals(flacLoader));
      expect(registry.getLoaderForMimeType('audio/wav'), equals(wavLoader));
      expect(registry.getLoaderForMimeType('audio/wave'), equals(wavLoader));
    });

    test('lists all registered extensions', () {
      final mp3Loader = TestParserLoader(
        extension: ['mp3', 'mpeg'],
        mimeType: ['audio/mpeg'],
        hasRandomAccessRequirements: false,
      );

      final flacLoader = TestParserLoader(
        extension: ['flac'],
        mimeType: ['audio/flac'],
        hasRandomAccessRequirements: false,
      );

      registry.register(mp3Loader);
      registry.register(flacLoader);

      final extensions = registry.getRegisteredExtensions();
      expect(extensions.length, equals(3));
      expect(extensions, contains('mp3'));
      expect(extensions, contains('mpeg'));
      expect(extensions, contains('flac'));
    });

    test('lists all registered MIME types', () {
      final mp3Loader = TestParserLoader(
        extension: ['mp3'],
        mimeType: ['audio/mpeg'],
        hasRandomAccessRequirements: false,
      );

      final flacLoader = TestParserLoader(
        extension: ['flac'],
        mimeType: ['audio/flac'],
        hasRandomAccessRequirements: false,
      );

      registry.register(mp3Loader);
      registry.register(flacLoader);

      final mimeTypes = registry.getRegisteredMimeTypes();
      expect(mimeTypes.length, equals(2));
      expect(mimeTypes, contains('audio/mpeg'));
      expect(mimeTypes, contains('audio/flac'));
    });

    test('handles empty registry gracefully', () {
      expect(registry.getLoader('mp3'), isNull);
      expect(registry.getLoaderForMimeType('audio/mpeg'), isNull);
      expect(registry.getRegisteredExtensions(), isEmpty);
      expect(registry.getRegisteredMimeTypes(), isEmpty);
    });

    test('supports multiple MIME types per loader', () {
      final loader = TestParserLoader(
        extension: ['ogg', 'oga'],
        mimeType: ['audio/ogg', 'audio/vorbis', 'audio/x-vorbis'],
        hasRandomAccessRequirements: false,
      );

      registry.register(loader);

      expect(registry.getLoaderForMimeType('audio/ogg'), equals(loader));
      expect(registry.getLoaderForMimeType('audio/vorbis'), equals(loader));
      expect(registry.getLoaderForMimeType('audio/x-vorbis'), equals(loader));
    });
  });
}
