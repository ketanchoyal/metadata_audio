import 'package:metadata_audio/src/core.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/utils/audio_metadata_cache.dart';
import 'package:test/test.dart';

void main() {
  group('AudioMetadataCache general metadata', () {
    test('round-trips metadata for a non-MP4 format (MP3)', () async {
      final path = 'test/samples/mp3/id3v2.3.mp3';

      final first = await parseFile(path, options: ParseOptions(useCache: true));

      // Second call should be served from cache.
      final second = await parseFile(path, options: ParseOptions(useCache: true));

      expect(second.common.title, first.common.title);
      expect(second.format.container, first.format.container);
      expect(second.format.duration, first.format.duration);
      expect(second.quality.warnings.length, first.quality.warnings.length);
    });
  });
}
