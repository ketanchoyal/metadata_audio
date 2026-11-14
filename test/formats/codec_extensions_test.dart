import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/dsdiff/dsdiff_loader.dart';
import 'package:metadata_audio/src/dsdiff/dsdiff_parser.dart';
import 'package:metadata_audio/src/dsf/dsf_loader.dart';
import 'package:metadata_audio/src/dsf/dsf_parser.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/ogg/ogg_loader.dart';
import 'package:metadata_audio/src/ogg/opus/opus_decoder.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:metadata_audio/src/wav/wave_loader.dart';
import 'package:test/test.dart';

void main() {
  group('Opus Channel Mapping and Gain Extensions', () {
    test('parses Family 0 (mono and stereo) with output gain', () {
      // Family 0, stereo (2 channels), pre-skip 312, input rate 48000, output gain -768 (-3.0 dB)
      final headerBytes = <int>[
        ...ascii.encode('OpusHead'),
        1, // Version 1
        2, // 2 channels
        ..._u16le(312), // preSkip
        ..._u32le(48000), // inputSampleRate
        ..._i16le(-768), // outputGain: -768 / 256.0 = -3.0 dB
        0, // Family 0
      ];

      final header = OpusDecoder.parseIdHeader(headerBytes);
      expect(header.version, 1);
      expect(header.channelCount, 2);
      expect(header.preSkip, 312);
      expect(header.inputSampleRate, 48000);
      expect(header.outputGain, -768);
      expect(header.outputGainDb, closeTo(-3.0, 0.001));
      expect(header.channelMapping, 0);
      expect(header.streamCount, 1);
      expect(header.coupledCount, 1);
      expect(header.channelMappingTable, equals(const [0, 1]));

      final names = OpusDecoder.channelPositions(2, 0);
      expect(names, equals(const ['front-left', 'front-right']));
    });

    test('parses Family 1 (5.1 surround) with mapping table', () {
      // Family 1, 6 channels (5.1), preSkip 384, rate 48000, gain +256 (+1.0 dB)
      // streamCount: 4, coupledCount: 2
      // mapping: [0, 4, 1, 2, 3, 5] (FL, C, FR, RL, RR, LFE)
      final headerBytes = <int>[
        ...ascii.encode('OpusHead'),
        1, // Version 1
        6, // 6 channels
        ..._u16le(384),
        ..._u32le(48000),
        ..._i16le(256), // +1.0 dB
        1, // Family 1
        4, // Stream count (M)
        2, // Coupled count (N)
        0, 4, 1, 2, 3, 5, // Mapping table
      ];

      final header = OpusDecoder.parseIdHeader(headerBytes);
      expect(header.channelCount, 6);
      expect(header.outputGainDb, closeTo(1.0, 0.001));
      expect(header.channelMapping, 1);
      expect(header.streamCount, 4);
      expect(header.coupledCount, 2);
      expect(header.channelMappingTable, equals(const [0, 4, 1, 2, 3, 5]));

      final names = OpusDecoder.channelPositions(6, 1);
      expect(
        names,
        equals(const [
          'front-left',
          'front-center',
          'front-right',
          'rear-left',
          'rear-right',
          'lfe',
        ]),
      );
    });

    test('rejects truncated Family 1 mapping table', () {
      final truncated = <int>[
        ...ascii.encode('OpusHead'),
        1,
        6, // 6 channels expected
        ..._u16le(384),
        ..._u32le(48000),
        0, 0,
        1, // Family 1
        4, 2,
        0, 1, // Only 2 bytes instead of 6 bytes!
      ];

      expect(
        () => OpusDecoder.parseIdHeader(truncated),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('truncated'),
        )),
      );
    });

    test('OggLoader integrates Opus gain and channel positions into metadata', () async {
      // Synthetic Ogg Opus stream with ID header (gain -512 = -2.0 dB, 6 channels) and comment page
      final idHeader = <int>[
        ...ascii.encode('OpusHead'),
        1,
        6,
        ..._u16le(384),
        ..._u32le(48000),
        ..._i16le(-512), // -2.0 dB
        1,
        4, 2,
        0, 4, 1, 2, 3, 5,
      ];
      final idPage = _buildOggPage(
        headerType: 0x02, // BOS
        granulePos: 0,
        streamSerial: 0x1234,
        pageSeq: 0,
        payload: idHeader,
      );

      final tagsHeader = <int>[
        ...ascii.encode('OpusTags'),
        ..._u32le(4),
        ...ascii.encode('Test'),
        ..._u32le(1), // 1 comment
        ..._u32le(12),
        ...ascii.encode('TITLE=Opus51'),
      ];
      final tagsPage = _buildOggPage(
        headerType: 0x00,
        granulePos: 0,
        streamSerial: 0x1234,
        pageSeq: 1,
        payload: tagsHeader,
      );

      final audioPage = _buildOggPage(
        headerType: 0x04, // EOS
        granulePos: 48000 + 384, // 1 second of audio (48000 samples)
        streamSerial: 0x1234,
        pageSeq: 2,
        payload: List<int>.filled(50, 0),
      );

      final oggFile = <int>[...idPage, ...tagsPage, ...audioPage];
      final loader = OggLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(oggFile)),
        const ParseOptions(duration: true),
      );

      expect(res.format.codec, 'Opus');
      expect(res.format.numberOfChannels, 6);
      expect(res.format.trackGain, closeTo(-2.0, 0.001));
      expect(res.common.title, 'Opus51');

      expect(res.format.trackInfo, isNotEmpty);
      final track = res.format.trackInfo.first.audio;
      expect(track, isNotNull);
      expect(track!.channels, 6);
      expect(track.channelPositions, equals(const [0, 4, 1, 2, 3, 5]));
    });
  });

  group('RIFF CSET Extended Encodings', () {
    List<int> buildWavWithCset({
      required int codePage,
      required String infoId,
      required List<int> rawValueBytes,
    }) {
      final fmtPayload = <int>[
        ..._u16le(1), // PCM
        ..._u16le(1), // 1 channel
        ..._u32le(8000), // 8000 Hz
        ..._u32le(16000),
        ..._u16le(2),
        ..._u16le(16),
      ];

      final chunks = <int>[];
      chunks.addAll(ascii.encode('fmt '));
      chunks.addAll(_u32le(fmtPayload.length));
      chunks.addAll(fmtPayload);

      // CSET chunk (8 bytes)
      chunks.addAll(ascii.encode('CSET'));
      chunks.addAll(_u32le(8));
      chunks.addAll(_u16le(codePage));
      chunks.addAll(_u16le(0)); // country code
      chunks.addAll(_u16le(0)); // language
      chunks.addAll(_u16le(0)); // dialect

      // LIST/INFO chunk
      final infoPayload = <int>[
        ...ascii.encode('INFO'),
        ...ascii.encode(infoId),
        ..._u32le(rawValueBytes.length),
        ...rawValueBytes,
        if (rawValueBytes.length.isOdd) 0,
      ];
      chunks.addAll(ascii.encode('LIST'));
      chunks.addAll(_u32le(infoPayload.length));
      chunks.addAll(infoPayload);
      if (infoPayload.length.isOdd) chunks.add(0);

      // data chunk (empty dummy)
      chunks.addAll(ascii.encode('data'));
      chunks.addAll(_u32le(0));

      final riff = <int>[
        ...ascii.encode('RIFF'),
        ..._u32le(4 + chunks.length),
        ...ascii.encode('WAVE'),
        ...chunks,
      ];

      return riff;
    }

    test('decodes UTF-16LE in code page 1200', () async {
      const text = 'Unicode Song';
      final utf16leBytes = <int>[];
      for (final code in text.codeUnits) {
        utf16leBytes.addAll(_u16le(code));
      }
      utf16leBytes.addAll([0x00, 0x00]); // NUL

      final wav = buildWavWithCset(
        codePage: 1200,
        infoId: 'INAM',
        rawValueBytes: utf16leBytes,
      );

      final loader = WaveLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wav)),
        const ParseOptions(),
      );

      expect(res.common.title, 'Unicode Song');
    });

    test('decodes UTF-16BE in code page 1201', () async {
      const text = 'BigEndian Title';
      final utf16beBytes = <int>[];
      for (final code in text.codeUnits) {
        utf16beBytes.addAll(_u16be(code));
      }
      utf16beBytes.addAll([0x00, 0x00]); // NUL

      final wav = buildWavWithCset(
        codePage: 1201,
        infoId: 'INAM',
        rawValueBytes: utf16beBytes,
      );

      final loader = WaveLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wav)),
        const ParseOptions(),
      );

      expect(res.common.title, 'BigEndian Title');
    });

    test('decodes Windows-1250 Central European (0x8A = Š, 0x9A = š)', () async {
      // "Škoda" in Windows-1250: [0x8A, 'k', 'o', 'd', 'a', 0x00]
      final cp1250Bytes = <int>[0x8A, 0x6B, 0x6F, 0x64, 0x61, 0x00];
      final wav = buildWavWithCset(
        codePage: 1250,
        infoId: 'IART',
        rawValueBytes: cp1250Bytes,
      );

      final loader = WaveLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wav)),
        const ParseOptions(),
      );

      expect(res.common.artist, 'Škoda');
    });

    test('emits warning and omits tags on unsupported code page', () async {
      final wav = buildWavWithCset(
        codePage: 9999, // Unknown code page
        infoId: 'INAM',
        rawValueBytes: ascii.encode('Ignored Song\x00'),
      );

      final loader = WaveLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wav)),
        const ParseOptions(),
      );

      expect(res.common.title, isNull);
      expect(
        res.quality.warnings,
        anyElement(predicate<ParserWarning>((w) => w.message.contains('Unsupported RIFF CSET code page: 9999'))),
      );
    });
  });

  group('DSF & DSDIFF Channel Layout Extensions', () {
    test('DSF maps 5.1 channelType (7) to channel layout and stream info', () async {
      // Build minimal DSF header + fmt chunk (channelType = 7, channelNum = 6)
      final dsdChunk = <int>[
        ...ascii.encode('DSD '),
        ..._u64le(28), // size = 28
        ..._u64le(100), // total size
        ..._u64le(0), // metadata offset
      ];

      final fmtPayload = ByteData(40);
      fmtPayload.setInt32(0, 1, Endian.little); // version 1
      fmtPayload.setInt32(4, 0, Endian.little); // id 0
      fmtPayload.setInt32(8, 7, Endian.little); // channelType = 7 (5.1 surround)
      fmtPayload.setInt32(12, 6, Endian.little); // channelNum = 6
      fmtPayload.setInt32(16, 2822400, Endian.little); // samplingFrequency
      fmtPayload.setInt32(20, 1, Endian.little); // bitsPerSample = 1
      fmtPayload.setInt64(24, 2822400 * 2, Endian.little); // sampleCount (2 seconds)
      fmtPayload.setInt32(32, 4096, Endian.little); // blockSizePerChannel

      final fmtChunk = <int>[
        ...ascii.encode('fmt '),
        ..._u64le(12 + 40),
        ...fmtPayload.buffer.asUint8List(),
      ];

      final dsfBytes = <int>[...dsdChunk, ...fmtChunk];
      final loader = DsfLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(dsfBytes)),
        const ParseOptions(),
      );

      expect(res.format.numberOfChannels, 6);
      expect(res.format.bitsPerSample, 1);
      expect(res.format.sampleRate, 2822400);
      expect(res.format.duration, closeTo(2.0, 0.001));

      expect(res.format.trackInfo, isNotEmpty);
      final audioTrack = res.format.trackInfo.first.audio;
      expect(audioTrack, isNotNull);
      expect(audioTrack!.channels, 6);
      // Standard 5.1 channel mask
      expect(audioTrack.channelPositions, equals(const [0x01, 0x02, 0x04, 0x08, 0x10, 0x20]));

      final names = DsfParser.channelNames(7);
      expect(
        names,
        equals(const [
          'front-left',
          'front-center',
          'front-right',
          'rear-left',
          'rear-right',
          'lfe',
        ]),
      );
    });

    test('DSDIFF maps CHNL 4CC identifiers into channel layout and stream info', () async {
      // Build minimal DSDIFF FRM8 + PROP sndp + DSD
      final propSubchunks = <int>[
        ...ascii.encode('SND '),
        // FS chunk (4 + 8 + 4 = 16 bytes)
        ...ascii.encode('FS  '),
        ..._u64be(4),
        ..._u32be(2822400),
        // CHNL chunk (4 + 8 + 2 + 8 = 22 bytes): 2 channels (SLFT, SRGT)
        ...ascii.encode('CHNL'),
        ..._u64be(10),
        ..._u16be(2),
        ...ascii.encode('SLFT'),
        ...ascii.encode('SRGT'),
        // CMPR chunk (4 + 8 + 4 + 1 + 3 = 20 bytes): DSD (DSD)
        ...ascii.encode('CMPR'),
        ..._u64be(8),
        ...ascii.encode('DSD '),
        3,
        ...ascii.encode('DSD'),
      ];

      final propChunk = <int>[
        ...ascii.encode('PROP'),
        ..._u64be(propSubchunks.length),
        ...propSubchunks,
      ];

      // DSD chunk (16 bytes = 16 * 8 / 2 = 64 samples at 2 channels)
      const audioSize = 16;
      final dsdChunk = <int>[
        ...ascii.encode('DSD '),
        ..._u64be(audioSize),
        ...Uint8List(audioSize),
      ];

      final frm8Payload = <int>[
        ...ascii.encode('DSD '),
        ...propChunk,
        ...dsdChunk,
      ];

      final dsdiffBytes = <int>[
        ...ascii.encode('FRM8'),
        ..._u64be(frm8Payload.length),
        ...frm8Payload,
      ];

      final loader = DsdiffLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(dsdiffBytes)),
        const ParseOptions(duration: true),
      );

      expect(res.format.container, 'DSDIFF/DSD');
      expect(res.format.numberOfChannels, 2);
      expect(res.format.numberOfSamples, 64);
      expect(res.format.duration, closeTo(64 / 2822400.0, 0.00001));

      expect(res.format.trackInfo, isNotEmpty);
      final audioTrack = res.format.trackInfo.first.audio;
      expect(audioTrack, isNotNull);
      expect(audioTrack!.channels, 2);
      expect(audioTrack.channelPositions, equals(const [0x01, 0x02]));

      final names = DsdiffParser.channelNames(['SLFT', 'SRGT']);
      expect(names, equals(const ['front-left', 'front-right']));
    });
  });
}

List<int> _u16le(int value) => <int>[value & 0xFF, (value >> 8) & 0xFF];

List<int> _u16be(int value) => <int>[(value >> 8) & 0xFF, value & 0xFF];

List<int> _i16le(int value) {
  final bd = ByteData(2);
  bd.setInt16(0, value, Endian.little);
  return bd.buffer.asUint8List();
}

List<int> _u32le(int value) => <int>[
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

List<int> _u32be(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _u64le(int value) {
  final bd = ByteData(8);
  bd.setInt64(0, value, Endian.little);
  return bd.buffer.asUint8List();
}

List<int> _u64be(int value) {
  final bd = ByteData(8);
  bd.setInt64(0, value);
  return bd.buffer.asUint8List();
}

List<int> _buildOggPage({
  required int headerType,
  required int granulePos,
  required int streamSerial,
  required int pageSeq,
  required List<int> payload,
}) {
  final segments = <int>[];
  var remaining = payload.length;
  while (remaining > 0) {
    final segSize = remaining > 255 ? 255 : remaining;
    segments.add(segSize);
    remaining -= segSize;
  }
  if (segments.isEmpty) {
    segments.add(0);
  }

  final header = ByteData(27);
  final oggs = ascii.encode('OggS');
  for (var i = 0; i < 4; i++) {
    header.setUint8(i, oggs[i]);
  }
  header.setUint8(4, 0); // version
  header.setUint8(5, headerType);
  header.setInt64(6, granulePos, Endian.little);
  header.setUint32(14, streamSerial, Endian.little);
  header.setUint32(18, pageSeq, Endian.little);
  header.setUint32(22, 0, Endian.little); // crc
  header.setUint8(26, segments.length);

  return <int>[
    ...header.buffer.asUint8List(),
    ...segments,
    ...payload,
  ];
}
