library;

import 'dart:convert';

import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/id3v1/id3v1_parser.dart';
import 'package:metadata_audio/src/id3v2/id3v2_parser.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/mpeg/adts_frame_header.dart';
import 'package:metadata_audio/src/mpeg/replay_gain_data_format.dart';
import 'package:metadata_audio/src/mpeg/xing_tag.dart';
import 'package:metadata_audio/src/parse_error.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class MpegContentError extends ParseError {
  MpegContentError(super.message);

  @override
  String get name => 'MpegContentError';
}

class MpegParser {
  MpegParser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });
  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  int _frameCount = 0;
  int? _mpegOffset;
  int? _frameSize;
  int? _samplesPerFrame;
  bool _calculateEofDuration = false;
  final List<int> _bitrates = <int>[];
  bool _hasId3v1 = false;
  int _adtsTotalDataLength = 0;

  Future<void> parse() async {
    metadata.setFormat(lossless: false, hasAudio: true, hasVideo: false);

    final id3v2 = Id3v2Parser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await id3v2.parse();

    while (true) {
      final syncResult = await _syncToFrame();
      if (syncResult == null) {
        break;
      }

      final shouldQuit = syncResult.kind == _FrameSyncKind.adts
          ? _parseAdtsFrame()
          : _parseMpegAudioFrame();
      if (shouldQuit) {
        break;
      }
    }

    if (!options.skipPostHeaders && tokenizer.canSeek) {
      final id3v1 = Id3v1Parser(metadata: metadata, tokenizer: tokenizer);
      _hasId3v1 = await id3v1.parse();
    }

    _finalizeDurationAndBitrate();
  }

  void _parseFirstFrameInfo(MpegFrameHeader header, List<int> frameData) {
    var offset = 0;

    if (header.isProtectedByCrc) {
      if (frameData.length < 2) {
        metadata.addWarning('MPEG frame too short to contain CRC');
        return;
      }
      offset += 2;
    }

    final sideInfoLength = header.sideInformationLength;
    if (sideInfoLength == null) {
      return;
    }
    if (offset + sideInfoLength > frameData.length) {
      metadata.addWarning('MPEG frame too short for side information');
      return;
    }
    offset += sideInfoLength;

    if (offset + 4 > frameData.length) {
      return;
    }

    final tag = ascii.decode(
      frameData.sublist(offset, offset + 4),
      allowInvalid: true,
    );
    offset += 4;

    if (tag == 'Info') {
      metadata.setFormat(codecProfile: 'CBR');
      final info = parseXingHeader(frameData, offset);
      _applyXingInfo(
        header,
        info,
        frameData,
        offset,
        applyVbrProfile: false,
        useStreamSizeBitrate: false,
      );
      return;
    }

    if (tag == 'Xing') {
      final info = parseXingHeader(frameData, offset);
      _applyXingInfo(header, info, frameData, offset);
      return;
    }

    if (tag == 'LAME') {
      if (offset + 6 <= frameData.length) {
        final version = ascii
            .decode(frameData.sublist(offset, offset + 6), allowInvalid: true)
            .replaceAll(RegExp(r'\x00+$'), '')
            .trim();
        if (version.isNotEmpty) {
          metadata.setFormat(tool: 'LAME $version');
        }
      } else {
        metadata.addWarning('Corrupt LAME header');
      }
    }
  }

  void _applyXingInfo(
    MpegFrameHeader header,
    XingInfoTag info,
    List<int> frameData,
    int xingOffset, {
    bool applyVbrProfile = true,
    bool useStreamSizeBitrate = true,
  }) {
    if (applyVbrProfile && info.vbrScale != null) {
      final codecProfile = 'V${((100 - info.vbrScale!) / 10).floor()}';
      metadata.setFormat(codecProfile: codecProfile);
    }

    if (info.lameVersion != null && info.lameVersion!.isNotEmpty) {
      metadata.setFormat(tool: 'LAME ${info.lameVersion}');
    }

    if (info.lameMusicLengthMs != null && info.lameMusicLengthMs! > 0) {
      metadata.setFormat(duration: info.lameMusicLengthMs! / 1000.0);
    }

    _applyLameReplayGain(frameData, xingOffset);

    if (info.numFrames != null) {
      final duration = header.calcDuration(info.numFrames!);
      if (duration != null) {
        metadata.setFormat(duration: duration);
      }
    }

    final duration = metadata.format.duration;
    if (useStreamSizeBitrate &&
        info.streamSize != null &&
        duration != null &&
        duration > 0) {
      metadata.setFormat(bitrate: 8 * info.streamSize! / duration);
    }
  }

  void _applyLameReplayGain(List<int> frameData, int xingOffset) {
    final extOffset = _findLameExtendedHeaderOffset(frameData, xingOffset);
    if (extOffset == null || extOffset + 27 > frameData.length) {
      return;
    }

    final peakRaw = _readUint32Be(frameData, extOffset + 2);
    if (peakRaw > 0) {
      metadata.setFormat(trackPeakLevel: peakRaw / 8388608.0);
    }

    final trackReplayGain = ReplayGainDataFormat.parse(
      frameData,
      offset: extOffset + 6,
    );
    final albumReplayGain = ReplayGainDataFormat.parse(
      frameData,
      offset: extOffset + 8,
    );

    _applyReplayGain(trackReplayGain);
    _applyReplayGain(albumReplayGain);
  }

  void _applyReplayGain(ReplayGainData? replayGain) {
    if (replayGain == null) {
      return;
    }

    if (replayGain.type == ReplayGainNameCode.radio) {
      metadata.setFormat(trackGain: replayGain.adjustment);
      return;
    }

    if (replayGain.type == ReplayGainNameCode.audiophile) {
      metadata.setFormat(albumGain: replayGain.adjustment);
    }
  }

  int? _findLameExtendedHeaderOffset(List<int> frameData, int xingOffset) {
    if (xingOffset + 4 > frameData.length) {
      return null;
    }

    var cursor = xingOffset;
    final flags = _readUint32Be(frameData, cursor);
    cursor += 4;

    if ((flags & 0x00000001) != 0) {
      cursor += 4;
    }
    if ((flags & 0x00000002) != 0) {
      cursor += 4;
    }
    if ((flags & 0x00000004) != 0) {
      cursor += 100;
    }
    if ((flags & 0x00000008) != 0) {
      cursor += 4;
    }

    if (cursor + 9 > frameData.length) {
      return null;
    }

    final lameTag = ascii.decode(
      frameData.sublist(cursor, cursor + 4),
      allowInvalid: true,
    );
    if (lameTag != 'LAME') {
      return null;
    }

    return cursor + 9;
  }

  int _readUint32Be(List<int> data, int offset) =>
      (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];

  bool _parseMpegAudioFrame() {
    final frameStart = tokenizer.position;
    final headerBytes = _safePeekBytes(4);
    if (headerBytes == null || headerBytes.length < 4) {
      return true;
    }

    final header = MpegFrameHeader.parse(headerBytes);
    if (header == null) {
      _safeSkip(1);
      return false;
    }
    if (_safeReadBytes(4) == null) {
      return true;
    }

    _mpegOffset ??= frameStart;
    _frameCount++;
    _frameSize = header.frameLength;
    _samplesPerFrame = header.samplesPerFrame;

    metadata.setFormat(
      container: 'MPEG',
      codec: header.codec,
      sampleRate: header.sampleRate,
      numberOfChannels: header.channelMode == MpegChannelMode.mono ? 1 : 2,
      bitrate: header.bitrate,
    );

    _bitrates.add(header.bitrate);

    final payloadLength = header.frameLength - 4;
    if (payloadLength < 0) {
      metadata.addWarning('Invalid MPEG frame length: ${header.frameLength}');
      return false;
    }

    if (_frameCount == 1) {
      final frameData = _safeReadBytes(payloadLength);
      if (frameData == null) {
        return true;
      }
      _parseFirstFrameInfo(header, frameData);

      if (!options.duration && metadata.format.duration != null) {
        return true;
      }
    } else {
      if (!_safeSkip(payloadLength)) {
        return true;
      }
    }

    if (_frameCount == 3) {
      final isCbr = _areAllSame(_bitrates);
      if (isCbr) {
        metadata.setFormat(codecProfile: 'CBR');
        if (tokenizer.fileInfo?.size != null) {
          return true;
        }
      } else if (metadata.format.duration != null) {
        return true;
      }

      return false;
    }

    if (_frameCount == 4) {
      _calculateEofDuration = true;
    }

    return false;
  }

  bool _parseAdtsFrame() {
    final frameStart = tokenizer.position;
    final firstSevenBytes = _safePeekBytes(7);
    if (firstSevenBytes == null || firstSevenBytes.length < 7) {
      return true;
    }

    final header = AdtsFrameHeader.parse(firstSevenBytes);
    if (header == null) {
      _safeSkip(1);
      return false;
    }

    if (_safeReadBytes(header.headerLength) == null) {
      return true;
    }

    _mpegOffset ??= frameStart;
    _frameCount++;
    _frameSize = header.frameLength;
    _samplesPerFrame = header.samplesPerFrame;
    _adtsTotalDataLength += header.frameLength;

    metadata.setFormat(
      container: header.container,
      codec: header.codec,
      codecProfile: header.codecProfile,
      sampleRate: header.sampleRate,
      numberOfChannels: header.numberOfChannels,
    );

    if (header.sampleRate != null) {
      final framesPerSecond = header.sampleRate! / header.samplesPerFrame;
      final bytesPerFrame = _adtsTotalDataLength / _frameCount;
      final bitrate = (8 * bytesPerFrame * framesPerSecond).round();
      metadata.setFormat(bitrate: bitrate);
    }

    final payloadLength = header.frameLength - header.headerLength;
    if (payloadLength < 0) {
      metadata.addWarning('Invalid ADTS frame length: ${header.frameLength}');
      if (!_safeSkip(1)) {
        return true;
      }
    } else if (payloadLength > 0 && !_safeSkip(payloadLength)) {
      return true;
    }

    if (_frameCount == 3) {
      _calculateEofDuration = true;
    }

    return false;
  }

  Future<_FrameSyncResult?> _syncToFrame() async {
    while (true) {
      final sync = _safePeekBytes(2);
      if (sync == null || sync.length < 2) {
        return null;
      }

      if (sync[0] == 0xFF && (sync[1] & 0xE0) == 0xE0) {
        final kind = MpegFrameHeader.isAdtsHeader(sync)
            ? _FrameSyncKind.adts
            : _FrameSyncKind.mpeg;
        return _FrameSyncResult(kind: kind);
      }

      if (!_safeSkip(1)) {
        return null;
      }
    }
  }

  void _finalizeDurationAndBitrate() {
    final fileSize = tokenizer.fileInfo?.size;
    final sampleRate = metadata.format.sampleRate;

    if (fileSize != null &&
        _mpegOffset != null &&
        _frameSize != null &&
        _samplesPerFrame != null) {
      final id3v1Size = _hasId3v1 ? 128 : 0;
      final mpegSize = fileSize - _mpegOffset! - id3v1Size;

      if (metadata.format.codecProfile == 'CBR') {
        final numberOfSamples =
            (mpegSize / _frameSize!).round() * _samplesPerFrame!;
        metadata.setFormat(numberOfSamples: numberOfSamples);
        if (sampleRate != null && metadata.format.duration == null) {
          metadata.setFormat(duration: numberOfSamples / sampleRate);
        }
      }

      final profile = metadata.format.codecProfile;
      final duration = metadata.format.duration;
      if (duration != null &&
          duration > 0 &&
          (profile == null || profile.startsWith('V'))) {
        final calculatedBitrate = mpegSize * 8 / duration;
        metadata.setFormat(bitrate: calculatedBitrate);
      }
    }

    if (_calculateEofDuration &&
        metadata.format.duration == null &&
        _samplesPerFrame != null &&
        sampleRate != null) {
      final numberOfSamples = _frameCount * _samplesPerFrame!;
      metadata.setFormat(
        numberOfSamples: options.duration ? numberOfSamples : null,
        duration: numberOfSamples / sampleRate,
      );
    }
  }

  List<int>? _safeReadBytes(int length) {
    try {
      return tokenizer.readBytes(length);
    } on TokenizerException {
      return null;
    }
  }

  List<int>? _safePeekBytes(int length) {
    try {
      return tokenizer.peekBytes(length);
    } on TokenizerException {
      return null;
    }
  }

  bool _safeSkip(int length) {
    if (length <= 0) {
      return true;
    }
    try {
      tokenizer.skip(length);
      return true;
    } on TokenizerException {
      return false;
    }
  }

  bool _areAllSame(List<int> values) {
    if (values.isEmpty) {
      return true;
    }
    final first = values.first;
    for (final value in values) {
      if (value != first) {
        return false;
      }
    }
    return true;
  }
}

enum MpegChannelMode { stereo, jointStereo, dualChannel, mono }

class MpegFrameHeader {
  const MpegFrameHeader({
    required this.version,
    required this.layer,
    required this.isProtectedByCrc,
    required this.bitrate,
    required this.sampleRate,
    required this.padding,
    required this.channelMode,
    required this.frameLength,
  });
  static const List<double?> _versionTable = <double?>[2.5, null, 2, 1];
  static const List<int> _layerTable = <int>[0, 3, 2, 1];
  static const List<MpegChannelMode> _channelModeTable = <MpegChannelMode>[
    MpegChannelMode.stereo,
    MpegChannelMode.jointStereo,
    MpegChannelMode.dualChannel,
    MpegChannelMode.mono,
  ];

  static const Map<int, Map<int, int>> _bitrateTable = <int, Map<int, int>>{
    1: <int, int>{11: 32, 12: 32, 13: 32, 21: 32, 22: 8, 23: 8},
    2: <int, int>{11: 64, 12: 48, 13: 40, 21: 48, 22: 16, 23: 16},
    3: <int, int>{11: 96, 12: 56, 13: 48, 21: 56, 22: 24, 23: 24},
    4: <int, int>{11: 128, 12: 64, 13: 56, 21: 64, 22: 32, 23: 32},
    5: <int, int>{11: 160, 12: 80, 13: 64, 21: 80, 22: 40, 23: 40},
    6: <int, int>{11: 192, 12: 96, 13: 80, 21: 96, 22: 48, 23: 48},
    7: <int, int>{11: 224, 12: 112, 13: 96, 21: 112, 22: 56, 23: 56},
    8: <int, int>{11: 256, 12: 128, 13: 112, 21: 128, 22: 64, 23: 64},
    9: <int, int>{11: 288, 12: 160, 13: 128, 21: 144, 22: 80, 23: 80},
    10: <int, int>{11: 320, 12: 192, 13: 160, 21: 160, 22: 96, 23: 96},
    11: <int, int>{11: 352, 12: 224, 13: 192, 21: 176, 22: 112, 23: 112},
    12: <int, int>{11: 384, 12: 256, 13: 224, 21: 192, 22: 128, 23: 128},
    13: <int, int>{11: 416, 12: 320, 13: 256, 21: 224, 22: 144, 23: 144},
    14: <int, int>{11: 448, 12: 384, 13: 320, 21: 256, 22: 160, 23: 160},
  };

  static final Map<double, List<int>> _samplingRateTable = <double, List<int>>{
    1.0: <int>[44100, 48000, 32000],
    2.0: <int>[22050, 24000, 16000],
    2.5: <int>[11025, 12000, 8000],
  };

  final double version;
  final int layer;
  final bool isProtectedByCrc;
  final int bitrate;
  final int sampleRate;
  final bool padding;
  final MpegChannelMode channelMode;
  final int frameLength;

  String get codec {
    final versionLabel = version == version.roundToDouble()
        ? version.round().toString()
        : version.toString();
    return 'MPEG $versionLabel Layer $layer';
  }

  int get samplesPerFrame {
    if (version == 1.0) {
      if (layer == 1) return 384;
      if (layer == 2) return 1152;
      if (layer == 3) return 1152;
      return 0;
    }
    if (layer == 1) return 384;
    if (layer == 2) return 1152;
    if (layer == 3) return 576;
    return 0;
  }

  int? get sideInformationLength {
    if (layer != 3) {
      return 2;
    }

    final mono = channelMode == MpegChannelMode.mono;
    if (version == 1.0) {
      return mono ? 17 : 32;
    }
    if (version == 2.0 || version == 2.5) {
      return mono ? 9 : 17;
    }
    return null;
  }

  double? calcDuration(int numFrames) {
    if (sampleRate <= 0 || samplesPerFrame <= 0) {
      return null;
    }
    return numFrames * samplesPerFrame / sampleRate;
  }

  static MpegFrameHeader? parse(List<int> bytes) {
    if (bytes.length < 4) {
      return null;
    }

    if (bytes[0] != 0xFF || (bytes[1] & 0xE0) != 0xE0) {
      return null;
    }

    if (isAdtsHeader(bytes)) {
      return null;
    }

    final versionIndex = (bytes[1] >> 3) & 0x03;
    final layerIndex = (bytes[1] >> 1) & 0x03;
    final version = _versionTable[versionIndex];
    final layer = _layerTable[layerIndex];
    if (version == null || layer == 0) {
      return null;
    }

    final isProtectedByCrc = ((bytes[1] & 0x01) == 0);
    final bitrateIndex = (bytes[2] >> 4) & 0x0F;
    final sampleRateIndex = (bytes[2] >> 2) & 0x03;
    final padding = ((bytes[2] >> 1) & 0x01) == 1;
    final channelModeIndex = (bytes[3] >> 6) & 0x03;

    if (bitrateIndex == 0 || bitrateIndex == 0x0F || sampleRateIndex == 0x03) {
      return null;
    }

    final channelMode = _channelModeTable[channelModeIndex];
    final codecIndex = (version.floor() * 10) + layer;
    final bitrateKbps = _bitrateTable[bitrateIndex]?[codecIndex];
    final samplingCandidates = _samplingRateTable[version];
    if (bitrateKbps == null || samplingCandidates == null) {
      return null;
    }

    final sampleRate = samplingCandidates[sampleRateIndex];
    final bitrate = bitrateKbps * 1000;

    final samplesPerFrame = version == 1.0
        ? (layer == 1 ? 384 : 1152)
        : (layer == 1 ? 384 : (layer == 3 ? 576 : 1152));

    final slotSize = layer == 1 ? 4 : 1;
    final frameLength =
        ((samplesPerFrame / 8.0 * bitrate / sampleRate) +
                (padding ? slotSize : 0))
            .floor();

    if (frameLength <= 4) {
      return null;
    }

    return MpegFrameHeader(
      version: version,
      layer: layer,
      isProtectedByCrc: isProtectedByCrc,
      bitrate: bitrate,
      sampleRate: sampleRate,
      padding: padding,
      channelMode: channelMode,
      frameLength: frameLength,
    );
  }

  static bool isAdtsHeader(List<int> bytes) {
    if (bytes.length < 2) {
      return false;
    }
    if (bytes[0] != 0xFF || (bytes[1] & 0xE0) != 0xE0) {
      return false;
    }

    final versionIndex = (bytes[1] >> 3) & 0x03;
    final layerIndex = (bytes[1] >> 1) & 0x03;
    return versionIndex > 1 && layerIndex == 0;
  }
}

enum _FrameSyncKind { mpeg, adts }

class _FrameSyncResult {
  const _FrameSyncResult({required this.kind});
  final _FrameSyncKind kind;
}
