import 'dart:io';

import 'package:metadata_audio/src/model/types.dart';

/// Formats audio metadata into human-readable terminal output.
class TableFormatter {
  /// Create a [TableFormatter] with color support according to terminal capabilities.
  TableFormatter({bool? enableColor})
      : enableColor = enableColor ?? _detectAnsi();

  /// Whether ANSI escape codes should be emitted.
  final bool enableColor;

  static bool _detectAnsi() {
    try {
      return stdout.hasTerminal &&
          stdout.supportsAnsiEscapes &&
          !Platform.environment.containsKey('NO_COLOR');
    } catch (_) {
      return false;
    }
  }

  String _bold(String text) => enableColor ? '\x1B[1m$text\x1B[0m' : text;
  String _cyan(String text) => enableColor ? '\x1B[36m$text\x1B[0m' : text;
  String _green(String text) => enableColor ? '\x1B[32m$text\x1B[0m' : text;
  String _yellow(String text) => enableColor ? '\x1B[33m$text\x1B[0m' : text;
  String _dim(String text) => enableColor ? '\x1B[2m$text\x1B[0m' : text;

  /// Formats [AudioMetadata] into a readable terminal summary.
  String formatMetadata(
    AudioMetadata metadata, {
    String? source,
    bool full = false,
  }) {
    final buffer = StringBuffer();

    if (source != null) {
      buffer.writeln(_bold(_cyan('=== Source: $source ===')));
    }

    // Format section
    buffer.writeln(_bold('\nAudio Format & Stream:'));
    _writeRow(buffer, 'Container', metadata.format.container ?? 'Unknown');
    _writeRow(buffer, 'Codec', metadata.format.codec ?? 'Unknown');
    if (metadata.format.duration != null) {
      _writeRow(buffer, 'Duration', _formatDuration(metadata.format.duration!));
    }
    if (metadata.format.sampleRate != null) {
      _writeRow(buffer, 'Sample Rate', '${metadata.format.sampleRate} Hz');
    }
    if (metadata.format.numberOfChannels != null) {
      _writeRow(
        buffer,
        'Channels',
        '${metadata.format.numberOfChannels} ${_formatChannelLabel(metadata.format.numberOfChannels!)}',
      );
    }
    if (metadata.format.bitsPerSample != null) {
      _writeRow(buffer, 'Bit Depth', '${metadata.format.bitsPerSample}-bit');
    }
    if (metadata.format.bitrate != null) {
      _writeRow(
        buffer,
        'Bitrate',
        '${(metadata.format.bitrate! / 1000).toStringAsFixed(1)} kbps',
      );
    }
    if (metadata.format.lossless != null) {
      _writeRow(
        buffer,
        'Lossless',
        metadata.format.lossless! ? _green('true') : 'false',
      );
    }
    if (metadata.format.trackGain != null) {
      _writeRow(
        buffer,
        'Track Gain',
        '${metadata.format.trackGain!.toStringAsFixed(2)} dB',
      );
    }

    // Common Tags section
    buffer.writeln(_bold('\nCommon Metadata:'));
    final common = metadata.common;
    if (common.title != null) _writeRow(buffer, 'Title', common.title!);
    if (common.artist != null) _writeRow(buffer, 'Artist', common.artist!);
    if (common.albumartist != null) {
      _writeRow(buffer, 'Album Artist', common.albumartist!);
    }
    if (common.album != null) _writeRow(buffer, 'Album', common.album!);
    if (common.year != null) _writeRow(buffer, 'Year', common.year.toString());
    if (common.date != null) _writeRow(buffer, 'Date', common.date!);
    if (common.track.no != null) {
      final total = common.track.of != null ? '/${common.track.of}' : '';
      _writeRow(buffer, 'Track', '${common.track.no}$total');
    }
    if (common.disk.no != null) {
      final total = common.disk.of != null ? '/${common.disk.of}' : '';
      _writeRow(buffer, 'Disc', '${common.disk.no}$total');
    }
    if (common.genre != null && common.genre!.isNotEmpty) {
      _writeRow(buffer, 'Genre', common.genre!.join(', '));
    }
    if (common.composer != null && common.composer!.isNotEmpty) {
      _writeRow(buffer, 'Composer', common.composer!.join(', '));
    }
    if (common.copyright != null) {
      _writeRow(buffer, 'Copyright', common.copyright!);
    }
    if (common.compilation != null) {
      _writeRow(buffer, 'Compilation', common.compilation.toString());
    }

    // ReplayGain section
    if (common.replaygain_track_gain != null ||
        common.replaygain_track_peak != null ||
        common.replaygain_album_gain != null ||
        common.replaygain_album_peak != null) {
      buffer.writeln(_bold('\nReplayGain:'));
      if (common.replaygain_track_gain != null) {
        _writeRow(
          buffer,
          'Track Gain',
          '${common.replaygain_track_gain!.dB?.toStringAsFixed(2) ?? 'N/A'} dB',
        );
      }
      if (common.replaygain_track_peak != null) {
        _writeRow(
          buffer,
          'Track Peak',
          common.replaygain_track_peak!.ratio.toStringAsFixed(4),
        );
      }
      if (common.replaygain_album_gain != null) {
        _writeRow(
          buffer,
          'Album Gain',
          '${common.replaygain_album_gain!.dB?.toStringAsFixed(2) ?? 'N/A'} dB',
        );
      }
      if (common.replaygain_album_peak != null) {
        _writeRow(
          buffer,
          'Album Peak',
          common.replaygain_album_peak!.ratio.toStringAsFixed(4),
        );
      }
    }

    // Chapters count
    if (metadata.format.chapters != null &&
        metadata.format.chapters!.isNotEmpty) {
      _writeRow(
        buffer,
        'Chapters',
        _cyan('${metadata.format.chapters!.length} chapters'),
      );
    }

    // Lyrics count
    if (common.lyrics != null && common.lyrics!.isNotEmpty) {
      _writeRow(
        buffer,
        'Lyrics',
        _cyan('${common.lyrics!.length} lyrics block(s)'),
      );
    }

    // Native tags if requested
    if (full && metadata.native.isNotEmpty) {
      buffer.writeln(_bold('\nNative Tags:'));
      for (final entry in metadata.native.entries) {
        buffer.writeln(_cyan('  [${entry.key}]:'));
        for (final tag in entry.value) {
          final val = tag.value is Picture ? '<Cover Art Picture>' : tag.value;
          buffer.writeln('    ${_dim(tag.id)}: $val');
        }
      }
    }

    // Warnings if any
    if (metadata.quality.warnings.isNotEmpty) {
      buffer.writeln(_bold(_yellow('\nWarnings:')));
      for (final warning in metadata.quality.warnings) {
        buffer.writeln('  ${_yellow('!')} ${warning.message}');
      }
    }

    return buffer.toString();
  }

  /// Formats chapters into a tabular string.
  String formatChapters(List<Chapter> chapters, {String? source}) {
    final buffer = StringBuffer();
    if (source != null) {
      buffer.writeln(_bold(_cyan('=== Chapters: $source ===\n')));
    }

    const colNum = 4;
    const colStart = 12;
    const colEnd = 12;
    const colDur = 12;

    buffer.writeln(
      _bold(
        '${'#'.padRight(colNum)}'
        '${'Start'.padRight(colStart)}'
        '${'End'.padRight(colEnd)}'
        '${'Duration'.padRight(colDur)}'
        'Title',
      ),
    );
    buffer.writeln(_dim('-' * 70));

    for (var i = 0; i < chapters.length; i++) {
      final ch = chapters[i];
      final start = _formatTimeMs(ch.start);
      final end = ch.end != null ? _formatTimeMs(ch.end!) : 'N/A';
      final dur = ch.end != null ? _formatTimeMs(ch.end! - ch.start) : 'N/A';
      final title = ch.title.isNotEmpty ? ch.title : 'Chapter ${i + 1}';

      buffer.writeln(
        '${(i + 1).toString().padRight(colNum)}'
        '${start.padRight(colStart)}'
        '${end.padRight(colEnd)}'
        '${dur.padRight(colDur)}'
        '$title',
      );
    }

    return buffer.toString();
  }

  void _writeRow(StringBuffer buffer, String label, String value) {
    buffer.writeln('  ${_dim(label.padRight(16))}: $value');
  }

  String _formatDuration(double seconds) {
    final totalSec = seconds.toInt();
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    if (h > 0) {
      return '${h}h ${m}m ${s}s (${seconds.toStringAsFixed(2)}s)';
    }
    return '${m}m ${s}s (${seconds.toStringAsFixed(2)}s)';
  }

  String _formatTimeMs(int ms) {
    final totalSec = ms ~/ 1000;
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    final millis = ms % 1000;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${millis ~/ 100}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${millis ~/ 100}';
  }

  String _formatChannelLabel(int channels) {
    switch (channels) {
      case 1:
        return '(Mono)';
      case 2:
        return '(Stereo)';
      case 6:
        return '(5.1 Surround)';
      case 8:
        return '(7.1 Surround)';
      default:
        return '';
    }
  }
}
