import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/cli/cli_runner.dart';
import 'package:metadata_audio/src/cli/formatters/lrc_formatter.dart';

/// Command to inspect and export embedded lyrics.
class LyricsCommand extends Command<int> {
  /// Creates a [LyricsCommand] bound to [runner].
  LyricsCommand(this.runner) {
    argParser
      ..addOption(
        'format',
        abbr: 'f',
        allowed: ['lrc', 'txt'],
        defaultsTo: 'lrc',
        help: 'Output format: synchronized LRC or plain text.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Write output to specified file instead of stdout.',
      );
  }

  @override
  final MetadataAudioCommandRunner runner;

  @override
  String get name => 'lyrics';

  @override
  String get description =>
      'Inspect and export embedded lyrics in LRC or plain text format.';

  @override
  String get invocation => 'metadata_audio lyrics <path-or-url> [options]';

  @override
  void printUsage() => runner.out.writeln(usage);

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? [];
    if (rest.isEmpty) {
      throw UsageException('Missing required audio file path or URL.', usage);
    }

    final source = rest.first;
    final isUrl =
        source.startsWith('http://') || source.startsWith('https://');

    if (!isUrl) {
      final file = File(source);
      if (!await file.exists()) {
        throw FileSystemException('File does not exist: $source', source);
      }
    }

    final metadata = isUrl ? await parseUrl(source) : await parseFile(source);
    final lyricsList = metadata.common.lyrics;

    if (lyricsList == null || lyricsList.isEmpty) {
      runner.err.writeln('No embedded lyrics found in $source');
      return 1;
    }

    final lyrics = lyricsList.firstWhere(
      (l) => l.syncText.isNotEmpty,
      orElse: () => lyricsList.firstWhere(
        (l) => l.text != null && l.text!.isNotEmpty,
        orElse: () => lyricsList.first,
      ),
    );
    final format = argResults!['format'] as String;

    String content;
    if (format == 'lrc') {
      content = LrcFormatter.format(
        lyrics,
        title: metadata.common.title,
        artist: metadata.common.artist,
        album: metadata.common.album,
      );
    } else {
      if (lyrics.text != null && lyrics.text!.isNotEmpty) {
        content = lyrics.text!;
      } else {
        content = lyrics.syncText.map((s) => s.text).join('\n');
      }
      if (!content.endsWith('\n')) {
        content = '$content\n';
      }
    }

    final outputPath = argResults!['output'] as String?;
    if (outputPath != null) {
      final outFile = File(outputPath);
      await outFile.writeAsString(content);
      runner.out.writeln('Lyrics written to $outputPath');
    } else {
      runner.out.write(content);
    }

    return 0;
  }
}
