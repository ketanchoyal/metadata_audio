/// Regression test: VBR MP3 files without a Xing/LAME header must report a
/// reasonable duration even when parsed through a URL tokenizer that only has
/// partial file data (e.g. RangeTokenizer or ProbingRangeTokenizer).
///
/// Previously, the MPEG parser fell back to counting the ~630 frames that fit
/// in the 256KB header region and produced a duration of ~16 s instead of the
/// actual duration.  The fix uses the known file size together with the average
/// sampled bitrate to estimate the duration whenever the tokenizer reports that
/// it does not hold the complete file.
library;

import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/mpeg/mpeg_loader.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fake partial tokenizer that simulates a URL tokenizer with incomplete data.
// It exposes the full file size but only stores the first [windowSize] bytes.
// ---------------------------------------------------------------------------
class _PartialTokenizer extends Tokenizer {
  _PartialTokenizer(this._bytes, {required int fullFileSize})
    : fileInfo = FileInfo(path: 'test.mp3', size: fullFileSize);

  final Uint8List _bytes;
  int _position = 0;

  @override
  final FileInfo? fileInfo;

  @override
  int get position => _position;

  @override
  bool get canSeek => true;

  /// Simulate a partial URL tokenizer – the complete file is NOT available.
  @override
  bool get hasCompleteData => false;

  @override
  int readUint8() {
    if (_position >= _bytes.length) {
      throw TokenizerException('End of partial data at position $_position');
    }
    return _bytes[_position++];
  }

  @override
  int readUint16() {
    final b1 = readUint8();
    final b2 = readUint8();
    return (b1 << 8) | b2;
  }

  @override
  int readUint32() {
    final b1 = readUint8();
    final b2 = readUint8();
    final b3 = readUint8();
    final b4 = readUint8();
    return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4;
  }

  @override
  List<int> readBytes(int length) {
    if (_position + length > _bytes.length) {
      throw TokenizerException('Not enough partial data');
    }
    final result = _bytes.sublist(_position, _position + length);
    _position += length;
    return result;
  }

  @override
  int peekUint8() {
    if (_position >= _bytes.length) {
      throw TokenizerException('End of partial data');
    }
    return _bytes[_position];
  }

  @override
  List<int> peekBytes(int length) {
    if (_position + length > _bytes.length) {
      throw TokenizerException('Not enough partial data for peek');
    }
    return _bytes.sublist(_position, _position + length);
  }

  @override
  void skip(int length) {
    _position += length;
  }

  @override
  void seek(int newPosition) {
    // Seeking beyond the available window silently clamps to the window end
    // so that callers such as the ID3v1 parser get a TokenizerException on
    // the subsequent read rather than on the seek itself.
    _position = newPosition.clamp(0, _bytes.length);
  }
}

// ---------------------------------------------------------------------------
// Helpers to build synthetic MPEG frames
// ---------------------------------------------------------------------------

/// Build a single MPEG 1 Layer 3 frame at [bitrateIndex] for 44100 Hz stereo.
List<int> _buildFrame({int bitrateIndex = 9}) {
  // bitrateIndex 9 → 128 kbps
  const sampleRate = 44100;
  const samplesPerFrame = 1152;
  final bitrateKbps = _bitrateFromIndex(bitrateIndex);
  final bitrate = bitrateKbps * 1000;
  final frameLength = (samplesPerFrame / 8.0 * bitrate / sampleRate).floor();

  // Header bytes: sync (0xFF 0xFB), bitrate+sampleRate byte, channel byte
  final header = <int>[0xFF, 0xFB, (bitrateIndex << 4), 0x40];
  final payload = List<int>.filled(frameLength - 4, 0);
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

void main() {
  group('URL MP3 duration (partial tokenizer)', () {
    setUp(() {
      final registry = ParserRegistry()..register(MpegLoader());
      initializeParserFactory(ParserFactory(registry));
    });

    test(
      'VBR MP3 without Xing header: duration estimated from file size + bitrate',
      () async {
        // Build a synthetic VBR file: 300 frames alternating between 128kbps
        // and 160kbps so there is no uniform CBR profile.
        const totalFrames = 300;
        final allFrameBytes = <int>[];
        for (var i = 0; i < totalFrames; i++) {
          allFrameBytes.addAll(_buildFrame(bitrateIndex: i.isEven ? 9 : 10));
        }

        final fullFileSize = allFrameBytes.length;

        // Simulate a partial tokenizer: expose only the first 100 frames.
        const visibleFrames = 100;
        final partialBytes = <int>[];
        for (var i = 0; i < visibleFrames; i++) {
          partialBytes.addAll(_buildFrame(bitrateIndex: i.isEven ? 9 : 10));
        }

        final tokenizer = _PartialTokenizer(
          Uint8List.fromList(partialBytes),
          fullFileSize: fullFileSize,
        );

        final metadata = await parseFromTokenizer(tokenizer);

        // The duration should be estimated from the full file size and average
        // bitrate, not from the partial frame count.
        // Average of 128kbps and 160kbps = 144kbps.
        // Expected ≈ fullFileSize * 8 / 144000.
        final expectedDuration = fullFileSize * 8 / 144000;

        expect(metadata.format.duration, isNotNull);
        expect(
          metadata.format.duration!,
          closeTo(expectedDuration, expectedDuration * 0.05),
          reason:
              'Duration should be close to the file-size/bitrate estimate, '
              'not the partial frame count',
        );

        // Sanity: the wrong value (from counting only visible frames) would be
        // visibleFrames * 1152 / 44100 ≈ 2.6 s, while the correct value is
        // around totalFrames * 1152 / 44100 ≈ 7.8 s.
        const wrongDuration = visibleFrames * 1152 / 44100;
        expect(
          metadata.format.duration!,
          isNot(closeTo(wrongDuration, 0.5)),
          reason:
              'Duration must not be the partial-frame-count value (~$wrongDuration s)',
        );
      },
    );

    test(
      'CBR MP3 without Info header: duration still uses file-size method',
      () async {
        // All frames at the same bitrate → CBR detected at frame 3.
        const totalFrames = 300;
        final allFrameBytes = <int>[];
        for (var i = 0; i < totalFrames; i++) {
          allFrameBytes.addAll(_buildFrame(bitrateIndex: 9)); // 128kbps
        }

        final fullFileSize = allFrameBytes.length;

        // Only the first 50 frames are visible.
        final partialBytes = <int>[];
        for (var i = 0; i < 50; i++) {
          partialBytes.addAll(_buildFrame(bitrateIndex: 9));
        }

        final tokenizer = _PartialTokenizer(
          Uint8List.fromList(partialBytes),
          fullFileSize: fullFileSize,
        );

        final metadata = await parseFromTokenizer(tokenizer);

        // CBR with known file size → duration from file-size / frame-size.
        const sampleRate = 44100;
        const samplesPerFrame = 1152;
        final expectedDuration = totalFrames * samplesPerFrame / sampleRate;

        expect(metadata.format.duration, isNotNull);
        expect(metadata.format.duration!, closeTo(expectedDuration, 0.01));
      },
    );

    test(
      'Full MP3 with too few frames still estimates duration from file size',
      () async {
        final bytes = <int>[
          ..._buildFrame(bitrateIndex: 9),
          ..._buildFrame(bitrateIndex: 10),
          ..._buildFrame(bitrateIndex: 9),
          ...List<int>.filled(1000, 0),
        ];

        final metadata = await parseBytes(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(path: 'short-mpeg.mp3', size: bytes.length),
          options: const ParseOptions(duration: true),
        );

        expect(metadata.format.container, equals('MPEG'));
        expect(metadata.format.codec, equals('MPEG 1 Layer 3'));
        expect(metadata.format.duration, isNotNull);
        expect(
          metadata.format.duration,
          closeTo(bytes.length * 8 / 128000, 0.05),
        );
      },
    );

    test(
      'malformed ID3v2.3 frame header still allows MPEG duration recovery',
      () async {
        final malformedTag = <int>[
          0x49,
          0x44,
          0x33,
          0x03,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x0A,
          0x74,
          0x49,
          0x54,
          0x32,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
        ];

        final bytes = <int>[
          ...malformedTag,
          ..._buildFrame(bitrateIndex: 9),
          ..._buildFrame(bitrateIndex: 10),
          ..._buildFrame(bitrateIndex: 9),
        ];

        final tokenizer = BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(path: 'malformed-id3.mp3', size: bytes.length),
        );

        final metadata = await parseFromTokenizer(tokenizer);

        expect(metadata.format.container, equals('MPEG'));
        expect(metadata.format.codec, isNotNull);
        expect(metadata.format.duration, isNotNull);
        expect(
          metadata.quality.warnings.map((warning) => warning.message),
          contains(
            contains('Invalid ID3v2.3 frame header ID'),
          ),
        );
      },
    );
  });
}
