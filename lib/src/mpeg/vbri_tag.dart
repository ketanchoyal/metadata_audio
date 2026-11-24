library;

/// Fraunhofer VBRI header information.
class VbriInfoTag {
  const VbriInfoTag({
    required this.version,
    required this.delay,
    required this.quality,
    required this.streamBytes,
    required this.numFrames,
    required this.tocEntries,
    required this.tocScale,
    required this.tocEntrySize,
    required this.tocFramesPerEntry,
  });

  /// VBRI version (typically 1).
  final int version;

  /// Encoder delay.
  final int delay;

  /// Quality indicator.
  final int quality;

  /// Total number of bytes in the stream.
  final int streamBytes;

  /// Total number of MPEG audio frames in the stream.
  final int numFrames;

  /// Number of entries in the TOC.
  final int tocEntries;

  /// Scale factor for TOC entries.
  final int tocScale;

  /// Size of each TOC entry in bytes (1, 2, or 4).
  final int tocEntrySize;

  /// Number of frames per TOC entry.
  final int tocFramesPerEntry;
}

int _readUint16Be(List<int> data, int offset) =>
    (data[offset] << 8) | data[offset + 1];

int _readUint32Be(List<int> data, int offset) =>
    (data[offset] << 24) |
    (data[offset + 1] << 16) |
    (data[offset + 2] << 8) |
    data[offset + 3];

/// Parses a Fraunhofer VBRI header starting at [offset] in [data].
///
/// Returns `null` if [data] does not contain a valid VBRI header.
VbriInfoTag? parseVbriHeader(List<int> data, int offset) {
  // VBRI header requires at least 26 bytes:
  // 4 bytes magic ('VBRI') + 22 bytes fixed header fields
  if (offset + 26 > data.length) {
    return null;
  }

  // Tag must be ASCII 'VBRI' (0x56, 0x42, 0x52, 0x49)
  if (data[offset] != 0x56 ||
      data[offset + 1] != 0x42 ||
      data[offset + 2] != 0x52 ||
      data[offset + 3] != 0x49) {
    return null;
  }

  final version = _readUint16Be(data, offset + 4);
  final delay = _readUint16Be(data, offset + 6);
  final quality = _readUint16Be(data, offset + 8);
  final streamBytes = _readUint32Be(data, offset + 10);
  final numFrames = _readUint32Be(data, offset + 14);
  final tocEntries = _readUint16Be(data, offset + 18);
  final tocScale = _readUint16Be(data, offset + 20);
  final tocEntrySize = _readUint16Be(data, offset + 22);
  final tocFramesPerEntry = _readUint16Be(data, offset + 24);

  return VbriInfoTag(
    version: version,
    delay: delay,
    quality: quality,
    streamBytes: streamBytes,
    numFrames: numFrames,
    tocEntries: tocEntries,
    tocScale: tocScale,
    tocEntrySize: tocEntrySize,
    tocFramesPerEntry: tocFramesPerEntry,
  );
}
