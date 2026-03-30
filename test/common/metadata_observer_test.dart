import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/src/common/case_insensitive_tag_map.dart';
import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/generic_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/mp4/mp4_loader.dart';
import 'package:metadata_audio/src/mpeg/mpeg_loader.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:test/test.dart';

class _SimpleObserverMapper extends GenericTagMapper {
  @override
  CaseInsensitiveTagMap<String> get tagMap {
    final map = CaseInsensitiveTagMap<String>();
    map['title'] = 'title';
    return map;
  }
}

void main() {
  final darkForestSample = File(
    '${Directory.current.path}/test/samples/mp4/The Dark Forest.m4a',
  );

  group('MetadataObserver', () {
    test('collector emits format and common tag events with snapshots', () {
      final mapper = CombinedTagMapper()
        ..registerMapper('test', _SimpleObserverMapper());
      final events = <MetadataEvent>[];

      MetadataCollector(mapper, ParseOptions(observer: events.add))
        ..setFormat(container: 'mp3')
        ..addNativeTag('test', 'title', 'Observed Title');

      expect(events, hasLength(2));

      final formatEvent = events[0];
      expect(formatEvent.tag?.type, MetadataEventTagType.format);
      expect(formatEvent.tag?.id, MetadataFormatId.container);
      expect(formatEvent.tag?.value, 'mp3');
      expect(formatEvent.metadata?.format.container, 'mp3');

      final commonEvent = events[1];
      expect(commonEvent.tag?.type, MetadataEventTagType.common);
      expect(commonEvent.tag?.id, MetadataCommonId.title);
      expect(commonEvent.tag?.value, 'Observed Title');
      expect(commonEvent.metadata?.common.title, 'Observed Title');
      expect(commonEvent.metadata?.native['test']?.first.id, 'title');
    });

    test('loader parsing emits observer events from ParseOptions', () async {
      final events = <MetadataEvent>[];
      final bytes = <int>[
        ..._buildMpegFrame(),
        ..._buildId3v1(title: 'Tail Title'),
      ];

      await MpegLoader().parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        ParseOptions(observer: events.add),
      );

      expect(events, isNotEmpty);
      expect(
        events.any(
          (event) =>
              event.tag?.type == MetadataEventTagType.format &&
              event.tag?.id == MetadataFormatId.container &&
              event.tag?.value == 'mp3',
        ),
        isTrue,
      );
      expect(
        events.any(
          (event) =>
              event.tag?.type == MetadataEventTagType.common &&
              event.tag?.id == MetadataCommonId.title &&
              event.metadata?.common.title == 'Tail Title',
        ),
        isTrue,
      );
    });

    test(
      'file-based parsing emits metadata events before parsing completes',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'metadata_observer_',
        );
        final file = File('${tempDir.path}/live-events.mp3')
          ..writeAsBytesSync([
            ..._buildMpegFrame(),
            ..._buildId3v1(title: 'Live Title'),
          ]);

        var parseCompleted = false;
        var containerSeenWhilePending = false;
        var titleSeenWhilePending = false;
        final tokenizer = FileTokenizer.fromPath(file.path);

        try {
          final metadata = await MpegLoader().parse(
            tokenizer,
            ParseOptions(
              observer: (event) {
                if (event.tag?.id == MetadataFormatId.container &&
                    !parseCompleted) {
                  containerSeenWhilePending = true;
                }
                if (event.tag?.id == MetadataCommonId.title &&
                    !parseCompleted) {
                  titleSeenWhilePending = true;
                }
              },
            ),
          );
          parseCompleted = true;

          expect(metadata.common.title, 'Live Title');
          expect(containerSeenWhilePending, isTrue);
          expect(titleSeenWhilePending, isTrue);
          expect(parseCompleted, isTrue);
        } finally {
          tokenizer.close();
          if (file.existsSync()) {
            file.deleteSync();
          }
          if (tempDir.existsSync()) {
            tempDir.deleteSync();
          }
        }
      },
    );

    test(
      'file-based parsing emits chapter events before parsing completes',
      () async {
        var parseCompleted = false;
        var chaptersSeenWhilePending = false;

        final tokenizer = FileTokenizer.fromPath(darkForestSample.path);

        try {
          final metadata = await Mp4Loader().parse(
            tokenizer,
            ParseOptions(
              includeChapters: true,
              observer: (event) {
                if (event.tag?.id == MetadataFormatId.chapters &&
                    !parseCompleted) {
                  final chapters = event.tag?.value;
                  if (chapters is List<Chapter> && chapters.isNotEmpty) {
                    chaptersSeenWhilePending = true;
                  }
                }
              },
            ),
          );
          parseCompleted = true;

          expect(metadata.format.chapters, isNotNull);
          expect(metadata.format.chapters, isNotEmpty);
          expect(chaptersSeenWhilePending, isTrue);
          expect(parseCompleted, isTrue);
        } finally {
          tokenizer.close();
        }
      },
      skip: darkForestSample.existsSync()
          ? false
          : 'Local sample not available: ${darkForestSample.path}',
    );

    test('allows unknown IDs to be created manually', () {
      const unknownCommon = MetadataCommonId<Object?>('custom-common');
      const unknownFormat = MetadataFormatId<Object?>('custom-format');

      expect(unknownCommon.path, 'custom-common');
      expect(unknownFormat.path, 'custom-format');
    });

    test('ad hoc IDs compare equal to built-in constants', () {
      const dynamicTitle = MetadataCommonId<Object?>('title');
      const dynamicContainer = MetadataFormatId<Object?>('container');

      expect(dynamicTitle, MetadataCommonId.title);
      expect(dynamicContainer, MetadataFormatId.container);
      expect(dynamicTitle.path, MetadataCommonId.title.path);
      expect(dynamicContainer.path, MetadataFormatId.container.path);
    });

    test(
      'collector emits additional format fields using direct ID construction',
      () {
        final mapper = CombinedTagMapper();
        final events = <MetadataEvent>[];

        MetadataCollector(
          mapper,
          ParseOptions(observer: events.add),
        ).setFormat(container: 'mp3', duration: 12.5, hasAudio: true);

        expect(
          events.any(
            (event) =>
                event.tag?.type == MetadataEventTagType.format &&
                event.tag?.id == const MetadataFormatId<Object?>('duration') &&
                event.tag?.value == 12.5,
          ),
          isTrue,
        );
        expect(
          events.any(
            (event) =>
                event.tag?.type == MetadataEventTagType.format &&
                event.tag?.id == const MetadataFormatId<Object?>('hasAudio') &&
                event.tag?.value == true,
          ),
          isTrue,
        );
      },
    );
  });
}

List<int> _buildMpegFrame({int bitrateIndex = 9}) {
  const sampleRate = 44100;
  const samplesPerFrame = 1152;
  final bitrateKbps = _bitrateFromIndex(bitrateIndex);
  final bitrate = bitrateKbps * 1000;
  final frameLength = (samplesPerFrame / 8 * bitrate / sampleRate).floor();

  final header = <int>[0xFF, 0xFB, (bitrateIndex << 4), 0x40];
  final payload = List<int>.filled(frameLength - 4, 0);
  return <int>[...header, ...payload];
}

List<int> _buildId3v1({required String title}) {
  final tag = List<int>.filled(128, 0);
  tag[0] = 0x54;
  tag[1] = 0x41;
  tag[2] = 0x47;

  final titleBytes = title.codeUnits;
  for (var i = 0; i < titleBytes.length && i < 30; i++) {
    tag[3 + i] = titleBytes[i];
  }
  return tag;
}

int _bitrateFromIndex(int index) {
  const table = <int, int>{
    1: 32,
    2: 40,
    3: 48,
    4: 56,
    5: 64,
    6: 80,
    7: 96,
    8: 112,
    9: 128,
    10: 160,
    11: 192,
    12: 224,
    13: 256,
    14: 320,
  };
  return table[index] ?? 128;
}
