library;

class AdtsFrameHeader {

  const AdtsFrameHeader({
    required this.version,
    required this.profileIndex,
    required this.sampleRateIndex,
    required this.channelConfigIndex,
    required this.frameLength,
    required this.protectionAbsent,
  });
  static const List<String> _audioObjectTypes = <String>[
    'AAC Main',
    'AAC LC',
    'AAC SSR',
    'AAC LTP',
  ];

  static const List<int?> _samplingFrequencies = <int?>[
    96000,
    88200,
    64000,
    48000,
    44100,
    32000,
    24000,
    22050,
    16000,
    12000,
    11025,
    8000,
    7350,
    null,
    null,
    -1,
  ];

  static const List<int?> _channelConfigurations = <int?>[
    null,
    1,
    2,
    3,
    4,
    5,
    6,
    8,
  ];

  final int version;
  final int profileIndex;
  final int sampleRateIndex;
  final int channelConfigIndex;
  final int frameLength;
  final bool protectionAbsent;

  static AdtsFrameHeader? parse(List<int> bytes) {
    if (bytes.length < 7) {
      return null;
    }

    if (bytes[0] != 0xFF || (bytes[1] & 0xE0) != 0xE0) {
      return null;
    }

    final versionIndex = (bytes[1] >> 3) & 0x03;
    final layerIndex = (bytes[1] >> 1) & 0x03;
    if (versionIndex <= 1 || layerIndex != 0) {
      return null;
    }

    final version = versionIndex == 2 ? 4 : 2;
    final protectionAbsent = (bytes[1] & 0x01) == 1;
    final profileIndex = (bytes[2] >> 6) & 0x03;
    final sampleRateIndex = (bytes[2] >> 2) & 0x0F;
    final channelConfigIndex =
        ((bytes[2] & 0x01) << 2) | ((bytes[3] >> 6) & 0x03);
    final frameLength =
        ((bytes[3] & 0x03) << 11) | (bytes[4] << 3) | ((bytes[5] >> 5) & 0x07);

    final headerLength = protectionAbsent ? 7 : 9;
    if (frameLength < headerLength) {
      return null;
    }

    return AdtsFrameHeader(
      version: version,
      profileIndex: profileIndex,
      sampleRateIndex: sampleRateIndex,
      channelConfigIndex: channelConfigIndex,
      frameLength: frameLength,
      protectionAbsent: protectionAbsent,
    );
  }

  String get container => 'ADTS/MPEG-$version';

  String get codec => 'AAC';

  String? get codecProfile {
    if (profileIndex < 0 || profileIndex >= _audioObjectTypes.length) {
      return null;
    }
    return _audioObjectTypes[profileIndex];
  }

  int? get sampleRate {
    if (sampleRateIndex < 0 || sampleRateIndex >= _samplingFrequencies.length) {
      return null;
    }
    final value = _samplingFrequencies[sampleRateIndex];
    if (value == null || value <= 0) {
      return null;
    }
    return value;
  }

  int? get numberOfChannels {
    if (channelConfigIndex < 0 ||
        channelConfigIndex >= _channelConfigurations.length) {
      return null;
    }
    return _channelConfigurations[channelConfigIndex];
  }

  int get samplesPerFrame => 1024;

  int get headerLength => protectionAbsent ? 7 : 9;
}
