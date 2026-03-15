import 'dart:typed_data';

import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/mpeg/mpeg_loader.dart';
import 'package:audio_metadata/src/mpeg/replay_gain_data_format.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:test/test.dart';

void main() {
  group('ReplayGainDataFormat', () {
    test('detects and parses radio gain adjustment', () {
      final data = _encodeReplayGainWord(
        type: ReplayGainNameCode.radio,
        origin: ReplayGainOriginator.automatic,
        negative: true,
        adjustmentTenthDb: 120,
      );

      final gain = ReplayGainDataFormat.parse(data);
      expect(gain, isNotNull);
      expect(gain!.type, ReplayGainNameCode.radio);
      expect(gain.origin, ReplayGainOriginator.automatic);
      expect(gain.adjustment, closeTo(-12.0, 0.0001));
    });

    test('detects and parses audiophile gain adjustment', () {
      final data = _encodeReplayGainWord(
        type: ReplayGainNameCode.audiophile,
        origin: ReplayGainOriginator.engineer,
        negative: false,
        adjustmentTenthDb: 25,
      );

      final gain = ReplayGainDataFormat.parse(data);
      expect(gain, isNotNull);
      expect(gain!.type, ReplayGainNameCode.audiophile);
      expect(gain.origin, ReplayGainOriginator.engineer);
      expect(gain.adjustment, closeTo(2.5, 0.0001));
    });

    test('returns null when gain type is not set', () {
      final gain = ReplayGainDataFormat.parse(const <int>[0x00, 0x00]);
      expect(gain, isNull);
    });
  });

  group('MpegParser ReplayGain integration', () {
    test(
      'parses track peak, track gain, and album gain from LAME header',
      () async {
        final bytes = <int>[
          ..._buildId3v2Header(),
          ..._buildMpegFrameWithReplayGain(
            trackGainWord: _encodeReplayGainWord(
              type: ReplayGainNameCode.radio,
              origin: ReplayGainOriginator.automatic,
              negative: true,
              adjustmentTenthDb: 120,
            ),
            albumGainWord: _encodeReplayGainWord(
              type: ReplayGainNameCode.audiophile,
              origin: ReplayGainOriginator.engineer,
              negative: false,
              adjustmentTenthDb: 25,
            ),
            trackPeakRaw: 0x00400000,
          ),
        ];

        final loader = MpegLoader();
        final metadata = await loader.parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(),
        );

        expect(metadata.format.trackPeakLevel, closeTo(0.5, 0.000001));
        expect(metadata.format.trackGain, closeTo(-12.0, 0.0001));
        expect(metadata.format.albumGain, closeTo(2.5, 0.0001));
      },
    );
  });
}

List<int> _buildId3v2Header() => <int>[0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];

List<int> _buildMpegFrameWithReplayGain({
  required List<int> trackGainWord,
  required List<int> albumGainWord,
  required int trackPeakRaw,
}) {
  const bitrateIndex = 9;
  const sampleRate = 44100;
  const samplesPerFrame = 1152;
  const bitrateKbps = 128;
  const bitrate = bitrateKbps * 1000;
  final frameLength = (samplesPerFrame / 8.0 * bitrate / sampleRate).floor();

  final header = <int>[0xFF, 0xFB, (bitrateIndex << 4), 0x40];
  final payload = List<int>.filled(frameLength - 4, 0);

  var cursor = 32; // MPEG1 Layer III, non-mono side info length.

  final xing = 'Xing'.codeUnits;
  payload.setRange(cursor, cursor + xing.length, xing);
  cursor += 4;

  payload.setRange(cursor, cursor + 4, const <int>[0x00, 0x00, 0x00, 0x09]);
  cursor += 4;

  payload.setRange(cursor, cursor + 4, const <int>[0x00, 0x00, 0x00, 0x64]);
  cursor += 4;

  payload.setRange(cursor, cursor + 4, const <int>[0x00, 0x00, 0x00, 0x28]);
  cursor += 4;

  final lame = 'LAME'.codeUnits;
  payload.setRange(cursor, cursor + lame.length, lame);
  cursor += 4;

  final version = '3.99r'.codeUnits;
  payload.setRange(cursor, cursor + version.length, version);
  cursor += 5;

  final ext = List<int>.filled(27, 0);
  ext[2] = (trackPeakRaw >> 24) & 0xFF;
  ext[3] = (trackPeakRaw >> 16) & 0xFF;
  ext[4] = (trackPeakRaw >> 8) & 0xFF;
  ext[5] = trackPeakRaw & 0xFF;
  ext[6] = trackGainWord[0];
  ext[7] = trackGainWord[1];
  ext[8] = albumGainWord[0];
  ext[9] = albumGainWord[1];
  ext[20] = 0x00;
  ext[21] = 0x00;
  ext[22] = 0x03;
  ext[23] = 0xE8; // 1000 ms
  payload.setRange(cursor, cursor + ext.length, ext);

  return <int>[...header, ...payload];
}

List<int> _encodeReplayGainWord({
  required int type,
  required int origin,
  required bool negative,
  required int adjustmentTenthDb,
}) {
  final value =
      ((type & 0x07) << 13) |
      ((origin & 0x07) << 10) |
      ((negative ? 1 : 0) << 9) |
      (adjustmentTenthDb & 0x1FF);

  return <int>[(value >> 8) & 0xFF, value & 0xFF];
}
