import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/apev2/apev2_token.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:metadata_audio/src/wavpack/wavpack_loader.dart';
import 'package:metadata_audio/src/wavpack/wavpack_parser.dart';
import 'package:test/test.dart';

void main() {
  group('WavPackParser / WavPackLoader', () {
    test('parses PCM WavPack block and tail APEv2 tags', () async {
      const totalSamples = 93744;
      final blockPayload = <int>[
        ..._metadataSubBlock(functionId: 0x26, data: _md5Sample()),
      ];

      final bytes = <int>[
        ..._buildWavPackBlock(
          blockIndex: 0,
          totalSamplesStored: totalSamples,
          blockSamples: totalSamples,
          flags: _buildFlags(bitsPerSample: 16, sampleRateIndex: 9),
          payload: blockPayload,
        ),
        ..._buildApev2FooterTag(
          items: <List<int>>[
            _textItem('Title', "Sinner's Prayer"),
            _textItem('Artist', 'Beth Hart'),
            _textItem('Artists', 'Beth Hart\u0000Joe Bonamassa'),
          ],
        ),
      ];

      final loader = WavPackLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.container, 'WavPack');
      expect(metadata.format.codec, 'PCM');
      expect(metadata.format.lossless, isTrue);
      expect(metadata.format.bitsPerSample, 16);
      expect(metadata.format.sampleRate, 44100);
      expect(metadata.format.numberOfChannels, 2);
      expect(metadata.format.numberOfSamples, totalSamples);
      expect(
        metadata.format.duration,
        closeTo(totalSamples / 44100.0, 0.0000001),
      );
      expect(metadata.format.audioMD5, equals(_md5Sample()));
      expect(metadata.format.bitrate, isNotNull);
      expect(metadata.common.title, "Sinner's Prayer");
      expect(metadata.common.artist, 'Beth Hart');
      expect(
        metadata.common.artists,
        equals(<String>['Beth Hart', 'Joe Bonamassa']),
      );
    });

    test('parses DSD metadata sub-block and updates sample rate', () async {
      final bytes = _buildWavPackBlock(
        blockIndex: 0,
        totalSamplesStored: 70560,
        blockSamples: 70560,
        flags: _buildFlags(bitsPerSample: 16, sampleRateIndex: 9, isDsd: true),
        payload: <int>[
          ..._metadataSubBlock(
            functionId: 0x0E,
            data: const <int>[4],
            oddSize: true,
          ),
        ],
      );

      final loader = WavPackLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.container, 'WavPack');
      expect(metadata.format.codec, 'DSD');
      expect(metadata.format.numberOfSamples, 564480);
      expect(metadata.format.sampleRate, 5644800);
      expect(metadata.format.duration, closeTo(0.1, 0.0000001));
    });

    test('throws on invalid metadata sub-block remaining size', () async {
      final invalidHeaderOnly = <int>[
        ...ascii.encode('wvpk'),
        ..._u32le(25),
        ..._u16le(0x410),
        0,
        0,
        ..._u32le(1000),
        ..._u32le(0),
        ..._u32le(1000),
        ..._u32le(_buildFlags(bitsPerSample: 16, sampleRateIndex: 9)),
        ..._u32le(0),
      ];

      final loader = WavPackLoader();
      await expectLater(
        loader.parse(
          BytesTokenizer(Uint8List.fromList(invalidHeaderOnly)),
          const ParseOptions(),
        ),
        throwsA(isA<WavPackContentError>()),
      );
    });

    test('loader declares extensions, MIME type and seek requirement', () {
      final loader = WavPackLoader();
      expect(loader.extension, equals(<String>['wv', 'wvp']));
      expect(loader.mimeType, equals(<String>['audio/wavpack']));
      expect(loader.hasRandomAccessRequirements, isTrue);
      expect(loader.supports(_NonSeekTokenizer()), isFalse);
    });
  });
}

List<int> _buildWavPackBlock({
  required int blockIndex,
  required int totalSamplesStored,
  required int blockSamples,
  required int flags,
  required List<int> payload,
}) {
  final blockSize = 24 + payload.length;
  return <int>[
    ...ascii.encode('wvpk'),
    ..._u32le(blockSize),
    ..._u16le(0x410),
    0,
    0,
    ..._u32le(totalSamplesStored),
    ..._u32le(blockIndex),
    ..._u32le(blockSamples),
    ..._u32le(flags),
    ..._u32le(0),
    ...payload,
  ];
}

List<int> _metadataSubBlock({
  required int functionId,
  required List<int> data,
  bool oddSize = false,
}) {
  final id = (functionId & 0x3F) | (oddSize ? 0x40 : 0);
  final words = ((data.length + (oddSize ? 1 : 0)) / 2).ceil();

  return <int>[id, words, ...data, if (oddSize) 0];
}

List<int> _buildApev2FooterTag({required List<List<int>> items}) {
  final payload = <int>[for (final item in items) ...item];
  final footer = _apeTagFooter(
    size: payload.length + Apev2Token.tagFooterLength,
    fields: items.length,
    flags: 0,
  );
  return <int>[...payload, ...footer];
}

List<int> _textItem(String key, String value) {
  final payload = utf8.encode(value);
  return <int>[
    ..._u32le(payload.length),
    ..._u32le(Apev2DataType.textUtf8 << 1),
    ...ascii.encode(key),
    0,
    ...payload,
  ];
}

List<int> _apeTagFooter({
  required int size,
  required int fields,
  required int flags,
}) => <int>[
  ...ascii.encode(Apev2Token.preamble),
  ..._u32le(2000),
  ..._u32le(size),
  ..._u32le(fields),
  ..._u32le(flags),
  ...List<int>.filled(8, 0),
];

int _buildFlags({
  required int bitsPerSample,
  required int sampleRateIndex,
  bool isMono = false,
  bool isHybrid = false,
  bool isDsd = false,
}) {
  final bytesPerSampleCode = ((bitsPerSample ~/ 8) - 1).clamp(0, 3);
  var flags = bytesPerSampleCode;
  if (isMono) {
    flags |= 1 << 2;
  }
  if (isHybrid) {
    flags |= 1 << 3;
  }
  flags |= (sampleRateIndex & 0x0F) << 23;
  if (isDsd) {
    flags |= 1 << 31;
  }
  return flags;
}

List<int> _md5Sample() => List<int>.generate(16, (index) => index);

List<int> _u16le(int value) => <int>[value & 0xFF, (value >> 8) & 0xFF];

List<int> _u32le(int value) => <int>[
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

class _NonSeekTokenizer extends Tokenizer {
  @override
  bool get canSeek => false;

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
