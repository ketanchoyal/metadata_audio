import 'package:audio_metadata/src/core.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:test/test.dart';

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
      expect(ratingToStars(0.0), equals(1));
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
      expect(ratingToStars(1.0), equals(5));
    });

    test('clamps values below 0.0 to 1 star', () {
      expect(ratingToStars(-0.5), equals(1));
      expect(ratingToStars(-1.0), equals(1));
    });

    test('clamps values above 1.0 to 5 stars', () {
      expect(ratingToStars(1.5), equals(5));
      expect(ratingToStars(2.0), equals(5));
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
}
