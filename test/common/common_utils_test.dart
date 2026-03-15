import 'package:audio_metadata/src/apev2/apev2_tag_map.dart';
import 'package:audio_metadata/src/asf/asf_tag_map.dart';
import 'package:audio_metadata/src/common/combined_tag_mapper.dart';
import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/core.dart';
import 'package:audio_metadata/src/id3v2/id3v2_tag_map.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/mp4/mp4_tag_mapper.dart';
import 'package:audio_metadata/src/parse_error.dart';
import 'package:audio_metadata/src/parser_factory.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

class _StaticParserLoader implements ParserLoader {

  _StaticParserLoader({required this.extension, required this.mimeType});
  @override
  final List<String> extension;

  @override
  final List<String> mimeType;

  @override
  bool get hasRandomAccessRequirements => false;

  @override
  bool supports(Tokenizer tokenizer) =>
      !hasRandomAccessRequirements || tokenizer.canSeek;

  @override
  Future<AudioMetadata> parse(Tokenizer tokenizer, ParseOptions options) {
    throw UnimplementedError('Not needed in parser selection tests');
  }
}

class _NoopTokenizer implements Tokenizer {
  @override
  FileInfo? get fileInfo => null;

  @override
  bool get canSeek => false;

  @override
  int get position => 0;

  @override
  int peekUint8() => throw UnimplementedError();

  @override
  List<int> peekBytes(int length) => throw UnimplementedError();

  @override
  int readUint8() => throw UnimplementedError();

  @override
  int readUint16() => throw UnimplementedError();

  @override
  int readUint32() => throw UnimplementedError();

  @override
  List<int> readBytes(int length) => throw UnimplementedError();

  @override
  void seek(int position) => throw UnimplementedError();

  @override
  void skip(int length) => throw UnimplementedError();
}

void main() {
  group('orderTags', () {
    test('returns empty map for empty tag list', () {
      final result = orderTags([]);
      expect(result, isEmpty);
    });

    test('groups single tag into map', () {
      final tags = [const Tag(id: 'TIT2', value: 'Song Title')];
      final result = orderTags(tags);

      expect(result.length, equals(1));
      expect(result['TIT2'], equals(['Song Title']));
    });

    test('groups multiple tags with same ID', () {
      final tags = [
        const Tag(id: 'TIT2', value: 'Song Title'),
        const Tag(id: 'TIT2', value: 'Alt Title'),
        const Tag(id: 'TIT2', value: 'Third Title'),
      ];
      final result = orderTags(tags);

      expect(result.length, equals(1));
      expect(
        result['TIT2'],
        equals(['Song Title', 'Alt Title', 'Third Title']),
      );
    });

    test('groups tags by different IDs', () {
      final tags = [
        const Tag(id: 'TIT2', value: 'Song Title'),
        const Tag(id: 'TPE1', value: 'Artist Name'),
        const Tag(id: 'TALB', value: 'Album Name'),
      ];
      final result = orderTags(tags);

      expect(result.length, equals(3));
      expect(result['TIT2'], equals(['Song Title']));
      expect(result['TPE1'], equals(['Artist Name']));
      expect(result['TALB'], equals(['Album Name']));
    });

    test('preserves order of tags within same ID', () {
      final tags = [
        const Tag(id: 'ARTIST', value: 'Artist 1'),
        const Tag(id: 'TITLE', value: 'Title 1'),
        const Tag(id: 'ARTIST', value: 'Artist 2'),
        const Tag(id: 'TITLE', value: 'Title 2'),
        const Tag(id: 'ARTIST', value: 'Artist 3'),
      ];
      final result = orderTags(tags);

      expect(result['ARTIST'], equals(['Artist 1', 'Artist 2', 'Artist 3']));
      expect(result['TITLE'], equals(['Title 1', 'Title 2']));
    });

    test('handles various value types', () {
      final tags = [
        const Tag(id: 'STRING', value: 'text'),
        const Tag(id: 'NUMBER', value: 42),
        const Tag(id: 'DOUBLE', value: 3.14),
        const Tag(id: 'BOOL', value: true),
      ];
      final result = orderTags(tags);

      expect(result['STRING'], equals(['text']));
      expect(result['NUMBER'], equals([42]));
      expect(result['DOUBLE'], equals([3.14]));
      expect(result['BOOL'], equals([true]));
    });
  });

  group('ratingToStars', () {
    test('returns null for null input', () {
      expect(ratingToStars(null), isNull);
    });

    test('converts 0.0 to 1 star', () {
      expect(ratingToStars(0), equals(1));
    });

    test('converts 0.25 to 2 stars', () {
      expect(ratingToStars(0.25), equals(2));
    });

    test('converts 0.5 to 3 stars', () {
      expect(ratingToStars(0.5), equals(3));
    });

    test('converts 0.75 to 4 stars', () {
      expect(ratingToStars(0.75), equals(4));
    });

    test('converts 1.0 to 5 stars', () {
      expect(ratingToStars(1), equals(5));
    });

    test('clamps values below 0.0 to 1 star', () {
      expect(ratingToStars(-0.5), equals(1));
      expect(ratingToStars(-1), equals(1));
    });

    test('clamps values above 1.0 to 5 stars', () {
      expect(ratingToStars(1.5), equals(5));
      expect(ratingToStars(2), equals(5));
    });

    test('rounds intermediate values correctly', () {
      expect(ratingToStars(0.1), isNotNull);
      expect(ratingToStars(0.1)!, greaterThanOrEqualTo(1));
      expect(ratingToStars(0.1)!, lessThanOrEqualTo(5));

      expect(ratingToStars(0.9), isNotNull);
      expect(ratingToStars(0.9)!, greaterThanOrEqualTo(1));
      expect(ratingToStars(0.9)!, lessThanOrEqualTo(5));
    });
  });

  group('selectCover', () {
    test('returns null for null list', () {
      expect(selectCover(null), isNull);
    });

    test('returns null for empty list', () {
      expect(selectCover([]), isNull);
    });

    test('returns first picture with type=Cover', () {
      final pictures = [
        const Picture(format: 'image/jpeg', data: [1, 2, 3], type: 'Back'),
        const Picture(format: 'image/jpeg', data: [4, 5, 6], type: 'Cover'),
        const Picture(format: 'image/png', data: [7, 8, 9], type: 'Front'),
      ];
      final result = selectCover(pictures);

      expect(result?.type, equals('Cover'));
      expect(result?.data, equals([4, 5, 6]));
    });

    test('returns first picture when no Cover type exists', () {
      final pictures = [
        const Picture(format: 'image/jpeg', data: [1, 2, 3], type: 'Back'),
        const Picture(format: 'image/png', data: [7, 8, 9], type: 'Front'),
      ];
      final result = selectCover(pictures);

      expect(result?.type, equals('Back'));
      expect(result?.data, equals([1, 2, 3]));
    });

    test('returns single picture with type=Cover', () {
      final pictures = [
        const Picture(format: 'image/jpeg', data: [1, 2, 3], type: 'Cover'),
      ];
      final result = selectCover(pictures);

      expect(result?.type, equals('Cover'));
      expect(result?.data, equals([1, 2, 3]));
    });

    test('returns single picture when no type is specified', () {
      final pictures = [
        const Picture(format: 'image/jpeg', data: [1, 2, 3]),
      ];
      final result = selectCover(pictures);

      expect(result?.format, equals('image/jpeg'));
      expect(result?.data, equals([1, 2, 3]));
    });

    test('prioritizes Cover over other types', () {
      final pictures = [
        const Picture(format: 'image/jpeg', data: [1, 2, 3], type: 'Front'),
        const Picture(format: 'image/jpeg', data: [4, 5, 6]),
        const Picture(format: 'image/jpeg', data: [7, 8, 9], type: 'Cover'),
        const Picture(format: 'image/png', data: [10, 11, 12], type: 'Back'),
      ];
      final result = selectCover(pictures);

      expect(result?.type, equals('Cover'));
      expect(result?.data, equals([7, 8, 9]));
    });

    test('handles pictures with null type', () {
      final pictures = [
        const Picture(format: 'image/jpeg', data: [1, 2, 3]),
        const Picture(format: 'image/png', data: [4, 5, 6]),
      ];
      final result = selectCover(pictures);

      expect(result?.format, equals('image/jpeg'));
      expect(result?.data, equals([1, 2, 3]));
    });

    test('handles mixed Cover and non-Cover types', () {
      final pictures = [
        const Picture(format: 'image/jpeg', data: [1, 2, 3], type: 'Other'),
        const Picture(format: 'image/jpeg', data: [4, 5, 6], type: 'Cover'),
        const Picture(format: 'image/png', data: [7, 8, 9], type: 'Other'),
      ];
      final result = selectCover(pictures);

      expect(result?.data, equals([4, 5, 6]));
    });
  });

  group('common metadata mapping parity', () {
    late MetadataCollector collector;

    setUp(() {
      final mapper = CombinedTagMapper();
      mapper.registerMapper('id3v2', Id3v2TagMapper());
      mapper.registerMapper('apev2', Apev2TagMapper());
      mapper.registerMapper('asf', AsfTagMapper());
      mapper.registerMapper('mp4', Mp4TagMapper());
      collector = MetadataCollector(mapper);
    });

    test('maps ID3v2 title/artist/album/year/genre/track into common tags', () {
      collector.addNativeTag('id3v2', 'TIT2', 'Space Oddity');
      collector.addNativeTag('id3v2', 'TPE1', 'David Bowie');
      collector.addNativeTag('id3v2', 'TALB', 'Space Oddity');
      collector.addNativeTag('id3v2', 'TYER', '1969');
      collector.addNativeTag('id3v2', 'TCON', ['Rock', 'Art Rock']);
      collector.addNativeTag('id3v2', 'TRCK', '1/10');

      final metadata = collector.toAudioMetadata();
      expect(metadata.common.title, equals('Space Oddity'));
      expect(metadata.common.artist, equals('David Bowie'));
      expect(metadata.common.album, equals('Space Oddity'));
      expect(metadata.common.year, equals(1969));
      expect(metadata.common.genre, equals(['Rock', 'Art Rock']));
      expect(metadata.common.track.no, equals(1));
    });

    test('maps APEv2 core common fields with normalized value types', () {
      collector.addNativeTag('apev2', 'Title', "Sinner's Prayer");
      collector.addNativeTag('apev2', 'Artist', 'Beth Hart');
      collector.addNativeTag('apev2', 'Album', "Don't Explain");
      collector.addNativeTag('apev2', 'Year', '2011');
      collector.addNativeTag('apev2', 'Genre', ['Blues Rock']);

      final metadata = collector.toAudioMetadata();
      expect(metadata.common.title, equals("Sinner's Prayer"));
      expect(metadata.common.artist, equals('Beth Hart'));
      expect(metadata.common.album, equals("Don't Explain"));
      expect(metadata.common.year, equals(2011));
      expect(metadata.common.genre, equals(['Blues Rock']));
    });
  });

  group('comment mapping parity', () {
    late MetadataCollector collector;

    setUp(() {
      final mapper = CombinedTagMapper();
      mapper.registerMapper('id3v2', Id3v2TagMapper());
      mapper.registerMapper('apev2', Apev2TagMapper());
      mapper.registerMapper('asf', AsfTagMapper());
      mapper.registerMapper('mp4', Mp4TagMapper());
      collector = MetadataCollector(mapper);
    });

    test(
      'maps ID3v2 COMM into common.comment preserving descriptor/language',
      () {
        collector.addNativeTag(
          'id3v2',
          'COMM',
          const Comment(descriptor: '', language: 'eng', text: 'Test 123'),
        );

        final comment = collector.toAudioMetadata().common.comment;
        expect(comment, hasLength(1));
        expect(comment?.first.descriptor, equals(''));
        expect(comment?.first.language, equals('eng'));
        expect(comment?.first.text, equals('Test 123'));
      },
    );

    test('maps ASF Description into common.comment text list', () {
      collector.addNativeTag('asf', 'Description', 'Test 123');

      final comment = collector.toAudioMetadata().common.comment;
      expect(comment, hasLength(1));
      expect(comment?.first.text, equals('Test 123'));
      expect(comment?.first.language, isNull);
      expect(comment?.first.descriptor, isNull);
    });

    test('maps MP4 iTunes NOTES into common.comment text list', () {
      collector.addNativeTag(
        'mp4',
        '----:com.apple.itunes:notes',
        'Medieval CUE Splitter',
      );

      final comment = collector.toAudioMetadata().common.comment;
      expect(comment, hasLength(1));
      expect(comment?.first.text, equals('Medieval CUE Splitter'));
    });
  });

  group('MIME handling parity', () {
    late ParserRegistry registry;
    late ParserFactory factory;

    late _StaticParserLoader mp3Loader;
    late _StaticParserLoader flacLoader;
    late _StaticParserLoader oggLoader;

    setUp(() {
      registry = ParserRegistry();
      factory = ParserFactory(registry);

      mp3Loader = _StaticParserLoader(
        extension: ['mp3'],
        mimeType: ['audio/mpeg'],
      );
      flacLoader = _StaticParserLoader(
        extension: ['flac'],
        mimeType: ['audio/flac'],
      );
      oggLoader = _StaticParserLoader(
        extension: ['ogg'],
        mimeType: ['audio/ogg', 'application/ogg'],
      );

      registry.register(mp3Loader);
      registry.register(flacLoader);
      registry.register(oggLoader);
    });

    test('selectParser prioritizes MIME type over extension', () {
      final loader = factory.selectParser(
        const FileInfo(path: '/music/example.mp3', mimeType: 'audio/flac'),
        _NoopTokenizer(),
      );
      expect(loader, same(flacLoader));
    });

    test('supports secondary MIME aliases for the same loader', () {
      final loader = factory.selectParser(
        const FileInfo(path: '/music/example.bin', mimeType: 'application/ogg'),
        _NoopTokenizer(),
      );
      expect(loader, same(oggLoader));
    });

    test('falls back to extension mapping when MIME type is absent', () {
      final loader = factory.selectParser(
        const FileInfo(path: '/music/example.mp3'),
        _NoopTokenizer(),
      );
      expect(loader, same(mp3Loader));
    });

    test('throws when MIME type and extension do not resolve a parser', () {
      expect(
        () => factory.selectParser(
          const FileInfo(
            path: '/music/example.unknown',
            mimeType: 'audio/none',
          ),
          _NoopTokenizer(),
        ),
        throwsA(isA<CouldNotDetermineFileTypeError>()),
      );
    });

    test('registry exposes a stable sorted MIME list', () {
      expect(
        registry.getRegisteredMimeTypes(),
        equals(['application/ogg', 'audio/flac', 'audio/mpeg', 'audio/ogg']),
      );
    });
  });
}
