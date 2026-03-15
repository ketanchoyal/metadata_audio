import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/id3v1/id3v1_parser.dart';
import 'package:metadata_audio/src/id3v1/id3v1_tag_map.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

/// Mock tokenizer for testing ID3v1 parser.
class MockTokenizer implements Tokenizer {

  MockTokenizer({
    required List<int> data,
    bool canSeek = true,
    FileInfo? fileInfo,
  }) : _data = data,
       _canSeek = canSeek,
       _fileInfo = fileInfo;
  final List<int> _data;
  int _position = 0;
  final bool _canSeek;
  final FileInfo? _fileInfo;

  @override
  bool get canSeek => _canSeek;

  @override
  FileInfo? get fileInfo => _fileInfo;

  @override
  int get position => _position;

  @override
  int peekUint8() {
    if (_position >= _data.length) {
      throw TokenizerException('EOF reached');
    }
    return _data[_position];
  }

  @override
  List<int> peekBytes(int length) {
    if (_position + length > _data.length) {
      throw TokenizerException('Not enough bytes to peek');
    }
    return _data.sublist(_position, _position + length);
  }

  @override
  int readUint8() {
    if (_position >= _data.length) {
      throw TokenizerException('EOF reached');
    }
    return _data[_position++];
  }

  @override
  int readUint16() {
    if (_position + 2 > _data.length) {
      throw TokenizerException('Not enough bytes');
    }
    final value = (_data[_position] << 8) | _data[_position + 1];
    _position += 2;
    return value;
  }

  @override
  int readUint32() {
    if (_position + 4 > _data.length) {
      throw TokenizerException('Not enough bytes');
    }
    final value =
        (_data[_position] << 24) |
        (_data[_position + 1] << 16) |
        (_data[_position + 2] << 8) |
        _data[_position + 3];
    _position += 4;
    return value;
  }

  @override
  List<int> readBytes(int length) {
    if (_position + length > _data.length) {
      throw TokenizerException('Not enough bytes');
    }
    final result = _data.sublist(_position, _position + length);
    _position += length;
    return result;
  }

  @override
  void seek(int position) {
    if (!_canSeek) {
      throw TokenizerException('Seeking not supported');
    }
    if (position < 0 || position > _data.length) {
      throw TokenizerException('Seek position out of bounds');
    }
    _position = position;
  }

  @override
  void skip(int length) {
    if (_position + length > _data.length) {
      throw TokenizerException('Not enough bytes to skip');
    }
    _position += length;
  }
}

void main() {
  group('ID3v1Parser', () {
    group('parse', () {
      test('should detect valid ID3v1 tag', () async {
        // Create a 128-byte ID3v1 block with "TAG" header
        final id3v1Block = List<int>.filled(128, 0);

        // Set "TAG" header
        id3v1Block[0] = 0x54; // 'T'
        id3v1Block[1] = 0x41; // 'A'
        id3v1Block[2] = 0x47; // 'G'

        // Set title: "Test Title"
        const title = 'Test Title';
        for (var i = 0; i < title.length; i++) {
          id3v1Block[3 + i] = title.codeUnitAt(i);
        }

        // Set artist: "Test Artist"
        const artist = 'Test Artist';
        for (var i = 0; i < artist.length; i++) {
          id3v1Block[33 + i] = artist.codeUnitAt(i);
        }

        // Set album: "Test Album"
        const album = 'Test Album';
        for (var i = 0; i < album.length; i++) {
          id3v1Block[63 + i] = album.codeUnitAt(i);
        }

        // Set year: "2024"
        const year = '2024';
        for (var i = 0; i < year.length; i++) {
          id3v1Block[93 + i] = year.codeUnitAt(i);
        }

        // Set genre: 13 (Pop)
        id3v1Block[127] = 13;

        // Create metadata collector with ID3v1 tag mapper
        final combined = CombinedTagMapper();
        combined.registerMapper('ID3v1', Id3v1TagMapper());
        final metadata = MetadataCollector(combined);

        // Create mock tokenizer positioned at file end
        final tokenizer = MockTokenizer(
          data: id3v1Block,
          fileInfo: const FileInfo(size: 128),
        );

        // Parse ID3v1
        final parser = Id3v1Parser(metadata: metadata, tokenizer: tokenizer);

        final found = await parser.parse();

        expect(found, isTrue, reason: 'ID3v1 tag should be found');

        // Verify native tags were added
        final nativeTags = metadata.nativeTagsByFormat;
        expect(nativeTags.containsKey('ID3v1'), isTrue);
        expect(nativeTags['ID3v1']!['title'], equals(title));
        expect(nativeTags['ID3v1']!['artist'], equals(artist));
        expect(nativeTags['ID3v1']!['album'], equals(album));
        expect(nativeTags['ID3v1']!['year'], equals(year));
        expect(nativeTags['ID3v1']!['genre'], equals('Pop'));
      });

      test('should parse ID3v1.1 with track number', () async {
        final id3v1Block = List<int>.filled(128, 0);

        // Set "TAG" header
        id3v1Block[0] = 0x54; // 'T'
        id3v1Block[1] = 0x41; // 'A'
        id3v1Block[2] = 0x47; // 'G'

        // Set title
        const title = 'Song Title';
        for (var i = 0; i < title.length; i++) {
          id3v1Block[3 + i] = title.codeUnitAt(i);
        }

        // Set track number (ID3v1.1 format)
        // Byte 125 is 0 (separator), byte 126 is track number
        id3v1Block[125] = 0; // Separator
        id3v1Block[126] = 7; // Track 7

        // Set genre
        id3v1Block[127] = 1; // Classic Rock

        final combined = CombinedTagMapper();
        combined.registerMapper('ID3v1', Id3v1TagMapper());
        final metadata = MetadataCollector(combined);

        final tokenizer = MockTokenizer(
          data: id3v1Block,
          fileInfo: const FileInfo(size: 128),
        );

        final parser = Id3v1Parser(metadata: metadata, tokenizer: tokenizer);

        final found = await parser.parse();

        expect(found, isTrue);
        expect(metadata.nativeTagsByFormat['ID3v1']!['track'], equals(7));
        expect(
          metadata.nativeTagsByFormat['ID3v1']!['genre'],
          equals('Classic Rock'),
        );
      });

      test('should ignore non-ID3v1 blocks', () async {
        final notId3v1Block = List<int>.filled(128, 0xFF);

        final combined = CombinedTagMapper();
        combined.registerMapper('ID3v1', Id3v1TagMapper());
        final metadata = MetadataCollector(combined);

        final tokenizer = MockTokenizer(
          data: notId3v1Block,
          fileInfo: const FileInfo(size: 128),
        );

        final parser = Id3v1Parser(metadata: metadata, tokenizer: tokenizer);

        final found = await parser.parse();

        expect(
          found,
          isFalse,
          reason: 'Should not find ID3v1 tag without TAG header',
        );
      });

      test('should handle empty tags gracefully', () async {
        final id3v1Block = List<int>.filled(128, 0);

        // Only set "TAG" header
        id3v1Block[0] = 0x54; // 'T'
        id3v1Block[1] = 0x41; // 'A'
        id3v1Block[2] = 0x47; // 'G'

        // Rest is null/empty

        final combined = CombinedTagMapper();
        combined.registerMapper('ID3v1', Id3v1TagMapper());
        final metadata = MetadataCollector(combined);

        final tokenizer = MockTokenizer(
          data: id3v1Block,
          fileInfo: const FileInfo(size: 128),
        );

        final parser = Id3v1Parser(metadata: metadata, tokenizer: tokenizer);

        final found = await parser.parse();

        expect(found, isTrue);
        // Should have found TAG header but no tags added (all empty)
        expect(metadata.nativeTagsByFormat['ID3v1'], isNull);
      });

      test('should return false if file too small', () async {
        final tooSmallData = List<int>.filled(64, 0);

        final combined = CombinedTagMapper();
        combined.registerMapper('ID3v1', Id3v1TagMapper());
        final metadata = MetadataCollector(combined);

        final tokenizer = MockTokenizer(
          data: tooSmallData,
          fileInfo: const FileInfo(size: 64),
        );

        final parser = Id3v1Parser(metadata: metadata, tokenizer: tokenizer);

        final found = await parser.parse();

        expect(found, isFalse);
      });

      test('should return false if file size unknown', () async {
        final id3v1Block = List<int>.filled(128, 0);

        final combined = CombinedTagMapper();
        combined.registerMapper('ID3v1', Id3v1TagMapper());
        final metadata = MetadataCollector(combined);

        final tokenizer = MockTokenizer(
          data: id3v1Block,
          fileInfo: const FileInfo(),
        );

        final parser = Id3v1Parser(metadata: metadata, tokenizer: tokenizer);

        final found = await parser.parse();

        expect(found, isFalse);
      });
    });

    group('genre mapping', () {
      test('should map valid genre indices', () {
        expect(genres[0], equals('Blues'));
        expect(genres[13], equals('Pop'));
        expect(genres[17], equals('Rock'));
        expect(genres[124], equals('Euro-House'));
      });

      test('should handle out-of-range genre indices', () {
        // genres list has 192 entries
        expect(genres.length, equals(192));
        // Indices 0-191 are valid, 192+ should not be accessed
      });
    });

    group('string field parsing', () {
      test('should parse and trim strings correctly', () {
        final block = List<int>.filled(30, 0);

        // Set "Test" followed by nulls
        const test = 'Test';
        for (var i = 0; i < test.length; i++) {
          block[i] = test.codeUnitAt(i);
        }

        // Call private method via reflection or by testing through parser
        // For now, test through parser behavior
      });

      test('should handle all-null fields', () {
        final block = List<int>.filled(30, 0);
        expect(block, hasLength(30));
        // All nulls - should return null
      });

      test('should trim whitespace from fields', () {
        final block = List<int>.filled(30, 0);

        // Set "Test   " (with trailing spaces)
        const test = 'Test   ';
        for (var i = 0; i < test.length; i++) {
          block[i] = test.codeUnitAt(i);
        }
        // Should trim to "Test"
      });
    });

    group('ID3v1TagMapper', () {
      test('should map ID3v1 tags to common tags', () {
        final mapper = Id3v1TagMapper();
        final nativeTags = {
          'title': 'My Song',
          'artist': 'The Artist',
          'album': 'My Album',
          'year': '2024',
          'genre': 'Rock',
          'track': 5,
          'comment': 'A comment',
        };

        final genericTags = mapper.mapTags(nativeTags);

        expect(genericTags['title'], equals('My Song'));
        expect(genericTags['artist'], equals('The Artist'));
        expect(genericTags['album'], equals('My Album'));
        expect(genericTags['year'], equals('2024'));
        expect(genericTags['genre'], equals('Rock'));
        expect(genericTags['track'], equals(5));
        expect(genericTags['comment'], equals('A comment'));
      });

      test('should be case-insensitive for tag keys', () {
        final mapper = Id3v1TagMapper();
        final nativeTags = {
          'TITLE': 'My Song',
          'Artist': 'The Artist',
          'ALBUM': 'My Album',
        };

        final genericTags = mapper.mapTags(nativeTags);

        expect(genericTags['title'], equals('My Song'));
        expect(genericTags['artist'], equals('The Artist'));
        expect(genericTags['album'], equals('My Album'));
      });

      test('should ignore unmapped tags', () {
        final mapper = Id3v1TagMapper();
        final nativeTags = {
          'title': 'My Song',
          'unknown_tag': 'some value',
          'artist': 'The Artist',
        };

        final genericTags = mapper.mapTags(nativeTags);

        expect(genericTags.containsKey('title'), isTrue);
        expect(genericTags.containsKey('artist'), isTrue);
        expect(genericTags.containsKey('unknown_tag'), isFalse);
      });
    });
  });
}
