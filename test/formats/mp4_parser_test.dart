import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/mp4/mp4_loader.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';
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

List<int> _nameLikeAtom(String id, String value) {
  return _atom(id, <int>[0, 0, 0, 0, ...utf8.encode(value)]);
}

List<int> _atom(String name, List<int> payload) {
  final length = 8 + payload.length;
  return <int>[..._u32(length), ...latin1.encode(name), ...payload];
}

List<int> _mvhdPayload({required int timeScale, required int duration}) {
  return <int>[
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
}

List<int> _tkhdPayload({required int trackId}) {
  return <int>[
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
}

List<int> _mdhdPayload({required int timeScale, required int duration}) {
  return <int>[
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
}

List<int> _hdlrPayload(String handlerType) {
  return <int>[
    0,
    0,
    0,
    0,
    ...latin1.encode('mhlr'),
    ...latin1.encode(handlerType),
    ...List<int>.filled(12, 0),
  ];
}

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

List<int> _u32(int value) {
  return <int>[
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];
}

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
