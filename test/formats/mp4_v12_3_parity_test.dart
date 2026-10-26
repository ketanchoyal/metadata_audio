/// Tests for music-metadata v12.3.0 MP4 parser parity:
/// - iTunes freeform movement tags (`----:com.apple.iTunes:Movement*`, #2835)
/// - signed integer data atoms (types 65/66/67, #2839)
/// - `maxChapterCount` ParseOption applied to the `chpl` atom (#2838)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/mp4/mp4_loader.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:test/test.dart';

void main() {
  Future<AudioMetadata> parse(List<int> bytes, [ParseOptions? options]) =>
      Mp4Loader().parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo.fromPath('file.m4a'),
        ),
        options ?? const ParseOptions(),
      );

  group('MP4 iTunes freeform movement tags (#2835)', () {
    test('maps Movement Name into common.movement', () async {
      final metadata = await parse(
        _buildMp4(<int>[
          ..._metadataItem(
            '----',
            _freeform('Movement Name', 'First Movement'),
          ),
        ]),
      );
      expect(metadata.common.movement, 'First Movement');
    });

    test(
      'maps Movement into common.movementIndex and Movement Total',
      () async {
        final metadata = await parse(
          _buildMp4(<int>[
            ..._metadataItem('----', _freeform('Movement', '2')),
            ..._metadataItem('----', _freeform('Movement Total', '3')),
          ]),
        );
        expect(metadata.common.movementIndex.no, 2);
        expect(metadata.common.movementTotal, 3);
      },
    );
  });

  group('MP4 signed integer data atoms (#2839)', () {
    test('decodes negative INT8, INT16_BE and INT32_BE values', () async {
      final metadata = await parse(
        _buildMp4(<int>[
          ..._metadataItem('i008', _dataAtom(65, <int>[0xF7])),
          ..._metadataItem('i016', _dataAtom(66, <int>[0xFE, 0x0C])),
          ..._metadataItem(
            'i032',
            _dataAtom(67, <int>[0xFF, 0x6E, 0xB8, 0x52]),
          ),
        ]),
      );
      final native = metadata.native['iTunes']!;
      expect(native.firstWhere((t) => t.id == 'i008').value, -9);
      expect(native.firstWhere((t) => t.id == 'i016').value, -500);
      expect(native.firstWhere((t) => t.id == 'i032').value, -9521070);
    });

    test('decodes positive values unchanged', () async {
      final metadata = await parse(
        _buildMp4(<int>[
          ..._metadataItem('i008', _dataAtom(65, <int>[9])),
          ..._metadataItem('i016', _dataAtom(66, <int>[0x01, 0xF4])),
          ..._metadataItem(
            'i032',
            _dataAtom(67, <int>[0x00, 0x0E, 0xF0, 0x00]),
          ),
        ]),
      );
      final native = metadata.native['iTunes']!;
      expect(native.firstWhere((t) => t.id == 'i008').value, 9);
      expect(native.firstWhere((t) => t.id == 'i016').value, 500);
      expect(native.firstWhere((t) => t.id == 'i032').value, 978944);
    });
  });

  group('MP4 maxChapterCount option (#2838)', () {
    test('caps chpl chapters and warns at the option limit', () async {
      final metadata = await parse(
        _buildMp4WithChpl(chapterCount: 5),
        const ParseOptions(includeChapters: true, maxChapterCount: 3),
      );
      expect(metadata.format.chapters, hasLength(3));
      expect(
        metadata.quality.warnings.map((warning) => warning.message),
        contains('Chapter count exceeds the 3 chapter limit'),
      );
    });

    test('keeps the default 1,000 chapter limit', () async {
      final metadata = await parse(
        _buildMp4WithChpl(chapterCount: 200, version: 0),
        const ParseOptions(includeChapters: true),
      );
      // The chpl count byte holds at most 255 chapters; all are parsed.
      expect(metadata.format.chapters, hasLength(200));
    });
  });
}

List<int> _buildMp4(List<int> ilstChildren) {
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

  final ilst = _atom('ilst', ilstChildren);
  final meta = _atom('meta', <int>[0, 0, 0, 0, ...ilst]);
  final udta = _atom('udta', meta);
  final moov = _atom('moov', <int>[...mvhd, ...trak, ...udta]);

  return <int>[...ftyp, ...moov];
}

List<int> _freeform(String name, String value) => <int>[
  ..._nameLikeAtom('mean', 'com.apple.iTunes'),
  ..._nameLikeAtom('name', name),
  ..._dataAtom(1, utf8.encode(value)),
];

List<int> _buildMp4WithChpl({required int chapterCount, int version = 1}) {
  final ftyp = _atom('ftyp', <int>[
    ...latin1.encode('M4A '),
    ...latin1.encode('isom'),
    ...latin1.encode('mp42'),
  ]);

  final mvhd = _atom('mvhd', _mvhdPayload(timeScale: 1000, duration: 2000));

  final tkhd = _atom('tkhd', _tkhdPayload(trackId: 1));
  final mdhd = _atom('mdhd', _mdhdPayload(timeScale: 1000, duration: 2000));
  final mp4aStsd = _atom('stsd', _stsdPayloadMp4a());
  // One 10 ms sample at 100 Hz so elapsed samples map onto chapters.
  final stts = _atom(
    'stts',
    _sttsPayload(<List<int>>[
      [1, 10],
    ]),
  );
  final stsz = _atom('stsz', _stszPayload(4, List<int>.filled(1, 4)));
  final stco = _atom('stco', _stcoPayload(<int>[0, 0]));
  final stbl = _atom('stbl', <int>[...mp4aStsd, ...stts, ...stsz, ...stco]);
  final minf = _atom('minf', stbl);
  final mdia = _atom('mdia', <int>[...mdhd, ...minf]);
  final trak = _atom('trak', <int>[...tkhd, ...mdia]);

  final chplPayload = <int>[
    version, // version
    0,
    0,
    0, // flags
    // Version 1 adds 4 extra header bytes; version 0 goes straight to count.
    if (version >= 1) ..._u32(0),
    chapterCount,
    for (var i = 0; i < chapterCount; i++) ...<int>[
      // 8-byte big-endian timestamp in 10,000,000 ticks/second units,
      // spaced 10 ms apart so every chapter lands within the file duration.
      ..._u64((i + 1) * 100000),
      // 1-byte title length + title
      ..._titleEntry('Chapter ${i + 1}'),
    ],
  ];
  final chpl = _atom('chpl', chplPayload);
  final udta = _atom('udta', chpl);
  final moov = _atom('moov', <int>[...mvhd, ...trak, ...udta]);

  return <int>[...ftyp, ...moov];
}

List<int> _titleEntry(String title) {
  final encoded = utf8.encode(title);
  return <int>[encoded.length, ...encoded];
}

List<int> _sttsPayload(List<List<int>> entries) => <int>[
  0,
  0,
  0,
  0,
  ..._u32(entries.length),
  for (final entry in entries) ...<int>[..._u32(entry[0]), ..._u32(entry[1])],
];

List<int> _stszPayload(int sampleSize, List<int> entries) => <int>[
  0,
  0,
  0,
  0,
  ..._u32(sampleSize),
  ..._u32(entries.length),
  if (sampleSize == 0)
    for (final entry in entries) ..._u32(entry),
];

List<int> _stcoPayload(List<int> offsets) => <int>[
  0,
  0,
  0,
  0,
  ..._u32(offsets.length),
  for (final offset in offsets) ..._u32(offset),
];

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

List<int> _nameLikeAtom(String id, String value) =>
    _atom(id, <int>[0, 0, 0, 0, ...utf8.encode(value)]);

List<int> _mvhdPayload({required int timeScale, required int duration}) =>
    <int>[
      0, 0, 0, 0, //
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
  0, 0, 0, 0, //
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

List<int> _u64(int value) => <int>[
  ..._u32(value >> 32),
  ..._u32(value & 0xFFFFFFFF),
];

List<int> _atom(String name, List<int> payload) {
  final length = 8 + payload.length;
  return <int>[..._u32(length), ...latin1.encode(name), ...payload];
}
