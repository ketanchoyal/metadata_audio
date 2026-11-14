import 'package:metadata_audio/src/model/types.dart';

/// Formatter that serializes [LyricsTag] to standard LRC format.
class LrcFormatter {
  /// Converts [lyrics] to an LRC-formatted string.
  static String format(
    LyricsTag lyrics, {
    String? title,
    String? artist,
    String? album,
  }) {
    final buffer = StringBuffer();

    if (title != null && title.trim().isNotEmpty) {
      buffer.writeln('[ti:${title.trim()}]');
    }
    if (artist != null && artist.trim().isNotEmpty) {
      buffer.writeln('[ar:${artist.trim()}]');
    }
    if (album != null && album.trim().isNotEmpty) {
      buffer.writeln('[al:${album.trim()}]');
    }

    if (lyrics.syncText.isNotEmpty) {
      for (final line in lyrics.syncText) {
        final ms = line.timestamp;
        if (ms != null) {
          final totalSeconds = ms ~/ 1000;
          final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
          final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
          final hundredths = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
          buffer.writeln('[$minutes:$seconds.$hundredths]${line.text}');
        } else {
          buffer.writeln(line.text);
        }
      }
    } else if (lyrics.text != null && lyrics.text!.isNotEmpty) {
      buffer.writeln(lyrics.text);
    }

    return buffer.toString();
  }
}
