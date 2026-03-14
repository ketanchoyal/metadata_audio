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

List<int> _buildId3v2Header() {
  return <int>[0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
}

List<int> _buildFlacFile({
  required List<int> streamInfo,
  required List<String> comments,
  List<int>? picture,
}) {
  final blocks = <List<int>>[];
  blocks.add(_buildMetadataBlock(type: 0, isLast: false, payload: streamInfo));

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

  if (comments.isEmpty && picture == null) {
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

  final sampleRateShifted = sampleRate << 4;
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

List<int> _uInt32Le(int value) {
  return <int>[
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ];
}

List<int> _uInt32Be(int value) {
  return <int>[
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];
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
