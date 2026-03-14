/// LRC lyrics parser for reading LRC format lyrics files.
///
/// LRC (Lyrics Karaoke) format is a plain text format with timestamped lyrics.
/// Each line with lyrics can have one or more timestamps in [mm:ss.xx] format.
///
/// Format:
/// - [ti:Title]
/// - [ar:Artist]
/// - [al:Album]
/// - [mm:ss.xx]Lyrics text
///
/// Spec: https://en.wikipedia.org/wiki/LRC_(file_format)
/// Based on upstream: https://github.com/Borewit/music-metadata/blob/master/lib/lrc/LyricsParser.ts
library;

import 'package:audio_metadata/src/model/types.dart';

/// Regex pattern for LRC timestamps: [mm:ss.xx]
/// - Matches [MM:SS.CC] or [MM:SS.CCC] format
/// - MM = minutes (00-99)
/// - SS = seconds (00-59)
/// - CC/CCC = centiseconds or milliseconds (00-999)
final _timestampRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');

/// Parser for LRC format lyrics.
///
/// LRC is a text-based format for karaoke/synchronized lyrics with timestamps.
/// Each lyric line can have multiple timestamps.
///
/// Example LRC content:
/// ```
/// [ti:Song Title]
/// [ar:Artist Name]
/// [al:Album Name]
/// [00:12.00]First line of lyrics
/// [00:17.20]Second line
/// [01:04.00]Third line
/// ```
class LrcParser {
  /// Parse LRC format lyrics from a string.
  ///
  /// If the content contains LRC timestamps, parses as synchronized lyrics.
  /// Otherwise, treats as unsynchronized lyrics.
  ///
  /// Parameters:
  /// - [input]: Raw LRC content string
  ///
  /// Returns: [LyricsTag] with parsed lyrics and metadata
  static LyricsTag parseLyrics(String input) {
    if (_hasTimestamps(input)) {
      return _parseLrc(input);
    }
    return _toUnsyncedLyrics(input);
  }

  /// Check if content contains LRC timestamps
  static bool _hasTimestamps(String content) =>
      _timestampRegex.hasMatch(content);

  /// Convert unsynchronized lyrics to LyricsTag.
  static LyricsTag _toUnsyncedLyrics(String lyrics) => LyricsTag(
    contentType: 'lyrics',
    timeStampFormat: 'unsynchronized',
    text: lyrics.trim(),
    syncText: const [],
  );

  /// Parse LRC formatted text with timestamps and metadata.
  ///
  /// Extracts:
  /// - Metadata fields: [ti:], [ar:], [al:], [au:], etc.
  /// - Timestamped lyrics: [mm:ss.xx]lyrics text
  ///
  /// Parameters:
  /// - [lrcString]: LRC content as a single string
  ///
  /// Returns: [LyricsTag] with synchronized lyrics and metadata
  static LyricsTag _parseLrc(String lrcString) {
    final lines = lrcString.split('\n');
    final syncText = <LyricsText>[];
    String? descriptor;
    String? language;

    for (final line in lines) {
      // Skip empty lines
      if (line.trim().isEmpty) {
        continue;
      }

      // Try to match timestamp pattern
      final match = _timestampRegex.firstMatch(line);
      if (match != null) {
        // Extract timestamp components
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final centisecondsStr = match.group(3)!;

        // Convert to milliseconds
        // If 2 digits, it's centiseconds; if 3 digits, it's milliseconds
        final ms = centisecondsStr.length == 3
            ? int.parse(centisecondsStr)
            : int.parse(centisecondsStr) * 10;

        // Calculate total timestamp in milliseconds
        final timestamp = (minutes * 60 + seconds) * 1000 + ms;

        // Extract lyrics text (everything after the timestamp)
        final text = line.replaceAll(_timestampRegex, '').trim();

        syncText.add(LyricsText(text: text, timestamp: timestamp));
      } else if (line.startsWith('[') && line.contains(':')) {
        // Parse metadata fields like [ti:Title], [ar:Artist]
        final closeIdx = line.indexOf(']');
        if (closeIdx > 1) {
          final field = line.substring(1, closeIdx);
          final colonIdx = field.indexOf(':');
          if (colonIdx > 0) {
            final key = field.substring(0, colonIdx);
            final value = field.substring(colonIdx + 1);

            // Store common metadata
            switch (key.toLowerCase()) {
              case 'ti':
                // Title is stored in the text field
                break;
              case 'ar':
                // Artist info
                break;
              case 'al':
                // Album info
                break;
              case 'au':
                // Author/Artist
                break;
              case 'by':
                // Created by (tool)
                break;
              case 'offset':
                // Time offset (not used currently)
                break;
              case 're':
                // Editor/Reviser (stored as descriptor)
                descriptor = value;
                break;
              case 'la':
                // Language code
                language = value;
                break;
            }
          }
        }
      }
    }

    // Build combined text from all synced lyrics
    final combinedText = syncText.map((line) => line.text).join('\n');

    return LyricsTag(
      descriptor: descriptor,
      language: language,
      text: combinedText.isEmpty ? null : combinedText,
      contentType: 'lyrics',
      timeStampFormat: 'milliseconds',
      syncText: syncText,
    );
  }
}
