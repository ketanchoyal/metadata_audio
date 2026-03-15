library;

import 'dart:convert';

typedef Id3v2MajorVersion = int;

class Id3v2ContentError implements Exception {

  const Id3v2ContentError(this.message);
  final String message;

  @override
  String toString() => 'Id3v2ContentError: $message';
}

class Id3v2Version {

  const Id3v2Version({required this.major, required this.revision});
  final Id3v2MajorVersion major;
  final int revision;
}

class Id3v2HeaderFlags {

  const Id3v2HeaderFlags({
    required this.unsynchronisation,
    required this.isExtendedHeader,
    required this.expIndicator,
    required this.footer,
  });
  final bool unsynchronisation;
  final bool isExtendedHeader;
  final bool expIndicator;
  final bool footer;
}

class Id3v2Header {

  const Id3v2Header({
    required this.fileIdentifier,
    required this.version,
    required this.flags,
    required this.size,
  });
  final String fileIdentifier;
  final Id3v2Version version;
  final Id3v2HeaderFlags flags;
  final int size;
}

class TextEncodingInfo {

  const TextEncodingInfo({required this.encoding, this.bom = false});
  final String encoding;
  final bool bom;
}

class TextHeader {

  const TextHeader({required this.encoding, required this.language});
  final TextEncodingInfo encoding;
  final String language;
}

class SyncTextHeader extends TextHeader {

  const SyncTextHeader({
    required super.encoding,
    required super.language,
    required this.timeStampFormat,
    required this.contentType,
  });
  final int timeStampFormat;
  final int contentType;
}

class ID3v2Token {
  static const int id3v2HeaderLength = 10;

  static const Map<int, String> attachedPictureType = {
    0: 'Other',
    1: "32x32 pixels 'file icon' (PNG only)",
    2: 'Other file icon',
    3: 'Cover (front)',
    4: 'Cover (back)',
    5: 'Leaflet page',
    6: 'Media (e.g. label side of CD)',
    7: 'Lead artist/lead performer/soloist',
    8: 'Artist/performer',
    9: 'Conductor',
    10: 'Band/Orchestra',
    11: 'Composer',
    12: 'Lyricist/text writer',
    13: 'Recording Location',
    14: 'During recording',
    15: 'During performance',
    16: 'Movie/video screen capture',
    17: 'A bright coloured fish',
    18: 'Illustration',
    19: 'Band/artist logotype',
    20: 'Publisher/Studio logotype',
  };

  static int uint24Be(List<int> bytes, int offset) {
    _expectLength(bytes, offset, 3, 'uint24');
    return (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
  }

  static int uint32Be(List<int> bytes, int offset) {
    _expectLength(bytes, offset, 4, 'uint32');
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  static int uint32Synchsafe(List<int> bytes, int offset) {
    _expectLength(bytes, offset, 4, 'uint32 synchsafe');
    return (bytes[offset + 3] & 0x7f) |
        (bytes[offset + 2] << 7) |
        (bytes[offset + 1] << 14) |
        (bytes[offset] << 21);
  }

  static Id3v2Header parseHeader(List<int> bytes, [int offset = 0]) {
    _expectLength(bytes, offset, id3v2HeaderLength, 'ID3v2 header');

    final fileIdentifier = ascii.decode(bytes.sublist(offset, offset + 3));
    final version = Id3v2Version(
      major: bytes[offset + 3],
      revision: bytes[offset + 4],
    );
    final flagByte = bytes[offset + 5];
    final flags = Id3v2HeaderFlags(
      unsynchronisation: _bit(flagByte, 7),
      isExtendedHeader: _bit(flagByte, 6),
      expIndicator: _bit(flagByte, 5),
      footer: _bit(flagByte, 4),
    );

    return Id3v2Header(
      fileIdentifier: fileIdentifier,
      version: version,
      flags: flags,
      size: uint32Synchsafe(bytes, offset + 6),
    );
  }

  static TextEncodingInfo textEncodingFromByte(int byte) {
    switch (byte) {
      case 0x00:
        return const TextEncodingInfo(encoding: 'latin1');
      case 0x01:
        return const TextEncodingInfo(encoding: 'utf16', bom: true);
      case 0x02:
        return const TextEncodingInfo(encoding: 'utf16be');
      case 0x03:
        return const TextEncodingInfo(encoding: 'utf8');
      default:
        return const TextEncodingInfo(encoding: 'utf8');
    }
  }

  static TextHeader parseTextHeader(List<int> bytes, [int offset = 0]) {
    _expectLength(bytes, offset, 4, 'text header');
    return TextHeader(
      encoding: textEncodingFromByte(bytes[offset]),
      language: latin1.decode(bytes.sublist(offset + 1, offset + 4)),
    );
  }

  static SyncTextHeader parseSyncTextHeader(List<int> bytes, [int offset = 0]) {
    _expectLength(bytes, offset, 6, 'sync text header');
    final textHeader = parseTextHeader(bytes, offset);
    return SyncTextHeader(
      encoding: textHeader.encoding,
      language: textHeader.language,
      timeStampFormat: bytes[offset + 4],
      contentType: bytes[offset + 5],
    );
  }

  static bool _bit(int value, int bitIndexFromLsb) =>
      (value & (1 << bitIndexFromLsb)) != 0;

  static void _expectLength(
    List<int> bytes,
    int offset,
    int needed,
    String label,
  ) {
    if (offset < 0 || offset + needed > bytes.length) {
      throw Id3v2ContentError(
        'Insufficient bytes for $label: need $needed at offset $offset, have ${bytes.length - offset}',
      );
    }
  }
}
