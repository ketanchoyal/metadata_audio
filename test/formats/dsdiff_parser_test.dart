import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/dsdiff/dsdiff_loader.dart';
import 'package:metadata_audio/src/dsdiff/dsdiff_token.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  group('DsdiffParser / DsdiffLoader', () {
    test('parses FRM8/PROP/DSD chunks and ID3 metadata', () async {
      final id3 = _buildId3v23Tag(
        title: 'Kyrie',
        artist: 'CANTUS (Tove Ramlo-Ystad) & Frode Fjellheim',
        album: 'SPES',
        track: '4/12',
      );

      final bytes = _buildDsdiff(
        channels: 2,
        sampleRate: 2822400,
        dsdDataBytes: 75200,
        id3Chunk: id3,
        comments: const <String>['Synthetic DSDIFF comment'],
      );

      final loader = DsdiffLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.container, 'DSDIFF/DSD');
      expect(metadata.format.lossless, isTrue);
      expect(metadata.format.bitsPerSample, 1);
      expect(metadata.format.numberOfChannels, 2);
      expect(metadata.format.sampleRate, 2822400);
      expect(metadata.format.numberOfSamples, 300800);
      expect(metadata.format.duration, closeTo(300800 / 2822400, 0.000000001));
      expect(metadata.format.bitrate, 5644800);

      expect(metadata.common.title, 'Kyrie');
      expect(
        metadata.common.artist,
        'CANTUS (Tove Ramlo-Ystad) & Frode Fjellheim',
      );
      expect(metadata.common.album, 'SPES');
      expect(metadata.common.track.no, 4);
      expect(metadata.common.track.of, 12);

      final comtTags = metadata.native['DSDIFF'];
      expect(comtTags, isNotNull);
      final comtTag = comtTags!.where((tag) => tag.id == 'COMT').single;
      expect(comtTag.value, contains('Synthetic DSDIFF comment'));
    });

    test('parses DSDIFF without ID3 chunk', () async {
      final bytes = _buildDsdiff(
        channels: 1,
        sampleRate: 2822400,
        dsdDataBytes: 35280,
      );

      final loader = DsdiffLoader();
      final metadata = await loader.parse(
        BytesTokenizer(Uint8List.fromList(bytes)),
        const ParseOptions(),
      );

      expect(metadata.format.container, 'DSDIFF/DSD');
      expect(metadata.format.numberOfChannels, 1);
      expect(metadata.format.sampleRate, 2822400);
      expect(metadata.format.numberOfSamples, 282240);
      expect(metadata.common.title, isNull);
    });

    test('throws on invalid FRM8 signature', () async {
      final bytes = _buildDsdiff(
        channels: 2,
        sampleRate: 2822400,
        dsdDataBytes: 100,
      );
      bytes.setRange(0, 4, ascii.encode('BAD!'));

      final loader = DsdiffLoader();
      await expectLater(
        loader.parse(
          BytesTokenizer(Uint8List.fromList(bytes)),
          const ParseOptions(),
        ),
        throwsA(isA<DsdiffContentError>()),
      );
    });

    test('loader declares extension, MIME type and no seek requirement', () {
      final loader = DsdiffLoader();

      expect(loader.extension, equals(const <String>['dff']));
      expect(
        loader.mimeType,
        containsAll(const <String>['audio/dsf', 'audio/dsd']),
      );
      expect(loader.hasRandomAccessRequirements, isFalse);
      expect(loader.supports(_NonSeekTokenizer()), isTrue);
    });
  });
}

List<int> _buildDsdiff({
  required int channels,
  required int sampleRate,
  required int dsdDataBytes,
  List<int>? id3Chunk,
  List<String> comments = const <String>[],
}) {
  final soundPropertyChunks = <int>[
    ..._chunk64('FS  ', _u32be(sampleRate)),
    ..._chunk64('CHNL', <int>[
      ..._u16be(channels),
      for (final id in _channelIds(channels)) ...ascii.encode(id),
    ]),
    ..._chunk64('CMPR', <int>[
      ...ascii.encode('DSD '),
      3,
      ...ascii.encode('raw'),
    ]),
  ];

  final chunks = <int>[
    ..._chunk64('FVER', _u32le(0x01050000)),
    ..._chunk64('PROP', <int>[...ascii.encode('SND '), ...soundPropertyChunks]),
    if (comments.isNotEmpty)
      ..._chunk64('COMT', _buildCommentPayload(comments)),
    ..._chunk64('DSD ', List<int>.filled(dsdDataBytes, 0x69)),
    if (id3Chunk != null && id3Chunk.isNotEmpty) ..._chunk64('ID3 ', id3Chunk),
  ];

  final formPayload = <int>[...ascii.encode('DSD '), ...chunks];
  return <int>[
    ...ascii.encode('FRM8'),
    ..._i64be(formPayload.length),
    ...formPayload,
  ];
}

List<int> _buildCommentPayload(List<String> comments) {
  final payload = <int>[..._u16be(comments.length)];
  for (final comment in comments) {
    final text = ascii.encode(comment);
    payload.addAll(<int>[
      ..._u32be(0),
      ..._u16be(0),
      ..._u16be(text.length),
      ...text,
    ]);
  }
  return payload;
}

List<String> _channelIds(int channels) {
  const defaults = <String>['SLFT', 'SRGT', 'C   ', 'LFE ', 'LS  ', 'RS  '];
  if (channels <= defaults.length) {
    return defaults.sublist(0, channels);
  }

  return <String>[
    ...defaults,
    for (var i = defaults.length; i < channels; i++)
      'C${i.toString().padLeft(3, '0')}',
  ];
}

List<int> _buildId3v23Tag({
  required String title,
  required String artist,
  required String album,
  required String track,
}) {
  final frames = <int>[
    ..._id3TextFrame('TIT2', title),
    ..._id3TextFrame('TPE1', artist),
    ..._id3TextFrame('TALB', album),
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

List<int> _chunk64(String id, List<int> payload) {
  final padded = payload.length.isOdd ? <int>[...payload, 0] : payload;
  return <int>[...ascii.encode(id), ..._i64be(payload.length), ...padded];
}

List<int> _u16be(int value) => <int>[(value >> 8) & 0xFF, value & 0xFF];

List<int> _u32be(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _u32le(int value) => <int>[
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

List<int> _i64be(int value) {
  final data = ByteData(8)..setInt64(0, value);
  return data.buffer.asUint8List();
}

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
