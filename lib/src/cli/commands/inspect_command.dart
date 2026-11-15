import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/cli/cli_runner.dart';
import 'package:metadata_audio/src/cli/formatters/table_formatter.dart';

/// Command to inspect audio metadata and stream specifications.
class InspectCommand extends Command<int> {
  /// Creates an [InspectCommand] bound to [runner].
  InspectCommand(this.runner) {
    argParser
      ..addFlag(
        'json',
        abbr: 'j',
        negatable: false,
        help: 'Output metadata as formatted JSON.',
      )
      ..addFlag(
        'duration',
        abbr: 'd',
        defaultsTo: true,
        help: 'Calculate and report audio duration.',
      )
      ..addFlag(
        'covers',
        abbr: 'c',
        defaultsTo: true,
        help: 'Parse and count embedded artwork pictures.',
      )
      ..addFlag(
        'full',
        negatable: false,
        help: 'Display all native container/codec tags in table output.',
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
  String get name => 'inspect';

  @override
  String get description =>
      'Inspect audio metadata and stream specifications from a file or URL.';

  @override
  String get invocation => 'metadata_audio inspect <path-or-url> [options]';

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

    final durationFlag = argResults!['duration'] as bool;
    final coversFlag = argResults!['covers'] as bool;
    final fullFlag = argResults!['full'] as bool;
    final jsonFlag = argResults!['json'] as bool;
    final colorFlag = argResults!['color'] as bool?;

    final options = ParseOptions(
      duration: durationFlag,
      skipCovers: !coversFlag,
      includeChapters: true,
    );

    final metadata = isUrl
        ? await parseUrl(source, options: options)
        : await parseFile(source, options: options);

    if (jsonFlag) {
      final jsonMap = audioMetadataToJson(metadata);
      const encoder = JsonEncoder.withIndent('  ');
      runner.out.writeln(encoder.convert(jsonMap));
    } else {
      final formatter = TableFormatter(enableColor: colorFlag);
      runner.out.write(
        formatter.formatMetadata(metadata, source: source, full: fullFlag),
      );
    }

    return 0;
  }
}
