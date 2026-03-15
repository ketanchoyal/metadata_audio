import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/dsf/dsf_chunk.dart';
import 'package:metadata_audio/src/dsf/dsf_loader.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  group('DsfParser / DsfLoader', () {
    test('parses DSF fmt chunk and trailing ID3v2 metadata', () async {
      final id3 = _buildId3v23Tag(
        title: 'Kyrie',
        artist: 'CANTUS (Tove Ramlo-Ystad) & Frode Fjellheim',
        track: '4/12',
      );
      final bytes = _buildDsfFile(
        channels: 2,
        sampleRate: 5644800,
        bitsPerSample: 1,
        sampleCount: 564480,
        id3Chunk: id3,
      );

      final loader = DsfLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.container, 'DSF');
      expect(metadata.format.lossless, isTrue);
      expect(metadata.format.hasAudio, isTrue);
      expect(metadata.format.hasVideo, isFalse);
      expect(metadata.format.numberOfChannels, 2);
      expect(metadata.format.bitsPerSample, 1);
      expect(metadata.format.sampleRate, 5644800);
      expect(metadata.format.numberOfSamples, 564480);
      expect(metadata.format.duration, closeTo(0.1, 0.000001));
      expect(metadata.format.bitrate, 11289600);

      expect(metadata.common.title, 'Kyrie');
      expect(
        metadata.common.artist,
        'CANTUS (Tove Ramlo-Ystad) & Frode Fjellheim',
      );
      expect(metadata.common.track.no, 4);
      expect(metadata.common.track.of, 12);

      final id3Tags = metadata.native['ID3v2.3'];
      expect(id3Tags, isNotNull);
      expect(id3Tags!.where((t) => t.id == 'TIT2').single.value, 'Kyrie');
    });

    test('parses format fields when metadata pointer is zero', () async {
      final bytes = _buildDsfFile(
        channels: 1,
        sampleRate: 2822400,
        bitsPerSample: 1,
        sampleCount: 282240,
        metadataPointer: 0,
      );

      final loader = DsfLoader();
      final metadata = await loader.parse(
        BytesTokenizer(Uint8List.fromList(bytes)),
        const ParseOptions(),
      );

      expect(metadata.format.container, 'DSF');
      expect(metadata.format.numberOfChannels, 1);
      expect(metadata.format.sampleRate, 2822400);
      expect(metadata.format.numberOfSamples, 282240);
      expect(metadata.common.title, isNull);
    });

    test('throws on invalid DSF chunk signature', () async {
      final bytes = _buildDsfFile(
        channels: 2,
        sampleRate: 2822400,
        bitsPerSample: 1,
        sampleCount: 282240,
      );
      bytes.setRange(0, 4, ascii.encode('BAD!'));

      final loader = DsfLoader();
      await expectLater(
        loader.parse(BytesTokenizer(bytes), const ParseOptions()),
        throwsA(isA<DsdContentError>()),
      );
    });

    test('loader declares extension, mime type and no seek requirement', () {
      final loader = DsfLoader();

      expect(loader.extension, contains('dsf'));
      expect(loader.mimeType, contains('audio/dsf'));
      expect(loader.hasRandomAccessRequirements, isFalse);
      expect(loader.supports(_NonSeekTokenizer()), isTrue);
    });
  });
}

Uint8List _buildDsfFile({
  required int channels,
  required int sampleRate,
  required int bitsPerSample,
  required int sampleCount,
  int? metadataPointer,
  List<int>? id3Chunk,
}) {
  final fmtPayload = <int>[
    ..._i32le(1),
    ..._i32le(0),
    ..._i32le(2),
    ..._i32le(channels),
    ..._i32le(sampleRate),
    ..._i32le(bitsPerSample),
    ..._i64le(sampleCount),
    ..._i32le(4096),
    ..._i32le(0),
  ];

  final fmtChunk = <int>[...ascii.encode('fmt '), ..._u64le(52), ...fmtPayload];

  final id3 = id3Chunk ?? const <int>[];
  final resolvedMetadataPointer =
      metadataPointer ?? (28 + fmtChunk.length + (id3.isEmpty ? 0 : 0));

  final fileSize = 28 + fmtChunk.length + id3.length;
  final dsdPayload = <int>[
    ..._i64le(fileSize),
    ..._i64le(id3.isEmpty ? resolvedMetadataPointer : resolvedMetadataPointer),
  ];
  final dsdChunk = <int>[...ascii.encode('DSD '), ..._u64le(28), ...dsdPayload];

  final bytes = <int>[...dsdChunk, ...fmtChunk, ...id3];

  final pointer = metadataPointer ?? (id3.isEmpty ? 0 : 28 + fmtChunk.length);
  bytes.setRange(20, 28, _i64le(pointer));
  bytes.setRange(12, 20, _i64le(bytes.length));
  return Uint8List.fromList(bytes);
}

List<int> _buildId3v23Tag({
  required String title,
  required String artist,
  required String track,
}) {
  final frames = <int>[
    ..._id3TextFrame('TIT2', title),
    ..._id3TextFrame('TPE1', artist),
    ..._id3TextFrame('TRCK', track),
  ];

  return <int>[
    ...ascii.encode('ID3'),
    0x03,
    0x00,
    0x00,
    ..._synchsafe(frames.length),
    ...frames,
  ];
}

List<int> _id3TextFrame(String id, String value) {
  final payload = <int>[0x00, ...latin1.encode(value)];
  return <int>[
    ...ascii.encode(id),
    ..._u32be(payload.length),
    0x00,
    0x00,
    ...payload,
  ];
}

List<int> _i32le(int value) {
  final data = ByteData(4)..setInt32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

List<int> _i64le(int value) {
  final data = ByteData(8)..setInt64(0, value, Endian.little);
  return data.buffer.asUint8List();
}

List<int> _u64le(int value) {
  final data = ByteData(8)..setUint64(0, value, Endian.little);
  return data.buffer.asUint8List();
}

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
