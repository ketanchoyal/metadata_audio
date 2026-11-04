import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

void main() {
  Future<AudioMetadata> parse(List<int> bytes, [ParseOptions? options]) =>
      Mp4Loader().parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo.fromPath('audiobook.m4b'),
        ),
        options ?? const ParseOptions(includeChapters: true),
      );

  group('M4B dual chapter storage (Nero chpl vs QuickTime tref/chap)', () {
    test('extracts chapters from standalone Nero chpl atom', () async {
      final bytes = _buildMp4WithDualChapters(
        includeQuickTime: false,
        includeNeroChpl: true,
        neroTitles: ['Nero Chapter 1', 'Nero Chapter 2'],
      );

      final metadata = await parse(bytes);
      final chapters = metadata.format.chapters;

      expect(chapters, isNotNull);
      expect(chapters!.length, equals(2));
      expect(chapters[0].title, equals('Nero Chapter 1'));
      expect(chapters[1].title, equals('Nero Chapter 2'));
    });

    test('extracts chapters from standalone QuickTime chapter track', () async {
      final bytes = _buildMp4WithDualChapters(
        includeQuickTime: true,
        includeNeroChpl: false,
        quickTimeTitles: ['QT Chapter 1', 'QT Chapter 2'],
      );

      final metadata = await parse(bytes);
      final chapters = metadata.format.chapters;

      expect(chapters, isNotNull);
      expect(chapters!.length, equals(2));
      expect(chapters[0].title, equals('QT Chapter 1'));
      expect(chapters[1].title, equals('QT Chapter 2'));
    });

    test(
      'when both are present with valid titles, QuickTime track wins',
      () async {
        final bytes = _buildMp4WithDualChapters(
          includeQuickTime: true,
          includeNeroChpl: true,
          quickTimeTitles: ['QT Part 1', 'QT Part 2'],
          neroTitles: ['Nero Alt 1', 'Nero Alt 2'],
        );

        final metadata = await parse(bytes);
        final chapters = metadata.format.chapters;

        expect(chapters, isNotNull);
        expect(chapters!.length, equals(2));
        expect(chapters[0].title, equals('QT Part 1'));
        expect(chapters[1].title, equals('QT Part 2'));
      },
    );

    test(
      'when QuickTime has empty titles but Nero chpl has titles, Nero chpl wins',
      () async {
        final bytes = _buildMp4WithDualChapters(
          includeQuickTime: true,
          includeNeroChpl: true,
          quickTimeTitles: ['', '   '], // Blank/empty titles from buggy tool
          neroTitles: ['Named Chapter 1', 'Named Chapter 2'],
        );

        final metadata = await parse(bytes);
        final chapters = metadata.format.chapters;

        expect(chapters, isNotNull);
        expect(chapters!.length, equals(2));
        expect(chapters[0].title, equals('Named Chapter 1'));
        expect(chapters[1].title, equals('Named Chapter 2'));
      },
    );

    test(
      'when QuickTime chapter track is corrupted, Nero chpl recovers chapters',
      () async {
        final bytes = _buildMp4WithCorruptedQuickTimeTrack(
          neroTitles: ['Rescued Chapter 1', 'Rescued Chapter 2'],
        );

        final metadata = await parse(bytes);
        final chapters = metadata.format.chapters;

        expect(chapters, isNotNull);
        expect(chapters!.length, equals(2));
        expect(chapters[0].title, equals('Rescued Chapter 1'));
        expect(chapters[1].title, equals('Rescued Chapter 2'));
      },
    );
  });
}

// =============================================================================
// Helper builders for synthesizing minimal M4B files with QT and Nero chapters
// =============================================================================

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

List<int> _chapterTextSample(String value) {
  final encoded = utf8.encode(value);
  return <int>[
    (encoded.length >> 8) & 0xFF,
    encoded.length & 0xFF,
    ...encoded,
  ];
}

List<int> _buildMp4WithDualChapters({
  required bool includeQuickTime,
  required bool includeNeroChpl,
  List<String> quickTimeTitles = const [],
  List<String> neroTitles = const [],
}) {
  final ftyp = _atom('ftyp', <int>[
    ...latin1.encode('M4B '),
    ..._u32(0),
    ...latin1.encode('M4B isommp42'),
  ]);

  final mvhd = _atom('mvhd', <int>[
    0, 0, 0, 0, // version + flags
    ..._u32(0), ..._u32(0), // creation, mod
    ..._u32(1000), // timescale = 1000
    ..._u32(2000), // duration = 2000 ms
    ...List<int>.filled(80, 0),
  ]);

  // Audio track (Track ID = 1)
  final audioTkhd = _atom('tkhd', <int>[
    0, 0, 0, 7,
    ..._u32(0), ..._u32(0),
    ..._u32(1), // trackId = 1
    ..._u32(0),
    ..._u32(2000),
    ...List<int>.filled(60, 0),
  ]);
  final audioMdhd = _atom('mdhd', <int>[
    0, 0, 0, 0,
    ..._u32(0), ..._u32(0),
    ..._u32(1000), // timescale = 1000
    ..._u32(2000), // duration = 2000
    0, 0, 0, 0,
  ]);
  final audioHdlr = _atom('hdlr', <int>[
    0, 0, 0, 0,
    ...latin1.encode('mhlr'),
    ...latin1.encode('soun'),
    ...List<int>.filled(12, 0),
  ]);
  final audioStsd = _atom('stsd', <int>[
    0, 0, 0, 0, ..._u32(1),
    ..._atom('mp4a', List<int>.filled(28, 0)),
  ]);
  final audioStts = _atom('stts', <int>[
    0, 0, 0, 0, ..._u32(1),
    ..._u32(1), ..._u32(2000),
  ]);
  final audioStsc = _atom('stsc', <int>[
    0, 0, 0, 0, ..._u32(1),
    ..._u32(1), ..._u32(1), ..._u32(1),
  ]);
  final audioStsz = _atom('stsz', <int>[
    0, 0, 0, 0, ..._u32(0), ..._u32(1),
    ..._u32(16),
  ]);
  final audioStco = _atom('stco', <int>[
    0, 0, 0, 0, ..._u32(1),
    ..._u32(0),
  ]);
  final audioStbl = _atom('stbl', <int>[
    ...audioStsd,
    ...audioStts,
    ...audioStsc,
    ...audioStsz,
    ...audioStco,
  ]);
  final audioMinf = _atom('minf', audioStbl);
  final audioMdia = _atom('mdia', <int>[
    ...audioMdhd,
    ...audioHdlr,
    ...audioMinf,
  ]);

  final chapRef = includeQuickTime
      ? _atom('tref', _atom('chap', _u32(2)))
      : <int>[];

  final audioTrak = _atom('trak', <int>[
    ...audioTkhd,
    ...audioMdia,
    ...chapRef,
  ]);

  // Construct QuickTime chapter samples and mdat
  final chapterSamples = quickTimeTitles.map(_chapterTextSample).toList();
  final mdatPayload = <int>[];

  // We place mdat at the end or calculate its offset
  // Let's compute offset of mdat body
  // ftyp is at 0
  // mdat will be right after moov or before moov. In our builder, moov first, then mdat!
  // Chapter track
  final chapterTraks = <int>[];
  var mdatOffset = 0;

  // Nero chpl
  final udtaList = <int>[];
  if (includeNeroChpl && neroTitles.isNotEmpty) {
    final chplPayload = <int>[
      1, 0, 0, 0, // version 1
      ..._u32(0),
      neroTitles.length,
      for (var i = 0; i < neroTitles.length; i++) ...<int>[
        ..._u64(i * 10000000), // 1 sec each in 10,000,000 base
        ..._titleEntry(neroTitles[i]),
      ],
    ];
    udtaList.addAll(_atom('udta', _atom('chpl', chplPayload)));
  }

  // Pre-calculate moov length without stco offsets, then adjust
  if (includeQuickTime && chapterSamples.isNotEmpty) {
    final chapterTkhd = _atom('tkhd', <int>[
      0, 0, 0, 7,
      ..._u32(0), ..._u32(0),
      ..._u32(2), // trackId = 2
      ..._u32(0),
      ..._u32(2000),
      ...List<int>.filled(60, 0),
    ]);
    final chapterMdhd = _atom('mdhd', <int>[
      0, 0, 0, 0,
      ..._u32(0), ..._u32(0),
      ..._u32(1000), // timescale = 1000
      ..._u32(2000), // duration
      0, 0, 0, 0,
    ]);
    final chapterHdlr = _atom('hdlr', <int>[
      0, 0, 0, 0,
      ...latin1.encode('mhlr'),
      ...latin1.encode('text'),
      ...List<int>.filled(12, 0),
    ]);
    final chapterStsd = _atom('stsd', <int>[
      0, 0, 0, 0, ..._u32(1),
      ..._atom('text', List<int>.filled(24, 0)),
    ]);
    final chapterStts = _atom('stts', <int>[
      0, 0, 0, 0, ..._u32(chapterSamples.length),
      for (var i = 0; i < chapterSamples.length; i++) ...<int>[
        ..._u32(1),
        ..._u32(1000), // 1000 ms each
      ],
    ]);
    final chapterStsc = _atom('stsc', <int>[
      0, 0, 0, 0, ..._u32(1),
      ..._u32(1), // first_chunk
      ..._u32(chapterSamples.length), // all samples in 1 chunk
      ..._u32(1),
    ]);
    final chapterStsz = _atom('stsz', <int>[
      0, 0, 0, 0, ..._u32(0), ..._u32(chapterSamples.length),
      for (final s in chapterSamples) ..._u32(s.length),
    ]);

    // Measure moov with dummy stco
    final dummyStco = _atom('stco', <int>[
      0, 0, 0, 0, ..._u32(1),
      ..._u32(0),
    ]);
    final dummyStbl = _atom('stbl', <int>[
      ...chapterStsd,
      ...chapterStts,
      ...chapterStsc,
      ...chapterStsz,
      ...dummyStco,
    ]);
    final dummyMinf = _atom('minf', dummyStbl);
    final dummyMdia = _atom('mdia', <int>[
      ...chapterMdhd,
      ...chapterHdlr,
      ...dummyMinf,
    ]);
    final dummyTrak = _atom('trak', <int>[...chapterTkhd, ...dummyMdia]);

    final dummyMoov = _atom('moov', <int>[
      ...mvhd,
      ...audioTrak,
      ...dummyTrak,
      ...udtaList,
    ]);

    // mdat will follow ftyp + moov
    mdatOffset = ftyp.length + dummyMoov.length;
    const mdatHeaderLen = 8;
    final firstChunkOffset = mdatOffset + mdatHeaderLen;

    // Real stco with exact offset
    final realStco = _atom('stco', <int>[
      0, 0, 0, 0, ..._u32(1),
      ..._u32(firstChunkOffset),
    ]);
    final realStbl = _atom('stbl', <int>[
      ...chapterStsd,
      ...chapterStts,
      ...chapterStsc,
      ...chapterStsz,
      ...realStco,
    ]);
    final realMinf = _atom('minf', realStbl);
    final realMdia = _atom('mdia', <int>[
      ...chapterMdhd,
      ...chapterHdlr,
      ...realMinf,
    ]);
    chapterTraks.addAll(_atom('trak', <int>[...chapterTkhd, ...realMdia]));

    for (final s in chapterSamples) {
      mdatPayload.addAll(s);
    }
  }

  final moov = _atom('moov', <int>[
    ...mvhd,
    ...audioTrak,
    ...chapterTraks,
    ...udtaList,
  ]);

  final mdat = _atom('mdat', mdatPayload);

  return <int>[...ftyp, ...moov, ...mdat];
}

List<int> _buildMp4WithCorruptedQuickTimeTrack({
  required List<String> neroTitles,
}) {
  final ftyp = _atom('ftyp', <int>[
    ...latin1.encode('M4B '),
    ..._u32(0),
    ...latin1.encode('M4B isommp42'),
  ]);

  final mvhd = _atom('mvhd', <int>[
    0, 0, 0, 0,
    ..._u32(0), ..._u32(0),
    ..._u32(1000), ..._u32(2000),
    ...List<int>.filled(80, 0),
  ]);

  final audioTrak = _atom('trak', <int>[
    ..._atom('tkhd', <int>[
      0, 0, 0, 7, ..._u32(0), ..._u32(0), ..._u32(1), ..._u32(0), ..._u32(2000),
      ...List<int>.filled(60, 0),
    ]),
    ..._atom('tref', _atom('chap', _u32(2))),
    ..._atom('mdia', <int>[
      ..._atom('mdhd', <int>[0, 0, 0, 0, ..._u32(0), ..._u32(0), ..._u32(1000), ..._u32(2000), 0, 0, 0, 0]),
      ..._atom('hdlr', <int>[0, 0, 0, 0, ...latin1.encode('mhlr'), ...latin1.encode('soun'), ...List<int>.filled(12, 0)]),
      ..._atom('minf', _atom('stbl', <int>[
        ..._atom('stsd', <int>[0, 0, 0, 0, ..._u32(1), ..._atom('mp4a', List<int>.filled(28, 0))]),
        ..._atom('stts', <int>[0, 0, 0, 0, ..._u32(1), ..._u32(1), ..._u32(2000)]),
        ..._atom('stsc', <int>[0, 0, 0, 0, ..._u32(1), ..._u32(1), ..._u32(1), ..._u32(1)]),
        ..._atom('stsz', <int>[0, 0, 0, 0, ..._u32(0), ..._u32(1), ..._u32(16)]),
        ..._atom('stco', <int>[0, 0, 0, 0, ..._u32(1), ..._u32(0)]),
      ])),
    ]),
  ]);

  // Corrupted QuickTime chapter track: stco points to offset 9999999 outside file
  final brokenChapTrak = _atom('trak', <int>[
    ..._atom('tkhd', <int>[
      0, 0, 0, 7, ..._u32(0), ..._u32(0), ..._u32(2), ..._u32(0), ..._u32(2000),
      ...List<int>.filled(60, 0),
    ]),
    ..._atom('mdia', <int>[
      ..._atom('mdhd', <int>[0, 0, 0, 0, ..._u32(0), ..._u32(0), ..._u32(1000), ..._u32(2000), 0, 0, 0, 0]),
      ..._atom('hdlr', <int>[0, 0, 0, 0, ...latin1.encode('mhlr'), ...latin1.encode('text'), ...List<int>.filled(12, 0)]),
      ..._atom('minf', _atom('stbl', <int>[
        ..._atom('stsd', <int>[0, 0, 0, 0, ..._u32(1), ..._atom('text', List<int>.filled(24, 0))]),
        ..._atom('stts', <int>[0, 0, 0, 0, ..._u32(1), ..._u32(1), ..._u32(1000)]),
        ..._atom('stsc', <int>[0, 0, 0, 0, ..._u32(1), ..._u32(1), ..._u32(1), ..._u32(1)]),
        ..._atom('stsz', <int>[0, 0, 0, 0, ..._u32(4), ..._u32(1)]),
        ..._atom('stco', <int>[0, 0, 0, 0, ..._u32(1), ..._u32(9999999)]), // Out of bounds offset!
      ])),
    ]),
  ]);

  final chplPayload = <int>[
    1, 0, 0, 0, ..._u32(0),
    neroTitles.length,
    for (var i = 0; i < neroTitles.length; i++) ...<int>[
      ..._u64(i * 10000000),
      ..._titleEntry(neroTitles[i]),
    ],
  ];

  final moov = _atom('moov', <int>[
    ...mvhd,
    ...audioTrak,
    ...brokenChapTrak,
    ..._atom('udta', _atom('chpl', chplPayload)),
  ]);

  return <int>[...ftyp, ...moov];
}

List<int> _titleEntry(String title) {
  final encoded = utf8.encode(title);
  return <int>[encoded.length, ...encoded];
}
