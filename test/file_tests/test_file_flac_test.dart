import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata/audio_metadata.dart';
import 'package:audio_metadata/src/flac/flac_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('FLAC file parsing', () {
    setUp(() {
      final registry = ParserRegistry()..register(FlacLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('parses FLAC with Vorbis comments from file', () async {
      // Build FLAC file with metadata
      final bytes = _buildFlacFile(
        streamInfo: _buildStreamInfoBlock(totalSamples: 44100),
        comments: <String>[
          'TITLE=FLAC Test Title',
          'ARTIST=FLAC Test Artist',
          'ALBUM=FLAC Test Album',
        ],
      );

      // Write to samples directory
      final sampleDir = Directory(p.join(samplePath, 'flac'))
        ..createSync(recursive: true);
      final file = File(p.join(sampleDir.path, 'vorbis_test.flac'))
        ..writeAsBytesSync(bytes);

      try {
        // Parse the file
        final metadata = await parseFile(file.path);

        // Verify format
        checkFormat(
          metadata.format,
          container: 'flac',
          codec: 'FLAC',
          sampleRate: 44100,
          numberOfChannels: 2,
          lossless: true,
        );

        // Verify common tags
        checkCommon(
          metadata.common,
          title: 'FLAC Test Title',
          artist: 'FLAC Test Artist',
          album: 'FLAC Test Album',
        );
      } finally {
        // Cleanup
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    });

    test('parses FLAC with picture block from file', () async {
      final pictureData = <int>[0x11, 0x22, 0x33, 0x44];
      final bytes = _buildFlacFile(
        streamInfo: _buildStreamInfoBlock(totalSamples: 88200),
        comments: <String>['TITLE=FLAC Picture Test'],
        picture: _buildPictureBlock(data: pictureData),
      );

      final sampleDir = Directory(p.join(samplePath, 'flac'))
        ..createSync(recursive: true);
      final file = File(p.join(sampleDir.path, 'picture_test.flac'))
        ..writeAsBytesSync(bytes);

      try {
        final metadata = await parseFile(file.path);

        checkFormat(metadata.format, container: 'flac');
        checkCommon(metadata.common, title: 'FLAC Picture Test');

        final picture = metadata.common.picture;
        expect(picture, isNotNull);
        expect(picture, hasLength(1));
        expect(picture!.single.data, equals(pictureData));
      } finally {
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    });

    test('parses minimal FLAC with only streaminfo', () async {
      final bytes = _buildFlacFile(
        streamInfo: _buildStreamInfoBlock(totalSamples: 22050),
        comments: <String>[],
      );

      final sampleDir = Directory(p.join(samplePath, 'flac'))
        ..createSync(recursive: true);
      final file = File(p.join(sampleDir.path, 'minimal_test.flac'))
        ..writeAsBytesSync(bytes);

      try {
        final metadata = await parseFile(file.path);

        checkFormat(
          metadata.format,
          container: 'flac',
          codec: 'FLAC',
          sampleRate: 44100,
          numberOfChannels: 2,
          lossless: true,
        );
      } finally {
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    });
  });
}

/// Build a complete FLAC file with metadata blocks
List<int> _buildFlacFile({
  required List<int> streamInfo,
  required List<String> comments,
  List<int>? picture,
}) {
  final blocks = <List<int>>[
    _buildMetadataBlock(type: 0, isLast: false, payload: streamInfo),
  ];

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

/// Build a FLAC metadata block header + payload
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

/// Build a FLAC streaminfo block
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

/// Build a Vorbis comment block payload
List<int> _buildVorbisCommentPayload(List<String> comments) {
  final data = <int>[];
  final vendor = ascii.encode('test-vendor');
  data
    ..addAll(_uInt32Le(vendor.length))
    ..addAll(vendor)
    ..addAll(_uInt32Le(comments.length));

  for (final comment in comments) {
    final encoded = utf8.encode(comment);
    data
      ..addAll(_uInt32Le(encoded.length))
      ..addAll(encoded);
  }

  return data;
}

/// Build a FLAC picture block
List<int> _buildPictureBlock({required List<int> data}) {
  final mime = ascii.encode('image/jpeg');
  final description = utf8.encode('');

  final payload = <int>[
    ..._uInt32Be(3),
    ..._uInt32Be(mime.length),
    ...mime,
    ..._uInt32Be(description.length),
    ...description,
    ..._uInt32Be(300),
    ..._uInt32Be(300),
    ..._uInt32Be(24),
    ..._uInt32Be(0),
    ..._uInt32Be(data.length),
    ...data,
  ];

  return payload;
}

/// Little-endian 32-bit integer
List<int> _uInt32Le(int value) => <int>[
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

/// Big-endian 32-bit integer
List<int> _uInt32Be(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];
