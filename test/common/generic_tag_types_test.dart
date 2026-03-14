import 'package:test/test.dart';
import 'package:audio_metadata/src/common/generic_tag_types.dart';

void main() {
  group('GenericTagType enum', () {
    test('has all expected tag types', () {
      expect(GenericTagType.title, isNotNull);
      expect(GenericTagType.artist, isNotNull);
      expect(GenericTagType.album, isNotNull);
      expect(GenericTagType.year, isNotNull);
      expect(GenericTagType.track, isNotNull);
      expect(GenericTagType.genre, isNotNull);
      expect(GenericTagType.picture, isNotNull);
      expect(GenericTagType.lyrics, isNotNull);
    });

    test('enum values are distinct', () {
      final values = GenericTagType.values;
      final uniqueValues = values.toSet();
      expect(values.length, equals(uniqueValues.length));
    });
  });

  group('TagTypeSemantics', () {
    test('creates singleton semantics', () {
      const semantics = TagTypeSemantics(isSingleton: true);
      expect(semantics.isSingleton, isTrue);
      expect(semantics.isUnique, isFalse);
    });

    test('creates list semantics with unique values', () {
      const semantics = TagTypeSemantics(isSingleton: false, isUnique: true);
      expect(semantics.isSingleton, isFalse);
      expect(semantics.isUnique, isTrue);
    });

    test('creates list semantics with duplicate values', () {
      const semantics = TagTypeSemantics(isSingleton: false, isUnique: false);
      expect(semantics.isSingleton, isFalse);
      expect(semantics.isUnique, isFalse);
    });

    test('default isUnique is false', () {
      const semantics = TagTypeSemantics(isSingleton: false);
      expect(semantics.isUnique, isFalse);
    });
  });

  group('GenericTagTypes.isSingleton', () {
    test('identifies core singleton tags', () {
      expect(GenericTagTypes.isSingleton('title'), isTrue);
      expect(GenericTagTypes.isSingleton('artist'), isTrue);
      expect(GenericTagTypes.isSingleton('album'), isTrue);
      expect(GenericTagTypes.isSingleton('year'), isTrue);
      expect(GenericTagTypes.isSingleton('track'), isTrue);
      expect(GenericTagTypes.isSingleton('disk'), isTrue);
    });

    test('identifies list tags', () {
      expect(GenericTagTypes.isSingleton('genre'), isFalse);
      expect(GenericTagTypes.isSingleton('comment'), isFalse);
      expect(GenericTagTypes.isSingleton('picture'), isFalse);
      expect(GenericTagTypes.isSingleton('composer'), isFalse);
      expect(GenericTagTypes.isSingleton('artists'), isFalse);
    });

    test('is case-insensitive', () {
      expect(GenericTagTypes.isSingleton('Title'), isTrue);
      expect(GenericTagTypes.isSingleton('TITLE'), isTrue);
      expect(GenericTagTypes.isSingleton('Genre'), isFalse);
      expect(GenericTagTypes.isSingleton('GENRE'), isFalse);
    });

    test('returns true for unknown tags (default)', () {
      expect(GenericTagTypes.isSingleton('unknownTag'), isTrue);
      expect(GenericTagTypes.isSingleton('custom'), isTrue);
    });
  });

  group('GenericTagTypes.isList', () {
    test('identifies list tags', () {
      expect(GenericTagTypes.isList('genre'), isTrue);
      expect(GenericTagTypes.isList('comment'), isTrue);
      expect(GenericTagTypes.isList('picture'), isTrue);
      expect(GenericTagTypes.isList('artists'), isTrue);
    });

    test('identifies singleton tags as non-list', () {
      expect(GenericTagTypes.isList('title'), isFalse);
      expect(GenericTagTypes.isList('artist'), isFalse);
      expect(GenericTagTypes.isList('album'), isFalse);
      expect(GenericTagTypes.isList('year'), isFalse);
    });

    test('is opposite of isSingleton', () {
      final testTags = ['title', 'artist', 'genre', 'picture', 'unknown'];
      for (final tag in testTags) {
        expect(
          GenericTagTypes.isList(tag),
          equals(!GenericTagTypes.isSingleton(tag)),
        );
      }
    });
  });

  group('GenericTagTypes.isUnique', () {
    test('returns true for singleton tags', () {
      expect(GenericTagTypes.isUnique('title'), isTrue);
      expect(GenericTagTypes.isUnique('artist'), isTrue);
      expect(GenericTagTypes.isUnique('album'), isTrue);
      expect(GenericTagTypes.isUnique('year'), isTrue);
    });

    test('returns true for tags marked as unique', () {
      expect(GenericTagTypes.isUnique('genre'), isTrue);
      expect(GenericTagTypes.isUnique('picture'), isTrue);
      expect(GenericTagTypes.isUnique('artists'), isTrue);
      expect(GenericTagTypes.isUnique('composer'), isTrue);
      expect(GenericTagTypes.isUnique('lyricist'), isTrue);
    });

    test('returns false for non-unique list tags', () {
      expect(GenericTagTypes.isUnique('comment'), isFalse);
      expect(GenericTagTypes.isUnique('lyrics'), isFalse);
      expect(GenericTagTypes.isUnique('notes'), isFalse);
      expect(GenericTagTypes.isUnique('description'), isFalse);
    });

    test('is case-insensitive', () {
      expect(GenericTagTypes.isUnique('Genre'), isTrue);
      expect(GenericTagTypes.isUnique('GENRE'), isTrue);
      expect(GenericTagTypes.isUnique('Comment'), isFalse);
    });
  });

  group('GenericTagTypes.getSemantics', () {
    test('returns singleton semantics for singleton tags', () {
      final semantics = GenericTagTypes.getSemantics('title');
      expect(semantics.isSingleton, isTrue);
    });

    test('returns list semantics with unique for genre', () {
      final semantics = GenericTagTypes.getSemantics('genre');
      expect(semantics.isSingleton, isFalse);
      expect(semantics.isUnique, isTrue);
    });

    test('returns list semantics without unique for comment', () {
      final semantics = GenericTagTypes.getSemantics('comment');
      expect(semantics.isSingleton, isFalse);
      expect(semantics.isUnique, isFalse);
    });

    test('is case-insensitive', () {
      final lowercase = GenericTagTypes.getSemantics('title');
      final uppercase = GenericTagTypes.getSemantics('TITLE');
      final mixedCase = GenericTagTypes.getSemantics('TiTlE');

      expect(lowercase.isSingleton, equals(uppercase.isSingleton));
      expect(lowercase.isSingleton, equals(mixedCase.isSingleton));
    });

    test('returns default singleton semantics for unknown tags', () {
      final semantics = GenericTagTypes.getSemantics('unknownTag');
      expect(semantics.isSingleton, isTrue);
      expect(semantics.isUnique, isFalse);
    });
  });

  group('GenericTagTypes collections', () {
    test('allTagNames contains all tags', () {
      final allTags = GenericTagTypes.allTagNames;
      expect(allTags.length, greaterThan(50));
      expect(allTags.contains('title'), isTrue);
      expect(allTags.contains('genre'), isTrue);
      expect(allTags.contains('artist'), isTrue);
    });

    test('singletonTags contains only singleton tags', () {
      final singletons = GenericTagTypes.singletonTags;
      expect(singletons.contains('title'), isTrue);
      expect(singletons.contains('artist'), isTrue);
      expect(singletons.contains('album'), isTrue);
      expect(singletons.contains('genre'), isFalse);
      expect(singletons.contains('picture'), isFalse);

      // Verify all are actually singletons
      for (final tag in singletons) {
        expect(
          GenericTagTypes.isSingleton(tag),
          isTrue,
          reason: '$tag should be singleton',
        );
      }
    });

    test('listTags contains only list tags', () {
      final lists = GenericTagTypes.listTags;
      expect(lists.contains('genre'), isTrue);
      expect(lists.contains('picture'), isTrue);
      expect(lists.contains('comment'), isTrue);
      expect(lists.contains('title'), isFalse);
      expect(lists.contains('artist'), isFalse);

      // Verify all are actually lists
      for (final tag in lists) {
        expect(
          GenericTagTypes.isList(tag),
          isTrue,
          reason: '$tag should be a list',
        );
      }
    });

    test('uniqueTags contains only unique tags', () {
      final unique = GenericTagTypes.uniqueTags;
      expect(unique.contains('title'), isTrue);
      expect(unique.contains('genre'), isTrue);
      expect(unique.contains('picture'), isTrue);
      expect(unique.contains('artist'), isTrue);

      // These should NOT be in unique tags
      expect(unique.contains('comment'), isFalse);
      expect(unique.contains('lyrics'), isFalse);
      expect(unique.contains('notes'), isFalse);

      // Verify all are actually unique
      for (final tag in unique) {
        expect(
          GenericTagTypes.isUnique(tag),
          isTrue,
          reason: '$tag should be unique',
        );
      }
    });

    test('singletonTags and listTags are mutually exclusive and complete', () {
      final singletons = GenericTagTypes.singletonTags;
      final lists = GenericTagTypes.listTags;
      final all = GenericTagTypes.allTagNames;

      // No overlap
      expect(singletons.intersection(lists).isEmpty, isTrue);

      // Together they cover all
      expect(singletons.union(lists), equals(all));
    });
  });

  group('Common tag types verification', () {
    test('core metadata tags', () {
      expect(GenericTagTypes.isSingleton('title'), isTrue);
      expect(GenericTagTypes.isSingleton('artist'), isTrue);
      expect(GenericTagTypes.isSingleton('album'), isTrue);
      expect(GenericTagTypes.isSingleton('year'), isTrue);
      expect(GenericTagTypes.isSingleton('track'), isTrue);
      expect(GenericTagTypes.isSingleton('disk'), isTrue);
    });

    test('list tags with unique values', () {
      expect(GenericTagTypes.isList('genre'), isTrue);
      expect(GenericTagTypes.isUnique('genre'), isTrue);

      expect(GenericTagTypes.isList('picture'), isTrue);
      expect(GenericTagTypes.isUnique('picture'), isTrue);

      expect(GenericTagTypes.isList('composer'), isTrue);
      expect(GenericTagTypes.isUnique('composer'), isTrue);
    });

    test('list tags without unique values', () {
      expect(GenericTagTypes.isList('comment'), isTrue);
      expect(GenericTagTypes.isUnique('comment'), isFalse);

      expect(GenericTagTypes.isList('lyrics'), isTrue);
      expect(GenericTagTypes.isUnique('lyrics'), isFalse);

      expect(GenericTagTypes.isList('notes'), isTrue);
      expect(GenericTagTypes.isUnique('notes'), isFalse);
    });

    test('sorting tags are singletons', () {
      expect(GenericTagTypes.isSingleton('titlesort'), isTrue);
      expect(GenericTagTypes.isSingleton('artistsort'), isTrue);
      expect(GenericTagTypes.isSingleton('albumsort'), isTrue);
    });

    test('creator roles are lists with unique values', () {
      final creatorRoles = [
        'composer',
        'lyricist',
        'writer',
        'conductor',
        'remixer',
        'arranger',
        'engineer',
        'producer',
      ];

      for (final role in creatorRoles) {
        expect(GenericTagTypes.isList(role), isTrue, reason: '$role');
        expect(GenericTagTypes.isUnique(role), isTrue, reason: '$role');
      }
    });

    test('recording info tags', () {
      expect(GenericTagTypes.isSingleton('bpm'), isTrue);
      expect(GenericTagTypes.isSingleton('key'), isTrue);
      expect(GenericTagTypes.isSingleton('mood'), isTrue);
    });

    test('MusicBrainz tags', () {
      expect(GenericTagTypes.isSingleton('musicbrainz_recordingid'), isTrue);
      expect(GenericTagTypes.isSingleton('musicbrainz_albumid'), isTrue);
      expect(GenericTagTypes.isList('musicbrainz_artistid'), isTrue);
    });

    test('ReplayGain tags are all singletons', () {
      expect(GenericTagTypes.isSingleton('replaygain_track_gain'), isTrue);
      expect(GenericTagTypes.isSingleton('replaygain_track_peak'), isTrue);
      expect(GenericTagTypes.isSingleton('replaygain_album_gain'), isTrue);
      expect(GenericTagTypes.isSingleton('replaygain_album_peak'), isTrue);
    });
  });

  group('Edge cases', () {
    test('empty string tag name', () {
      final semantics = GenericTagTypes.getSemantics('');
      expect(semantics.isSingleton, isTrue);
    });

    test('whitespace tag name', () {
      final semantics = GenericTagTypes.getSemantics('   ');
      // Should be treated as unknown and default to singleton
      expect(semantics.isSingleton, isTrue);
    });

    test('tag names with different cases', () {
      expect(
        GenericTagTypes.getSemantics('TITLE').isSingleton,
        equals(GenericTagTypes.getSemantics('title').isSingleton),
      );
      expect(
        GenericTagTypes.getSemantics('Genre').isSingleton,
        equals(GenericTagTypes.getSemantics('genre').isSingleton),
      );
    });

    test('tag name with underscores', () {
      expect(GenericTagTypes.isSingleton('replaygain_track_gain'), isTrue);
      expect(GenericTagTypes.isSingleton('musicbrainz_recordingid'), isTrue);
    });

    test('tag name with colons', () {
      expect(GenericTagTypes.isList('performer:instrument'), isTrue);
      expect(GenericTagTypes.isUnique('performer:instrument'), isTrue);
    });
  });
}
