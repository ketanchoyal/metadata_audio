import 'dart:io';

import 'package:metadata_audio/src/cli/cli_runner.dart';

/// Executable entry point for metadata_audio command-line tool.
Future<void> main(List<String> args) async {
  final exitCode = await runCli(args);
  exit(exitCode);
}
