import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata/src/flac/flac_loader.dart';
import 'package:audio_metadata/src/flac/flac_parser.dart';
import 'package:audio_metadata/src/flac/flac_token.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  group('FlacParser / FlacLoader', () {
    test('detects FLAC preamble when ID3v2 header is prefixed', () async {
      final bytes = <int>[
        ..._buildId3v2Header(),
        ..._buildFlacFile(
          streamInfo: _buildStreamInfoBlock(totalSamples: 88200),
          comments: const <String>[],
        ),
      ];

      final loader = FlacLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.container, 'FLAC');
      expect(metadata.format.codec, 'FLAC');
      expect(metadata.format.hasAudio, isTrue);
      expect(metadata.format.lossless, isTrue);
    });

    test('parses STREAMINFO values', () async {
      final bytes = _buildFlacFile(
        streamInfo: _buildStreamInfoBlock(totalSamples: 132300),
        comments: const <String>[],
      );

      final loader = FlacLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.sampleRate, 44100);
      expect(metadata.format.numberOfChannels, 2);
      expect(metadata.format.bitsPerSample, 16);
      expect(metadata.format.numberOfSamples, 132300);
      expect(metadata.format.duration, closeTo(3.0, 0.0001));
      expect(metadata.format.audioMD5, hasLength(16));
    });

    test('extracts Vorbis comments and maps to common tags', () async {
      final bytes = _buildFlacFile(
        streamInfo: _buildStreamInfoBlock(totalSamples: 88200),
        comments: const <String>[
          'TITLE=Test Title',
          'ARTIST=Test Artist',
          'ALBUM=Test Album',
          'TRACKNUMBER=07',
          'GENRE=Alt. Rock',
          'ENCODER=unit-test-encoder',
        ],
      );

      final loader = FlacLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.common.title, 'Test Title');
      expect(metadata.common.artist, 'Test Artist');
      expect(metadata.common.album, 'Test Album');
      expect(metadata.common.track.no, 7);
      expect(metadata.common.genre, equals(const <String>['Alt. Rock']));
      expect(metadata.format.tool, 'unit-test-encoder');

      final vorbisTags = metadata.native['vorbis'];
      expect(vorbisTags, isNotNull);
      expect(
        vorbisTags!.where((tag) => tag.id == 'TITLE').single.value,
        'Test Title',
      );
    });

    test(
      'extracts PICTURE block into native and common picture tags',
      () async {
        final pictureData = <int>[1, 2, 3, 4, 5, 6, 7, 8];
        final bytes = _buildFlacFile(
          streamInfo: _buildStreamInfoBlock(totalSamples: 88200),
          comments: const <String>['TITLE=With Picture'],
          picture: _buildPictureBlock(data: pictureData),
        );

        final loader = FlacLoader();
        final metadata = await loader.parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(),
        );

        final picture = metadata.common.picture;
        expect(picture, isNotNull);
        expect(picture!, hasLength(1));
        expect(picture.first.format, 'image/jpeg');
        expect(picture.first.type, 'Cover (front)');
        expect(picture.first.data, equals(pictureData));

        final vorbisTags = metadata.native['vorbis'];
        expect(vorbisTags, isNotNull);
        final nativePicture =
            vorbisTags!
                    .where((tag) => tag.id == 'METADATA_BLOCK_PICTURE')
                    .single
                    .value
                as FlacPicture;
        expect(nativePicture.width, 300);
        expect(nativePicture.height, 300);
        expect(nativePicture.colourDepth, 24);
        expect(nativePicture.data, equals(pictureData));
      },
    );

    test('parses CUESHEET into format.chapters when enabled', () async {
      final bytes = _buildFlacFile(
        streamInfo: _buildStreamInfoBlock(totalSamples: 132300),
        comments: const <String>[],
        cueSheet: _buildCueSheetBlock(
          trackOffsets: const <int>[0, 44100, 132300],
          trackNumbers: const <int>[1, 2, 0xAA],
        ),
      );

      final loader = FlacLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(includeChapters: true),
      );

      expect(metadata.format.chapters, isNotNull);
      expect(metadata.format.chapters, hasLength(2));
      expect(metadata.format.chapters![0].title, 'Track 01');
      expect(metadata.format.chapters![0].start, 0);
      expect(metadata.format.chapters![0].end, 1000);
      expect(metadata.format.chapters![0].sampleOffset, 0);
      expect(metadata.format.chapters![1].title, 'Track 02');
      expect(metadata.format.chapters![1].start, 1000);
      expect(metadata.format.chapters![1].end, 3000);
      final flacTags = metadata.native['flac'];
      expect(flacTags, isNotNull);
      expect(flacTags!.where((tag) => tag.id == 'CUESHEET'), isNotEmpty);
    });

    test('skips CUESHEET chapters when includeChapters is false', () async {
      final bytes = _buildFlacFile(
        streamInfo: _buildStreamInfoBlock(totalSamples: 132300),
        comments: const <String>[],
        cueSheet: _buildCueSheetBlock(
          trackOffsets: const <int>[0, 44100, 132300],
          trackNumbers: const <int>[1, 2, 0xAA],
        ),
      );

      final loader = FlacLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.chapters, isNull);
      final flacTags = metadata.native['flac'];
      expect(flacTags, isNotNull);
      expect(flacTags!.where((tag) => tag.id == 'CUESHEET'), isNotEmpty);
    });

    test('throws on invalid FLAC preamble', () async {
      final loader = FlacLoader();
      final bytes = Uint8List.fromList(<int>[0x00, 0x00, 0x00, 0x00]);

      await expectLater(
        loader.parse(BytesTokenizer(bytes), const ParseOptions()),
        throwsA(isA<FlacContentError>()),
      );
    });

    test('loader declares extension, MIME types and seek requirement', () {
      final loader = FlacLoader();
      expect(loader.extension, contains('flac'));
      expect(loader.mimeType, contains('audio/flac'));
      expect(loader.mimeType, contains('audio/x-flac'));
      expect(loader.hasRandomAccessRequirements, isTrue);
      expect(loader.supports(_NonSeekTokenizer()), isFalse);
    });
  });
}

List<int> _buildId3v2Header() => <int>[0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];

List<int> _buildFlacFile({
  required List<int> streamInfo,
  required List<String> comments,
  List<int>? picture,
  List<int>? cueSheet,
}) {
  final blocks = <List<int>>[];
  blocks.add(_buildMetadataBlock(type: 0, isLast: false, payload: streamInfo));

  if (cueSheet != null) {
    blocks.add(
      _buildMetadataBlock(
        type: 5,
        isLast: comments.isEmpty && picture == null,
        payload: cueSheet,
      ),
    );
  }

  if (comments.isNotEmpty) {
    blocks.add(
      _buildMetadataBlock(
        type: 4,
        isLast: picture == null,
        payload: _buildVorbisCommentPayload(comments),
      ),
    );
  }

  if (picture != null) {
    blocks.add(_buildMetadataBlock(type: 6, isLast: true, payload: picture));
  }

  if (comments.isEmpty && picture == null && cueSheet == null) {
    blocks[0] = _buildMetadataBlock(type: 0, isLast: true, payload: streamInfo);
  }

  return <int>[...ascii.encode('fLaC'), for (final block in blocks) ...block];
}

List<int> _buildMetadataBlock({
  required int type,
  required bool isLast,
  required List<int> payload,
}) {
  final headerByte = (isLast ? 0x80 : 0x00) | (type & 0x7F);
  final length = payload.length;
  return <int>[
    headerByte,
    (length >> 16) & 0xFF,
    (length >> 8) & 0xFF,
    length & 0xFF,
    ...payload,
  ];
}

List<int> _buildStreamInfoBlock({required int totalSamples}) {
  const sampleRate = 44100;
  const channels = 2;
  const bitsPerSample = 16;

  final streamInfo = List<int>.filled(34, 0);

  streamInfo[0] = 0x10;
  streamInfo[1] = 0x00;
  streamInfo[2] = 0x10;
  streamInfo[3] = 0x00;

  const sampleRateShifted = sampleRate << 4;
  streamInfo[10] = (sampleRateShifted >> 16) & 0xFF;
  streamInfo[11] = (sampleRateShifted >> 8) & 0xFF;
  streamInfo[12] =
      (sampleRateShifted & 0xF0) |
      (((channels - 1) & 0x07) << 1) |
      (((bitsPerSample - 1) >> 4) & 0x01);
  streamInfo[13] =
      (((bitsPerSample - 1) & 0x0F) << 4) | ((totalSamples >> 32) & 0x0F);
  streamInfo[14] = (totalSamples >> 24) & 0xFF;
  streamInfo[15] = (totalSamples >> 16) & 0xFF;
  streamInfo[16] = (totalSamples >> 8) & 0xFF;
  streamInfo[17] = totalSamples & 0xFF;

  return streamInfo;
}

List<int> _buildVorbisCommentPayload(List<String> comments) {
  final data = <int>[];
  final vendor = ascii.encode('test-vendor');
  data.addAll(_uInt32Le(vendor.length));
  data.addAll(vendor);
  data.addAll(_uInt32Le(comments.length));

  for (final comment in comments) {
    final encoded = utf8.encode(comment);
    data.addAll(_uInt32Le(encoded.length));
    data.addAll(encoded);
  }

  return data;
}

List<int> _buildPictureBlock({required List<int> data}) {
  final mime = ascii.encode('image/jpeg');
  final description = utf8.encode('');

  final payload = <int>[];
  payload.addAll(_uInt32Be(3));
  payload.addAll(_uInt32Be(mime.length));
  payload.addAll(mime);
  payload.addAll(_uInt32Be(description.length));
  payload.addAll(description);
  payload.addAll(_uInt32Be(300));
  payload.addAll(_uInt32Be(300));
  payload.addAll(_uInt32Be(24));
  payload.addAll(_uInt32Be(0));
  payload.addAll(_uInt32Be(data.length));
  payload.addAll(data);

  return payload;
}

List<int> _buildCueSheetBlock({
  required List<int> trackOffsets,
  required List<int> trackNumbers,
}) {
  final payload = <int>[
    ...List<int>.filled(128, 0),
    ..._uInt64Be(0),
    0,
    ...List<int>.filled(258, 0),
    trackOffsets.length,
  ];

  for (var i = 0; i < trackOffsets.length; i++) {
    payload.addAll(_uInt64Be(trackOffsets[i]));
    payload.add(trackNumbers[i]);
    payload.addAll(List<int>.filled(12, 0));
    payload.add(0);
    payload.addAll(List<int>.filled(13, 0));
    payload.add(0);
  }

  return payload;
}

List<int> _uInt32Le(int value) => <int>[
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ];

List<int> _uInt32Be(int value) => <int>[
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];

List<int> _uInt64Be(int value) => <int>[
    (value >> 56) & 0xFF,
    (value >> 48) & 0xFF,
    (value >> 40) & 0xFF,
    (value >> 32) & 0xFF,
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];

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
