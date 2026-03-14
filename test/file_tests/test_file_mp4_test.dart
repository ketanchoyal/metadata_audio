import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata/audio_metadata.dart';
import 'package:audio_metadata/src/mp4/mp4_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('MP4/M4A file parsing', () {
    setUp(() {
      final registry = ParserRegistry()..register(Mp4Loader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('parses M4A with iTunes metadata from file', () async {
      // Build a minimal M4A file with iTunes metadata
      final bytes = _buildSyntheticMp4(
        title: 'M4A Test Title',
        artist: 'M4A Test Artist',
        album: 'M4A Test Album',
        albumartist: 'M4A Album Artist',
        year: 2024,
        track: 1,
      );

      // Write to samples directory
      final sampleDir = Directory(p.join(samplePath, 'mp4'))
        ..createSync(recursive: true);
      final file = File(p.join(sampleDir.path, 'itunes_test.m4a'))
        ..writeAsBytesSync(bytes);

      try {
        // Parse the file
        final metadata = await parseFile(file.path);

        // Verify format
        checkFormat(
          metadata.format,
          container: 'M4A/isom/mp42',
          codec: 'MPEG-4/AAC',
          sampleRate: 44100,
          numberOfChannels: 2,
        );

        // Verify common tags
        checkCommon(
          metadata.common,
          title: 'M4A Test Title',
          artist: 'M4A Test Artist',
          album: 'M4A Test Album',
          albumartist: 'M4A Album Artist',
          track: 1,
        );
        expect(metadata.common.date, equals('2024'));
      } finally {
        // Cleanup
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    });

    test('parses M4A with minimal metadata from file', () async {
      // Build a minimal M4A file with just title
      final bytes = _buildSyntheticMp4(title: 'Minimal M4A');

      final sampleDir = Directory(p.join(samplePath, 'mp4'))
        ..createSync(recursive: true);
      final file = File(p.join(sampleDir.path, 'minimal_test.m4a'))
        ..writeAsBytesSync(bytes);

      try {
        final metadata = await parseFile(file.path);

        // Verify format
        checkFormat(
          metadata.format,
          container: 'M4A/isom/mp42',
          codec: 'MPEG-4/AAC',
        );

        // Verify title is present
        expect(metadata.common.title, equals('Minimal M4A'));
      } finally {
        // Cleanup
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    });
  });
}

/// Build a synthetic MP4/M4A file with iTunes metadata
List<int> _buildSyntheticMp4({
  String? title,
  String? artist,
  String? album,
  String? albumartist,
  int? year,
  int? track,
}) {
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

  final ilst = _buildIlst(
    title: title,
    artist: artist,
    album: album,
    albumartist: albumartist,
    year: year,
    track: track,
  );

  final meta = _atom('meta', <int>[0, 0, 0, 0, ...ilst]);
  final udta = _atom('udta', meta);
  final moov = _atom('moov', <int>[...mvhd, ...trak, ...udta]);

  return <int>[...ftyp, ...moov];
}

/// Build iTunes metadata atom (ilst)
List<int> _buildIlst({
  String? title,
  String? artist,
  String? album,
  String? albumartist,
  int? year,
  int? track,
}) {
  final items = <int>[];

  if (title != null) {
    items.addAll(_metadataItem('©nam', _dataAtom(1, utf8.encode(title))));
  }
  if (artist != null) {
    items.addAll(_metadataItem('©ART', _dataAtom(1, utf8.encode(artist))));
  }
  if (albumartist != null) {
    items.addAll(_metadataItem('aART', _dataAtom(1, utf8.encode(albumartist))));
  }
  if (album != null) {
    items.addAll(_metadataItem('©alb', _dataAtom(1, utf8.encode(album))));
  }
  if (year != null) {
    items.addAll(
      _metadataItem('©day', _dataAtom(1, utf8.encode(year.toString()))),
    );
  }
  if (track != null) {
    items.addAll(
      _metadataItem('trkn', _dataAtom(0, <int>[0, 0, 0, track, 0, 0, 0, 0])),
    );
  }

  return _atom('ilst', items);
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
