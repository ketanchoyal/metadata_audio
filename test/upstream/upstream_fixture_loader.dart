/// Helper that loads upstream music-metadata test fixtures straight from
/// GitHub at test time, so no binary fixtures are committed to this
/// repository.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

const _baseUrl = 'https://raw.githubusercontent.com/Borewit/music-metadata/'
    'master/test/samples/';

final Map<String, Uint8List> _cache = <String, Uint8List>{};

/// Fetches `test/samples/<path>` from the upstream repository.
///
/// Marks the calling test as skipped when the fixture cannot be fetched
/// (offline or HTTP error), returning an empty list; tests should return
/// early in that case.
Future<Uint8List> fetchUpstreamFixtureOrSkip(String path) async {
  final cached = _cache[path];
  if (cached != null) {
    if (cached.isEmpty) {
      // Previously failed to download: skip again (test runner treats
      // repeated skips fine).
      markTestSkipped('Upstream fixture was unavailable earlier: $path');
    }
    return cached;
  }

  try {
    final response = await HttpClient()
        .getUrl(Uri.parse('$_baseUrl$path'))
        .then(
          (request) => request.close().timeout(const Duration(seconds: 30)),
        );
    if (response.statusCode != 200) {
      markTestSkipped(
        'Upstream fixture fetch failed (HTTP ${response.statusCode}): $path',
      );
      return Uint8List(0);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      markTestSkipped('Upstream fixture is empty: $path');
      return bytes;
    }
    _cache[path] = bytes;
    return bytes;
  } catch (e) {
    markTestSkipped('Upstream fixture unavailable (network): $e');
    return Uint8List(0);
  }
}
