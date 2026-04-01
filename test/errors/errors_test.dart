import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

void main() {
  group('ParseError Hierarchy', () {
    test('CouldNotDetermineFileTypeError instantiates with message', () {
      const message = 'Unable to determine file type';
      final error = CouldNotDetermineFileTypeError(message);

      expect(error.message, equals(message));
      expect(error.name, equals('CouldNotDetermineFileTypeError'));
      expect(error.toString(), contains(message));
    });

    test('UnsupportedFileTypeError instantiates with message', () {
      const message = 'File type FLAC is not supported';
      final error = UnsupportedFileTypeError(message);

      expect(error.message, equals(message));
      expect(error.name, equals('UnsupportedFileTypeError'));
      expect(error.toString(), contains(message));
    });

    test('UnexpectedFileContentError includes fileType information', () {
      const fileType = 'mp3';
      const message = 'Invalid ID3 header';
      final error = UnexpectedFileContentError(fileType, message);

      expect(error.message, equals(message));
      expect(error.fileType, equals(fileType));
      expect(error.name, equals('UnexpectedFileContentError'));
      expect(error.toString(), contains(fileType));
      expect(error.toString(), contains(message));
    });

    test('FieldDecodingError instantiates with message', () {
      const message = 'Unable to decode UTF-8 field';
      final error = FieldDecodingError(message);

      expect(error.message, equals(message));
      expect(error.name, equals('FieldDecodingError'));
      expect(error.toString(), contains(message));
    });

    test('InternalParserError instantiates with message', () {
      const message = 'Unexpected state in parser';
      final error = InternalParserError(message);

      expect(error.message, equals(message));
      expect(error.name, equals('InternalParserError'));
      expect(error.toString(), contains(message));
    });

    test('All error types are instances of ParseError', () {
      expect(CouldNotDetermineFileTypeError('test'), isA<ParseError>());
      expect(UnsupportedFileTypeError('test'), isA<ParseError>());
      expect(UnexpectedFileContentError('mp3', 'test'), isA<ParseError>());
      expect(FieldDecodingError('test'), isA<ParseError>());
      expect(InternalParserError('test'), isA<ParseError>());
    });

    test('All error types implement Exception', () {
      expect(CouldNotDetermineFileTypeError('test'), isA<Exception>());
      expect(UnsupportedFileTypeError('test'), isA<Exception>());
      expect(UnexpectedFileContentError('mp3', 'test'), isA<Exception>());
      expect(FieldDecodingError('test'), isA<Exception>());
      expect(InternalParserError('test'), isA<Exception>());
    });
  });

  group('Invalid and unsupported input behavior', () {
    late ParserRegistry registry;

    setUp(() {
      registry = ParserRegistry();
      initializeParserFactory(ParserFactory(registry));
    });

    test('empty bytes throw CouldNotDetermineFileTypeError', () async {
      await expectLater(
        () => parseBytes(Uint8List(0)),
        throwsA(
          isA<CouldNotDetermineFileTypeError>().having(
            (error) => error.message,
            'message',
            contains('Could not determine file type'),
          ),
        ),
      );
    });

    test(
      'non-audio random bytes throw CouldNotDetermineFileTypeError',
      () async {
        final randomBytes = Uint8List.fromList([
          0x13,
          0x37,
          0xCA,
          0xFE,
          0xBA,
          0xBE,
          0x01,
          0x02,
        ]);

        await expectLater(
          () => parseBytes(
            randomBytes,
            fileInfo: const FileInfo(path: 'data.bin'),
          ),
          throwsA(isA<CouldNotDetermineFileTypeError>()),
        );
      },
    );

    test(
      'corrupted recognized content throws UnexpectedFileContentError',
      () async {
        registry.register(
          _TestParser(
            extension: const ['mp3'],
            mimeType: const ['audio/mpeg'],
            onParse: (_, _) async {
              throw UnexpectedFileContentError('mp3', 'Invalid frame header');
            },
          ),
        );

        await expectLater(
          () => parseBytes(
            Uint8List.fromList([0x49, 0x44, 0x33]),
            fileInfo: const FileInfo(
              path: 'broken.mp3',
              mimeType: 'audio/mpeg',
            ),
          ),
          throwsA(
            isA<UnexpectedFileContentError>()
                .having((error) => error.fileType, 'fileType', 'mp3')
                .having(
                  (error) => error.message,
                  'message',
                  contains('Invalid frame header'),
                ),
          ),
        );
      },
    );

    test('parser selection fails gracefully for unsupported format hints', () {
      final factory = ParserFactory(registry);

      expect(
        () => factory.selectParser(
          const FileInfo(path: 'tinytrans.gif', mimeType: 'image/gif'),
          _DummyTokenizer(),
        ),
        throwsA(
          isA<CouldNotDetermineFileTypeError>().having(
            (error) => error.message,
            'message',
            contains('MIME type'),
          ),
        ),
      );
    });

    test(
      'unsupported parser/tokenizer capabilities throw UnsupportedFileTypeError',
      () async {
        registry.register(
          _TestParser(
            mimeType: const ['audio/requires-seek'],
            hasRandomAccessRequirements: true,
          ),
        );

        await expectLater(
          () => parseFromTokenizer(
            _NonSeekTokenizer(const FileInfo(mimeType: 'audio/requires-seek')),
          ),
          throwsA(
            isA<UnsupportedFileTypeError>().having(
              (error) => error.message,
              'message',
              contains('requires random access'),
            ),
          ),
        );
      },
    );
  });
}

class _TestParser implements ParserLoader {
  _TestParser({
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
  bool supports(Tokenizer tokenizer) =>
      !hasRandomAccessRequirements || tokenizer.canSeek;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) async {
    if (onParse != null) {
      return onParse!(tokenizer, options);
    }
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

class _DummyTokenizer implements Tokenizer {
  @override
  bool get canSeek => true;

  @override
  bool get hasCompleteData => true;

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

class _NonSeekTokenizer implements Tokenizer {
  _NonSeekTokenizer(this._fileInfo);

  final FileInfo _fileInfo;

  @override
  bool get canSeek => false;

  @override
  bool get hasCompleteData => true;

  @override
  FileInfo? get fileInfo => _fileInfo;

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
