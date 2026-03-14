import 'dart:typed_data';

import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/mpeg/mpeg_loader.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:test/test.dart';

void main() {
  group('MpegParser / MpegLoader', () {
    test('parses MPEG frame, Xing/LAME headers, and ID3v1 tail', () async {
      final bytes = <int>[
        ..._buildId3v2Header(),
        ..._buildMpegFrame(includeXing: true, includeLame: true),
        ..._buildId3v1(title: 'Tail Title'),
      ];

      final loader = MpegLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.container, 'mp3');
      expect(metadata.format.sampleRate, 44100);
      expect(metadata.format.codec, contains('Layer 3'));
      expect(metadata.format.tool, startsWith('LAME'));
      expect(metadata.format.duration, closeTo(100 * 1152 / 44100, 0.01));
      expect(metadata.common.title, 'Tail Title');
    });

    test('calculates CBR duration from file size', () async {
      final frames = <int>[];
      for (var i = 0; i < 10; i++) {
        frames.addAll(_buildMpegFrame());
      }

      final loader = MpegLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(frames),
          fileInfo: FileInfo(size: frames.length),
        ),
        const ParseOptions(duration: true),
      );

      expect(metadata.format.codecProfile, 'CBR');
      expect(metadata.format.numberOfSamples, 10 * 1152);
      expect(metadata.format.duration, closeTo(10 * 1152 / 44100, 0.01));
    });

    test('calculates VBR duration at EOF when enabled', () async {
      final frames = <int>[
        ..._buildMpegFrame(bitrateIndex: 9),
        ..._buildMpegFrame(bitrateIndex: 11),
        ..._buildMpegFrame(bitrateIndex: 10),
        ..._buildMpegFrame(bitrateIndex: 9),
        ..._buildMpegFrame(bitrateIndex: 11),
      ];

      final loader = MpegLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(frames),
          fileInfo: FileInfo(size: frames.length),
        ),
        const ParseOptions(duration: true),
      );

      expect(metadata.format.codecProfile, isNot('CBR'));
      expect(metadata.format.numberOfSamples, 5 * 1152);
      expect(metadata.format.duration, closeTo(5 * 1152 / 44100, 0.01));
    });

    test('registers mp3 extension and audio/mpeg mime type', () {
      final loader = MpegLoader();
      expect(loader.extension, contains('mp3'));
      expect(loader.mimeType, contains('audio/mpeg'));
    });

    test('parses ADTS AAC frames', () async {
      final frames = <int>[
        ..._buildAdtsFrame(),
        ..._buildAdtsFrame(),
        ..._buildAdtsFrame(),
      ];

      final loader = MpegLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(frames),
          fileInfo: FileInfo(size: frames.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.format.container, 'ADTS/MPEG-4');
      expect(metadata.format.codec, 'AAC');
      expect(metadata.format.codecProfile, 'AAC LC');
      expect(metadata.format.sampleRate, 44100);
      expect(metadata.format.numberOfChannels, 2);
      expect(metadata.format.bitrate, closeTo(34453, 10));
    });

    test('calculates ADTS duration at EOF when enabled', () async {
      final frames = <int>[
        ..._buildAdtsFrame(),
        ..._buildAdtsFrame(),
        ..._buildAdtsFrame(),
        ..._buildAdtsFrame(),
        ..._buildAdtsFrame(),
      ];

      final loader = MpegLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(frames),
          fileInfo: FileInfo(size: frames.length),
        ),
        const ParseOptions(duration: true),
      );

      expect(metadata.format.container, 'ADTS/MPEG-4');
      expect(metadata.format.numberOfSamples, 5 * 1024);
      expect(metadata.format.duration, closeTo(5 * 1024 / 44100, 0.01));
    });
  });
}

List<int> _buildId3v2Header() {
  return <int>[0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
}

List<int> _buildId3v1({required String title}) {
  final tag = List<int>.filled(128, 0);
  tag[0] = 0x54;
  tag[1] = 0x41;
  tag[2] = 0x47;

  final titleBytes = title.codeUnits;
  for (var i = 0; i < titleBytes.length && i < 30; i++) {
    tag[3 + i] = titleBytes[i];
  }
  return tag;
}

List<int> _buildMpegFrame({
  int bitrateIndex = 9,
  bool includeXing = false,
  bool includeLame = false,
}) {
  const sampleRate = 44100;
  const samplesPerFrame = 1152;
  final bitrateKbps = _bitrateFromIndex(bitrateIndex);
  final bitrate = bitrateKbps * 1000;
  final frameLength = ((samplesPerFrame / 8.0 * bitrate / sampleRate)).floor();

  final header = <int>[0xFF, 0xFB, (bitrateIndex << 4), 0x40];

  final payload = List<int>.filled(frameLength - 4, 0);
  if (includeXing) {
    var cursor = 32; // MPEG1 Layer III non-mono side info length
    final marker = 'Xing'.codeUnits;
    payload.setRange(cursor, cursor + marker.length, marker);
    cursor += 4;

    // flags: frames + vbrScale
    payload.setRange(cursor, cursor + 4, const <int>[0x90, 0x00, 0x00, 0x00]);
    cursor += 4;

    // numFrames = 100
    payload.setRange(cursor, cursor + 4, const <int>[0x00, 0x00, 0x00, 0x64]);
    cursor += 4;

    // vbrScale = 40
    payload.setRange(cursor, cursor + 4, const <int>[0x00, 0x00, 0x00, 0x28]);
    cursor += 4;

    if (includeLame) {
      final lame = 'LAME'.codeUnits;
      payload.setRange(cursor, cursor + lame.length, lame);
      cursor += 4;

      final version = '3.99r'.codeUnits;
      payload.setRange(cursor, cursor + version.length, version);
      cursor += 5;

      // 27-byte extended lame header with music_length at byte offset +20.
      final ext = List<int>.filled(27, 0);
      ext[20] = 0x00;
      ext[21] = 0x00;
      ext[22] = 0x0B;
      ext[23] = 0xB8; // 3000 ms
      payload.setRange(cursor, cursor + ext.length, ext);
    }
  }

  return <int>[...header, ...payload];
}

int _bitrateFromIndex(int index) {
  const table = <int, int>{
    1: 32,
    2: 40,
    3: 48,
    4: 56,
    5: 64,
    6: 80,
    7: 96,
    8: 112,
    9: 128,
    10: 160,
    11: 192,
    12: 224,
    13: 256,
    14: 320,
  };
  return table[index] ?? 128;
}

List<int> _buildAdtsFrame({
  int versionIndex = 2,
  int profileIndex = 1,
  int sampleRateIndex = 4,
  int channelConfigIndex = 2,
  int frameLength = 100,
  bool protectionAbsent = true,
}) {
  final byte0 = 0xFF;
  final byte1 =
      0xE0 |
      ((versionIndex & 0x03) << 3) |
      ((0x00 & 0x03) << 1) |
      (protectionAbsent ? 1 : 0);
  final byte2 =
      ((profileIndex & 0x03) << 6) |
      ((sampleRateIndex & 0x0F) << 2) |
      ((channelConfigIndex >> 2) & 0x01);
  final byte3 =
      ((channelConfigIndex & 0x03) << 6) | ((frameLength >> 11) & 0x03);
  final byte4 = (frameLength >> 3) & 0xFF;
  final byte5 = ((frameLength & 0x07) << 5) | 0x1F;
  final byte6 = 0xFC;

  final header = <int>[byte0, byte1, byte2, byte3, byte4, byte5, byte6];
  final crc = protectionAbsent ? <int>[] : <int>[0x00, 0x00];
  final headerLength = protectionAbsent ? 7 : 9;
  final payloadLength = frameLength - headerLength;
  final payload = List<int>.filled(payloadLength > 0 ? payloadLength : 0, 0);

  return <int>[...header, ...crc, ...payload];
}
