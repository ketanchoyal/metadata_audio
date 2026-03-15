import 'package:audio_metadata/src/common/case_insensitive_tag_map.dart';
import 'package:audio_metadata/src/common/combined_tag_mapper.dart';
import 'package:audio_metadata/src/common/generic_tag_mapper.dart';
import 'package:test/test.dart';

/// Mock tag mapper for testing
class MockId3v2Mapper extends GenericTagMapper {

  MockId3v2Mapper() {
    _tagMap = CaseInsensitiveTagMap<String>();
    _tagMap['TIT2'] = 'title';
    _tagMap['TPE1'] = 'artist';
    _tagMap['TALB'] = 'album';
    _tagMap['TRCK'] = 'track';
  }
  late CaseInsensitiveTagMap<String> _tagMap;

  @override
  CaseInsensitiveTagMap<String> get tagMap => _tagMap;
}

/// Mock Vorbis tag mapper for testing
class MockVorbisMapper extends GenericTagMapper {

  MockVorbisMapper() {
    _tagMap = CaseInsensitiveTagMap<String>();
    _tagMap['TITLE'] = 'title';
    _tagMap['ARTIST'] = 'artist';
    _tagMap['ALBUM'] = 'album';
    _tagMap['TRACKNUMBER'] = 'track';
  }
  late CaseInsensitiveTagMap<String> _tagMap;

  @override
  CaseInsensitiveTagMap<String> get tagMap => _tagMap;
}

/// Mock MP4 tag mapper for testing
class MockMp4Mapper extends GenericTagMapper {

  MockMp4Mapper() {
    _tagMap = CaseInsensitiveTagMap<String>();
    _tagMap['©nam'] = 'title';
    _tagMap['©ART'] = 'artist';
    _tagMap['©alb'] = 'album';
    _tagMap['trkn'] = 'track';
  }
  late CaseInsensitiveTagMap<String> _tagMap;

  @override
  CaseInsensitiveTagMap<String> get tagMap => _tagMap;
}

void main() {
  group('CombinedTagMapper', () {
    late CombinedTagMapper combined;

    setUp(() {
      combined = CombinedTagMapper();
    });

    group('Registration', () {
      test('registerMapper adds a new mapper', () {
        final mapper = MockId3v2Mapper();
        combined.registerMapper('id3v2', mapper);

        expect(combined.hasMapper('id3v2'), isTrue);
      });

      test('registerMapper overwrites existing mapper for same format', () {
        final mapper1 = MockId3v2Mapper();
        final mapper2 = MockId3v2Mapper();

        combined.registerMapper('id3v2', mapper1);
        combined.registerMapper('id3v2', mapper2);

        expect(combined.mapperCount, equals(1));
      });

      test('can register multiple different format mappers', () {
        combined.registerMapper('id3v2', MockId3v2Mapper());
        combined.registerMapper('vorbis', MockVorbisMapper());
        combined.registerMapper('mp4', MockMp4Mapper());

        expect(combined.mapperCount, equals(3));
        expect(combined.hasMapper('id3v2'), isTrue);
        expect(combined.hasMapper('vorbis'), isTrue);
        expect(combined.hasMapper('mp4'), isTrue);
      });

      test('hasMapper returns false for unregistered formats', () {
        combined.registerMapper('id3v2', MockId3v2Mapper());

        expect(combined.hasMapper('id3v2'), isTrue);
        expect(combined.hasMapper('vorbis'), isFalse);
        expect(combined.hasMapper('mp4'), isFalse);
      });
    });

    group('Mapping tags', () {
      setUp(() {
        combined.registerMapper('id3v2', MockId3v2Mapper());
        combined.registerMapper('vorbis', MockVorbisMapper());
        combined.registerMapper('mp4', MockMp4Mapper());
      });

      test('mapTags dispatches to correct mapper for id3v2', () {
        final nativeTags = {
          'TIT2': 'Song Title',
          'TPE1': 'Artist Name',
          'TALB': 'Album Name',
          'TRCK': '5',
        };

        final result = combined.mapTags('id3v2', nativeTags);

        expect(
          result,
          equals({
            'title': 'Song Title',
            'artist': 'Artist Name',
            'album': 'Album Name',
            'track': '5',
          }),
        );
      });

      test('mapTags dispatches to correct mapper for vorbis', () {
        final nativeTags = {
          'TITLE': 'Song Title',
          'ARTIST': 'Artist Name',
          'ALBUM': 'Album Name',
          'TRACKNUMBER': '3',
        };

        final result = combined.mapTags('vorbis', nativeTags);

        expect(
          result,
          equals({
            'title': 'Song Title',
            'artist': 'Artist Name',
            'album': 'Album Name',
            'track': '3',
          }),
        );
      });

      test('mapTags dispatches to correct mapper for mp4', () {
        final nativeTags = {
          '©nam': 'Song Title',
          '©ART': 'Artist Name',
          '©alb': 'Album Name',
          'trkn': '7',
        };

        final result = combined.mapTags('mp4', nativeTags);

        expect(
          result,
          equals({
            'title': 'Song Title',
            'artist': 'Artist Name',
            'album': 'Album Name',
            'track': '7',
          }),
        );
      });

      test('mapTags handles unmapped tags within a format', () {
        final nativeTags = {
          'TIT2': 'Song Title',
          'TPE1': 'Artist Name',
          'PRIV': 'private data', // Unmapped
          'TXXX': 'custom frame', // Unmapped
        };

        final result = combined.mapTags('id3v2', nativeTags);

        expect(
          result,
          equals({'title': 'Song Title', 'artist': 'Artist Name'}),
        );
      });

      test('mapTags handles empty native tags', () {
        final result = combined.mapTags('id3v2', {});

        expect(result, isEmpty);
      });

      test('mapTags throws UnknownFormatException for unregistered format', () {
        expect(
          () => combined.mapTags('unknown_format', {'key': 'value'}),
          throwsA(isA<UnknownFormatException>()),
        );
      });

      test('mapTags throws UnknownFormatException with correct format ID', () {
        try {
          combined.mapTags('flac', {'key': 'value'});
          fail('Should have thrown UnknownFormatException');
        } on UnknownFormatException catch (e) {
          expect(e.formatId, equals('flac'));
          expect(e.toString(), contains('flac'));
        }
      });

      test('mapTags preserves value types', () {
        final nativeTags = {
          'TIT2': 'Song Title',
          'TPE1': 'Artist',
          'TRCK': 5, // Integer
        };

        final result = combined.mapTags('id3v2', nativeTags);

        expect(result['title'], isA<String>());
        expect(result['artist'], isA<String>());
        expect(result['track'], isA<int>());
      });
    });

    group('Format management', () {
      test('registeredFormats returns all registered format IDs', () {
        combined.registerMapper('id3v2', MockId3v2Mapper());
        combined.registerMapper('vorbis', MockVorbisMapper());
        combined.registerMapper('mp4', MockMp4Mapper());

        final formats = combined.registeredFormats;

        expect(formats, containsAll(['id3v2', 'vorbis', 'mp4']));
        expect(formats.length, equals(3));
      });

      test(
        'registeredFormats returns empty set when no mappers registered',
        () {
          final formats = combined.registeredFormats;

          expect(formats, isEmpty);
        },
      );

      test('mapperCount returns correct number of registered mappers', () {
        expect(combined.mapperCount, equals(0));

        combined.registerMapper('id3v2', MockId3v2Mapper());
        expect(combined.mapperCount, equals(1));

        combined.registerMapper('vorbis', MockVorbisMapper());
        expect(combined.mapperCount, equals(2));

        combined.registerMapper('mp4', MockMp4Mapper());
        expect(combined.mapperCount, equals(3));
      });

      test('clear removes all registered mappers', () {
        combined.registerMapper('id3v2', MockId3v2Mapper());
        combined.registerMapper('vorbis', MockVorbisMapper());

        expect(combined.mapperCount, equals(2));

        combined.clear();

        expect(combined.mapperCount, equals(0));
        expect(combined.hasMapper('id3v2'), isFalse);
        expect(combined.hasMapper('vorbis'), isFalse);
      });

      test('mapTags throws after clear', () {
        combined.registerMapper('id3v2', MockId3v2Mapper());
        combined.clear();

        expect(
          () => combined.mapTags('id3v2', {'TIT2': 'Song'}),
          throwsA(isA<UnknownFormatException>()),
        );
      });
    });

    group('Integration tests', () {
      test('realistic multi-format scenario', () {
        combined.registerMapper('id3v2', MockId3v2Mapper());
        combined.registerMapper('vorbis', MockVorbisMapper());

        // ID3v2 tags
        final id3Tags = {
          'TIT2': 'Imagine',
          'TPE1': 'John Lennon',
          'TALB': 'Imagine',
          'TRCK': '1',
        };

        // Vorbis tags
        final vorbisTags = {
          'TITLE': 'Imagine',
          'ARTIST': 'John Lennon',
          'ALBUM': 'Imagine',
          'TRACKNUMBER': '1',
        };

        final id3Result = combined.mapTags('id3v2', id3Tags);
        final vorbisResult = combined.mapTags('vorbis', vorbisTags);

        expect(
          id3Result,
          equals({
            'title': 'Imagine',
            'artist': 'John Lennon',
            'album': 'Imagine',
            'track': '1',
          }),
        );

        expect(
          vorbisResult,
          equals({
            'title': 'Imagine',
            'artist': 'John Lennon',
            'album': 'Imagine',
            'track': '1',
          }),
        );

        // Both formats produce the same generic tags
        expect(id3Result, equals(vorbisResult));
      });

      test('format-specific vs generic tags comparison', () {
        combined.registerMapper('id3v2', MockId3v2Mapper());

        // Same metadata in different format-specific tag names
        final id3NativeFormat = {
          'TIT2': 'Song',
          'TPE1': 'Artist',
          'TALB': 'Album',
        };

        final genericTags = combined.mapTags('id3v2', id3NativeFormat);

        // Generic tags use common names regardless of format
        expect(genericTags.keys, containsAll(['title', 'artist', 'album']));
        expect(genericTags.keys, isNot(contains('TIT2')));
        expect(genericTags.keys, isNot(contains('TPE1')));
      });

      test('switching between formats with same data', () {
        combined.registerMapper('id3v2', MockId3v2Mapper());
        combined.registerMapper('vorbis', MockVorbisMapper());

        const title = 'Test Song';
        const artist = 'Test Artist';

        final id3Tags = {'TIT2': title, 'TPE1': artist};

        final vorbisNativeTags = {'TITLE': title, 'ARTIST': artist};

        final id3Result = combined.mapTags('id3v2', id3Tags);
        final vorbisResult = combined.mapTags('vorbis', vorbisNativeTags);

        // Same generic output for same data in different formats
        expect(id3Result['title'], equals(title));
        expect(id3Result['artist'], equals(artist));
        expect(vorbisResult['title'], equals(title));
        expect(vorbisResult['artist'], equals(artist));
      });
    });

    group('Error handling', () {
      test('UnknownFormatException has correct message', () {
        final exception = UnknownFormatException('custom_format');

        expect(
          exception.toString(),
          contains('No tag mapper registered for format "custom_format"'),
        );
      });

      test('can catch UnknownFormatException specifically', () {
        var caught = false;
        try {
          combined.mapTags('undefined_format', {});
        } on UnknownFormatException {
          caught = true;
        }

        expect(caught, isTrue);
      });

      test('UnknownFormatException is Exception', () {
        final exception = UnknownFormatException('test');

        expect(exception, isA<Exception>());
      });
    });
  });
}
