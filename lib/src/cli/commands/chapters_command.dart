import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/cli/cli_runner.dart';
import 'package:metadata_audio/src/cli/formatters/table_formatter.dart';

/// Parent command to manage embedded chapters.
class ChaptersCommand extends Command<int> {
  /// Creates a [ChaptersCommand] with `list` and `extract` subcommands.
  ChaptersCommand(this.runner) {
    addSubcommand(ChaptersListCommand(runner));
    addSubcommand(ChaptersExtractCommand(runner));
  }

  @override
  final MetadataAudioCommandRunner runner;

  @override
  String get name => 'chapters';

  @override
  String get description =>
      'List or extract embedded chapters from an audio file or stream.';

  @override
  void printUsage() => runner.out.writeln(usage);
}

/// Subcommand to list embedded chapters.
class ChaptersListCommand extends Command<int> {
  /// Creates a [ChaptersListCommand] bound to [runner].
  ChaptersListCommand(this.runner) {
    argParser.addFlag(
      'color',
      defaultsTo: null,
      help: 'Colorize terminal output (defaults to auto-detect).',
    );
  }

  @override
  final MetadataAudioCommandRunner runner;

  @override
  String get name => 'list';

  @override
  String get description =>
      'List embedded chapters with start, end, and title.';

  @override
  String get invocation => 'metadata_audio chapters list <path-or-url> [options]';

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

    final metadata = isUrl
        ? await parseUrl(source, options: const ParseOptions(includeChapters: true))
        : await parseFile(source, options: const ParseOptions(includeChapters: true));
    final chapters = metadata.format.chapters;

    if (chapters == null || chapters.isEmpty) {
      runner.out.writeln('No embedded chapters found in $source');
      return 0;
    }

    final colorFlag = argResults!['color'] as bool?;
    final formatter = TableFormatter(enableColor: colorFlag);
    runner.out.write(formatter.formatChapters(chapters, source: source));
    return 0;
  }
}

/// Subcommand to extract standalone playable chapter files.
class ChaptersExtractCommand extends Command<int> {
  /// Creates a [ChaptersExtractCommand] bound to [runner].
  ChaptersExtractCommand(this.runner) {
    argParser
      ..addOption(
        'output-dir',
        abbr: 'o',
        defaultsTo: '.',
        help: 'Output directory for extracted chapter files.',
      )
      ..addOption(
        'index',
        abbr: 'i',
        help: 'Extract only a specific 1-based chapter index.',
      )
      ..addFlag(
        'color',
        defaultsTo: null,
        help: 'Colorize terminal output (defaults to auto-detect).',
      );
  }

  @override
  final MetadataAudioCommandRunner runner;

  @override
  String get name => 'extract';

  @override
  String get description =>
      'Extract playable standalone chapter audio files (.m4a/.mp3).';

  @override
  String get invocation =>
      'metadata_audio chapters extract <path-or-url> [options]';

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

    final metadata = isUrl
        ? await parseUrl(source, options: const ParseOptions(includeChapters: true))
        : await parseFile(source, options: const ParseOptions(includeChapters: true));
    final chapters = metadata.format.chapters;

    if (chapters == null || chapters.isEmpty) {
      runner.err.writeln('No embedded chapters found in $source');
      return 1;
    }

    final outDir = Directory(argResults!['output-dir'] as String);
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final indexOption = argResults!['index'] as String?;
    List<int> targetIndices;

    if (indexOption != null) {
      final idx = int.tryParse(indexOption);
      if (idx == null || idx < 1 || idx > chapters.length) {
        throw UsageException(
          'Invalid chapter index: $indexOption (file has ${chapters.length} chapters).',
          usage,
        );
      }
      targetIndices = [idx - 1];
    } else {
      targetIndices = List.generate(chapters.length, (i) => i);
    }

    runner.out.writeln(
      'Extracting ${targetIndices.length} chapter(s) from $source...',
    );

    var hasFailures = false;
    for (final i in targetIndices) {
      final ch = chapters[i];
      final safeTitle = ch.title
          .replaceAll(RegExp(r'[^\w\s\.-]'), '_')
          .trim();
      final numPrefix = (i + 1).toString().padLeft(2, '0');
      final fileName = safeTitle.isEmpty
          ? '${numPrefix}_Chapter_${i + 1}'
          : '${numPrefix}_$safeTitle';
      final outPath = '${outDir.path}/$fileName';

      final endMs = ch.end ??
          (metadata.format.duration != null
              ? (metadata.format.duration! * 1000).toInt()
              : ch.start);

      final result = await ChapterDownloader.downloadChapter(
        originalUrl: source,
        chapterStartMs: ch.start,
        chapterEndMs: endMs,
        outputPath: outPath,
        metadata: metadata,
      );

      if (result.isSuccess) {
        runner.out.writeln('  [✓] Chapter ${i + 1}: ${result.outputPath}');
      } else {
        hasFailures = true;
        runner.err.writeln('  [✗] Chapter ${i + 1}: ${result.error}');
      }
    }

    return hasFailures ? 1 : 0;
  }
}
