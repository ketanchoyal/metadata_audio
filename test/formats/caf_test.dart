/// Integration tests for the Apple CAF (Core Audio File) parser, ported
/// from upstream music-metadata v12.2.0 CAF support.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/caf/caf_loader.dart';
import 'package:metadata_audio/src/caf/caf_token.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:test/test.dart';

void main() {
  group('CafParser', () {
    test('parses header, description, info tags and data-driven duration',
        () async {
      final wav = _buildCaf(
        description: _audioDescription(
          sampleRate: 44100,
          formatId: 'lpcm',
          bytesPerPacket: 2,
          framesPerPacket: 1,
          channelsPerFrame: 1,
          bitsPerChannel: 16,
        ),
        infoEntries: const {
          'title': 'Test Song',
          'artist': 'Foo Bar',
          'tempo': '120',
        },
        dataBytes: <int>[0x00, 0xAA, 0x11, 0xBB, 0x22, 0xCC, 0x33, 0xDD],
        dataChunkSize: -1, // runs to end of file
      );

      // Parse with no path/mime so the magic-byte sniffing path is used.
      final metadata = await parseBytes(wav);
      expect(metadata.format.container, equals('CAF'));
      expect(metadata.format.sampleRate, equals(44100));
      expect(metadata.format.numberOfChannels, equals(1));
      expect(metadata.format.bitsPerSample, equals(16));
      expect(metadata.format.codec, equals('PCM'));
      expect(metadata.format.lossless, isTrue);
      expect(metadata.format.numberOfSamples, equals(4));
      expect(metadata.format.duration, closeTo(4 / 44100, 1e-9));
      expect(metadata.format.bitrate, closeTo(8 * 8 / (4 / 44100), 1e-6));
      expect(metadata.common.title, equals('Test Song'));
      expect(metadata.common.artist, equals('Foo Bar'));
      expect(metadata.common.bpm, equals(120));
      expect(metadata.format.hasAudio, isTrue);
      expect(metadata.format.hasVideo, isFalse);
    });

    test('packet table numberValidFrames drives the duration', () async {
      final bytes = _buildCaf(
        description: _audioDescription(
          sampleRate: 48000,
          formatId: 'alac',
          bytesPerPacket: 0, // variable per packet
          framesPerPacket: 0, // variable per packet
          channelsPerFrame: 2,
          bitsPerChannel: 0,
        ),
        packetTable: _packetTable(
          numberPackets: 2,
          numberValidFrames: 96000,
          primingFrames: 0,
          remainderFrames: 0,
          varIntEntries: const <int>[10, 20, 30, 40],
        ),
        dataBytes: <int>[],
        dataChunkSize: 4, // only the edit count, no audio
      );

      final metadata = await parseBytes(bytes);
      expect(metadata.format.container, equals('CAF'));
      expect(metadata.format.codec, equals('ALAC'));
      expect(metadata.format.lossless, isTrue);
      expect(metadata.format.numberOfSamples, equals(96000));
      expect(metadata.format.duration, closeTo(96000 / 48000, 1e-9));
    });

    test('invalid magic is rejected', () async {
      final bytes = <int>[...BOGUS_MAGIC];
      await expectLater(
        CafLoader().parse(BytesTokenizer(Uint8List.fromList(bytes)),
            const ParseOptions()),
        throwsA(
          isA<CafContentError>().having(
            (e) => e.message,
            'message',
            contains("expected 'caff', found "),
          ),
        ),
      );
    });

    test('empty chunk stream is rejected as missing Audio Description', () async {
      final bytes = Uint8List.fromList(<int>[
        ...'caff'.codeUnits,
        ..._u16be(1),
        ..._u16be(0),
      ]);
      await expectLater(
        CafLoader().parse(BytesTokenizer(bytes), const ParseOptions()),
        throwsA(
          isA<CafContentError>().having(
            (e) => e.message,
            'message',
            contains('Missing Audio Description chunk'),
          ),
        ),
      );
    });

    test('first chunk that is not desc is rejected', () {
      final bytes = _buildCaf(
        description: _audioDescription(
          sampleRate: 44100,
          formatId: 'lpcm',
          bytesPerPacket: 2,
          framesPerPacket: 1,
          channelsPerFrame: 1,
          bitsPerChannel: 16,
        ),
        dataBytes: <int>[],
        dataChunkSize: -1,
        omitDescription: true,
        unknownChunkFirst: true,
      );

      expect(
        () => parseBytes(bytes),
        throwsA(
          isA<UnexpectedFileContentError>().having(
            (e) => e.message,
            'message',
            contains('Expected an Audio Description chunk'),
          ),
        ),
      );
    });

    test('unknown chunk with -1 size is rejected', () {
      final bytes = _buildCaf(
        description: _audioDescription(
          sampleRate: 44100,
          formatId: 'lpcm',
          bytesPerPacket: 2,
          framesPerPacket: 1,
          channelsPerFrame: 1,
          bitsPerChannel: 16,
        ),
        dataBytes: <int>[],
        dataChunkSize: 4,
        unknownChunkSize: -1,
      );

      expect(
        () => parseBytes(bytes),
        throwsA(
          isA<UnexpectedFileContentError>().having(
            (e) => e.message,
            'message',
            contains('may only be -1 for an Audio Data chunk'),
          ),
        ),
      );
    });

    test('channel layout is kept as native CAF tags', () async {
      final bytes = _buildCaf(
        description: _audioDescription(
          sampleRate: 44100,
          formatId: 'lpcm',
          bytesPerPacket: 2,
          framesPerPacket: 1,
          channelsPerFrame: 2,
          bitsPerChannel: 16,
        ),
        dataBytes: <int>[],
        dataChunkSize: 4,
        channelLayout: _channelLayout(),
      );

      final metadata = await parseBytes(bytes);
      expect(metadata.format.numberOfChannels, equals(2));
      final cafTags = metadata.native['CAF'];
      expect(cafTags, isNotNull);
      final layoutTag = cafTags!
          .where((tag) => tag.id == 'channelLayoutTag')
          .single;
      expect(layoutTag.value, equals(0x660008));
    });

    test('getSupportedMimeTypes includes CAF', () {
      final mimeTypes = getSupportedMimeTypes();
      expect(mimeTypes, contains('audio/caf'));
      expect(mimeTypes, contains('audio/x-caf'));
      expect(mimeTypes, contains('application/caf'));
      expect(mimeTypes, contains('application/x-caf'));
    });
  });
}

/// Builds a minimal CAF byte stream.
Uint8List _buildCaf({
  required List<int> description,
  Map<String, String>? infoEntries,
  List<int> dataBytes = const <int>[],
  required int dataChunkSize,
  bool omitDescription = false,
  bool unknownChunkFirst = false,
  int? unknownChunkSize,
  List<int>? packetTable,
  List<int>? channelLayout,
}) {
  final chunks = <int>[];
  if (unknownChunkFirst) {
    chunks.addAll(_chunk('uuid', <int>[0, 0, 0, 0, 0, 0, 0, 0])); // skipped
  }
  if (!omitDescription) {
    chunks.addAll(_chunk('desc', description));
  }
  if (unknownChunkSize != null) {
    // Unknown chunk with a bad declared size; thrown before the body is read.
    chunks.addAll(<int>[...'uuid'.codeUnits, ..._i64be(unknownChunkSize)]);
  }
  if (packetTable != null) {
    chunks.addAll(_chunk('pakt', packetTable));
  }
  if (infoEntries != null) {
    chunks.addAll(_chunk('info', _infoChunk(infoEntries)));
  }
  if (channelLayout != null) {
    chunks.addAll(_chunk('chan', channelLayout));
  }
  // data chunk: declared size + edit count + payload
  final dataBody = <int>[..._u32be(0), ...dataBytes];
  chunks.addAll([
    ...'data'.codeUnits,
    ..._i64be(dataChunkSize),
    ...dataBody,
  ]);

  return Uint8List.fromList(<int>[
    ...'caff'.codeUnits,
    ..._u16be(1), // version
    ..._u16be(0), // flags
    ...chunks,
  ]);
}

List<int> _chunk(String type, List<int> body) => <int>[
  ...type.codeUnits,
  ..._i64be(body.length),
  ...body,
];

List<int> _audioDescription({
  required double sampleRate,
  required String formatId,
  required int bytesPerPacket,
  required int framesPerPacket,
  required int channelsPerFrame,
  required int bitsPerChannel,
}) {
  final sampleRateData = ByteData(8)..setFloat64(0, sampleRate, Endian.big);
  return <int>[
    ...sampleRateData.buffer.asUint8List(),
    ...formatId.codeUnits,
    ..._u32be(0), // format flags
    ..._u32be(bytesPerPacket),
    ..._u32be(framesPerPacket),
    ..._u32be(channelsPerFrame),
    ..._u32be(bitsPerChannel),
  ];
}

List<int> _packetTable({
  required int numberPackets,
  required int numberValidFrames,
  required int primingFrames,
  required int remainderFrames,
  required List<int> varIntEntries,
}) {
  final body = <int>[
    ..._i64be(numberPackets),
    ..._i64be(numberValidFrames),
    ..._i32be(primingFrames),
    ..._i32be(remainderFrames),
    ...varIntEntries,
  ];
  return body;
}

List<int> _infoChunk(Map<String, String> entries) {
  // CAF Info chunk: UINT32_BE entry count, then NUL-terminated UTF-8
  // key/value pairs.
  final body = <int>[..._u32be(entries.length)];
  for (final entry in entries.entries) {
    body.addAll(utf8.encode(entry.key));
    body.add(0);
    body.addAll(utf8.encode(entry.value));
    body.add(0);
  }
  return body;
}

List<int> _channelLayout() => <int>[
  ..._u32be(0x660008), // channelLayoutTag (DAC3 stereo)
  ..._u32be(0x3), // channelBitmap
  ..._u32be(1), // one channel description
  ..._u32be(1), // label: left
  ..._u32be(0), // flags
  0x3F,
  0x80,
  0x00,
  0x00, // Float32_BE 1.0
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
];

List<int> _u16be(int value) => <int>[(value >> 8) & 0xFF, value & 0xFF];

const List<int> BOGUS_MAGIC = <int>[
  0x42, 0x4F, 0x47, 0x55, 0x53, 0x00, 0x00, 0x00, // 'BOGUS'
];

List<int> _u32be(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _i32be(int value) => _u32be(value);

List<int> _i64be(int value) => <int>[
  (value >> 56) & 0xFF,
  (value >> 48) & 0xFF,
  (value >> 40) & 0xFF,
  (value >> 32) & 0xFF,
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];
