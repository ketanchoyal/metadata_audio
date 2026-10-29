import 'dart:io';

/// Runs the full test suite twice: once with caching disabled (default) and
/// once with caching enabled (METADATA_CACHE_ENABLED=1), reporting results
/// for both passes.
Future<void> main() async {
  final passes = <({String label, Map<String, String> env})>[
    (label: 'caching DISABLED', env: const {}),
    (label: 'caching ENABLED', env: const {'METADATA_CACHE_ENABLED': '1'}),
  ];

  var allPassed = true;
  for (final pass in passes) {
    print('\n========== ${pass.label} ==========');
    // Clear the disk cache between passes so each starts clean.
    await _clearCache();

    final result = await Process.run(
      'dart',
      ['test', '--exclude-tags', 'network,meta', 'test/'],
      environment: {...Platform.environment, ...pass.env},
      runInShell: true,
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    print('Exit code: ${result.exitCode}');
    if (result.exitCode != 0) allPassed = false;
  }

  print('\n========== SUMMARY ==========');
  print(allPassed ? 'ALL PASSES PASSED' : 'SOME PASSES FAILED');
  exit(allPassed ? 0 : 1);
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
