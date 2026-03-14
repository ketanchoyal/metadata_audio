library;

import 'package:audio_metadata/src/parse_error.dart';
import 'package:audio_metadata/src/riff/riff_chunk.dart';

class WaveContentError extends UnexpectedFileContentError {
  WaveContentError(String message) : super('Wave', message);
}

class WaveFormat {
  static const int pcm = 0x0001;
  static const int adpcm = 0x0002;
  static const int ieeeFloat = 0x0003;
  static const int drm = 0x0009;
  static const int mpeg = 0x0050;
  static const int dolbyAc3Spdif = 0x0092;
  static const int rawAac1 = 0x00FF;
  static const int mpegAdtsAac = 0x1600;
  static const int mpegLoas = 0x1602;
  static const int rawSport = 0x0240;
  static const int esstAc3 = 0x0241;
  static const int dvm = 0x2000;
  static const int dts2 = 0x2001;
}

const Map<int, String> waveFormatNameMap = <int, String>{
  WaveFormat.pcm: 'PCM',
  WaveFormat.adpcm: 'ADPCM',
  WaveFormat.ieeeFloat: 'IEEE_FLOAT',
  WaveFormat.drm: 'DRM',
  WaveFormat.mpeg: 'MPEG',
  WaveFormat.dolbyAc3Spdif: 'DOLBY_AC3_SPDIF',
  WaveFormat.rawAac1: 'RAW_AAC1',
  WaveFormat.mpegAdtsAac: 'MPEG_ADTS_AAC',
  WaveFormat.mpegLoas: 'MPEG_LOAS',
  WaveFormat.rawSport: 'RAW_SPORT',
  WaveFormat.esstAc3: 'ESST_AC3',
  WaveFormat.dvm: 'DVM',
  WaveFormat.dts2: 'DTS2',
};

class WaveFormatChunk {
  const WaveFormatChunk({
    required this.formatTag,
    required this.channels,
    required this.samplesPerSec,
    required this.avgBytesPerSec,
    required this.blockAlign,
    required this.bitsPerSample,
  });

  final int formatTag;
  final int channels;
  final int samplesPerSec;
  final int avgBytesPerSec;
  final int blockAlign;
  final int bitsPerSample;

  static WaveFormatChunk fromBytes(List<int> bytes) {
    if (bytes.length < 16) {
      throw WaveContentError('Invalid fmt chunk size');
    }

    return WaveFormatChunk(
      formatTag: RiffChunk.readUint16Le(bytes, 0),
      channels: RiffChunk.readUint16Le(bytes, 2),
      samplesPerSec: RiffChunk.readUint32Le(bytes, 4),
      avgBytesPerSec: RiffChunk.readUint32Le(bytes, 8),
      blockAlign: RiffChunk.readUint16Le(bytes, 12),
      bitsPerSample: RiffChunk.readUint16Le(bytes, 14),
    );
  }
}

class FactChunk {
  const FactChunk({required this.sampleLength});

  final int sampleLength;

  static FactChunk fromBytes(List<int> bytes) {
    if (bytes.length < 4) {
      throw WaveContentError('Invalid fact chunk size');
    }

    return FactChunk(sampleLength: RiffChunk.readUint32Le(bytes, 0));
  }
}

class CuePoint {
  const CuePoint({
    required this.id,
    required this.position,
    required this.chunkId,
    required this.chunkStart,
    required this.blockStart,
    required this.sampleOffset,
  });

  final int id;
  final int position;
  final String chunkId;
  final int chunkStart;
  final int blockStart;
  final int sampleOffset;
}

class CueChunk {
  const CueChunk({required this.points});

  final List<CuePoint> points;

  static CueChunk fromBytes(List<int> bytes) {
    if (bytes.length < 4) {
      throw WaveContentError('Invalid cue chunk size');
    }

    final count = RiffChunk.readUint32Le(bytes, 0);
    final points = <CuePoint>[];
    var offset = 4;
    for (var i = 0; i < count; i++) {
      if (offset + 24 > bytes.length) {
        throw WaveContentError('Invalid cue point table length');
      }
      points.add(
        CuePoint(
          id: RiffChunk.readUint32Le(bytes, offset),
          position: RiffChunk.readUint32Le(bytes, offset + 4),
          chunkId: String.fromCharCodes(bytes.sublist(offset + 8, offset + 12)),
          chunkStart: RiffChunk.readUint32Le(bytes, offset + 12),
          blockStart: RiffChunk.readUint32Le(bytes, offset + 16),
          sampleOffset: RiffChunk.readUint32Le(bytes, offset + 20),
        ),
      );
      offset += 24;
    }

    return CueChunk(points: points);
  }
}
