import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata/audio_metadata.dart';
import 'package:audio_metadata/src/ogg/ogg_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('OGG file parsing', () {
    setUp(() {
      final registry = ParserRegistry()..register(OggLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('parses OGG Vorbis with Vorbis comments from file', () async {
      // Build OGG Vorbis file with metadata
      final streamSerial = 1;
      final firstPage = _buildOggPage(
        headerTypeFlags: 0x02,
        granulePosition: 0,
        streamSerialNumber: streamSerial,
        pageSequenceNo: 0,
        payload: _buildVorbisIdentificationPayload(
          channels: 2,
          sampleRate: 44100,
        ),
      );
      final commentPage = _buildOggPage(
        headerTypeFlags: 0x00,
        granulePosition: 0,
        streamSerialNumber: streamSerial,
        pageSequenceNo: 1,
        payload: _buildVorbisCommentPayload(
          vendor: 'test-vorbis-encoder',
          comments: const <String>[
            'TITLE=OGG Vorbis Test Title',
            'ARTIST=OGG Vorbis Test Artist',
            'ALBUM=OGG Vorbis Test Album',
            'TRACKNUMBER=5',
          ],
        ),
      );
      final lastPage = _buildOggPage(
        headerTypeFlags: 0x04,
        granulePosition: 88200,
        streamSerialNumber: streamSerial,
        pageSequenceNo: 2,
        payload: <int>[0],
      );

      final bytes = <int>[...firstPage, ...commentPage, ...lastPage];

      // Write to samples directory
      final sampleDir = Directory(p.join(samplePath, 'ogg'))
        ..createSync(recursive: true);
      final file = File(p.join(sampleDir.path, 'vorbis_test.ogg'))
        ..writeAsBytesSync(bytes);

      try {
        // Parse the file
        final metadata = await parseFile(file.path);

        // Verify format
        checkFormat(
          metadata.format,
          container: 'ogg',
          codec: 'Vorbis I',
          sampleRate: 44100,
          numberOfChannels: 2,
        );

        // Verify common tags
        checkCommon(
          metadata.common,
          title: 'OGG Vorbis Test Title',
          artist: 'OGG Vorbis Test Artist',
          album: 'OGG Vorbis Test Album',
          track: 5,
        );
      } finally {
        // Cleanup
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    });

    test('parses minimal OGG Vorbis with only identification header', () async {
      final streamSerial = 2;
      final firstPage = _buildOggPage(
        headerTypeFlags: 0x02,
        granulePosition: 0,
        streamSerialNumber: streamSerial,
        pageSequenceNo: 0,
        payload: _buildVorbisIdentificationPayload(
          channels: 1,
          sampleRate: 48000,
        ),
      );
      final lastPage = _buildOggPage(
        headerTypeFlags: 0x04,
        granulePosition: 0,
        streamSerialNumber: streamSerial,
        pageSequenceNo: 1,
        payload: <int>[0],
      );

      final bytes = <int>[...firstPage, ...lastPage];

      // Write to samples directory
      final sampleDir = Directory(p.join(samplePath, 'ogg'))
        ..createSync(recursive: true);
      final file = File(p.join(sampleDir.path, 'minimal_test.ogg'))
        ..writeAsBytesSync(bytes);

      try {
        // Parse the file
        final metadata = await parseFile(file.path);

        // Verify format
        checkFormat(
          metadata.format,
          container: 'ogg',
          codec: 'Vorbis I',
          sampleRate: 48000,
          numberOfChannels: 1,
        );

        // Verify no common tags
        expect(metadata.common.title, isNull);
        expect(metadata.common.artist, isNull);
      } finally {
        // Cleanup
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    });
  });
}

List<int> _buildOggPage({
  required int headerTypeFlags,
  required int granulePosition,
  required int streamSerialNumber,
  required int pageSequenceNo,
  required List<int> payload,
}) {
  if (payload.length > 255) {
    throw ArgumentError('Test helper currently supports payload <= 255 bytes');
  }

  return <int>[
    ...ascii.encode('OggS'),
    0,
    headerTypeFlags,
    ..._uint64Le(granulePosition),
    ..._uint32Le(streamSerialNumber),
    ..._uint32Le(pageSequenceNo),
    ..._uint32Le(0),
    1,
    payload.length,
    ...payload,
  ];
}

List<int> _buildVorbisIdentificationPayload({
  required int channels,
  required int sampleRate,
}) {
  return <int>[
    0x01,
    ...ascii.encode('vorbis'),
    ..._uint32Le(0),
    channels,
    ..._uint32Le(sampleRate),
    ..._uint32Le(0),
    ..._uint32Le(192000),
    ..._uint32Le(0),
    0,
    1,
  ];
}

List<int> _buildVorbisCommentPayload({
  required String vendor,
  required List<String> comments,
}) {
  final data = <int>[0x03, ...ascii.encode('vorbis')];
  final vendorBytes = utf8.encode(vendor);
  data.addAll(_uint32Le(vendorBytes.length));
  data.addAll(vendorBytes);
  data.addAll(_uint32Le(comments.length));

  for (final comment in comments) {
    final encoded = utf8.encode(comment);
    data.addAll(_uint32Le(encoded.length));
    data.addAll(encoded);
  }

  data.add(1);
  return data;
}

List<int> _uint32Le(int value) {
  return <int>[
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ];
}

List<int> _uint64Le(int value) {
  final low = value & 0xFFFFFFFF;
  final high = (value >> 32) & 0xFFFFFFFF;
  return <int>[..._uint32Le(low), ..._uint32Le(high)];
}
