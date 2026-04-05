import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/mp4/mp4_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('MP4/M4A file parsing (real samples)', () {
    setUp(() {
      final registry = ParserRegistry()..register(Mp4Loader());
      initializeParserFactory(ParserFactory(registry));
    });

    test('parses sample.m4a', () async {
      final file = File(p.join(samplePath, 'mp4', 'sample.m4a'));
      if (!file.existsSync()) {
        markTestSkipped('Sample file not found: ${file.path}');
        return;
      }

      final metadata = await parseFile(
        file.path,
        options: const ParseOptions(includeChapters: true),
      );

      checkFormat(metadata.format, container: 'M4A/isom/iso2');

      // Should have iTunes atoms
      expect(metadata.native.containsKey('iTunes'), isTrue);

      // Verify chapters
      expect(metadata.format.chapters, isNotNull);
      expect(metadata.format.chapters!.length, 3);
      expect(metadata.format.chapters![0].title, 'Chapter 1');
      expect(metadata.format.chapters![0].start, 0);
      expect(metadata.format.chapters![1].title, 'Chapter 2');
      expect(metadata.format.chapters![1].start, 2000);
      expect(metadata.format.chapters![2].title, 'Chapter 3');
      expect(metadata.format.chapters![2].start, 4000);
    });

    test(
      'parses mirrored Dune m4b sample with version 1 mvhd timestamps',
      () async {
        // This fixture mirrors the failure mode from the shared audiobook URL:
        // version 1 mvhd fields with very large 64-bit timestamps.
        final file = await _writeMirroredMvhdSample();
        addTearDown(() async {
          if (await file.exists()) {
            await file.delete();
          }
        });

        final metadata = await parseFile(
          file.path,
          options: const ParseOptions(duration: true),
        );

        expect(metadata.format.container, startsWith('M4A/isom'));
        expect(
          metadata.format.creationTime,
          DateTime.fromMillisecondsSinceEpoch(8640000000000000, isUtc: true),
        );
        expect(
          metadata.format.modificationTime,
          DateTime.fromMillisecondsSinceEpoch(8640000000000000, isUtc: true),
        );
        expect(metadata.format.duration, closeTo(2.0, 0.0001));
      },
    );
  });
}

Future<File> _writeMirroredMvhdSample() async {
  final file = File(
    p.join(
      Directory.systemTemp.path,
      'metadata_audio_mirrored_mvhd_v1_${DateTime.now().microsecondsSinceEpoch}.m4b',
    ),
  );
  await file.writeAsBytes(_buildMirroredMvhdSample());
  return file;
}

List<int> _buildMirroredMvhdSample() {
  final ftyp = _atom('ftyp', <int>[
    ...latin1.encode('M4A '),
    ...latin1.encode('isom'),
    ...latin1.encode('mp42'),
  ]);

  final mvhd = _atom(
    'mvhd',
    _mvhdPayloadV1(
      creationTime: BigInt.parse('9223372036854775807'),
      modificationTime: BigInt.parse('9223372036854775807'),
      timeScale: 1000,
      duration: 2000,
    ),
  );

  final moov = _atom('moov', mvhd);
  return <int>[...ftyp, ...moov];
}

List<int> _mvhdPayloadV1({
  required Object creationTime,
  required Object modificationTime,
  required int timeScale,
  required Object duration,
}) => <int>[
  1,
  0,
  0,
  0,
  ..._u64Value(creationTime),
  ..._u64Value(modificationTime),
  ..._u32(timeScale),
  ..._u64Value(duration),
  ...List<int>.filled(80, 0),
];

List<int> _atom(String name, List<int> payload) {
  final length = 8 + payload.length;
  return <int>[..._u32(length), ...latin1.encode(name), ...payload];
}

List<int> _u32(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _u64(int value) => <int>[
  (value >> 56) & 0xFF,
  (value >> 48) & 0xFF,
  (value >> 40) & 0xFF,
  (value >> 32) & 0xFF,
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _u64Value(Object value) {
  if (value is int) {
    return _u64(value);
  }
  if (value is BigInt) {
    return _u64BigInt(value);
  }
  throw ArgumentError.value(value, 'value', 'Expected int or BigInt');
}

List<int> _u64BigInt(BigInt value) => <int>[
  ((value >> 56) & BigInt.from(0xFF)).toInt(),
  ((value >> 48) & BigInt.from(0xFF)).toInt(),
  ((value >> 40) & BigInt.from(0xFF)).toInt(),
  ((value >> 32) & BigInt.from(0xFF)).toInt(),
  ((value >> 24) & BigInt.from(0xFF)).toInt(),
  ((value >> 16) & BigInt.from(0xFF)).toInt(),
  ((value >> 8) & BigInt.from(0xFF)).toInt(),
  (value & BigInt.from(0xFF)).toInt(),
];
