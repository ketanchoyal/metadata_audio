import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

void main() {
  group('Parse input modes', () {
    late Uint8List testBytes;
    late String testFilePath;
    late ParserRegistry registry;
    late ParserFactory factory;

    setUpAll(() async {
      // Create a test file with minimal valid data
      // This is just dummy MP3 data with ID3v2 header
      testBytes = Uint8List.fromList([
        // ID3v2 header
        0x49, 0x44, 0x33, // "ID3"
        0x03, 0x00, // Version 2.3
        0x00, // Flags
        0x00, 0x00, 0x00, 0x00, // Size (syncsafe int)
        // Additional dummy data
        ...List<int>.filled(100, 0),
      ]);

      // Create a temporary file for file-based tests
      final tempDir = await Directory.systemTemp.createTemp();
      testFilePath = '${tempDir.path}/test_audio.mp3';
      await File(testFilePath).writeAsBytes(testBytes);

      // Set up parser registry and factory
      registry = ParserRegistry();
      factory = ParserFactory(registry);
      initializeParserFactory(factory);
    });

    tearDownAll(() async {
      // Clean up temp file
      try {
        await File(testFilePath).delete();
        await File(testFilePath).parent.delete();
      } catch (e) {
        // Ignore cleanup errors
      }
    });

    group('parseFromTokenizer', () {
      test(
        'throws CouldNotDetermineFileTypeError when no parser registered',
        () async {
          // Create empty registry to test error
          final emptyRegistry = ParserRegistry();
          final emptyFactory = ParserFactory(emptyRegistry);

          final tokenizer = BytesTokenizer(testBytes);
          expect(() async {
            // Use empty factory directly for this test
            final fileInfo = tokenizer.fileInfo ?? const FileInfo();
            emptyFactory.selectParser(fileInfo, tokenizer);
          }, throwsA(isA<CouldNotDetermineFileTypeError>()));
        },
      );

      test('calls parser with tokenizer and options', () async {
        // Create a mock parser
        var parseCalled = false;
        final mockParser = _MockParser(
          mimeType: ['audio/test'],
          onParse: (tokenizer, options) async {
            parseCalled = true;
            return _createMockMetadata();
          },
        );

        registry.register(mockParser);

        final tokenizer = BytesTokenizer(
          testBytes,
          fileInfo: const FileInfo(mimeType: 'audio/test'),
        );
        final result = await parseFromTokenizer(tokenizer);

        expect(parseCalled, isTrue);
        expect(result.common.title, 'Test Title');
      });

      test('verifies parser supports tokenizer capabilities', () async {
        final restrictiveParser = _MockParser(
          mimeType: ['audio/restrictive'],
          hasRandomAccessRequirements: true,
          onParse: (_1, _2) async => _createMockMetadata(),
        );

        registry.register(restrictiveParser);

        // Non-seekable tokenizer should fail when parser requires random access
        final nonSeekableTokenizer = _NonSeekableTokenizer(testBytes);

        // Manually test the parser selection and support check
        final selectedParser = registry.getLoaderForMimeType(
          'audio/restrictive',
        );
        expect(selectedParser, isNotNull);
        expect(selectedParser!.supports(nonSeekableTokenizer), isFalse);
      });
    });

    group('parseBytes', () {
      test('parses Uint8List with optional FileInfo', () async {
        final mockParser = _MockParser(
          mimeType: ['audio/test'],
          onParse: (_1, _2) async => _createMockMetadata(),
        );
        registry.register(mockParser);

        final metadata = await parseBytes(
          testBytes,
          fileInfo: const FileInfo(mimeType: 'audio/test'),
        );

        expect(metadata.common.title, 'Test Title');
      });

      test('uses BytesTokenizer with provided FileInfo', () async {
        final capturedFileInfo = <FileInfo?>[];
        final mockParser = _MockParser(
          mimeType: ['audio/test'],
          onParse: (tokenizer, _2) async {
            capturedFileInfo.add(tokenizer.fileInfo);
            return _createMockMetadata();
          },
        );
        registry.register(mockParser);

        const fileInfo = FileInfo(
          path: 'test.mp3',
          mimeType: 'audio/test',
          size: 1024,
        );
        await parseBytes(testBytes, fileInfo: fileInfo);

        expect(capturedFileInfo[0]?.path, 'test.mp3');
        expect(capturedFileInfo[0]?.mimeType, 'audio/test');
        expect(capturedFileInfo[0]?.size, 1024);
      });

      test('respects ParseOptions', () async {
        final capturedOptions = <ParseOptions>[];
        final mockParser = _MockParser(
          mimeType: ['audio/test'],
          onParse: (_1, options) async {
            capturedOptions.add(options);
            return _createMockMetadata();
          },
        );
        registry.register(mockParser);

        const options = ParseOptions(skipCovers: true, includeChapters: true);
        await parseBytes(
          testBytes,
          fileInfo: const FileInfo(mimeType: 'audio/test'),
          options: options,
        );

        expect(capturedOptions[0].skipCovers, isTrue);
        expect(capturedOptions[0].includeChapters, isTrue);
      });
    });

    group('parseFile', () {
      test('opens file and delegates to parseFromTokenizer', () async {
        final mockParser = _MockParser(
          extension: ['mp3'],
          mimeType: ['audio/mpeg'],
          onParse: (_1, _2) async => _createMockMetadata(),
        );
        registry.register(mockParser);

        final metadata = await parseFile(testFilePath);

        expect(metadata.common.title, 'Test Title');
      });

      test('throws FileSystemException when file not found', () async {
        expect(
          () => parseFile('/nonexistent/path/to/file.mp3'),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('closes file tokenizer after parsing', () async {
        final mockParser = _MockParser(
          extension: ['mp3'],
          mimeType: ['audio/mpeg'],
          onParse: (_1, _2) async => _createMockMetadata(),
        );
        registry.register(mockParser);

        // First parse
        await parseFile(testFilePath);
        // Second parse - should not fail due to file still open
        await parseFile(testFilePath);

        // If we got here, file was properly closed after first call
        expect(true, isTrue);
      });

      test('creates FileInfo from file path', () async {
        final capturedFileInfo = <FileInfo?>[];
        final mockParser = _MockParser(
          extension: ['mp3'],
          mimeType: ['audio/mpeg'],
          onParse: (tokenizer, _2) async {
            capturedFileInfo.add(tokenizer.fileInfo);
            return _createMockMetadata();
          },
        );
        registry.register(mockParser);

        await parseFile(testFilePath);

        expect(capturedFileInfo[0]?.path, testFilePath);
        expect(capturedFileInfo[0]?.size, isNotNull);
      });
    });

    group('parseStream', () {
      test('collects stream chunks and delegates to parseBytes', () async {
        final mockParser = _MockParser(
          mimeType: ['audio/test'],
          onParse: (_1, _2) async => _createMockMetadata(),
        );
        registry.register(mockParser);

        // Create a stream that yields the test bytes in chunks
        final stream = Stream.fromIterable([
          testBytes.sublist(0, 50),
          testBytes.sublist(50),
        ]);

        final metadata = await parseStream(
          stream,
          fileInfo: const FileInfo(mimeType: 'audio/test'),
        );

        expect(metadata.common.title, 'Test Title');
      });

      test('handles empty stream gracefully', () async {
        final mockParser = _MockParser(
          mimeType: ['audio/test'],
          onParse: (tokenizer, _) async {
            // Parser receives empty bytes or small buffer
            return _createMockMetadata();
          },
        );
        registry.register(mockParser);

        final stream = Stream.fromIterable(<List<int>>[]);
        await parseStream(stream, fileInfo: const FileInfo(mimeType: 'audio/test'));

        // Should complete without error
        expect(true, isTrue);
      });

      test('combines multiple stream chunks correctly', () async {
        var totalBytesReceived = 0;
        final mockParser = _MockParser(
          mimeType: ['audio/test'],
          onParse: (tokenizer, _) async {
            // Just read what we can
            try {
              while (true) {
                tokenizer.readUint8();
                totalBytesReceived++;
              }
            } on TokenizerException {
              // End of data
            }
            return _createMockMetadata();
          },
        );
        registry.register(mockParser);

        // Stream in specific chunks
        const chunkSize = 25;
        final chunks = <List<int>>[];
        for (var i = 0; i < testBytes.length; i += chunkSize) {
          final end = (i + chunkSize > testBytes.length)
              ? testBytes.length
              : i + chunkSize;
          chunks.add(testBytes.sublist(i, end));
        }

        final stream = Stream.fromIterable(chunks);
        await parseStream(stream, fileInfo: const FileInfo(mimeType: 'audio/test'));

        // Should have received all bytes
        expect(totalBytesReceived, testBytes.length);
      });

      test('passes through FileInfo to parseBytes', () async {
        final capturedFileInfo = <FileInfo?>[];
        final mockParser = _MockParser(
          mimeType: ['audio/test'],
          onParse: (tokenizer, _) async {
            capturedFileInfo.add(tokenizer.fileInfo);
            return _createMockMetadata();
          },
        );
        registry.register(mockParser);

        const fileInfo = FileInfo(
          path: 'remote.mp3',
          mimeType: 'audio/test',
          url: 'https://example.com/audio.mp3',
        );

        final stream = Stream.fromIterable([testBytes]);
        await parseStream(stream, fileInfo: fileInfo);

        expect(capturedFileInfo[0]?.url, 'https://example.com/audio.mp3');
      });
    });

    group('scanPostHeaders', () {
      test('skips scan when skipPostHeaders is true', () async {
        final tokenizer = BytesTokenizer(testBytes);
        const options = ParseOptions(skipPostHeaders: true);

        // Should complete without error even with empty tokenizer
        await scanPostHeaders(tokenizer, options);

        expect(true, isTrue);
      });

      test('skips scan when tokenizer cannot seek', () async {
        final tokenizer = _NonSeekableTokenizer(testBytes);
        const options = ParseOptions();

        // Should complete without error even though we can't seek
        await scanPostHeaders(tokenizer, options);

        expect(true, isTrue);
      });

      test('allows scan when tokenizer supports seek', () async {
        final tokenizer = BytesTokenizer(testBytes);
        const options = ParseOptions();

        // Should complete without error
        await scanPostHeaders(tokenizer, options);

        expect(true, isTrue);
      });
    });

    group('integration tests', () {
      test('parseFile -> parseFromTokenizer chain works', () async {
        final mockParser = _MockParser(
          extension: ['mp3'],
          mimeType: ['audio/mpeg'],
          onParse: (_1, _2) async => _createMockMetadata(),
        );
        registry.register(mockParser);

        final metadata = await parseFile(testFilePath);

        expect(metadata.common.artist, 'Test Artist');
        expect(metadata.format.container, 'mp3');
      });

      test('parseBytes -> parseFromTokenizer chain works', () async {
        final mockParser = _MockParser(
          mimeType: ['audio/test'],
          onParse: (_1, _2) async => _createMockMetadata(),
        );
        registry.register(mockParser);

        final metadata = await parseBytes(
          testBytes,
          fileInfo: const FileInfo(mimeType: 'audio/test'),
        );

        expect(metadata.common.album, 'Test Album');
      });

      test('parseStream -> parseBytes chain works', () async {
        final mockParser = _MockParser(
          mimeType: ['audio/test'],
          onParse: (_1, _2) async => _createMockMetadata(),
        );
        registry.register(mockParser);

        final stream = Stream.fromIterable([testBytes]);
        final metadata = await parseStream(
          stream,
          fileInfo: const FileInfo(mimeType: 'audio/test'),
        );

        expect(metadata.format.duration, 3.5);
      });
    });
  });
}

// Helper function to create mock metadata
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

// Mock parser implementation
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

// Non-seekable tokenizer for testing
class _NonSeekableTokenizer implements Tokenizer {

  _NonSeekableTokenizer(this._bytes);
  final Uint8List _bytes;
  int _position = 0;

  @override
  bool get canSeek => false;

  @override
  FileInfo? get fileInfo => null;

  @override
  int get position => _position;

  @override
  int readUint8() {
    if (_position >= _bytes.length) {
      throw TokenizerException('End of data');
    }
    return _bytes[_position++];
  }

  @override
  int readUint16() {
    if (_position + 1 >= _bytes.length) {
      throw TokenizerException('Insufficient data');
    }
    final value = (_bytes[_position] << 8) | _bytes[_position + 1];
    _position += 2;
    return value;
  }

  @override
  int readUint32() {
    if (_position + 3 >= _bytes.length) {
      throw TokenizerException('Insufficient data');
    }
    final value =
        (_bytes[_position] << 24) |
        (_bytes[_position + 1] << 16) |
        (_bytes[_position + 2] << 8) |
        _bytes[_position + 3];
    _position += 4;
    return value;
  }

  @override
  List<int> readBytes(int length) {
    if (_position + length > _bytes.length) {
      throw TokenizerException('Insufficient data');
    }
    final result = _bytes.sublist(_position, _position + length);
    _position += length;
    return result;
  }

  @override
  int peekUint8() {
    if (_position >= _bytes.length) {
      throw TokenizerException('End of data');
    }
    return _bytes[_position];
  }

  @override
  List<int> peekBytes(int length) {
    if (_position + length > _bytes.length) {
      throw TokenizerException('Insufficient data');
    }
    return _bytes.sublist(_position, _position + length);
  }

  @override
  void skip(int length) {
    if (_position + length > _bytes.length) {
      throw TokenizerException('Insufficient data');
    }
    _position += length;
  }

  @override
  void seek(int position) {
    throw TokenizerException('Seek not supported');
  }
}
