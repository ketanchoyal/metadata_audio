import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/aiff/aiff_loader.dart';
import 'package:metadata_audio/src/aiff/aiff_token.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  group('AiffParser / AiffLoader', () {
    test('parses AIFF COMM/SSND and text tags', () async {
      final bytes = _buildAiffFile(
        type: 'AIFF',
        numChannels: 2,
        numSampleFrames: 8000,
        sampleSize: 16,
        sampleRate: 8000,
        ssndDataSize: 16000,
        textChunks: const <String, String>{
          'NAME': 'Unit Test Title',
          'AUTH': 'Unit Test Artist',
          'ANNO': 'Unit Test Comment',
          '(c) ': 'Unit Test Copyright',
        },
      );

      final metadata = await AiffLoader().parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(duration: true),
      );

      expect(metadata.format.container, 'AIFF');
      expect(metadata.format.lossless, isTrue);
      expect(metadata.format.codec, 'PCM');
      expect(metadata.format.sampleRate, 8000);
      expect(metadata.format.bitsPerSample, 16);
      expect(metadata.format.numberOfChannels, 2);
      expect(metadata.format.numberOfSamples, 8000);
      expect(metadata.format.duration, closeTo(1.0, 0.0001));
      expect(metadata.format.bitrate, 128064);
      expect(metadata.format.hasAudio, isTrue);
      expect(metadata.format.hasVideo, isFalse);

      expect(metadata.common.title, 'Unit Test Title');
      expect(metadata.common.artist, 'Unit Test Artist');
      expect(metadata.common.copyright, 'Unit Test Copyright');
      expect(metadata.common.comment, hasLength(1));
      expect(metadata.common.comment!.single.text, 'Unit Test Comment');

      final nativeTags = metadata.native['AIFF'];
      expect(nativeTags, isNotNull);
      expect(
        nativeTags!.where((tag) => tag.id == 'NAME').single.value,
        'Unit Test Title',
      );
      expect(
        nativeTags.where((tag) => tag.id == 'AUTH').single.value,
        'Unit Test Artist',
      );
    });

    test('parses AIFC codec fields', () async {
      final bytes = _buildAiffFile(
        type: 'AIFC',
        numChannels: 1,
        numSampleFrames: 4000,
        sampleSize: 16,
        sampleRate: 8000,
        compressionType: 'alaw',
        compressionName: 'Alaw 2:1',
        ssndDataSize: 4000,
      );

      final metadata = await AiffLoader().parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(duration: true),
      );

      expect(metadata.format.container, 'AIFF-C');
      expect(metadata.format.lossless, isFalse);
      expect(metadata.format.codec, 'Alaw 2:1');
      expect(metadata.format.duration, closeTo(0.5, 0.0001));
    });

    test('parses embedded ID3v2 chunk', () async {
      final id3Payload = _buildId3v23Tag(title: 'Title From AIFF ID3');
      final bytes = _buildAiffFile(
        type: 'AIFF',
        numChannels: 2,
        numSampleFrames: 44100,
        sampleSize: 16,
        sampleRate: 44100,
        ssndDataSize: 176400,
        id3Chunk: id3Payload,
      );

      final metadata = await AiffLoader().parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.common.title, 'Title From AIFF ID3');
      final id3Tags = metadata.native['ID3v2.3'];
      expect(id3Tags, isNotNull);
      expect(
        id3Tags!.where((tag) => tag.id == 'TIT2').single.value,
        'Title From AIFF ID3',
      );
    });

    test('throws on invalid FORM type', () async {
      final bytes = _buildForm('NOTA', const <List<int>>[]);

      await expectLater(
        AiffLoader().parse(
          BytesTokenizer(Uint8List.fromList(bytes)),
          const ParseOptions(),
        ),
        throwsA(isA<AiffContentError>()),
      );
    });

    test('loader declares extensions, MIME types and seek requirement', () {
      final loader = AiffLoader();

      expect(loader.extension, containsAll(<String>['aiff', 'aif', 'aifc']));
      expect(
        loader.mimeType,
        containsAll(<String>['audio/aiff', 'audio/x-aiff', 'sound/aiff']),
      );
      expect(loader.hasRandomAccessRequirements, isTrue);
      expect(loader.supports(_NonSeekTokenizer()), isFalse);
    });
  });
}

List<int> _buildAiffFile({
  required String type,
  required int numChannels,
  required int numSampleFrames,
  required int sampleSize,
  required int sampleRate,
  required int ssndDataSize,
  Map<String, String> textChunks = const <String, String>{},
  String compressionType = 'NONE',
  String? compressionName,
  List<int>? id3Chunk,
}) {
  final chunks = <List<int>>[];

  final commPayload = <int>[
    ..._u16be(numChannels),
    ..._u32be(numSampleFrames),
    ..._u16be(sampleSize),
    ..._sampleRateExtended80(sampleRate),
  ];

  if (type == 'AIFC') {
    commPayload.addAll(ascii.encode(compressionType));
    if (compressionName != null) {
      final nameBytes = latin1.encode(compressionName);
      commPayload.add(nameBytes.length);
      commPayload.addAll(nameBytes);
      if ((nameBytes.length + 1).isOdd) {
        commPayload.add(0);
      }
    }
  }

  chunks.add(_chunk('COMM', commPayload));

  for (final entry in textChunks.entries) {
    chunks.add(_chunk(entry.key, ascii.encode(entry.value)));
  }

  if (id3Chunk != null) {
    chunks.add(_chunk('ID3 ', id3Chunk));
  }

  final ssndPayload = <int>[
    ..._u32be(0),
    ..._u32be(0),
    ...List<int>.filled(ssndDataSize, 0),
  ];
  chunks.add(_chunk('SSND', ssndPayload));

  return _buildForm(type, chunks);
}

List<int> _buildForm(String type, List<List<int>> chunks) {
  final payload = <int>[
    ...ascii.encode(type),
    for (final chunk in chunks) ...chunk,
  ];
  return <int>[...ascii.encode('FORM'), ..._u32be(payload.length), ...payload];
}

List<int> _chunk(String id, List<int> payload) {
  final padded = payload.length.isOdd ? <int>[...payload, 0] : payload;
  return <int>[...ascii.encode(id), ..._u32be(payload.length), ...padded];
}

List<int> _sampleRateExtended80(int sampleRate) => <int>[
    0x40,
    0x0E,
    (sampleRate >> 8) & 0xFF,
    sampleRate & 0xFF,
    0,
    0,
    0,
    0,
    0,
    0,
  ];

List<int> _buildId3v23Tag({required String title}) {
  final titlePayload = <int>[0x00, ...latin1.encode(title)];
  final frame = <int>[
    ...ascii.encode('TIT2'),
    ..._u32be(titlePayload.length),
    0x00,
    0x00,
    ...titlePayload,
  ];

  return <int>[
    ...ascii.encode('ID3'),
    0x03,
    0x00,
    0x00,
    ..._synchsafe(frame.length),
    ...frame,
  ];
}

List<int> _u16be(int value) => <int>[(value >> 8) & 0xFF, value & 0xFF];

List<int> _u32be(int value) => <int>[
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];

List<int> _synchsafe(int value) => <int>[
    (value >> 21) & 0x7F,
    (value >> 14) & 0x7F,
    (value >> 7) & 0x7F,
    value & 0x7F,
  ];

class _NonSeekTokenizer extends Tokenizer {
  @override
  bool get canSeek => false;

  @override
  FileInfo? get fileInfo => const FileInfo();

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
