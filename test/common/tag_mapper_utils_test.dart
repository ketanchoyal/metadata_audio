import 'package:metadata_audio/src/common/case_insensitive_tag_map.dart';
import 'package:metadata_audio/src/common/generic_tag_mapper.dart';
import 'package:test/test.dart';

/// Concrete implementation of GenericTagMapper for testing.
class TestTagMapper extends GenericTagMapper {

  TestTagMapper({Map<String, String>? initialMap}) {
    _tagMap = CaseInsensitiveTagMap<String>();
    if (initialMap != null) {
      _tagMap.addAll(initialMap);
    }
  }
  late CaseInsensitiveTagMap<String> _tagMap;

  @override
  CaseInsensitiveTagMap<String> get tagMap => _tagMap;
}

void main() {
  group('CaseInsensitiveTagMap', () {
    test('stores and retrieves values with exact case', () {
      final map = CaseInsensitiveTagMap<String>();
      map['title'] = 'My Song';
      expect(map['title'], equals('My Song'));
    });

    test('retrieves values with different case combinations', () {
      final map = CaseInsensitiveTagMap<String>();
      map['TIT2'] = 'Song Title';

      expect(map['TIT2'], equals('Song Title'));
      expect(map['tit2'], equals('Song Title'));
      expect(map['Tit2'], equals('Song Title'));
      expect(map['TIT2'], equals('Song Title'));
    });

    test('stores values with different case as same key', () {
      final map = CaseInsensitiveTagMap<String>();
      map['Title'] = 'First';
      map['TITLE'] = 'Second';
      map['title'] = 'Third';

      expect(map.length, equals(1));
      expect(map['title'], equals('Third'));
    });

    test('returns null for missing keys', () {
      final map = CaseInsensitiveTagMap<String>();
      map['TIT2'] = 'Title';

      expect(map['MISSING'], isNull);
      expect(map['missing'], isNull);
    });

    test('containsKey works case-insensitively', () {
      final map = CaseInsensitiveTagMap<String>();
      map['Artist'] = 'John Doe';

      expect(map.containsKey('Artist'), isTrue);
      expect(map.containsKey('ARTIST'), isTrue);
      expect(map.containsKey('artist'), isTrue);
      expect(map.containsKey('NotExist'), isFalse);
    });

    test('remove works case-insensitively', () {
      final map = CaseInsensitiveTagMap<String>();
      map['Album'] = 'Greatest Hits';

      expect(map.remove('ALBUM'), equals('Greatest Hits'));
      expect(map.containsKey('album'), isFalse);
      expect(map.length, equals(0));
    });

    test('addAll adds all entries with lowercase keys', () {
      final map = CaseInsensitiveTagMap<String>();
      map.addAll({'Title': 'Song', 'Artist': 'Band', 'Album': 'Album Name'});

      expect(map.length, equals(3));
      expect(map['TITLE'], equals('Song'));
      expect(map['artist'], equals('Band'));
      expect(map['ALBUM'], equals('Album Name'));
    });

    test('length, isEmpty, and isNotEmpty work correctly', () {
      final map = CaseInsensitiveTagMap<String>();

      expect(map.length, equals(0));
      expect(map.isEmpty, isTrue);
      expect(map.isNotEmpty, isFalse);

      map['Key1'] = 'Value1';
      expect(map.length, equals(1));
      expect(map.isEmpty, isFalse);
      expect(map.isNotEmpty, isTrue);

      map.clear();
      expect(map.length, equals(0));
      expect(map.isEmpty, isTrue);
    });

    test('keys returns all keys in lowercase', () {
      final map = CaseInsensitiveTagMap<String>();
      map['TIT2'] = 'Title';
      map['TPE1'] = 'Artist';
      map['TALB'] = 'Album';

      final keys = map.keys;
      expect(keys, containsAll(['tit2', 'tpe1', 'talb']));
      expect(keys.length, equals(3));
    });

    test('values returns all values', () {
      final map = CaseInsensitiveTagMap<String>();
      map['Key1'] = 'Value1';
      map['Key2'] = 'Value2';
      map['Key3'] = 'Value3';

      final values = map.values.toList();
      expect(values, containsAll(['Value1', 'Value2', 'Value3']));
      expect(values.length, equals(3));
    });

    test('entries returns all key-value pairs', () {
      final map = CaseInsensitiveTagMap<String>();
      map['First'] = 'Value1';
      map['Second'] = 'Value2';

      final entries = map.entries.toList();
      expect(entries.length, equals(2));
      expect(entries.map((e) => e.key), containsAll(['first', 'second']));
      expect(entries.map((e) => e.value), containsAll(['Value1', 'Value2']));
    });

    test('forEach iterates over all entries', () {
      final map = CaseInsensitiveTagMap<String>();
      map['Key1'] = 'Value1';
      map['Key2'] = 'Value2';

      final result = <String, String>{};
      map.forEach((key, value) {
        result[key] = value;
      });

      expect(result, equals({'key1': 'Value1', 'key2': 'Value2'}));
    });

    test('putIfAbsent adds key if not present', () {
      final map = CaseInsensitiveTagMap<String>();

      final result = map.putIfAbsent('NewKey', () => 'NewValue');

      expect(result, equals('NewValue'));
      expect(map['newkey'], equals('NewValue'));
    });

    test('putIfAbsent returns existing value if present', () {
      final map = CaseInsensitiveTagMap<String>();
      map['ExistingKey'] = 'ExistingValue';

      final result = map.putIfAbsent('EXISTINGKEY', () => 'NewValue');

      expect(result, equals('ExistingValue'));
      expect(map['existingkey'], equals('ExistingValue'));
    });

    test('update modifies existing value', () {
      final map = CaseInsensitiveTagMap<String>();
      map['Count'] = '5';

      final result = map.update(
        'COUNT',
        (value) => (int.parse(value) + 1).toString(),
      );

      expect(result, equals('6'));
      expect(map['count'], equals('6'));
    });

    test('toMap returns regular map with lowercase keys', () {
      final map = CaseInsensitiveTagMap<String>();
      map['TIT2'] = 'Title';
      map['TPE1'] = 'Artist';

      final regularMap = map.toMap();
      expect(regularMap, equals({'tit2': 'Title', 'tpe1': 'Artist'}));
    });

    test('works with different value types', () {
      final mapInt = CaseInsensitiveTagMap<int>();
      mapInt['Age'] = 25;
      expect(mapInt['AGE'], equals(25));

      final mapDynamic = CaseInsensitiveTagMap<dynamic>();
      mapDynamic['String'] = 'Value';
      mapDynamic['Number'] = 42;
      mapDynamic['Bool'] = true;

      expect(mapDynamic['string'], equals('Value'));
      expect(mapDynamic['number'], equals(42));
      expect(mapDynamic['bool'], isTrue);
    });
  });

  group('GenericTagMapper', () {
    test('mapTag returns mapped tag name if mapping exists', () {
      final mapper = TestTagMapper(
        initialMap: {'TIT2': 'title', 'TPE1': 'artist'},
      );

      expect(mapper.mapTag('TIT2', 'Song Title'), equals('title'));
      expect(mapper.mapTag('TPE1', 'Artist Name'), equals('artist'));
    });

    test('mapTag returns null for unmapped tags', () {
      final mapper = TestTagMapper(initialMap: {'TIT2': 'title'});

      expect(mapper.mapTag('UNKNOWN', 'Some Value'), isNull);
      expect(mapper.mapTag('TXXX', 'Custom'), isNull);
    });

    test('mapTag works case-insensitively', () {
      final mapper = TestTagMapper(initialMap: {'TIT2': 'title'});

      expect(mapper.mapTag('tit2', 'Value'), equals('title'));
      expect(mapper.mapTag('TIT2', 'Value'), equals('title'));
      expect(mapper.mapTag('Tit2', 'Value'), equals('title'));
    });

    test('mapTags converts all mapped tags from native format', () {
      final mapper = TestTagMapper(
        initialMap: {'TIT2': 'title', 'TPE1': 'artist', 'TALB': 'album'},
      );

      final nativeTags = {
        'TIT2': 'My Song',
        'TPE1': 'The Band',
        'TALB': 'Best Album',
        'TXXX': 'Custom Frame', // Unmapped
      };

      final genericTags = mapper.mapTags(nativeTags);

      expect(
        genericTags,
        equals({
          'title': 'My Song',
          'artist': 'The Band',
          'album': 'Best Album',
        }),
      );
    });

    test('mapTags handles empty native tags', () {
      final mapper = TestTagMapper(initialMap: {'TIT2': 'title'});

      final genericTags = mapper.mapTags({});

      expect(genericTags, isEmpty);
    });

    test('mapTags handles all unmapped tags', () {
      final mapper = TestTagMapper(initialMap: {'TIT2': 'title'});

      final nativeTags = {'UNKNOWN1': 'Value1', 'UNKNOWN2': 'Value2'};

      final genericTags = mapper.mapTags(nativeTags);

      expect(genericTags, isEmpty);
    });

    test('mapTags preserves original value types', () {
      final mapper = TestTagMapper(
        initialMap: {
          'StringTag': 'title',
          'IntTag': 'track',
          'ListTag': 'genres',
          'MapTag': 'metadata',
        },
      );

      final nativeTags = {
        'StringTag': 'Song Title',
        'IntTag': 5,
        'ListTag': ['Rock', 'Pop'],
        'MapTag': {'custom': 'data'},
      };

      final genericTags = mapper.mapTags(nativeTags);

      expect(genericTags['title'], equals('Song Title'));
      expect(genericTags['track'], equals(5));
      expect(genericTags['genres'], equals(['Rock', 'Pop']));
      expect(genericTags['metadata'], equals({'custom': 'data'}));
    });

    test('mapTags handles case-insensitive tag names', () {
      final mapper = TestTagMapper(
        initialMap: {'TIT2': 'title', 'TPE1': 'artist'},
      );

      // Mixed case in native tags
      final nativeTags = {
        'tit2': 'Lower Case',
        'TPE1': 'Upper Case',
        'TiTlE': 'Mixed Case (unmapped)',
      };

      final genericTags = mapper.mapTags(nativeTags);

      expect(
        genericTags,
        equals({'title': 'Lower Case', 'artist': 'Upper Case'}),
      );
    });

    test('multiple tags can map to same generic tag', () {
      final mapper = TestTagMapper(
        initialMap: {
          'TIT2': 'title',
          'TT1': 'title', // Alternative tag for title
        },
      );

      final nativeTags = {'TIT2': 'Primary Title', 'TT1': 'Alternative Title'};

      final genericTags = mapper.mapTags(nativeTags);

      // Last one wins when multiple tags map to same generic tag
      expect(genericTags['title'], isNotNull);
    });

    test('tagMap is accessible and modifiable', () {
      final mapper = TestTagMapper();

      expect(mapper.tagMap.isEmpty, isTrue);

      mapper.tagMap['NewTag'] = 'newGenericTag';

      expect(mapper.mapTag('NewTag', 'value'), equals('newGenericTag'));
    });

    test('can handle complex tag value objects', () {
      final mapper = TestTagMapper(
        initialMap: {'PICTURE': 'picture', 'COMMENT': 'comment'},
      );

      final pictureData = {
        'type': 'cover_front',
        'data': [255, 216, 255], // JPEG header
        'description': 'Album art',
      };

      final nativeTags = {'PICTURE': pictureData, 'COMMENT': 'Great album!'};

      final genericTags = mapper.mapTags(nativeTags);

      expect(genericTags['picture'], equals(pictureData));
      expect(genericTags['comment'], equals('Great album!'));
    });
  });

  group('Integration tests', () {
    test('CaseInsensitiveTagMap and GenericTagMapper work together', () {
      final mapper = TestTagMapper();

      // Build tag map case-insensitively
      mapper.tagMap['TIT2'] = 'title';
      mapper.tagMap['tpe1'] = 'artist';
      mapper.tagMap['TALB'] = 'album';

      // Query with format-specific tag names (ID3-like)
      final nativeTags = {
        'TIT2': 'Song', // Different case variations should work
        'TPE1': 'Band', // tpe1 in tagMap should match TPE1
        'talb': 'Album', // TALB in tagMap should match talb
        'custom': 'Value', // Unmapped
      };

      final result = mapper.mapTags(nativeTags);

      expect(
        result,
        equals({'title': 'Song', 'artist': 'Band', 'album': 'Album'}),
      );
    });

    test('realistic ID3v2-like mapping scenario', () {
      final mapper = TestTagMapper(
        initialMap: {
          'TIT2': 'title',
          'TPE1': 'artist',
          'TPE2': 'albumartist',
          'TALB': 'album',
          'TRCK': 'track',
          'TYER': 'year',
          'TCON': 'genre',
          'COMM': 'comment',
        },
      );

      final id3Tags = {
        'TIT2': 'Imagine',
        'TPE1': 'John Lennon',
        'TPE2': 'John Lennon',
        'TALB': 'Imagine',
        'TRCK': '1',
        'TYER': '1971',
        'TCON': 'Rock',
        'COMM': 'Great song!',
        'PRIV': 'private data', // Unmapped ID3 frame
      };

      final genericTags = mapper.mapTags(id3Tags);

      expect(genericTags['title'], equals('Imagine'));
      expect(genericTags['artist'], equals('John Lennon'));
      expect(genericTags['albumartist'], equals('John Lennon'));
      expect(genericTags['album'], equals('Imagine'));
      expect(genericTags['track'], equals('1'));
      expect(genericTags['year'], equals('1971'));
      expect(genericTags['genre'], equals('Rock'));
      expect(genericTags['comment'], equals('Great song!'));
      expect(genericTags.containsKey('PRIV'), isFalse);
    });
  });
}
