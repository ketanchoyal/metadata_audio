import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/flac/flac_loader.dart';
import 'package:test/test.dart';

void main() {
  group('concurrent parsing', () {
    late Directory tempDir;
    late _FlacFixture fixtureA;
    late _FlacFixture fixtureB;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'audio_metadata_concurrent_',
      );

      fixtureA = await _writeFixture(
        directory: tempDir,
        fileName: 'flac.flac',
        title: 'Concurrent Fixture A',
        pictureData: <int>[0x11, 0x22, 0x33, 0x44],
      );
      fixtureB = await _writeFixture(
        directory: tempDir,
        fileName: 'flac-bug.flac',
        title: 'Concurrent Fixture B',
        pictureData: <int>[0xAA, 0xBB, 0xCC, 0xDD, 0xEE],
      );
    });

    setUp(() {
      final registry = ParserRegistry()..register(FlacLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    tearDownAll(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'handles concurrent file parsing with picture extraction parity',
      () async {
        final fixtures = <_FlacFixture>[fixtureA, fixtureB];

        final metadataList = await Future.wait<AudioMetadata>(
          fixtures.map((fixture) => parseFile(fixture.filePath)),
        );

        for (var i = 0; i < fixtures.length; i++) {
          final metadata = metadataList[i];
          final expected = await File(fixtures[i].jpgPath).readAsBytes();
          final picture = metadata.common.picture;

          expect(metadata.common.title, equals(fixtures[i].title));
          expect(picture, isNotNull);
          expect(picture, hasLength(1));
          expect(picture!.single.data, equals(expected));
        }
      },
    );

    test(
      'keeps metadata and picture data isolated under heavy concurrency',
      () async {
        final jobs = <({_FlacFixture fixture, Future<AudioMetadata> future})>[];

        for (var i = 0; i < 32; i++) {
          final fixture = i.isEven ? fixtureA : fixtureB;
          jobs.add((
            fixture: fixture,
            future: parseBytes(
              Uint8List.fromList(fixture.fileBytes),
              fileInfo: const FileInfo(mimeType: 'audio/flac'),
            ),
          ));
        }

        final metadataList = await Future.wait<AudioMetadata>(
          jobs.map((job) => job.future),
        );

        for (var i = 0; i < metadataList.length; i++) {
          final expectedFixture = jobs[i].fixture;
          final metadata = metadataList[i];
          final picture = metadata.common.picture;

          expect(metadata.common.title, equals(expectedFixture.title));
          expect(picture, isNotNull);
          expect(picture, hasLength(1));
          expect(picture!.single.data, equals(expectedFixture.pictureData));
        }
      },
    );

    test('does not leak skipCovers state across concurrent parses', () async {
      final futures = <Future<AudioMetadata>>[];

      for (var i = 0; i < 24; i++) {
        final skipCovers = i.isOdd;
        futures.add(
          parseBytes(
            Uint8List.fromList(fixtureA.fileBytes),
            fileInfo: const FileInfo(mimeType: 'audio/flac'),
            options: ParseOptions(skipCovers: skipCovers),
          ),
        );
      }

      final results = await Future.wait<AudioMetadata>(futures);

      for (var i = 0; i < results.length; i++) {
        if (i.isOdd) {
          expect(results[i].common.picture, isNull);
        } else {
          expect(results[i].common.picture, isNotNull);
          expect(results[i].common.picture, hasLength(1));
          expect(results[i].common.picture!.single.data, fixtureA.pictureData);
        }
      }
    });
  });
}

class _FlacFixture {
  const _FlacFixture({
    required this.filePath,
    required this.jpgPath,
    required this.fileBytes,
    required this.pictureData,
    required this.title,
  });

  final String filePath;
  final String jpgPath;
  final List<int> fileBytes;
  final List<int> pictureData;
  final String title;
}

Future<_FlacFixture> _writeFixture({
  required Directory directory,
  required String fileName,
  required String title,
  required List<int> pictureData,
}) async {
  final bytes = _buildFlacFile(
    streamInfo: _buildStreamInfoBlock(totalSamples: 88200),
    comments: <String>['TITLE=$title'],
    picture: _buildPictureBlock(data: pictureData),
  );

  final filePath = '${directory.path}/$fileName';
  final jpgPath = '$filePath.jpg';

  await File(filePath).writeAsBytes(bytes);
  await File(jpgPath).writeAsBytes(pictureData);

  return _FlacFixture(
    filePath: filePath,
    jpgPath: jpgPath,
    fileBytes: bytes,
    pictureData: pictureData,
    title: title,
  );
}

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
  final vendor = ascii.encode('concurrent-test-vendor');
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
