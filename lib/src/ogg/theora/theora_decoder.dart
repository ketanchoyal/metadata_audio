library;

import 'dart:convert';

class TheoraIdentificationHeader {
  const TheoraIdentificationHeader({
    required this.versionMajor,
    required this.versionMinor,
    required this.versionRevision,
    required this.frameWidth,
    required this.frameHeight,
    required this.pictureWidth,
    required this.pictureHeight,
    required this.frameRateNumerator,
    required this.frameRateDenominator,
    required this.keyframeGranuleShift,
    required this.bitrate,
  });

  /// The major version number ('\x03' for the current format)
  final int versionMajor;

  /// The minor version number (packed version byte)
  final int versionMinor;

  /// The version revision number ('2.1' related)
  final int versionRevision;

  /// The width of the frame in macro blocks
  final int frameWidth;

  /// The height of the frame in macro blocks
  final int frameHeight;

  /// The width of the picture region (scaled picture width)
  final int pictureWidth;

  /// The height of the picture region (scaled picture height)
  final int pictureHeight;

  /// Frame rate numerator
  final int frameRateNumerator;

  /// Frame rate denominator
  final int frameRateDenominator;

  /// Keyframe granule position packing shift
  final int keyframeGranuleShift;

  /// The nominal bitrate of the stream, in bits per second.
  final int bitrate;

  /// Frame rate as a fraction-free value, or null if not decorable
  double? get frameRate => frameRateDenominator > 0 && frameRateNumerator > 0
      ? frameRateNumerator / frameRateDenominator
      : null;

  /// Pixel width: width of the frame scaled to whole pixels
  int get pixelWidth => frameWidth * 16;

  /// Pixel height: height of the frame scaled to whole pixels
  int get pixelHeight => frameHeight * 16;

  /// Whether the version is below 3.2.1 (legacy 0-based granule semantics)
  bool get isLegacyVersion =>
      versionMajor * 65536 + versionMinor * 256 + versionRevision < 0x030201;
}

class TheoraDecoder {
  static const int identificationHeaderLength = 42;

  static bool isIdentificationHeader(List<int> data) =>
      data.length >= 7 && data[0] == 0x80 && _ascii(data, 1, 6) == 'theora';

  static TheoraIdentificationHeader parseIdentificationHeader(List<int> data) {
    if (!isIdentificationHeader(data) ||
        data.length < identificationHeaderLength) {
      throw const FormatException('Invalid Theora identification header');
    }

    return TheoraIdentificationHeader(
      versionMajor: data[7],
      versionMinor: data[8],
      versionRevision: data[9],
      frameWidth: _uint16Be(data, 10),
      frameHeight: _uint16Be(data, 12),
      pictureWidth: _uint24Be(data, 14),
      pictureHeight: _uint24Be(data, 17),
      frameRateNumerator: _uint32Be(data, 22),
      frameRateDenominator: _uint32Be(data, 26),
      keyframeGranuleShift: (_uint16Be(data, 40) >> 5) & 0x1f,
      bitrate: _uint24Be(data, 37),
    );
  }

  static String _ascii(List<int> data, int offset, int length) {
    if (offset < 0 || offset + length > data.length) {
      return '';
    }

    return ascii.decode(
      data.sublist(offset, offset + length),
      allowInvalid: true,
    );
  }

  static int _uint16Be(List<int> d, int o) => (d[o] << 8) | d[o + 1];

  static int _uint24Be(List<int> d, int o) =>
      (d[o] << 16) | (d[o + 1] << 8) | d[o + 2];

  static int _uint32Be(List<int> d, int o) =>
      (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];
}
