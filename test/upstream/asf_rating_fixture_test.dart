/// Fixture test using upstream music-metadata's `wma_rating.wma` sample,
/// fetched from GitHub at test time and asserting the same POPULARIMETER /
/// WM/SharedUserRating expectations as upstream `test/test-file-asf.ts`.
library;

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

import 'upstream_fixture_loader.dart';

void main() {
  group('upstream ASF rating fixture', () {
    test('decodes popm rating + shared user rating', () async {
      final bytes = await fetchUpstreamFixtureOrSkip('asf/wma_rating.wma');
      if (bytes.isEmpty) return;
      final metadata = await parseBytes(bytes, fileInfo: FileInfo.fromPath('asf/wma_rating.wma'));

      // Native tags keep the raw values.
      final asfTags = metadata.native['asf'];
      expect(asfTags, isNotNull);
      final popm = asfTags!.where((tag) => tag.id == 'POPULARIMETER').single;
      expect(popm.value, equals('hobbes|128|0'));
      final sharedUser =
          asfTags.where((tag) => tag.id == 'WM/SharedUserRating').single;
      expect(sharedUser.value, equals(75));

      // Common ratings: POPULARIMETER ('hobbes|128|0') → source 'hobbes',
      // (128 - 1) / 254 == 0.5; WM/SharedUserRating 75 → 75 / 99.
      final ratings = metadata.common.rating;
      expect(ratings, isNotNull);
      expect(ratings, isNotEmpty);

      final hobbes = ratings!.where((r) => r.source == 'hobbes').toList();
      expect(hobbes, hasLength(1));
      expect(hobbes.single.rating, closeTo(0.5, 1e-9));

      expect(
        ratings
            .any((r) => r.rating != null && (r.rating! - 75 / 99).abs() < 1e-9),
        isTrue,
        reason: 'Expected a rating of 75/99 from WM/SharedUserRating',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
