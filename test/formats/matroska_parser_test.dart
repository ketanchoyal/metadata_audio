import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata/src/matroska/matroska_loader.dart';
import 'package:audio_metadata/src/matroska/matroska_parser.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  group('MatroskaParser / MatroskaLoader', () {
    test(
      'parses EBML matroska docType, info, tracks, tags, and attachments',
      () async {
        final bytes = _buildMatroskaFile(docType: 'matroska');

        final loader = MatroskaLoader();
        final metadata = await loader.parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(includeChapters: true),
        );

        expect(metadata.format.container, 'EBML/matroska');
        expect(metadata.format.duration, closeTo(5.0, 0.0001));
        expect(metadata.format.codec, 'OPUS');
        expect(metadata.format.sampleRate, 48000);
        expect(metadata.format.numberOfChannels, 2);
        expect(metadata.format.hasAudio, isTrue);
        expect(metadata.format.hasVideo, isTrue);

        expect(metadata.common.title, 'Track Title');
        expect(metadata.common.artist, 'Unit Artist');
        expect(metadata.common.album, 'Unit Album');
        expect(metadata.common.genre, equals(const <String>['Folk']));

        final pictures = metadata.common.picture;
        expect(pictures, isNotNull);
        expect(pictures, hasLength(1));
        expect(pictures!.first.format, 'image/jpeg');
        expect(pictures.first.description, 'Poster');
        expect(pictures.first.name, 'cover.jpg');
        expect(pictures.first.data, equals(const <int>[0x11, 0x22, 0x33]));

        expect(metadata.format.chapters, isNotNull);
        expect(metadata.format.chapters, hasLength(1));
        expect(metadata.format.chapters!.first.title, 'Intro');
        expect(metadata.format.chapters!.first.start, 0);
        expect(metadata.format.chapters!.first.end, 5000);
      },
    );

    test('accepts webm docType', () async {
      final bytes = _buildMatroskaFile(docType: 'webm');

      final loader = MatroskaLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.container, 'EBML/webm');
    });

    test('rejects unsupported EBML docType', () async {
      final bytes = _buildMatroskaFile(docType: 'x-custom');

      final loader = MatroskaLoader();
      await expectLater(
        loader.parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(),
        ),
        throwsA(isA<MatroskaContentError>()),
      );
    });

    test('extracts trackInfo for video and audio tracks', () async {
      final bytes = _buildMatroskaFile(docType: 'matroska');

      final loader = MatroskaLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.trackInfo, hasLength(2));

      final videoTrack = metadata.format.trackInfo.first;
      expect(videoTrack.type, 'video');
      expect(videoTrack.codecName, 'VP8');
      expect(videoTrack.video, isNotNull);
      expect(videoTrack.video!.pixelWidth, 640);
      expect(videoTrack.video!.pixelHeight, 360);

      final audioTrack = metadata.format.trackInfo[1];
      expect(audioTrack.type, 'audio');
      expect(audioTrack.codecName, 'OPUS');
      expect(audioTrack.audio, isNotNull);
      expect(audioTrack.audio!.samplingFrequency, 48000);
      expect(audioTrack.audio!.channels, 2);
    });

    test('loader declares extensions, MIME types, and seek requirement', () {
      final loader = MatroskaLoader();

      expect(
        loader.extension,
        containsAll(<String>['mka', 'mkv', 'mk3d', 'mks', 'webm']),
      );
      expect(
        loader.mimeType,
        containsAll(<String>[
          'audio/matroska',
          'video/matroska',
          'audio/webm',
          'video/webm',
        ]),
      );
      expect(loader.hasRandomAccessRequirements, isTrue);
      expect(loader.supports(_NonSeekTokenizer()), isFalse);
    });
  });
}

List<int> _buildMatroskaFile({required String docType}) {
  final ebmlHeader = _element(const <int>[
    0x1A,
    0x45,
    0xDF,
    0xA3,
  ], _element(const <int>[0x42, 0x82], utf8.encode(docType)));

  final info = _element(
    const <int>[0x15, 0x49, 0xA9, 0x66],
    <int>[
      ..._element(const <int>[0x2A, 0xD7, 0xB1], _encodeUint(1000000)),
      ..._element(const <int>[0x44, 0x89], _encodeFloat64(5000)),
      ..._element(const <int>[0x7B, 0xA9], utf8.encode('Segment Title')),
      ..._element(const <int>[0x57, 0x41], utf8.encode('unit-writer')),
    ],
  );

  final videoEntry = _element(
    const <int>[0xAE],
    <int>[
      ..._element(const <int>[0xD7], _encodeUint(1)),
      ..._element(const <int>[0x83], _encodeUint(1)),
      ..._element(const <int>[0x86], utf8.encode('V_VP8')),
      ..._element(
        const <int>[0xE0],
        <int>[
          ..._element(const <int>[0xB0], _encodeUint(640)),
          ..._element(const <int>[0xBA], _encodeUint(360)),
          ..._element(const <int>[0x54, 0xB0], _encodeUint(640)),
          ..._element(const <int>[0x54, 0xBA], _encodeUint(360)),
        ],
      ),
    ],
  );

  final audioEntry = _element(
    const <int>[0xAE],
    <int>[
      ..._element(const <int>[0xD7], _encodeUint(2)),
      ..._element(const <int>[0x83], _encodeUint(2)),
      ..._element(const <int>[0x88], _encodeUint(1)),
      ..._element(const <int>[0x22, 0xB5, 0x9C], utf8.encode('eng')),
      ..._element(const <int>[0x86], utf8.encode('A_OPUS')),
      ..._element(
        const <int>[0xE1],
        <int>[
          ..._element(const <int>[0xB5], _encodeFloat32(48000)),
          ..._element(const <int>[0x9F], _encodeUint(2)),
        ],
      ),
    ],
  );

  final tracks = _element(
    const <int>[0x16, 0x54, 0xAE, 0x6B],
    <int>[...videoEntry, ...audioEntry],
  );

  final tags = _element(
    const <int>[0x12, 0x54, 0xC3, 0x67],
    <int>[
      ..._tagEntry(
        targetTypeValue: 30,
        simpleTags: const <List<String>>[
          <String>['TITLE', 'Track Title'],
          <String>['ARTIST', 'Unit Artist'],
          <String>['GENRE', 'Folk'],
        ],
      ),
      ..._tagEntry(
        targetTypeValue: 50,
        simpleTags: const <List<String>>[
          <String>['TITLE', 'Unit Album'],
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
        ..._element(const <int>[0x46, 0x7E], utf8.encode('Poster')),
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

class _NonSeekTokenizer implements Tokenizer {
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
