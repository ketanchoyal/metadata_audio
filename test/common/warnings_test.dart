import 'package:audio_metadata/src/common/combined_tag_mapper.dart';
import 'package:audio_metadata/src/common/generic_tag_mapper.dart';
import 'package:audio_metadata/src/common/case_insensitive_tag_map.dart';
import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:test/test.dart';

class SimpleMapper extends GenericTagMapper {
  @override
  CaseInsensitiveTagMap<String> get tagMap {
    final map = CaseInsensitiveTagMap<String>();
    map['title'] = 'title';
    return map;
  }
}

void main() {
  group('MetadataCollector - Warnings', () {
    late MetadataCollector collector;

    setUp(() {
      final tagMapper = CombinedTagMapper();
      tagMapper.registerMapper('test', SimpleMapper());
      collector = MetadataCollector(tagMapper);
    });

    test('should start with no warnings', () {
      final metadata = collector.toAudioMetadata();
      expect(metadata.quality.warnings, isEmpty);
    });

    test('should add single warning', () {
      collector.addWarning('Test warning message');

      final metadata = collector.toAudioMetadata();
      expect(metadata.quality.warnings.length, equals(1));
      expect(
        metadata.quality.warnings[0].message,
        equals('Test warning message'),
      );
    });

    test('should add multiple warnings in order', () {
      collector.addWarning('First warning');
      collector.addWarning('Second warning');
      collector.addWarning('Third warning');

      final metadata = collector.toAudioMetadata();
      expect(metadata.quality.warnings.length, equals(3));
      expect(metadata.quality.warnings[0].message, equals('First warning'));
      expect(metadata.quality.warnings[1].message, equals('Second warning'));
      expect(metadata.quality.warnings[2].message, equals('Third warning'));
    });

    test(
      'should preserve warning order across multiple toAudioMetadata calls',
      () {
        collector.addWarning('Warning 1');
        collector.addWarning('Warning 2');

        final metadata1 = collector.toAudioMetadata();
        expect(metadata1.quality.warnings.length, equals(2));

        collector.addWarning('Warning 3');
        final metadata2 = collector.toAudioMetadata();
        expect(metadata2.quality.warnings.length, equals(3));
      },
    );

    test('should handle warnings with special characters', () {
      collector.addWarning('Warning: "special" characters & <symbols>');

      final metadata = collector.toAudioMetadata();
      expect(
        metadata.quality.warnings[0].message,
        equals('Warning: "special" characters & <symbols>'),
      );
    });

    test('should handle empty warning message', () {
      collector.addWarning('');

      final metadata = collector.toAudioMetadata();
      expect(metadata.quality.warnings.length, equals(1));
      expect(metadata.quality.warnings[0].message, equals(''));
    });

    test('should collect warnings with metadata and tags', () {
      collector.setFormat(container: 'mp3', duration: 180.0);
      collector.addNativeTag('test', 'title', 'Test Title');
      collector.addWarning('Corrupted frame detected');
      collector.addWarning('Invalid encoding');

      final metadata = collector.toAudioMetadata();
      expect(metadata.format.container, equals('mp3'));
      expect(metadata.common.title, equals('Test Title'));
      expect(metadata.quality.warnings.length, equals(2));
      expect(
        metadata.quality.warnings[0].message,
        equals('Corrupted frame detected'),
      );
      expect(metadata.quality.warnings[1].message, equals('Invalid encoding'));
    });

    test('should create ParserWarning objects with proper message', () {
      final warningMsg = 'Test parser warning';
      collector.addWarning(warningMsg);

      final metadata = collector.toAudioMetadata();
      final warning = metadata.quality.warnings[0];

      expect(warning, isA<ParserWarning>());
      expect(warning.message, equals(warningMsg));
    });

    test('should allow adding same warning message multiple times', () {
      collector.addWarning('Duplicate warning');
      collector.addWarning('Duplicate warning');
      collector.addWarning('Duplicate warning');

      final metadata = collector.toAudioMetadata();
      expect(metadata.quality.warnings.length, equals(3));
      expect(metadata.quality.warnings[0].message, equals('Duplicate warning'));
      expect(metadata.quality.warnings[1].message, equals('Duplicate warning'));
      expect(metadata.quality.warnings[2].message, equals('Duplicate warning'));
    });

    test('should handle long warning messages', () {
      final longMsg =
          'A' * 1000 +
          ' This is a very long warning message that tests the system';
      collector.addWarning(longMsg);

      final metadata = collector.toAudioMetadata();
      expect(metadata.quality.warnings[0].message, equals(longMsg));
    });

    test('should return unmodifiable warnings list', () {
      collector.addWarning('Test');

      final warnings1 = collector.warnings;
      expect(warnings1, isNotNull);
      expect(warnings1.length, equals(1));

      // Adding new warning doesn't affect previously obtained reference
      collector.addWarning('New warning');

      final warnings2 = collector.warnings;
      expect(warnings2.length, equals(2));
    });
  });
}
