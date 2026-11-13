import 'dart:typed_data';

import 'package:metadata_audio/src/apev2/apev2_tag_map.dart';
import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/common/util.dart';
import 'package:metadata_audio/src/id3v2/id3v2_tag_map.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/mpeg/mpeg_loader.dart';
import 'package:metadata_audio/src/mpeg/replay_gain_data_format.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
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

  group('toRatio string validation', () {
    test('parses valid ReplayGain expressions', () {
      final r1 = toRatio('0 dB');
      expect(r1, isNotNull);
      expect(r1!.dB, 0.0);
      expect(r1.ratio, 1.0);

      final r2 = toRatio('0');
      expect(r2, isNotNull);
      expect(r2!.ratio, 0.0);
      expect(r2.dB, isNull);

      final r3 = toRatio('-7.03 dB');
      expect(r3, isNotNull);
      expect(r3!.dB, closeTo(-7.03, 0.001));

      final r4 = toRatio(' \t-3.00\tDB\n');
      expect(r4, isNotNull);
      expect(r4!.dB, -3.0);

      final r5 = toRatio('+1.e-1');
      expect(r5, isNotNull);
      expect(r5!.ratio, closeTo(0.1, 0.0001));
    });

    for (final invalid in [
      '',
      ' ',
      'NaN',
      'Infinity',
      '-Infinity',
      '1e309',
      '1e309 dB',
      '-1',
      '1garbage',
      '1 dB garbage',
    ]) {
      test('rejects invalid ReplayGain "$invalid"', () {
        expect(toRatio(invalid), isNull);
      });
    }
  });

  group('ReplayGain tag fallback and priority', () {
    test('ignores invalid ReplayGain without claiming priority', () {
      final mapper = CombinedTagMapper()
        ..registerMapper('APEv2', Apev2TagMapper())
        ..registerMapper('ID3v2.3', Id3v2TagMapper());

      final collector = MetadataCollector(mapper);

      // Higher priority APEv2 provides invalid value
      collector.addNativeTag('APEv2', 'REPLAYGAIN_TRACK_GAIN', 'not-a-number');
      // ID3v2.3 provides valid value
      collector.addNativeTag('ID3v2.3', 'TXXX:REPLAYGAIN_TRACK_GAIN', '0 dB');

      final meta = collector.toAudioMetadata();
      expect(meta.common.replaygain_track_gain, isNotNull);
      expect(meta.common.replaygain_track_gain!.dB, 0.0);
      expect(meta.common.replaygain_track_gain!.ratio, 1.0);
      expect(
        meta.quality.warnings.any((w) => w.message.contains('Invalid ReplayGain value')),
        isTrue,
      );
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

List<int> _buildId3v2Header() => <int>[
  0x49,
  0x44,
  0x33,
  0x03,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
];

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
