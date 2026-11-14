import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:metadata_audio/src/cli/commands/chapters_command.dart';
import 'package:metadata_audio/src/cli/commands/inspect_command.dart';
import 'package:metadata_audio/src/cli/commands/lyrics_command.dart';
import 'package:metadata_audio/src/parse_error.dart';

/// Command runner for the metadata_audio command line tool.
class MetadataAudioCommandRunner extends CommandRunner<int> {
  /// Creates a [MetadataAudioCommandRunner] with specified sinks.
  MetadataAudioCommandRunner({StringSink? out, StringSink? err})
      : out = out ?? stdout,
        err = err ?? stderr,
        super(
          'metadata_audio',
          'Fast, stream-oriented audio metadata & chapter inspection CLI.',
        ) {
    argParser.addFlag(
      'version',
      abbr: 'v',
      negatable: false,
      help: 'Print the tool version.',
    );

    addCommand(InspectCommand(this));
    addCommand(ChaptersCommand(this));
    addCommand(LyricsCommand(this));
  }

  /// Output stream sink (stdout or test mock).
  final StringSink out;

  /// Error stream sink (stderr or test mock).
  final StringSink err;

  @override
  void printUsage() {
    out.writeln(usage);
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults['version'] as bool? ?? false) {
      out.writeln('metadata_audio 1.0.0');
      return 0;
    }

    if (topLevelResults.command == null) {
      if (topLevelResults.rest.isNotEmpty) {
        return super.runCommand(topLevelResults);
      }
      printUsage();
      return 0;
    }

    return super.runCommand(topLevelResults);
  }
}

/// Entrypoint to execute the CLI with arguments and redirectable stream sinks.
///
/// Returns exit codes:
/// - `0`: Success
/// - `64`: Command-line usage error (invalid syntax, unknown flags, missing parameters)
/// - `65`: Data format, parser, or file-not-found error
/// - `70`: Internal / unhandled error
Future<int> runCli(
  List<String> args, {
  StringSink? out,
  StringSink? err,
}) async {
  final outSink = out ?? stdout;
  final errSink = err ?? stderr;
  final runner = MetadataAudioCommandRunner(out: outSink, err: errSink);

  try {
    final exitCode = await runner.run(args);
    return exitCode ?? 0;
  } on UsageException catch (e) {
    errSink.writeln(e.message);
    errSink.writeln();
    errSink.writeln(e.usage);
    return 64;
  } on FileSystemException catch (e) {
    errSink.writeln('File error: ${e.message} (${e.path})');
    return 65;
  } on FormatException catch (e) {
    errSink.writeln('Format error: ${e.message}');
    return 65;
  } on ParseError catch (e) {
    errSink.writeln('Parser error: ${e.message}');
    return 65;
  } catch (e, st) {
    errSink.writeln('Unexpected error: $e');
    errSink.writeln(st);
    return 70;
  }
}
