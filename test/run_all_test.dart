import 'dart:io';

import 'package:test/test.dart';

/// Runs the entire test suite twice (caching off, then on) so the VS Code
/// testing panel can trigger both passes with a single "Run".
void main() {
  test('run all tests twice (cache off then on)', () async {
    // Collect every test file except this one to avoid infinite recursion.
    final testDir = Directory('test');
    final files = testDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('_test.dart'))
        .where((f) => !f.path.endsWith('run_all_test.dart'))
        .map((f) => f.path)
        .toList()
      ..sort();

    final passes = <({String label, Map<String, String> env})>[
      (label: 'caching DISABLED', env: const {}),
      (label: 'caching ENABLED', env: const {'METADATA_CACHE_ENABLED': '1'}),
    ];

    var allPassed = true;
    for (final pass in passes) {
      print('\n========== ${pass.label} ==========');
      await _clearCache();

      final result = await Process.run(
        'dart',
        ['test', '--exclude-tags', 'network', ...files],
        environment: {...Platform.environment, ...pass.env},
        runInShell: true,
      );
      stdout.write(result.stdout);
      stderr.write(result.stderr);
      print('Exit code: ${result.exitCode}');
      if (result.exitCode != 0) allPassed = false;
    }

    expect(allPassed, isTrue, reason: 'One or more passes failed');
  }, timeout: const Timeout(Duration(minutes: 15)));
}

Future<void> _clearCache() async {
  final tempDir = Directory.systemTemp;
  await for (final entity in tempDir.list()) {
    if (entity is Directory && entity.path.contains('metadata_audio_cache')) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }
}
