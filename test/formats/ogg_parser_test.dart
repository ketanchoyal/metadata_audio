import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/ogg/ogg_loader.dart';
import 'package:audio_metadata/src/ogg/ogg_parser.dart';
import 'package:audio_metadata/src/ogg/ogg_token.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:test/test.dart';

void main() {
  group('OggToken', () {
    test('parses page header and segment table', () {
      final payload = _buildVorbisIdentificationPayload(
        channels: 2,
        sampleRate: 44100,
      );
      final page = _buildOggPage(
        headerTypeFlags: 0x02,
        granulePosition: 0,
        streamSerialNumber: 17,
        pageSequenceNo: 3,
        payload: payload,
      );

      final header = OggToken.parsePageHeader(page.sublist(0, 27));
      expect(header.capturePattern, 'OggS');
      expect(header.version, 0);
      expect(header.headerType.firstPage, isTrue);
      expect(header.streamSerialNumber, 17);
      expect(header.pageSequenceNo, 3);
      expect(header.pageSegments, 1);

      final segments = OggToken.parseSegmentTable(page.sublist(27, 28), 1);
      expect(segments.totalPageSize, payload.length);
      expect(segments.lacingValues, equals(<int>[payload.length]));
    });
  });

  group('OggParser / OggLoader', () {
    test('detects Ogg header and identifies Vorbis stream', () async {
      final payload = _buildVorbisIdentificationPayload(
        channels: 2,
        sampleRate: 44100,
      );
      final bytes = _buildOggPage(
        headerTypeFlags: 0x06,
        granulePosition: 0,
        streamSerialNumber: 1,
        pageSequenceNo: 0,
        payload: payload,
      );

      final loader = OggLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.container, 'ogg');
      expect(metadata.format.codec, 'Vorbis I');
      expect(metadata.format.sampleRate, 44100);
      expect(metadata.format.numberOfChannels, 2);
      expect(metadata.format.hasAudio, isTrue);
      expect(metadata.format.hasVideo, isFalse);
    });

    test('derives duration from granule position on last page', () async {
      final streamSerial = 9;
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
      final lastPage = _buildOggPage(
        headerTypeFlags: 0x04,
        granulePosition: 88200,
        streamSerialNumber: streamSerial,
        pageSequenceNo: 1,
        payload: <int>[0],
      );
      final bytes = <int>[...firstPage, ...lastPage];

      final loader = OggLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(duration: true),
      );

      expect(metadata.format.numberOfSamples, 88200);
      expect(metadata.format.duration, closeTo(2.0, 0.0001));
      expect(metadata.format.bitrate, isNotNull);
    });

    test('throws on invalid Ogg capture pattern', () async {
      final invalidPage = <int>[
        ...ascii.encode('Bad!'),
        ...List<int>.filled(23, 0),
      ];

      final loader = OggLoader();
      await expectLater(
        loader.parse(
          BytesTokenizer(Uint8List.fromList(invalidPage)),
          const ParseOptions(),
        ),
        throwsA(isA<OggContentError>()),
      );
    });

    test('loader declares extensions and MIME types', () {
      final loader = OggLoader();
      expect(loader.extension, containsAll(<String>['ogg', 'oga', 'ogv']));
      expect(
        loader.mimeType,
        containsAll(<String>['audio/ogg', 'application/ogg', 'audio/vorbis']),
      );
      expect(loader.hasRandomAccessRequirements, isFalse);
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
  ];
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
