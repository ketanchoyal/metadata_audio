import 'package:metadata_audio/src/core.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:test/test.dart';

void main() {
  group('Caching enabled (useCache) across formats', () {
    final samples = <String, String>{
      'mp3': 'test/samples/mp3/id3v2.3.mp3',
      'flac': 'test/samples/flac/sample.flac',
      'ogg': 'test/samples/ogg/vorbis.ogg',
      'wav': 'test/samples/wav/issue-819.wav',
      'aiff': 'test/samples/aiff/sample.aiff',
      'mp4': 'test/samples/mp4/sample.m4a',
    };

    for (final entry in samples.entries) {
      final format = entry.key;
      final path = entry.value;

      test('$format: second parse is served from cache and matches', () async {
        final first = await parseFile(path, options: ParseOptions(useCache: true));
        final second = await parseFile(path, options: ParseOptions(useCache: true));

        expect(second.format.container, first.format.container);
        expect(second.common.title, first.common.title);
        expect(second.format.duration, first.format.duration);
        expect(second.quality.warnings.length, first.quality.warnings.length);
        expect(second.native.length, first.native.length);
      });

      test('$format: cached result equals a fresh (uncached) parse', () async {
        final cached = await parseFile(path, options: ParseOptions(useCache: true));
        final fresh = await parseFile(path); // useCache false by default

        expect(cached.format.container, fresh.format.container);
        expect(cached.common.title, fresh.common.title);
        expect(cached.format.duration, fresh.format.duration);
        expect(cached.quality.warnings.length, fresh.quality.warnings.length);
      });
    }
  });
}
