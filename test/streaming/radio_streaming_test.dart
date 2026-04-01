import 'dart:async';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

void main() {
  group('radio stream parsing', () {
    late ParserRegistry registry;
    late ParserFactory factory;

    setUp(() {
      registry = ParserRegistry();
      factory = ParserFactory(registry);
      initializeParserFactory(factory);
    });

    const oggRadioPayload = <int>[
      0x4f,
      0x67,
      0x67,
      0x53,
      0x00,
      0x02,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x11,
      0x22,
      0x33,
      0x44,
      0x01,
      0x1e,
      0x01,
      0x76,
      0x6f,
      0x72,
      0x62,
      0x69,
      0x73,
    ];

    const mp4RadioPayload = <int>[
      0x00,
      0x00,
      0x00,
      0x20,
      0x66,
      0x74,
      0x79,
      0x70,
      0x69,
      0x73,
      0x6f,
      0x6d,
      0x00,
      0x00,
      0x02,
      0x00,
      0x69,
      0x73,
      0x6f,
      0x6d,
      0x6d,
      0x70,
      0x34,
      0x31,
      0xaa,
      0xbb,
      0xcc,
      0xdd,
    ];

    test('parses Ogg radio stream from chunked non-seekable source', () async {
      List<int>? observedBytes;

      registry.register(
        _StreamingParserLoader(
          mimeType: const ['audio/ogg'],
          hasRandomAccessRequirements: false,
          onParse: (tokenizer, options) async {
            observedBytes = _drainTokenizer(tokenizer);
            return _mockOggMetadata();
          },
        ),
      );

      final metadata = await parseStream(
        _chunkedStream(oggRadioPayload, const [1, 2, 5, 3]),
        fileInfo: const FileInfo(mimeType: 'audio/ogg'),
      );

      expect(observedBytes, equals(oggRadioPayload));
      expect(metadata.format.container, equals('Ogg'));
      expect(metadata.format.codec, equals('Vorbis I'));
      expect(metadata.format.sampleRate, equals(44100));
    });

    test('parses MP4 radio stream when content-length is absent', () async {
      FileInfo? observedFileInfo;

      registry.register(
        _StreamingParserLoader(
          mimeType: const ['audio/mp4'],
          hasRandomAccessRequirements: true,
          onParse: (tokenizer, options) async {
            observedFileInfo = tokenizer.fileInfo;
            final observedBytes = _drainTokenizer(tokenizer);
            expect(observedBytes, equals(mp4RadioPayload));
            return _mockMp4Metadata();
          },
        ),
      );

      final metadata = await parseStream(
        _chunkedStream(mp4RadioPayload, const [4, 1, 8, 2]),
        fileInfo: const FileInfo(mimeType: 'audio/mp4'),
      );

      expect(observedFileInfo?.mimeType, equals('audio/mp4'));
      expect(observedFileInfo?.size, isNull);
      expect(metadata.format.container, equals('M4A/isom'));
      expect(metadata.format.codec, equals('MPEG-4/AAC'));
      expect(metadata.format.sampleRate, equals(48000));
    });

    test(
      'non-seekable tokenizer is accepted for Ogg parser capabilities',
      () async {
        var parseCalled = false;
        registry.register(
          _StreamingParserLoader(
            mimeType: const ['audio/ogg'],
            hasRandomAccessRequirements: false,
            onParse: (tokenizer, options) async {
              parseCalled = true;
              return _mockOggMetadata();
            },
          ),
        );

        final metadata = await parseFromTokenizer(
          _NonSeekableTokenizer(const FileInfo(mimeType: 'audio/ogg')),
        );

        expect(parseCalled, isTrue);
        expect(metadata.format.container, equals('Ogg'));
      },
    );
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

AudioMetadata _mockOggMetadata() => const AudioMetadata(
  format: Format(container: 'Ogg', codec: 'Vorbis I', sampleRate: 44100),
  native: {},
  common: CommonTags(
    title: 'Radio Ogg',
    track: TrackNo(),
    disk: TrackNo(),
    movementIndex: TrackNo(),
  ),
  quality: QualityInformation(),
);
AudioMetadata _mockMp4Metadata() => const AudioMetadata(
  format: Format(container: 'M4A/isom', codec: 'MPEG-4/AAC', sampleRate: 48000),
  native: {},
  common: CommonTags(
    title: 'Radio MP4',
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
  _NonSeekableTokenizer(this._fileInfo);

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
