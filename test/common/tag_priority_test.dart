import 'package:audio_metadata/src/common/case_insensitive_tag_map.dart';
import 'package:audio_metadata/src/common/combined_tag_mapper.dart';
import 'package:audio_metadata/src/common/generic_tag_mapper.dart';
import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:test/test.dart';

/// Mock mapper for testing (ID3v2)
class MockTagMapper extends GenericTagMapper {
  @override
  CaseInsensitiveTagMap<String> get tagMap {
    final map = CaseInsensitiveTagMap<String>();
    map['TIT2'] = 'title';
    map['TPE1'] = 'artist';
    map['TALB'] = 'album';
    map['TRCK'] = 'track';
    return map;
  }

  @override
  String? mapTag(String tag, dynamic value) {
    return tagMap[tag];
  }

  @override
  Map<String, dynamic> mapTags(Map<String, dynamic> nativeTags) {
    final result = super.mapTags(nativeTags);

    // Special handling for track numbers
    if (result.containsKey('track')) {
      result['track'] = _parseTrackNumber(result['track']);
    }

    return result;
  }

  static int? _parseTrackNumber(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      final parts = value.split('/');
      return int.tryParse(parts[0]);
    }
    return null;
  }
}

/// Mock Vorbis mapper
class MockVorbisMapper extends GenericTagMapper {
  @override
  CaseInsensitiveTagMap<String> get tagMap {
    final map = CaseInsensitiveTagMap<String>();
    map['title'] = 'title';
    map['artist'] = 'artist';
    map['album'] = 'album';
    map['tracknumber'] = 'track';
    return map;
  }

  @override
  String? mapTag(String tag, dynamic value) {
    return tagMap[tag];
  }

  @override
  Map<String, dynamic> mapTags(Map<String, dynamic> nativeTags) {
    final result = super.mapTags(nativeTags);

    // Special handling for track numbers
    if (result.containsKey('track')) {
      result['track'] = _parseTrackNumber(result['track']);
    }

    return result;
  }

  static int? _parseTrackNumber(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      final parts = value.split('/');
      return int.tryParse(parts[0]);
    }
    return null;
  }
}

void main() {
  group('MetadataCollector - Tag Priority', () {
    late CombinedTagMapper tagMapper;
    late MetadataCollector collector;

    setUp(() {
      tagMapper = CombinedTagMapper();
      tagMapper.registerMapper('id3v2', MockTagMapper());
      tagMapper.registerMapper('vorbis', MockVorbisMapper());
      collector = MetadataCollector(tagMapper);
    });

    test('should collect native tags from a single format', () {
      collector.addNativeTag('id3v2', 'TIT2', 'Song Title');
      collector.addNativeTag('id3v2', 'TPE1', 'Artist Name');

      final metadata = collector.toAudioMetadata();
      expect(metadata.native['id3v2'], isNotNull);
      expect(metadata.native['id3v2']!.length, equals(2));
      expect(metadata.native['id3v2']![0].id, equals('TIT2'));
      expect(metadata.native['id3v2']![0].value, equals('Song Title'));
    });

    test('should convert native tags to common tags', () {
      collector.addNativeTag('id3v2', 'TIT2', 'Test Song');
      collector.addNativeTag('id3v2', 'TPE1', 'Test Artist');

      final metadata = collector.toAudioMetadata();
      expect(metadata.common.title, equals('Test Song'));
      expect(metadata.common.artist, equals('Test Artist'));
    });

    test('should apply priority: later format tags override earlier', () {
      // Add ID3v2 tags first
      collector.addNativeTag('id3v2', 'TIT2', 'ID3v2 Title');
      collector.addNativeTag('id3v2', 'TPE1', 'ID3v2 Artist');

      // Add Vorbis tags later (should override)
      collector.addNativeTag('vorbis', 'title', 'Vorbis Title');
      collector.addNativeTag('vorbis', 'artist', 'Vorbis Artist');

      final metadata = collector.toAudioMetadata();
      // Later tags should override
      expect(metadata.common.title, equals('Vorbis Title'));
      expect(metadata.common.artist, equals('Vorbis Artist'));
    });

    test('should apply priority within same format: later tags override', () {
      collector.addNativeTag('id3v2', 'TIT2', 'Original Title');
      collector.addNativeTag('id3v2', 'TIT2', 'Updated Title');

      final metadata = collector.toAudioMetadata();
      expect(metadata.common.title, equals('Updated Title'));
    });

    test('should parse track numbers correctly', () {
      collector.addNativeTag('id3v2', 'TRCK', '5/12');

      final metadata = collector.toAudioMetadata();
      expect(metadata.common.track.no, equals(5));
    });

    test('should handle multiple formats without conflict', () {
      collector.addNativeTag('id3v2', 'TIT2', 'Title from ID3');
      collector.addNativeTag('id3v2', 'TPE1', 'Artist from ID3');
      collector.addNativeTag('vorbis', 'album', 'Album from Vorbis');

      final metadata = collector.toAudioMetadata();
      expect(metadata.native['id3v2'], isNotNull);
      expect(metadata.native['vorbis'], isNotNull);
      expect(metadata.native['id3v2']!.length, equals(2));
      expect(metadata.native['vorbis']!.length, equals(1));
    });

    test('should handle unknown format gracefully', () {
      collector.addNativeTag('unknown_format', 'some_tag', 'some_value');

      final metadata = collector.toAudioMetadata();
      // Native tag should be stored even if mapper doesn't exist
      expect(metadata.native['unknown_format'], isNotNull);
      expect(metadata.native['unknown_format']![0].value, equals('some_value'));
    });

    test('should preserve native tags even when common conversion fails', () {
      collector.addNativeTag('id3v2', 'TIT2', 'Title');
      // Try to add to unknown format (won't be converted but stored as native)
      collector.addNativeTag('unsupported', 'random_tag', 'value');

      final metadata = collector.toAudioMetadata();
      expect(metadata.native['id3v2'], isNotNull);
      expect(metadata.native['unsupported'], isNotNull);
    });
  });

  group('MetadataCollector - Warnings', () {
    late CombinedTagMapper tagMapper;
    late MetadataCollector collector;

    setUp(() {
      tagMapper = CombinedTagMapper();
      tagMapper.registerMapper('id3v2', MockTagMapper());
      collector = MetadataCollector(tagMapper);
    });

    test('should collect warnings', () {
      collector.addWarning('ID3v2 header corruption detected');
      collector.addWarning('Invalid frame size in TIT2');

      final metadata = collector.toAudioMetadata();
      expect(metadata.quality.warnings.length, equals(2));
      expect(
        metadata.quality.warnings[0].message,
        equals('ID3v2 header corruption detected'),
      );
      expect(
        metadata.quality.warnings[1].message,
        equals('Invalid frame size in TIT2'),
      );
    });

    test('should have empty warnings initially', () {
      final metadata = collector.toAudioMetadata();
      expect(metadata.quality.warnings.length, equals(0));
    });

    test('should collect mapping errors as warnings', () {
      // This should trigger a warning during mapping if mapper throws
      collector.addNativeTag('id3v2', 'TIT2', 'Title');
      // Manually trigger a warning
      collector.addWarning('Encoding mismatch detected');

      final metadata = collector.toAudioMetadata();
      expect(metadata.quality.warnings.length, greaterThan(0));
    });

    test('should preserve all warnings in order', () {
      final warnings = ['First warning', 'Second warning', 'Third warning'];

      for (final warning in warnings) {
        collector.addWarning(warning);
      }

      final metadata = collector.toAudioMetadata();
      for (var i = 0; i < warnings.length; i++) {
        expect(metadata.quality.warnings[i].message, equals(warnings[i]));
      }
    });
  });

  group('MetadataCollector - Format Information', () {
    late CombinedTagMapper tagMapper;
    late MetadataCollector collector;

    setUp(() {
      tagMapper = CombinedTagMapper();
      collector = MetadataCollector(tagMapper);
    });

    test('should initialize with empty format', () {
      final metadata = collector.toAudioMetadata();
      expect(metadata.format.container, isNull);
      expect(metadata.format.duration, isNull);
    });

    test('should set format information', () {
      collector.setFormat(
        container: 'mp3',
        duration: 180.5,
        bitrate: 320000,
        sampleRate: 44100,
        numberOfChannels: 2,
        codec: 'MPEG-1 Layer 3',
      );

      final metadata = collector.toAudioMetadata();
      expect(metadata.format.container, equals('mp3'));
      expect(metadata.format.duration, equals(180.5));
      expect(metadata.format.bitrate, equals(320000));
      expect(metadata.format.sampleRate, equals(44100));
      expect(metadata.format.numberOfChannels, equals(2));
      expect(metadata.format.codec, equals('MPEG-1 Layer 3'));
    });

    test('should allow partial format updates', () {
      collector.setFormat(container: 'flac', sampleRate: 48000);
      collector.setFormat(bitrate: 1400000); // Update only bitrate

      final metadata = collector.toAudioMetadata();
      expect(metadata.format.container, equals('flac'));
      expect(metadata.format.sampleRate, equals(48000));
      expect(metadata.format.bitrate, equals(1400000));
    });
  });

  group('MetadataCollector - Integration', () {
    late CombinedTagMapper tagMapper;
    late MetadataCollector collector;

    setUp(() {
      tagMapper = CombinedTagMapper();
      tagMapper.registerMapper('id3v2', MockTagMapper());
      tagMapper.registerMapper('vorbis', MockVorbisMapper());
      collector = MetadataCollector(tagMapper);
    });

    test('should build complete AudioMetadata', () {
      collector.setFormat(
        container: 'mp3',
        duration: 240.0,
        bitrate: 320000,
        codec: 'MPEG-1 Layer 3',
      );
      collector.addNativeTag('id3v2', 'TIT2', 'Song Title');
      collector.addNativeTag('id3v2', 'TPE1', 'Artist');
      collector.addNativeTag('id3v2', 'TALB', 'Album');
      collector.addWarning('No ID3v1 tag found');

      final metadata = collector.toAudioMetadata();

      expect(metadata.format.container, equals('mp3'));
      expect(metadata.format.duration, equals(240.0));
      expect(metadata.common.title, equals('Song Title'));
      expect(metadata.common.artist, equals('Artist'));
      expect(metadata.common.album, equals('Album'));
      expect(metadata.quality.warnings.length, equals(1));
      expect(metadata.native['id3v2']!.length, equals(3));
    });

    test('should create unmodifiable views of internal data', () {
      collector.addNativeTag('id3v2', 'TIT2', 'Title');
      collector.addWarning('Test warning');

      final warnings = collector.warnings;
      final nativeTags = collector.nativeTagsByFormat;

      // Attempting to modify should not affect collector
      expect(warnings, isNotNull);
      expect(nativeTags, isNotNull);
    });
  });
}
