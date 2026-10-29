/// TrackInfo tests for Ogg parsers: every identified logical audio/video
/// stream must surface a `format.trackInfo` entry (upstream parity).
library;

import 'dart:typed_data';

import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/ogg/ogg_loader.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:test/test.dart';

List<int> _buildOggPage({
  required int headerTypeFlags,
  required int granulePosition,
  required int streamSerialNumber,
  required int pageSequenceNo,
  required List<int> payload,
  List<int> segmentSizes = const [255, 4],
}) {
  final segments = <int>[];
  var remaining = payload.length;
  var sizes = segmentSizes.toList();
  while (remaining > 0) {
    if (sizes.isEmpty) sizes = [255, 4];
    final take = sizes.removeAt(0).clamp(1, remaining);
    segments.add(take);
    remaining -= take;
  }

  final bytes = <int>[
    ...'OggS'.codeUnits,
    0x00, // version
    headerTypeFlags,
    ..._littleEndian64(granulePosition),
    ..._littleEndian32(streamSerialNumber),
    ..._littleEndian32(pageSequenceNo),
    0x00, 0x00, 0x00, 0x00, // CRC (not validated by our parser)
    segments.length,
    if (segments.isEmpty) 0,
    ...segments,
    ...payload,
  ];
  return bytes;
}

List<int> _littleEndian64(int value) => [
  for (var i = 0; i < 8; i++) (value >> (8 * i)) & 0xff,
];

List<int> _littleEndian32(int value) => [
  for (var i = 0; i < 4; i++) (value >> (8 * i)) & 0xff,
];

List<int> _buildVorbisIdentificationPayload({
  required int channels,
  required int sampleRate,
  int bitrateNominal = 112000,
}) => [
  0x01,
  ...'vorbis'.codeUnits,
  // version = 0
  0x00, 0x00, 0x00, 0x00,
  channels,
  ..._littleEndian32(sampleRate),
  // bitrates: min == 0, nominal, max == 0
  0x00, 0x00, 0x00, 0x00,
  ..._littleEndian32(bitrateNominal),
  0x00, 0x00, 0x00, 0x00,
  // block sizes
  0x01,
  0x01, // framing
];

void main() {
  Future<AudioMetadata> parse(List<int> bytes, {required int fileLength}) {
    final loader = OggLoader();
    return loader.parse(
      BytesTokenizer(
        Uint8List.fromList(bytes),
        fileInfo: FileInfo(size: fileLength),
      ),
      const ParseOptions(),
    );
  }

  group('Ogg trackInfo', () {
    test('creates an audio track for a Vorbis stream', () async {
      final pageNoBytes = _buildVorbisIdentificationPayload(
        channels: 2,
        sampleRate: 44100,
      );
      final firstPage = _buildOggPage(
        headerTypeFlags: 0x02, // first page
        granulePosition: 0,
        streamSerialNumber: 17,
        pageSequenceNo: 0,
        payload: pageNoBytes,
      );

      final samples = 9000;
      final secondPayload = <int>[0x00];
      final secondPage = _buildOggPage(
        headerTypeFlags: 0x04, // last page
        granulePosition: samples,
        streamSerialNumber: 17,
        pageSequenceNo: 1,
        payload: secondPayload,
      );

      final bytes = [...firstPage, ...secondPage];
      final metadata = await parse(bytes, fileLength: bytes.length);

      expect(metadata.format.trackInfo, hasLength(1));
      final track = metadata.format.trackInfo.single;
      expect(track.type, equals('audio'));
      expect(track.codecName, equals('Vorbis I'));
      expect(track.id, equals(17));
      expect(track.audio?.samplingFrequency, equals(44100));
      expect(track.audio?.channels, equals(2));
      expect(track.audio?.numberOfSamples, equals(samples));
      expect(track.duration, closeTo(samples / 44100, 1e-9));
      expect(track.bitrate, isNotNull);
      expect(track.bitrate, greaterThan(0));
    });

    test(
      'creates one track per logical stream with its serial as id',
      () async {
        final idPayload = _buildVorbisIdentificationPayload(
          channels: 2,
          sampleRate: 44100,
        );

        final first = _buildOggPage(
          headerTypeFlags: 0x02,
          granulePosition: 0,
          streamSerialNumber: 1,
          pageSequenceNo: 0,
          payload: idPayload,
        );
        final second = _buildOggPage(
          headerTypeFlags: 0x04,
          granulePosition: 5000,
          streamSerialNumber: 1,
          pageSequenceNo: 1,
          payload: const [0x00],
        );
        final third = _buildOggPage(
          headerTypeFlags: 0x02,
          granulePosition: 0,
          streamSerialNumber: 2,
          pageSequenceNo: 0,
          payload: idPayload,
        );
        final fourth = _buildOggPage(
          headerTypeFlags: 0x04,
          granulePosition: 8000,
          streamSerialNumber: 2,
          pageSequenceNo: 1,
          payload: const [0x00],
        );

        final bytes = [...first, ...third, ...second, ...fourth];
        final metadata = await parse(bytes, fileLength: bytes.length);

        expect(metadata.format.trackInfo, hasLength(2));
        expect(
          metadata.format.trackInfo.map((track) => track.id).toSet(),
          equals({1, 2}),
        );
        for (final track in metadata.format.trackInfo) {
          expect(track.type, equals('audio'));
          expect(track.codecName, equals('Vorbis I'));
          expect(track.duration, greaterThan(0));
        }
      },
    );
  });
}
