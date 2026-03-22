import 'package:test/test.dart';
import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/id3v2/id3v2_tag_map.dart';
import 'package:metadata_audio/src/model/types.dart';

void main() {
  group('MetadataCollector - Observer', () {
    test('emits events on format and common tag changes', () {
      final events = <MetadataEvent>[];

      final tagMapper = CombinedTagMapper()
        ..registerMapper('ID3v2.4', Id3v2TagMapper());

      final collector = MetadataCollector(
        tagMapper,
        observer: (event) {
          events.add(event);
        },
      );

      // Update format
      collector.setFormat(container: 'mp3', bitrate: 320000);

      expect(events.length, 2);
      expect(events[0].tag.type, 'format');
      expect(events[0].tag.id, 'container');
      expect(events[1].tag.type, 'format');
      expect(events[1].tag.id, 'bitrate');

      expect(events[1].metadata.format.container, 'mp3');
      expect(events[1].metadata.format.bitrate, 320000);

      events.clear();

      // Add a native tag that maps to common tag
      collector.addNativeTag('ID3v2.4', 'TIT2', 'Test Title');

      // The Id3v2TagMapper maps TIT2 to 'title'
      expect(events.length, 1);
      expect(events[0].tag.type, 'common');
      expect(events[0].tag.id, 'title');
      expect(events[0].metadata.common.title, 'Test Title');

      events.clear();

      // Update format again
      collector.setFormat(duration: 123.4);
      expect(events.length, 1);
      expect(events[0].tag.type, 'format');
      expect(events[0].tag.id, 'duration');
      expect(events[0].metadata.format.duration, 123.4);
    });
  });
}
