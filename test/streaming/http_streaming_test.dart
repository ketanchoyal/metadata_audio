import 'dart:async';

import 'package:audio_metadata/audio_metadata.dart';
import 'package:test/test.dart';

void main() {
  group('HTTP streaming', () {
    late ParserRegistry registry;
    late ParserFactory factory;

    setUp(() {
      registry = ParserRegistry();
      factory = ParserFactory(registry);
      initializeParserFactory(factory);
    });

    const httpM4aPayload = <int>[
      0x00,
      0x00,
      0x00,
      0x18,
      0x66,
      0x74,
      0x79,
      0x70,
      0x4d,
      0x34,
      0x41,
      0x20,
      0x00,
      0x00,
      0x00,
      0x00,
      0x69,
      0x73,
      0x6f,
      0x6d,
      0x6d,
      0x70,
      0x34,
      0x32,
      0x01,
      0x23,
      0x45,
      0x67,
      0x89,
      0xab,
      0xcd,
      0xef,
    ];

    test(
      'parses HTTP stream with content-length metadata and accumulates chunks',
      () async {
        var parserCalled = false;
        FileInfo? observedFileInfo;
        List<int>? observedBytes;

        registry.register(
          _StreamingParserLoader(
            mimeType: const ['audio/mp4'],
            hasRandomAccessRequirements: true,
            onParse: (tokenizer, options) async {
              parserCalled = true;
              observedFileInfo = tokenizer.fileInfo;
              observedBytes = _drainTokenizer(tokenizer);
              return _mockHttpMetadata();
            },
          ),
        );

        final stream = _chunkedStream(httpM4aPayload, const [2, 5, 3, 7]);
        final metadata = await parseStream(
          stream,
          fileInfo: FileInfo(
            mimeType: 'audio/mp4',
            size: httpM4aPayload.length,
          ),
        );

        expect(parserCalled, isTrue);
        expect(observedFileInfo?.mimeType, equals('audio/mp4'));
        expect(observedFileInfo?.size, equals(httpM4aPayload.length));
        expect(observedBytes, equals(httpM4aPayload));

        expect(metadata.format.container, equals('M4A/mp42/isom'));
        expect(metadata.format.codec, equals('MPEG-4/AAC'));
        expect(metadata.format.lossless, isFalse);
        expect(
          metadata.common.title,
          equals('Super Mario Galaxy "Into The Galaxy"'),
        );
        expect(
          metadata.common.artist,
          equals('club nintendo CD "SUPER MARIO GALAXY"より'),
        );
        expect(
          metadata.common.album,
          equals('SUPER MARIO GALAXY ORIGINAL SOUNDTRACK'),
        );
      },
    );

    test('parses HTTP stream when content-length is missing', () async {
      FileInfo? observedFileInfo;

      registry.register(
        _StreamingParserLoader(
          mimeType: const ['audio/mp4'],
          hasRandomAccessRequirements: true,
          onParse: (tokenizer, options) async {
            observedFileInfo = tokenizer.fileInfo;
            _drainTokenizer(tokenizer);
            return _mockHttpMetadata();
          },
        ),
      );

      final stream = _chunkedStream(httpM4aPayload, const [1, 1, 4, 8, 3]);
      final metadata = await parseStream(
        stream,
        fileInfo: const FileInfo(mimeType: 'audio/mp4'),
      );

      expect(observedFileInfo?.mimeType, equals('audio/mp4'));
      expect(observedFileInfo?.size, isNull);
      expect(metadata.format.container, equals('M4A/mp42/isom'));
      expect(metadata.format.codec, equals('MPEG-4/AAC'));
    });

    test('parseFromTokenizer rejects non-seekable tokenizer '
        'for random-access parser', () async {
      registry.register(
        _StreamingParserLoader(
          mimeType: const ['audio/mp4'],
          hasRandomAccessRequirements: true,
          onParse: (tokenizer, options) async => _mockHttpMetadata(),
        ),
      );

      await expectLater(
        () => parseFromTokenizer(_NonSeekableTokenizer()),
        throwsA(
          isA<UnsupportedFileTypeError>().having(
            (error) => error.message,
            'message',
            contains('requires random access'),
          ),
        ),
      );
    });
  });
}

List<int> _drainTokenizer(Tokenizer tokenizer) {
  final bytes = <int>[];
  try {
    while (true) {
      bytes.add(tokenizer.readUint8());
    }
  } on TokenizerException {
    // End of stream.
  }
  return bytes;
}

Stream<List<int>> _chunkedStream(
  List<int> bytes,
  List<int> chunkPattern,
) async* {
  var offset = 0;
  var chunkIndex = 0;

  while (offset < bytes.length) {
    final chunkSize = chunkPattern[chunkIndex % chunkPattern.length];
    final end = (offset + chunkSize).clamp(0, bytes.length);
    yield bytes.sublist(offset, end);
    offset = end;
    chunkIndex++;
    await Future<void>.delayed(Duration.zero);
  }
}

AudioMetadata _mockHttpMetadata() => const AudioMetadata(
  format: Format(
    container: 'M4A/mp42/isom',
    codec: 'MPEG-4/AAC',
    lossless: false,
    sampleRate: 44100,
  ),
  native: {},
  common: CommonTags(
    title: 'Super Mario Galaxy "Into The Galaxy"',
    artist: 'club nintendo CD "SUPER MARIO GALAXY"より',
    album: 'SUPER MARIO GALAXY ORIGINAL SOUNDTRACK',
    track: TrackNo(),
    disk: TrackNo(),
    movementIndex: TrackNo(),
  ),
  quality: QualityInformation(),
);

class _StreamingParserLoader extends ParserLoader {
  _StreamingParserLoader({
    required this.mimeType,
    required this.hasRandomAccessRequirements,
    required this.onParse,
  });

  @override
  final List<String> mimeType;

  @override
  final bool hasRandomAccessRequirements;

  final Future<AudioMetadata> Function(
    Tokenizer tokenizer,
    ParseOptions options,
  )
  onParse;

  @override
  List<String> get extension => const [];

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) =>
      onParse(tokenizer, options);
}

class _NonSeekableTokenizer implements Tokenizer {
  @override
  bool get canSeek => false;

  @override
  FileInfo? get fileInfo => const FileInfo(mimeType: 'audio/mp4');

  @override
  int get position => 0;

  @override
  int peekUint8() => throw TokenizerException('peek unsupported');

  @override
  List<int> peekBytes(int length) =>
      throw TokenizerException('peek unsupported');

  @override
  int readUint8() => throw TokenizerException('read unsupported');

  @override
  int readUint16() => throw TokenizerException('read unsupported');

  @override
  int readUint32() => throw TokenizerException('read unsupported');

  @override
  List<int> readBytes(int length) =>
      throw TokenizerException('read unsupported');

  @override
  void seek(int position) => throw TokenizerException('seek unsupported');

  @override
  void skip(int length) => throw TokenizerException('skip unsupported');
}
