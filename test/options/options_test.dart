import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata/src/matroska/matroska_loader.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/mp4/mp4_loader.dart';
import 'package:audio_metadata/src/mpeg/mpeg_loader.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:test/test.dart';

void main() {
  group('ParseOptions behavior parity', () {
    group('duration', () {
      test(
        'duration=false estimates duration from bitrate for MPEG VBR',
        () async {
          final bytes = <int>[
            ..._buildMpegFrame(),
            ..._buildMpegFrame(bitrateIndex: 11),
            ..._buildMpegFrame(bitrateIndex: 10),
            ..._buildMpegFrame(),
            ..._buildMpegFrame(bitrateIndex: 11),
          ];

          final metadata = await MpegLoader().parse(
            BytesTokenizer(
              Uint8List.fromList(bytes),
              fileInfo: FileInfo(size: bytes.length),
            ),
            const ParseOptions(),
          );

          // Duration is estimated from average bitrate and file size
          // (not from EOF frame counting, which requires duration: true)
          expect(metadata.format.duration, isNotNull);
          // numberOfSamples requires full frame counting (duration: true)
          expect(metadata.format.numberOfSamples, isNull);
        },
      );

      test('duration=true calculates EOF duration for MPEG VBR', () async {
        final bytes = <int>[
          ..._buildMpegFrame(),
          ..._buildMpegFrame(bitrateIndex: 11),
          ..._buildMpegFrame(bitrateIndex: 10),
          ..._buildMpegFrame(),
          ..._buildMpegFrame(bitrateIndex: 11),
        ];

        final metadata = await MpegLoader().parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(duration: true),
        );

        expect(metadata.format.duration, closeTo(5 * 1152 / 44100, 0.01));
        expect(metadata.format.numberOfSamples, 5 * 1152);
      });
    });

    group('skipCovers', () {
      test('skipCovers=false keeps MP4 cover tag and common picture', () async {
        final bytes = _buildSyntheticMp4();
        final metadata = await Mp4Loader().parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(),
        );

        expect(metadata.common.picture, isNotNull);
        expect(metadata.common.picture, hasLength(1));
        final iTunes = metadata.native['iTunes'] ?? const <Tag>[];
        expect(iTunes.any((tag) => tag.id == 'covr'), isTrue);
      });

      test('skipCovers=true drops MP4 cover tag and common picture', () async {
        final bytes = _buildSyntheticMp4();
        final metadata = await Mp4Loader().parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(skipCovers: true),
        );

        expect(metadata.common.picture, isNull);
        final iTunes = metadata.native['iTunes'] ?? const <Tag>[];
        expect(iTunes.any((tag) => tag.id == 'covr'), isFalse);
      });
    });

    group('includeChapters', () {
      test('includeChapters=false omits Matroska chapters', () async {
        final bytes = _buildMatroskaFile();
        final metadata = await MatroskaLoader().parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(),
        );

        expect(metadata.format.chapters, isNull);
      });

      test('includeChapters=true parses Matroska chapters', () async {
        final bytes = _buildMatroskaFile();
        final metadata = await MatroskaLoader().parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(includeChapters: true),
        );

        expect(metadata.format.chapters, isNotNull);
        expect(metadata.format.chapters, hasLength(1));
        expect(metadata.format.chapters!.first.title, 'Intro');
      });
    });

    group('skipPostHeaders', () {
      test('skipPostHeaders=false reads MPEG ID3v1 post-header tags', () async {
        final bytes = <int>[
          ..._buildId3v2Header(),
          ..._buildMpegFrame(includeXing: true),
          ..._buildId3v1(title: 'Tail'),
        ];
        final metadata = await MpegLoader().parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(),
        );

        expect(metadata.common.title, 'Tail');
      });

      test('skipPostHeaders=true skips MPEG ID3v1 post-header tags', () async {
        final bytes = <int>[
          ..._buildId3v2Header(),
          ..._buildMpegFrame(includeXing: true),
          ..._buildId3v1(title: 'Tail'),
        ];
        final metadata = await MpegLoader().parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(skipPostHeaders: true),
        );

        expect(metadata.common.title, isNull);
      });
    });

    group('option combinations', () {
      test('combined Matroska options apply independently', () async {
        final bytes = _buildMatroskaFile();
        final metadata = await MatroskaLoader().parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(skipCovers: true),
        );

        expect(metadata.common.picture, isNull);
        expect(metadata.format.chapters, isNull);
      });

      test(
        'combined MPEG options parse duration while skipping post-headers',
        () async {
          final frames = <int>[
            ..._buildMpegFrame(),
            ..._buildMpegFrame(bitrateIndex: 11),
            ..._buildMpegFrame(bitrateIndex: 10),
            ..._buildMpegFrame(),
            ..._buildMpegFrame(bitrateIndex: 11),
          ];
          final bytes = <int>[...frames, ..._buildId3v1(title: 'Tail')];

          final metadata = await MpegLoader().parse(
            BytesTokenizer(
              Uint8List.fromList(bytes),
              fileInfo: FileInfo(size: bytes.length),
            ),
            const ParseOptions(duration: true, skipPostHeaders: true),
          );

          expect(metadata.format.duration, closeTo(5 * 1152 / 44100, 0.01));
          expect(metadata.common.title, isNull);
        },
      );
    });
  });
}

List<int> _buildId3v2Header() => <int>[
  0x49,
  0x44,
  0x33,
  0x03,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
];

List<int> _buildMpegFrame({int bitrateIndex = 9, bool includeXing = false}) {
  const sampleRate = 44100;
  const samplesPerFrame = 1152;
  final bitrateKbps = _bitrateFromIndex(bitrateIndex);
  final bitrate = bitrateKbps * 1000;
  final frameLength = (samplesPerFrame / 8 * bitrate / sampleRate).floor();

  final header = <int>[0xFF, 0xFB, (bitrateIndex << 4), 0x40];
  final payload = List<int>.filled(frameLength - 4, 0);

  if (includeXing) {
    var cursor = 32;
    final marker = 'Xing'.codeUnits;
    payload.setRange(cursor, cursor + marker.length, marker);
    cursor += 4;

    payload.setRange(cursor, cursor + 4, const <int>[0x80, 0x00, 0x00, 0x00]);
    cursor += 4;

    payload.setRange(cursor, cursor + 4, const <int>[0x00, 0x00, 0x00, 0x01]);
  }

  return <int>[...header, ...payload];
}

List<int> _buildId3v1({required String title}) {
  final tag = List<int>.filled(128, 0);
  tag[0] = 0x54;
  tag[1] = 0x41;
  tag[2] = 0x47;

  final titleBytes = title.codeUnits;
  for (var i = 0; i < titleBytes.length && i < 30; i++) {
    tag[3 + i] = titleBytes[i];
  }
  return tag;
}

int _bitrateFromIndex(int index) {
  const table = <int, int>{
    1: 32,
    2: 40,
    3: 48,
    4: 56,
    5: 64,
    6: 80,
    7: 96,
    8: 112,
    9: 128,
    10: 160,
    11: 192,
    12: 224,
    13: 256,
    14: 320,
  };
  return table[index] ?? 128;
}

List<int> _buildSyntheticMp4() {
  final ftyp = _atom('ftyp', <int>[
    ...latin1.encode('M4A '),
    ...latin1.encode('isom'),
    ...latin1.encode('mp42'),
  ]);

  final mvhd = _atom('mvhd', _mvhdPayload(timeScale: 1000, duration: 2000));
  final tkhd = _atom('tkhd', _tkhdPayload(trackId: 1));
  final mdhd = _atom('mdhd', _mdhdPayload(timeScale: 44100, duration: 88200));
  final hdlr = _atom('hdlr', _hdlrPayload('soun'));
  final stsd = _atom('stsd', _stsdPayloadMp4a());
  final stbl = _atom('stbl', stsd);
  final minf = _atom('minf', stbl);
  final mdia = _atom('mdia', <int>[...mdhd, ...hdlr, ...minf]);
  final trak = _atom('trak', <int>[...tkhd, ...mdia]);

  final ilst = _atom('ilst', <int>[
    ..._metadataItem('©nam', _dataAtom(1, utf8.encode('Test Title'))),
    ..._metadataItem('covr', _dataAtom(13, <int>[1, 2, 3, 4])),
  ]);
  final meta = _atom('meta', <int>[0, 0, 0, 0, ...ilst]);
  final udta = _atom('udta', meta);
  final moov = _atom('moov', <int>[...mvhd, ...trak, ...udta]);

  return <int>[...ftyp, ...moov];
}

List<int> _metadataItem(String key, List<int> children) => _atom(key, children);

List<int> _dataAtom(int type, List<int> value) {
  final payload = <int>[
    0,
    (type >> 16) & 0xFF,
    (type >> 8) & 0xFF,
    type & 0xFF,
    0,
    0,
    0,
    0,
    ...value,
  ];
  return _atom('data', payload);
}

List<int> _atom(String name, List<int> payload) {
  final length = 8 + payload.length;
  return <int>[..._u32(length), ...latin1.encode(name), ...payload];
}

List<int> _mvhdPayload({required int timeScale, required int duration}) =>
    <int>[
      0,
      0,
      0,
      0,
      ..._u32(0),
      ..._u32(0),
      ..._u32(timeScale),
      ..._u32(duration),
      ...List<int>.filled(80, 0),
    ];

List<int> _tkhdPayload({required int trackId}) => <int>[
  0,
  0,
  0,
  7,
  ..._u32(0),
  ..._u32(0),
  ..._u32(trackId),
  ..._u32(0),
  ..._u32(88200),
  ...List<int>.filled(60, 0),
];

List<int> _mdhdPayload({required int timeScale, required int duration}) =>
    <int>[
      0,
      0,
      0,
      0,
      ..._u32(0),
      ..._u32(0),
      ..._u32(timeScale),
      ..._u32(duration),
      0,
      0,
      0,
      0,
    ];

List<int> _hdlrPayload(String handlerType) => <int>[
  0,
  0,
  0,
  0,
  ...latin1.encode('mhlr'),
  ...latin1.encode(handlerType),
  ...List<int>.filled(12, 0),
];

List<int> _stsdPayloadMp4a() {
  final sampleEntry = <int>[
    ..._u32(36),
    ...latin1.encode('mp4a'),
    ...List<int>.filled(6, 0),
    0,
    1,
    ...List<int>.filled(8, 0),
    0,
    2,
    0,
    16,
    0,
    0,
    0,
    0,
    ..._u32(44100 << 16),
  ];

  return <int>[0, 0, 0, 0, ..._u32(1), ...sampleEntry];
}

List<int> _u32(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _buildMatroskaFile() {
  final ebmlHeader = _element(const <int>[0x1A, 0x45, 0xDF, 0xA3], <int>[]);

  final info = _element(
    const <int>[0x15, 0x49, 0xA9, 0x66],
    <int>[
      ..._element(const <int>[0x2A, 0xD7, 0xB1], _encodeUint(1000000)),
      ..._element(const <int>[0x44, 0x89], _encodeFloat64(5000.toDouble())),
    ],
  );

  final tracks = _element(
    const <int>[0x16, 0x54, 0xAE, 0x6B],
    _element(
      const <int>[0xAE],
      <int>[
        ..._element(const <int>[0xD7], _encodeUint(1)),
        ..._element(const <int>[0x83], _encodeUint(2)),
        ..._element(const <int>[0x86], utf8.encode('A_OPUS')),
        ..._element(
          const <int>[0xE1],
          <int>[
            ..._element(const <int>[0xB5], _encodeFloat32(48000.toDouble())),
            ..._element(const <int>[0x9F], _encodeUint(2)),
          ],
        ),
      ],
    ),
  );

  final attachments = _element(
    const <int>[0x19, 0x41, 0xA4, 0x69],
    _element(
      const <int>[0x61, 0xA7],
      <int>[
        ..._element(const <int>[0x46, 0x6E], utf8.encode('cover.jpg')),
        ..._element(const <int>[0x46, 0x60], utf8.encode('image/jpeg')),
        ..._element(const <int>[0x46, 0x5C], const <int>[0x11, 0x22, 0x33]),
      ],
    ),
  );

  final chapterAtom = _element(
    const <int>[0xB6],
    <int>[
      ..._element(const <int>[0x73, 0xC4], const <int>[0x01]),
      ..._element(const <int>[0x91], _encodeUint(0)),
      ..._element(const <int>[0x92], _encodeUint(5000000000)),
      ..._element(
        const <int>[0x8F],
        _element(const <int>[
          0x80,
        ], _element(const <int>[0x85], utf8.encode('Intro'))),
      ),
    ],
  );

  final chapters = _element(const <int>[
    0x10,
    0x43,
    0xA7,
    0x70,
  ], _element(const <int>[0x45, 0xB9], chapterAtom));

  final segment = _element(
    const <int>[0x18, 0x53, 0x80, 0x67],
    <int>[...info, ...tracks, ...attachments, ...chapters],
  );

  return <int>[...ebmlHeader, ...segment];
}

List<int> _element(List<int> id, List<int> payload) => <int>[
  ...id,
  ..._encodeSize(payload.length),
  ...payload,
];

List<int> _encodeUint(int value) {
  if (value == 0) {
    return const <int>[0x00];
  }

  final bytes = <int>[];
  var remaining = value;
  while (remaining > 0) {
    bytes.insert(0, remaining & 0xFF);
    remaining >>= 8;
  }
  return bytes;
}

List<int> _encodeFloat32(double value) =>
    (ByteData(4)..setFloat32(0, value)).buffer.asUint8List();

List<int> _encodeFloat64(double value) =>
    (ByteData(8)..setFloat64(0, value)).buffer.asUint8List();

List<int> _encodeSize(int value) {
  if (value <= 0x7F) {
    return <int>[0x80 | value];
  }
  if (value <= 0x3FFF) {
    return <int>[0x40 | ((value >> 8) & 0x3F), value & 0xFF];
  }
  if (value <= 0x1FFFFF) {
    return <int>[
      0x20 | ((value >> 16) & 0x1F),
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }
  throw ArgumentError('Unsupported EBML size in synthetic test: $value');
}
