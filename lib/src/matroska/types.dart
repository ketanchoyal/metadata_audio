library;

// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

import 'package:audio_metadata/src/model/types.dart';

/// Matroska track type values.
class MatroskaTrackType {
  static const int video = 0x01;
  static const int audio = 0x02;
  static const int complex = 0x03;
  static const int logo = 0x04;
  static const int subtitle = 0x11;
  static const int button = 0x12;
  static const int control = 0x20;

  static String? nameOf(int? value) {
    switch (value) {
      case video:
        return 'video';
      case audio:
        return 'audio';
      case complex:
        return 'complex';
      case logo:
        return 'logo';
      case subtitle:
        return 'subtitle';
      case button:
        return 'button';
      case control:
        return 'control';
    }
    return null;
  }
}

const Map<int, String> targetTypeByValue = <int, String>{
  10: 'shot',
  20: 'scene',
  30: 'track',
  40: 'part',
  50: 'album',
  60: 'edition',
  70: 'collection',
};

class MatroskaTrackEntry {
  const MatroskaTrackEntry({
    required this.trackNumber,
    required this.codecID,
    this.trackType,
    this.audio,
    this.video,
    this.flagEnabled,
    this.flagDefault,
    this.flagLacing,
    this.codecSettings,
    this.language,
    this.name,
  });

  final int trackNumber;
  final int? trackType;
  final String codecID;
  final AudioTrack? audio;
  final VideoTrack? video;
  final bool? flagEnabled;
  final bool? flagDefault;
  final bool? flagLacing;
  final String? codecSettings;
  final String? language;
  final String? name;
}

class MatroskaSimpleTag {
  const MatroskaSimpleTag({
    this.name,
    this.string,
    this.binary,
    this.language,
    this.languageIETF,
    this.isDefault,
  });

  final String? name;
  final String? string;
  final Uint8List? binary;
  final String? language;
  final String? languageIETF;
  final bool? isDefault;
}
