/// Lyrics3 parser for reading Lyrics3 tags.
///
/// Lyrics3 tags are positioned before ID3v1 tags (if present) at the end of
/// MP3 files. The format allows embedding lyrics in MP3 files with metadata.
///
/// Spec: http://id3.org/Lyrics3
/// Based on upstream:
/// https://github.com/Borewit/music-metadata/blob/master/lib/lyrics3/Lyrics3.ts
library;

import 'dart:convert';

import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

/// Lyrics3 tag end marker for version 2.00
const String lyrics3v2EndTag = 'LYRICS200';

/// Lyrics3 tag end marker for version 1.00
const String lyrics3v1EndTag = 'LYRICSEND';

/// Lyrics3 tag begin marker
const String lyrics3BeginTag = 'LYRICSBEGIN';

/// Parser for Lyrics3 metadata tags.
///
/// Lyrics3 tags are found before ID3v1 tags at the end of MP3 files.
/// This parser seeks near the end of file looking for Lyrics3 markers.
///
/// Lyrics3 v2.00 structure (footer = 15 bytes):
/// - Bytes 0-5: Size of lyrics data (6 bytes, ASCII digits)
/// - Bytes 6-14: "LYRICS200" (9 bytes)
///
/// Lyrics3 v1.00 structure:
/// - "LYRICSBEGIN" ... "LYRICSEND"
/// - No fixed footer
///
/// Fields within lyrics data:
/// - IND: Indicators (3 bytes, binary flags)
/// - LYR: Lyrics text
/// - INF: Informational data
/// - AUT: Author/artist
/// - EAL: Extended album name
/// - TIT: Title
/// - ART: Artist
/// - ALB: Album
/// - EAU: Extended artist
/// - ETT: Extended title
class Lyrics3Parser {
  static const int lyrics3v2FooterLength = 15; // Size (6) + "LYRICS200" (9)
  static const int maxLyrics3Size = 102400; // 100 KB max

  final MetadataCollector metadata;
  final Tokenizer tokenizer;

  Lyrics3Parser({required this.metadata, required this.tokenizer});

  /// Get the size of Lyrics3 tag from file footer.
  ///
  /// Looks at the last 15 bytes for Lyrics3 v2.00 footer.
  /// The footer format is: [6-digit size][9-byte "LYRICS200"]
  ///
  /// Returns the size in bytes, or 0 if no Lyrics3 tag is found.
  Future<int> _getLyricsHeaderLength() async {
    final fileInfo = tokenizer.fileInfo;
    if (fileInfo == null || fileInfo.size == null || fileInfo.size! < 143) {
      return 0;
    }

    try {
      // Need random access to read from end
      if (!tokenizer.canSeek) {
        return 0;
      }

      // Save current position
      final originalPosition = tokenizer.position;

      // Seek to 15 bytes before end
      final position = fileInfo.size! - lyrics3v2FooterLength;
      tokenizer.seek(position);

      // Read the footer
      final buf = tokenizer.peekBytes(lyrics3v2FooterLength);

      // Restore position
      tokenizer.seek(originalPosition);

      if (buf.length == lyrics3v2FooterLength) {
        // Decode as latin1
        final txt = latin1.decode(buf);
        final tag = txt.substring(6); // Last 9 chars should be "LYRICS200"

        if (tag == lyrics3v2EndTag) {
          // First 6 chars are the size
          final sizeStr = txt.substring(0, 6);
          try {
            final size = int.parse(sizeStr);
            // Sanity check: lyrics data shouldn't be larger than maxLyrics3Size
            if (size > 0 && size <= maxLyrics3Size) {
              return size + lyrics3v2FooterLength;
            }
          } on FormatException {
            // Invalid size format
            return 0;
          }
        }
      }
    } on Exception {
      // Ignore errors, just means no Lyrics3 tag
    }

    return 0;
  }

  /// Parse Lyrics3 tag if present
  Future<void> parse() async {
    final headerLength = await _getLyricsHeaderLength();

    if (headerLength == 0) {
      // No Lyrics3 v2.00 found, check for v1.00
      await _parseLyrics3v1();
      return;
    }

    final fileInfo = tokenizer.fileInfo;
    if (fileInfo == null ||
        fileInfo.size == null ||
        headerLength > fileInfo.size!) {
      return;
    }

    try {
      if (!tokenizer.canSeek) {
        return;
      }

      // Save current position
      final originalPosition = tokenizer.position;

      // Seek to lyrics data start
      final position = fileInfo.size! - headerLength;
      tokenizer.seek(position);

      // Read the entire Lyrics3 data
      final buf = tokenizer.readBytes(headerLength);

      // Restore position
      tokenizer.seek(originalPosition);

      if (buf.length == headerLength) {
        // Parse the Lyrics3 data (exclude the footer)
        final lyricsData = latin1.decode(
          buf.sublist(0, headerLength - lyrics3v2FooterLength),
        );
        final lyricsTag = _parseLyricsData(lyricsData);

        if (lyricsTag != null) {
          metadata.addNativeTag('Lyrics3', 'LYR', lyricsTag);
        }
      }
    } on Exception {
      // Ignore parsing errors
    }
  }

  /// Parse Lyrics3 v1.00 format (LYRICSBEGIN...LYRICSEND)
  Future<void> _parseLyrics3v1() async {
    // Lyrics3 v1.00 doesn't have a footer, would need to search backwards
    // For now, this is a placeholder - full implementation would require scanning
    // This is less common than v2.00
  }

  /// Parse lyrics data fields
  ///
  /// Lyrics3 data is a series of [FIELD_ID:SIZE]data records
  /// where FIELD_ID is 3 characters and SIZE is the byte count.
  LyricsTag? _parseLyricsData(String lyricsData) {
    final syncText = <LyricsText>[];
    String? lyricsText;
    String? descriptor;

    // Split data into records: [ID:SIZE]data pattern
    var pos = 0;

    while (pos < lyricsData.length) {
      if (lyricsData[pos] != '[') {
        pos++;
        continue;
      }

      // Find the end of field header [ID:SIZE]
      final endBracket = lyricsData.indexOf(']', pos);
      if (endBracket == -1) {
        break;
      }

      final header = lyricsData.substring(pos + 1, endBracket);
      final parts = header.split(':');

      if (parts.length != 2) {
        pos = endBracket + 1;
        continue;
      }

      final fieldId = parts[0];
      int fieldSize;
      try {
        fieldSize = int.parse(parts[1]);
      } on FormatException {
        pos = endBracket + 1;
        continue;
      }

      pos = endBracket + 1;

      if (pos + fieldSize > lyricsData.length) {
        break;
      }

      final fieldData = lyricsData.substring(pos, pos + fieldSize);
      pos += fieldSize;

      // Process field based on ID
      switch (fieldId) {
        case 'LYR':
          lyricsText = fieldData.trim();
          break;
        case 'IND':
          // Indicators: 3 bytes (currently unused)
          break;
        case 'INF':
          descriptor = fieldData.trim();
          break;
        case 'AUT':
        case 'TIT':
        case 'ALB':
        case 'ART':
          // Other metadata fields - currently stored in native tags
          break;
      }
    }

    if (lyricsText == null || lyricsText.isEmpty) {
      return null;
    }

    return LyricsTag(
      descriptor: descriptor,
      text: lyricsText,
      contentType: 'lyrics',
      timeStampFormat: 'unsynchronized',
      syncText: syncText,
    );
  }
}
