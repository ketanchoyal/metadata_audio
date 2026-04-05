import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/mp4/mp4_loader.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  group('Mp4Parser / Mp4Loader', () {
    test('parses ftyp/mvhd/trak/mdia/minf/stbl and iTunes metadata', () async {
      final bytes = _buildSyntheticMp4();

      final loader = Mp4Loader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(duration: true),
      );

      expect(metadata.format.container, 'M4A/isom/mp42');
      expect(metadata.format.codec, 'MPEG-4/AAC');
      expect(metadata.format.sampleRate, 44100);
      expect(metadata.format.numberOfChannels, 2);
      expect(metadata.format.bitsPerSample, 16);
      expect(metadata.format.duration, closeTo(2.0, 0.0001));
      expect(metadata.format.bitrate, isNotNull);
      expect(metadata.format.hasAudio, isTrue);
      expect(metadata.format.hasVideo, isFalse);

      expect(metadata.common.title, 'Test Title');
      expect(metadata.common.artist, 'Test Artist');
      expect(metadata.common.albumartist, 'Test Album Artist');
      expect(metadata.common.album, 'Test Album');
      expect(metadata.common.date, '2024');
      expect(metadata.common.track.no, 1);
      expect(metadata.common.track.of, 12);
      expect(metadata.common.musicbrainz_recordingid, 'mbid-track-123');

      expect(metadata.common.picture, isNotNull);
      expect(metadata.common.picture, hasLength(1));
      expect(metadata.common.picture!.first.format, 'image/jpeg');
      expect(metadata.common.picture!.first.data, equals(<int>[1, 2, 3, 4]));

      final iTunesTags = metadata.native['iTunes'];
      expect(iTunesTags, isNotNull);
      expect(
        iTunesTags!.where((tag) => tag.id == '©nam').single.value,
        'Test Title',
      );
      expect(iTunesTags.where((tag) => tag.id == 'trkn').single.value, '1/12');
    });

    test('respects skipCovers parse option', () async {
      final bytes = _buildSyntheticMp4();

      final loader = Mp4Loader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(skipCovers: true),
      );

      expect(metadata.common.picture, isNull);
      final tags = metadata.native['iTunes'] ?? const <Tag>[];
      expect(tags.any((tag) => tag.id == 'covr'), isFalse);
    });

    test('parses MP4 chapter track into format.chapters', () async {
      final bytes = _buildSyntheticMp4WithChapters();

      final loader = Mp4Loader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(includeChapters: true),
      );

      expect(metadata.format.chapters, isNotNull);
      expect(metadata.format.chapters, hasLength(2));
      expect(metadata.format.chapters![0].title, 'Intro');
      expect(metadata.format.chapters![0].start, 0);
      expect(metadata.format.chapters![0].end, 1000);
      expect(metadata.format.chapters![1].title, 'Outro');
      expect(metadata.format.chapters![1].start, 1000);
      expect(metadata.format.chapters![1].end, 2000);
    });

    test('parses version 1 mvhd atoms with large 64-bit durations', () async {
      final ftyp = _atom('ftyp', <int>[
        ...latin1.encode('M4A '),
        ...latin1.encode('isom'),
      ]);
      final mvhd = _atom(
        'mvhd',
        _mvhdPayloadV1(
          timeScale: 1000,
          duration: BigInt.parse('9223372036854775808'),
        ),
      );
      final moov = _atom('moov', mvhd);
      final bytes = <int>[...ftyp, ...moov];

      final loader = Mp4Loader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(duration: true),
      );

      expect(metadata.format.duration, isNotNull);
      expect(metadata.format.duration!, greaterThan(9000000000000000));
    });

    test('clamps out-of-range mvhd timestamps instead of crashing', () async {
      final ftyp = _atom('ftyp', <int>[
        ...latin1.encode('M4A '),
        ...latin1.encode('isom'),
      ]);
      final mvhd = _atom(
        'mvhd',
        _mvhdPayloadV1(
          creationTime: BigInt.parse('9223372036854775807'),
          modificationTime: BigInt.parse('9223372036854775807'),
          timeScale: 1000,
          duration: 2000,
        ),
      );
      final moov = _atom('moov', mvhd);
      final bytes = <int>[...ftyp, ...moov];

      final loader = Mp4Loader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(duration: true),
      );

      expect(metadata.format.creationTime, isNotNull);
      expect(metadata.format.modificationTime, isNotNull);
      expect(
        metadata.format.creationTime,
        DateTime.fromMillisecondsSinceEpoch(8640000000000000, isUtc: true),
      );
      expect(
        metadata.format.modificationTime,
        DateTime.fromMillisecondsSinceEpoch(8640000000000000, isUtc: true),
      );
    });

    test('ignores MP4 chapter track when includeChapters is false', () async {
      final bytes = _buildSyntheticMp4WithChapters();

      final loader = Mp4Loader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.chapters, isNull);
    });

    test('loader declares extension, MIME types and seek requirement', () {
      final loader = Mp4Loader();

      expect(
        loader.extension,
        containsAll(<String>['mp4', 'm4a', 'm4b', 'm4p', 'm4r', 'm4v']),
      );
      expect(
        loader.mimeType,
        containsAll(<String>['audio/mp4', 'video/mp4', 'audio/x-m4a']),
      );
      expect(loader.hasRandomAccessRequirements, isTrue);
      expect(loader.supports(_NonSeekTokenizer()), isFalse);
    });
  });
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
    ..._metadataItem('©ART', _dataAtom(1, utf8.encode('Test Artist'))),
    ..._metadataItem('aART', _dataAtom(1, utf8.encode('Test Album Artist'))),
    ..._metadataItem('©alb', _dataAtom(1, utf8.encode('Test Album'))),
    ..._metadataItem('©day', _dataAtom(1, utf8.encode('2024'))),
    ..._metadataItem('trkn', _dataAtom(0, <int>[0, 0, 0, 1, 0, 12, 0, 0])),
    ..._metadataItem('covr', _dataAtom(13, <int>[1, 2, 3, 4])),
    ..._metadataItem('----', <int>[
      ..._nameLikeAtom('mean', 'com.apple.iTunes'),
      ..._nameLikeAtom('name', 'MusicBrainz Track Id'),
      ..._dataAtom(1, utf8.encode('mbid-track-123')),
    ]),
  ]);

  final meta = _atom('meta', <int>[0, 0, 0, 0, ...ilst]);
  final udta = _atom('udta', meta);
  final moov = _atom('moov', <int>[...mvhd, ...trak, ...udta]);

  return <int>[...ftyp, ...moov];
}

List<int> _buildSyntheticMp4WithChapters() {
  final ftyp = _atom('ftyp', <int>[
    ...latin1.encode('M4A '),
    ...latin1.encode('isom'),
    ...latin1.encode('mp42'),
  ]);

  final mvhd = _atom('mvhd', _mvhdPayload(timeScale: 1000, duration: 2000));

  final audioTkhd = _atom('tkhd', _tkhdPayload(trackId: 1));
  final audioMdhd = _atom(
    'mdhd',
    _mdhdPayload(timeScale: 1000, duration: 2000),
  );
  final audioHdlr = _atom('hdlr', _hdlrPayload('soun'));
  final chapRef = _atom('tref', _atom('chap', _u32(2)));
  final audioStsd = _atom('stsd', _stsdPayloadMp4a());
  final audioStts = _atom(
    'stts',
    _sttsPayload(<List<int>>[
      <int>[2, 1000],
    ]),
  );
  final audioStsc = _atom(
    'stsc',
    _stscPayload(<List<int>>[
      <int>[1, 1],
    ]),
  );
  final audioStco = _atom('stco', _stcoPayload(<int>[0, 0]));
  final audioStbl = _atom('stbl', <int>[
    ...audioStsd,
    ...audioStts,
    ...audioStsc,
    ...audioStco,
  ]);
  final audioMinf = _atom('minf', audioStbl);
  final audioMdia = _atom('mdia', <int>[
    ...audioMdhd,
    ...audioHdlr,
    ...audioMinf,
  ]);
  final audioTrak = _atom('trak', <int>[
    ...audioTkhd,
    ...audioMdia,
    ...chapRef,
  ]);

  final chapterTkhd = _atom('tkhd', _tkhdPayload(trackId: 2));
  final chapterMdhd = _atom(
    'mdhd',
    _mdhdPayload(timeScale: 1000, duration: 2000),
  );
  final chapterHdlr = _atom('hdlr', _hdlrPayload('text'));
  final chapter1 = _chapterTextSample('Intro');
  final chapter2 = _chapterTextSample('Outro');
  final chapterStsc = _atom(
    'stsc',
    _stscPayload(<List<int>>[
      <int>[1, 1],
    ]),
  );
  final chapterStts = _atom(
    'stts',
    _sttsPayload(<List<int>>[
      <int>[2, 1000],
    ]),
  );
  final chapterStsz = _atom(
    'stsz',
    _stszPayload(0, <int>[chapter1.length, chapter2.length]),
  );
  final chapterStco = _atom('stco', _stcoPayload(<int>[0, 0]));
  final chapterStbl = _atom('stbl', <int>[
    ...chapterStts,
    ...chapterStsc,
    ...chapterStsz,
    ...chapterStco,
  ]);
  final chapterMinf = _atom('minf', chapterStbl);
  final chapterMdia = _atom('mdia', <int>[
    ...chapterMdhd,
    ...chapterHdlr,
    ...chapterMinf,
  ]);
  final chapterTrak = _atom('trak', <int>[...chapterTkhd, ...chapterMdia]);

  final moov = _atom('moov', <int>[...mvhd, ...audioTrak, ...chapterTrak]);

  final mdatPayload = <int>[
    ...chapter1,
    ...List<int>.filled(20, 0x11),
    ...chapter2,
    ...List<int>.filled(20, 0x22),
  ];
  final mdat = _atom('mdat', mdatPayload);

  final file = <int>[...ftyp, ...moov, ...mdat];
  final mdatDataOffset = ftyp.length + moov.length + 8;
  final chapter1Offset = mdatDataOffset;
  final audio1Offset = mdatDataOffset + chapter1.length;
  final chapter2Offset = mdatDataOffset + chapter1.length + 20;
  final audio2Offset = chapter2Offset + chapter2.length;

  final audioStcoOffset = _findSequence(file, audioStco);
  final chapterStcoOffset = _findSequence(file, chapterStco, occurrence: 2);
  _patchU32(file, audioStcoOffset + 16, audio1Offset);
  _patchU32(file, audioStcoOffset + 20, audio2Offset);
  _patchU32(file, chapterStcoOffset + 16, chapter1Offset);
  _patchU32(file, chapterStcoOffset + 20, chapter2Offset);

  return file;
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

List<int> _nameLikeAtom(String id, String value) =>
    _atom(id, <int>[0, 0, 0, 0, ...utf8.encode(value)]);

List<int> _chapterTextSample(String value) {
  final encoded = utf8.encode(value);
  return <int>[(encoded.length >> 8) & 0xFF, encoded.length & 0xFF, ...encoded];
}

List<int> _sttsPayload(List<List<int>> entries) => <int>[
  0,
  0,
  0,
  0,
  ..._u32(entries.length),
  for (final entry in entries) ...<int>[..._u32(entry[0]), ..._u32(entry[1])],
];

List<int> _stscPayload(List<List<int>> entries) => <int>[
  0,
  0,
  0,
  0,
  ..._u32(entries.length),
  for (final entry in entries) ...<int>[
    ..._u32(entry[0]),
    ..._u32(entry[1]),
    ..._u32(1),
  ],
];

List<int> _stszPayload(int sampleSize, List<int> entries) => <int>[
  0,
  0,
  0,
  0,
  ..._u32(sampleSize),
  ..._u32(entries.length),
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

List<int> _atom(String name, List<int> payload) {
  final length = 8 + payload.length;
  return <int>[..._u32(length), ...latin1.encode(name), ...payload];
}

int _findSequence(List<int> source, List<int> pattern, {int occurrence = 1}) {
  var seen = 0;
  for (var i = 0; i <= source.length - pattern.length; i++) {
    var matches = true;
    for (var j = 0; j < pattern.length; j++) {
      if (source[i + j] != pattern[j]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      seen++;
      if (seen == occurrence) {
        return i;
      }
    }
  }
  throw StateError('Pattern occurrence not found');
}

void _patchU32(List<int> target, int offset, int value) {
  target[offset] = (value >> 24) & 0xFF;
  target[offset + 1] = (value >> 16) & 0xFF;
  target[offset + 2] = (value >> 8) & 0xFF;
  target[offset + 3] = value & 0xFF;
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

List<int> _mvhdPayloadV1({
  required int timeScale,
  required Object duration,
  Object creationTime = 0,
  Object modificationTime = 0,
}) => <int>[
  1,
  0,
  0,
  0,
  ..._u64Value(creationTime),
  ..._u64Value(modificationTime),
  ..._u32(timeScale),
  ..._u64Value(duration),
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

List<int> _u64(int value) => <int>[
  (value >> 56) & 0xFF,
  (value >> 48) & 0xFF,
  (value >> 40) & 0xFF,
  (value >> 32) & 0xFF,
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _u64Value(Object value) {
  if (value is int) {
    return _u64(value);
  }
  if (value is BigInt) {
    return _u64BigInt(value);
  }
  throw ArgumentError.value(value, 'value', 'Expected int or BigInt');
}

List<int> _u64BigInt(BigInt value) => <int>[
  ((value >> 56) & BigInt.from(0xFF)).toInt(),
  ((value >> 48) & BigInt.from(0xFF)).toInt(),
  ((value >> 40) & BigInt.from(0xFF)).toInt(),
  ((value >> 32) & BigInt.from(0xFF)).toInt(),
  ((value >> 24) & BigInt.from(0xFF)).toInt(),
  ((value >> 16) & BigInt.from(0xFF)).toInt(),
  ((value >> 8) & BigInt.from(0xFF)).toInt(),
  (value & BigInt.from(0xFF)).toInt(),
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
