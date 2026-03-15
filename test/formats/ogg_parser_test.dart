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

      expect(metadata.format.container, 'Ogg');
      expect(metadata.format.codec, 'Vorbis I');
      expect(metadata.format.sampleRate, 44100);
      expect(metadata.format.numberOfChannels, 2);
      expect(metadata.format.hasAudio, isTrue);
      expect(metadata.format.hasVideo, isFalse);
    });

    test('parses Vorbis comments and maps common tags', () async {
      const streamSerial = 3;
      final firstPage = _buildOggPage(
        headerTypeFlags: 0x02,
        granulePosition: 0,
        streamSerialNumber: streamSerial,
        pageSequenceNo: 0,
        payload: _buildVorbisIdentificationPayload(
          channels: 2,
          sampleRate: 48000,
        ),
      );
      final commentPage = _buildOggPage(
        headerTypeFlags: 0x00,
        granulePosition: 0,
        streamSerialNumber: streamSerial,
        pageSequenceNo: 1,
        payload: _buildVorbisCommentPayload(
          vendor: 'ogg-unit-test',
          comments: const <String>[
            'TITLE=Vorbis Test Title',
            'ARTIST=Vorbis Artist',
            'TRACKNUMBER=4',
            'ENCODER=Vorbis Encoder',
          ],
        ),
      );
      final lastPage = _buildOggPage(
        headerTypeFlags: 0x04,
        granulePosition: 0,
        streamSerialNumber: streamSerial,
        pageSequenceNo: 2,
        payload: <int>[0],
      );

      final bytes = <int>[...firstPage, ...commentPage, ...lastPage];
      final loader = OggLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.common.title, 'Vorbis Test Title');
      expect(metadata.common.artist, 'Vorbis Artist');
      expect(metadata.common.track.no, 4);
      expect(metadata.format.tool, 'Vorbis Encoder');
      expect(metadata.native['vorbis'], isNotNull);
    });

    test('parses Vorbis chapter tags into format.chapters', () async {
      const streamSerial = 31;
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
          vendor: 'ogg-chapter-test',
          comments: const <String>[
            'CHAPTER001=00:00:00.000',
            'CHAPTER001NAME=Intro',
            'CHAPTER002=00:01:30.500',
            'CHAPTER002NAME=Verse',
          ],
        ),
      );
      final lastPage = _buildOggPage(
        headerTypeFlags: 0x04,
        granulePosition: 44100 * 120,
        streamSerialNumber: streamSerial,
        pageSequenceNo: 2,
        payload: <int>[0],
      );

      final metadata = await OggLoader().parse(
        BytesTokenizer(
          Uint8List.fromList(<int>[...firstPage, ...commentPage, ...lastPage]),
          fileInfo: FileInfo(
            size: firstPage.length + commentPage.length + lastPage.length,
          ),
        ),
        const ParseOptions(includeChapters: true),
      );

      expect(metadata.format.chapters, isNotNull);
      expect(metadata.format.chapters, hasLength(2));
      expect(metadata.format.chapters![0].title, 'Intro');
      expect(metadata.format.chapters![0].start, 0);
      expect(metadata.format.chapters![0].end, 90500);
      expect(metadata.format.chapters![1].title, 'Verse');
      expect(metadata.format.chapters![1].start, 90500);
    });

    test('parses Opus identification header and OpusTags comments', () async {
      const streamSerial = 5;
      final firstPage = _buildOggPage(
        headerTypeFlags: 0x02,
        granulePosition: 0,
        streamSerialNumber: streamSerial,
        pageSequenceNo: 0,
        payload: _buildOpusHeadPayload(
          channels: 2,
          preSkip: 312,
          sampleRate: 48000,
        ),
      );
      final tagsPage = _buildOggPage(
        headerTypeFlags: 0x00,
        granulePosition: 0,
        streamSerialNumber: streamSerial,
        pageSequenceNo: 1,
        payload: _buildOpusTagsPayload(
          vendor: 'opus-unit-test',
          comments: const <String>['TITLE=Opus Title', 'ARTIST=Opus Artist'],
        ),
      );
      final lastPage = _buildOggPage(
        headerTypeFlags: 0x04,
        granulePosition: 96000,
        streamSerialNumber: streamSerial,
        pageSequenceNo: 2,
        payload: <int>[0],
      );

      final bytes = <int>[...firstPage, ...tagsPage, ...lastPage];
      final loader = OggLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(duration: true),
      );

      expect(metadata.format.codec, 'Opus');
      expect(metadata.format.sampleRate, 48000);
      expect(metadata.format.numberOfChannels, 2);
      expect(metadata.common.title, 'Opus Title');
      expect(metadata.common.artist, 'Opus Artist');
      expect(metadata.format.numberOfSamples, 96000 - 312);
      expect(
        metadata.format.duration,
        closeTo((96000 - 312) / 48000.0, 0.0001),
      );
    });

    test('parses Speex header', () async {
      final bytes = _buildOggPage(
        headerTypeFlags: 0x06,
        granulePosition: 0,
        streamSerialNumber: 6,
        pageSequenceNo: 0,
        payload: _buildSpeexHeaderPayload(
          version: 'speex-1.2rc',
          channels: 1,
          sampleRate: 16000,
          bitrate: 32000,
        ),
      );

      final loader = OggLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.codec, startsWith('Speex'));
      expect(metadata.format.sampleRate, 16000);
      expect(metadata.format.numberOfChannels, 1);
      expect(metadata.format.hasAudio, isTrue);
    });

    test('parses Theora identification header as video stream', () async {
      final bytes = _buildOggPage(
        headerTypeFlags: 0x06,
        granulePosition: 0,
        streamSerialNumber: 7,
        pageSequenceNo: 0,
        payload: _buildTheoraIdentificationPayload(bitrate: 900000),
      );

      final loader = OggLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.codec, 'Theora');
      expect(metadata.format.hasVideo, isTrue);
      expect(metadata.format.bitrate, 900000);
    });

    test('parses Ogg-FLAC first page stream info', () async {
      final bytes = _buildOggPage(
        headerTypeFlags: 0x06,
        granulePosition: 0,
        streamSerialNumber: 8,
        pageSequenceNo: 0,
        payload: _buildOggFlacFirstPayload(totalSamples: 88200),
      );

      final loader = OggLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.codec, 'FLAC');
      expect(metadata.format.lossless, isTrue);
      expect(metadata.format.sampleRate, 44100);
      expect(metadata.format.numberOfChannels, 2);
      expect(metadata.format.bitsPerSample, 16);
      expect(metadata.format.numberOfSamples, 88200);
      expect(metadata.format.duration, closeTo(2.0, 0.0001));
    });

    test('derives duration from granule position on last page', () async {
      const streamSerial = 9;
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
}) => <int>[
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

List<int> _buildOpusHeadPayload({
  required int channels,
  required int preSkip,
  required int sampleRate,
}) => <int>[
    ...ascii.encode('OpusHead'),
    1,
    channels,
    preSkip & 0xFF,
    (preSkip >> 8) & 0xFF,
    ..._uint32Le(sampleRate),
    0,
    0,
    0,
  ];

List<int> _buildOpusTagsPayload({
  required String vendor,
  required List<String> comments,
}) {
  final data = <int>[...ascii.encode('OpusTags')];
  final vendorBytes = utf8.encode(vendor);
  data.addAll(_uint32Le(vendorBytes.length));
  data.addAll(vendorBytes);
  data.addAll(_uint32Le(comments.length));

  for (final comment in comments) {
    final encoded = utf8.encode(comment);
    data.addAll(_uint32Le(encoded.length));
    data.addAll(encoded);
  }

  return data;
}

List<int> _buildSpeexHeaderPayload({
  required String version,
  required int channels,
  required int sampleRate,
  required int bitrate,
}) {
  final data = List<int>.filled(80, 0);
  final signature = ascii.encode('Speex   ');
  for (var i = 0; i < signature.length; i++) {
    data[i] = signature[i];
  }

  final versionBytes = ascii.encode(version);
  for (var i = 0; i < versionBytes.length && i < 20; i++) {
    data[8 + i] = versionBytes[i];
  }

  _writeInt32Le(data, 36, sampleRate);
  _writeInt32Le(data, 48, channels);
  _writeInt32Le(data, 52, bitrate);
  return data;
}

List<int> _buildTheoraIdentificationPayload({required int bitrate}) {
  final data = List<int>.filled(42, 0);
  data[0] = 0x80;
  final signature = ascii.encode('theora');
  for (var i = 0; i < signature.length; i++) {
    data[1 + i] = signature[i];
  }
  data[37] = (bitrate >> 16) & 0xFF;
  data[38] = (bitrate >> 8) & 0xFF;
  data[39] = bitrate & 0xFF;
  return data;
}

List<int> _buildOggFlacFirstPayload({required int totalSamples}) {
  final streamInfo = _buildFlacStreamInfoBlock(totalSamples: totalSamples);
  return <int>[
    0x7F,
    ...ascii.encode('FLAC'),
    0x01,
    0x00,
    0x00,
    0x00,
    ...ascii.encode('fLaC'),
    0x80,
    0x00,
    0x00,
    streamInfo.length,
    ...streamInfo,
  ];
}

List<int> _buildFlacStreamInfoBlock({required int totalSamples}) {
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

void _writeInt32Le(List<int> target, int offset, int value) {
  target[offset] = value & 0xFF;
  target[offset + 1] = (value >> 8) & 0xFF;
  target[offset + 2] = (value >> 16) & 0xFF;
  target[offset + 3] = (value >> 24) & 0xFF;
}

List<int> _uint32Le(int value) => <int>[
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ];

List<int> _uint64Le(int value) {
  final low = value & 0xFFFFFFFF;
  final high = (value >> 32) & 0xFFFFFFFF;
  return <int>[..._uint32Le(low), ..._uint32Le(high)];
}
