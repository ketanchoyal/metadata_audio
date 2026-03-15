import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/musepack/musepack_content_error.dart';
import 'package:audio_metadata/src/musepack/musepack_loader.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  group('MusepackParser / MusepackLoader', () {
    test('parses Musepack SV7 stream and APEv2 tags', () async {
      final bytes = _buildSv7File();

      final metadata = await MusepackLoader().parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.container, 'Musepack, SV7');
      expect(metadata.format.hasAudio, isTrue);
      expect(metadata.format.hasVideo, isFalse);
      expect(metadata.format.sampleRate, 44100);
      expect(metadata.format.numberOfChannels, 2);
      expect(metadata.format.numberOfSamples, 1268);
      expect(metadata.format.duration, closeTo(1268 / 44100, 0.000001));
      expect(metadata.format.codec, '1.15');
      expect(metadata.format.bitrate, closeTo(11825, 2));

      expect(metadata.common.title, 'SV7 Title');
      expect(metadata.common.artist, 'SV7 Artist');
      expect(metadata.common.album, 'SV7 Album');
      expect(metadata.common.track.no, 9);
      expect(metadata.common.track.of, isNull);
    });

    test('parses Musepack SV8 packets and APEv2 tags', () async {
      final bytes = _buildSv8File();

      final metadata = await MusepackLoader().parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.container, 'Musepack, SV8');
      expect(metadata.format.hasAudio, isTrue);
      expect(metadata.format.hasVideo, isFalse);
      expect(metadata.format.sampleRate, 48000);
      expect(metadata.format.numberOfChannels, 2);
      expect(metadata.format.numberOfSamples, 24000);
      expect(metadata.format.duration, closeTo(0.5, 0.000001));
      expect(metadata.format.bitrate, 32368);

      expect(metadata.common.title, 'SV8 Title');
      expect(metadata.common.artist, 'SV8 Artist');
      expect(metadata.common.track.no, 5);
      expect(metadata.common.track.of, isNull);
    });

    test(
      'parses Musepack in Matroska (mka) with tracks, tags, chapters',
      () async {
        final bytes = _buildMatroskaMusepackFile();

        final metadata = await MusepackLoader().parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(includeChapters: true),
        );

        expect(metadata.format.container, 'EBML/matroska');
        expect(metadata.format.hasAudio, isTrue);
        expect(metadata.format.hasVideo, isFalse);
        expect(metadata.format.codec, 'MPC');
        expect(metadata.format.sampleRate, 48000);
        expect(metadata.format.numberOfChannels, 2);
        expect(metadata.format.duration, closeTo(5.0, 0.0001));

        expect(metadata.common.title, 'MKA Track Title');
        expect(metadata.common.artist, 'MKA Artist');
        expect(metadata.common.album, 'MKA Album');
        expect(metadata.common.track.no, 2);

        expect(metadata.common.picture, isNotNull);
        expect(metadata.common.picture, hasLength(1));
        expect(metadata.common.picture!.first.format, 'image/jpeg');

        expect(metadata.format.chapters, isNotNull);
        expect(metadata.format.chapters, hasLength(1));
        expect(metadata.format.chapters!.first.title, 'Intro');
        expect(metadata.format.trackInfo, hasLength(1));
        expect(metadata.format.trackInfo.first.type, 'audio');
        expect(metadata.format.trackInfo.first.codecName, 'MPC');
      },
    );

    test('throws on unsupported signature', () async {
      final bytes = Uint8List.fromList(<int>[0x00, 0x01, 0x02, 0x03]);

      await expectLater(
        MusepackLoader().parse(BytesTokenizer(bytes), const ParseOptions()),
        throwsA(isA<MusepackContentError>()),
      );
    });

    test('loader declares extensions, MIME types, and seek requirement', () {
      final loader = MusepackLoader();

      expect(
        loader.extension,
        containsAll(<String>['mpc', 'mp+', 'mpk', 'mka']),
      );
      expect(
        loader.mimeType,
        containsAll(<String>[
          'audio/x-musepack',
          'audio/musepack',
          'video/x-musepack',
          'video/webm',
        ]),
      );
      expect(loader.hasRandomAccessRequirements, isTrue);
      expect(loader.supports(_NonSeekTokenizer()), isFalse);
    });
  });
}

List<int> _buildSv7File() {
  final header = _buildSv7Header(
    frameCount: 2,
    sampleFrequencyIndex: 0,
    intensityStereo: true,
    midSideStereo: false,
    streamMajorVersion: 7,
    streamMinorVersion: 1,
    lastFrameLength: 116,
  );

  final bitstream = _packBitsToLittleEndianWords(<_BitField>[
    const _BitField(value: 115, bits: 8),
    const _BitField(value: 0, bits: 20),
    const _BitField(value: 0, bits: 20),
    const _BitField(value: 300, bits: 11),
  ]);

  final ape = _buildApeHeaderTag(<List<int>>[
    _textItem('Title', 'SV7 Title'),
    _textItem('Artist', 'SV7 Artist'),
    _textItem('Album', 'SV7 Album'),
    _textItem('Track', '9/10'),
  ]);

  return <int>[...header, ...bitstream, ...ape];
}

List<int> _buildSv8File() {
  final shPayload = <int>[
    ..._u32le(0xAABBCCDD),
    8,
    ..._encodeSv8VarInt(24000),
    ..._encodeSv8VarInt(0),
    0x20,
    0x10,
  ];

  final apPayload = List<int>.filled(2023, 0);

  final packets = <int>[
    ..._sv8Packet('SH', shPayload),
    ..._sv8Packet('AP', apPayload),
    ..._sv8Packet('SE', const <int>[]),
  ];

  final ape = _buildApeHeaderTag(<List<int>>[
    _textItem('Title', 'SV8 Title'),
    _textItem('Artist', 'SV8 Artist'),
    _textItem('Track', '5/32'),
  ]);

  return <int>[...ascii.encode('MPCK'), ...packets, ...ape];
}

List<int> _buildMatroskaMusepackFile() {
  final ebmlHeader = _element(const <int>[
    0x1A,
    0x45,
    0xDF,
    0xA3,
  ], _element(const <int>[0x42, 0x82], utf8.encode('matroska')));

  final info = _element(
    const <int>[0x15, 0x49, 0xA9, 0x66],
    <int>[
      ..._element(const <int>[0x2A, 0xD7, 0xB1], _encodeUint(1000000)),
      ..._element(const <int>[0x44, 0x89], _encodeFloat64(5000)),
      ..._element(const <int>[0x57, 0x41], utf8.encode('mk-writer')),
    ],
  );

  final audioEntry = _element(
    const <int>[0xAE],
    <int>[
      ..._element(const <int>[0xD7], _encodeUint(1)),
      ..._element(const <int>[0x83], _encodeUint(2)),
      ..._element(const <int>[0x88], _encodeUint(1)),
      ..._element(const <int>[0x86], utf8.encode('A_MPC')),
      ..._element(
        const <int>[0xE1],
        <int>[
          ..._element(const <int>[0xB5], _encodeFloat32(48000)),
          ..._element(const <int>[0x9F], _encodeUint(2)),
        ],
      ),
    ],
  );

  final tracks = _element(const <int>[0x16, 0x54, 0xAE, 0x6B], audioEntry);

  final tags = _element(
    const <int>[0x12, 0x54, 0xC3, 0x67],
    <int>[
      ..._tagEntry(
        targetTypeValue: 30,
        simpleTags: const <List<String>>[
          <String>['TITLE', 'MKA Track Title'],
          <String>['ARTIST', 'MKA Artist'],
          <String>['PART_NUMBER', '2'],
        ],
      ),
      ..._tagEntry(
        targetTypeValue: 50,
        simpleTags: const <List<String>>[
          <String>['TITLE', 'MKA Album'],
        ],
      ),
    ],
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
    <int>[...info, ...tracks, ...tags, ...attachments, ...chapters],
  );

  return <int>[...ebmlHeader, ...segment];
}

List<int> _buildSv7Header({
  required int frameCount,
  required int sampleFrequencyIndex,
  required bool intensityStereo,
  required bool midSideStereo,
  required int streamMajorVersion,
  required int streamMinorVersion,
  required int lastFrameLength,
}) {
  final bytes = List<int>.filled(24, 0);
  bytes[0] = 0x4D;
  bytes[1] = 0x50;
  bytes[2] = 0x2B;
  bytes[3] = ((streamMajorVersion & 0x0F) << 4) | (streamMinorVersion & 0x0F);

  bytes.setRange(4, 8, _u32le(frameCount));

  final word2b2 = (sampleFrequencyIndex & 0x03) << 6;
  bytes[10] = word2b2;
  var word2b3 = 0;
  if (intensityStereo) {
    word2b3 |= 0x40;
  }
  if (midSideStereo) {
    word2b3 |= 0x80;
  }
  bytes[11] = word2b3;

  final word5 = (lastFrameLength & 0x07FF) << 20;
  bytes.setRange(20, 24, _u32le(word5));

  return bytes;
}

List<int> _packBitsToLittleEndianWords(List<_BitField> fields) {
  final bits = <int>[];
  for (final field in fields) {
    for (var bit = field.bits - 1; bit >= 0; bit--) {
      bits.add((field.value >> bit) & 0x01);
    }
  }

  final out = <int>[];
  for (var i = 0; i < bits.length; i += 32) {
    var word = 0;
    for (var b = 0; b < 32; b++) {
      final bit = (i + b) < bits.length ? bits[i + b] : 0;
      word = (word << 1) | bit;
    }
    out.addAll(_u32le(word));
  }
  return out;
}

List<int> _sv8Packet(String key, List<int> payload) {
  final keyBytes = ascii.encode(key);
  var sizeField = _encodeSv8VarInt(payload.length + 3);
  while (true) {
    final expectedValue = payload.length + 2 + sizeField.length;
    final updated = _encodeSv8VarInt(expectedValue);
    if (updated.length == sizeField.length) {
      sizeField = updated;
      break;
    }
    sizeField = updated;
  }
  return <int>[...keyBytes, ...sizeField, ...payload];
}

List<int> _encodeSv8VarInt(int value) {
  if (value < 0) {
    throw ArgumentError.value(value, 'value', 'Must be non-negative');
  }

  final groups = <int>[value & 0x7F];
  var remaining = value >> 7;
  while (remaining > 0) {
    groups.insert(0, remaining & 0x7F);
    remaining >>= 7;
  }

  for (var i = 0; i < groups.length - 1; i++) {
    groups[i] |= 0x80;
  }
  return groups;
}

List<int> _buildApeHeaderTag(List<List<int>> items) {
  final payload = <int>[for (final item in items) ...item];
  return <int>[
    ..._apeTagFooter(
      size: payload.length + 32,
      fields: items.length,
      flags: (1 << 30) | (1 << 29),
    ),
    ...payload,
  ];
}

List<int> _textItem(String key, String value) {
  final payload = utf8.encode(value);
  return <int>[
    ..._u32le(payload.length),
    ..._u32le(0),
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
    ...ascii.encode('APETAGEX'),
    ..._u32le(2000),
    ..._u32le(size),
    ..._u32le(fields),
    ..._u32le(flags),
    ...List<int>.filled(8, 0),
  ];

List<int> _tagEntry({
  required int targetTypeValue,
  required List<List<String>> simpleTags,
}) {
  final target = _element(const <int>[
    0x63,
    0xC0,
  ], _element(const <int>[0x68, 0xCA], _encodeUint(targetTypeValue)));

  final tags = <int>[];
  for (final simpleTag in simpleTags) {
    tags.addAll(
      _element(
        const <int>[0x67, 0xC8],
        <int>[
          ..._element(const <int>[0x45, 0xA3], utf8.encode(simpleTag[0])),
          ..._element(const <int>[0x44, 0x87], utf8.encode(simpleTag[1])),
        ],
      ),
    );
  }

  return _element(const <int>[0x73, 0x73], <int>[...target, ...tags]);
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

List<int> _encodeFloat32(double value) {
  final bytes = ByteData(4)..setFloat32(0, value);
  return bytes.buffer.asUint8List();
}

List<int> _encodeFloat64(double value) {
  final bytes = ByteData(8)..setFloat64(0, value);
  return bytes.buffer.asUint8List();
}

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

List<int> _u32le(int value) => <int>[
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

class _BitField {
  const _BitField({required this.value, required this.bits});

  final int value;
  final int bits;
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
