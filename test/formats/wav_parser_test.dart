import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';
import 'package:audio_metadata/src/wav/wave_chunk.dart';
import 'package:audio_metadata/src/wav/wave_loader.dart';
import 'package:test/test.dart';

void main() {
  group('WaveParser / WaveLoader', () {
    test('parses RIFF/WAVE fmt/data and LIST/INFO metadata', () async {
      final bytes = _buildWaveFile(
        formatTag: 0x0001,
        channels: 2,
        sampleRate: 1000,
        bitsPerSample: 16,
        dataSize: 4000,
        infoTags: const <String, String>{
          'INAM': 'Unit Test Title',
          'IART': 'Unit Test Artist',
          'IPRD': 'Unit Test Album',
          'ICRD': '2025-01-02',
        },
      );

      final loader = WaveLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(duration: true),
      );

      expect(metadata.format.container, 'WAVE');
      expect(metadata.format.codec, 'PCM');
      expect(metadata.format.numberOfChannels, 2);
      expect(metadata.format.sampleRate, 1000);
      expect(metadata.format.bitsPerSample, 16);
      expect(metadata.format.numberOfSamples, 1000);
      expect(metadata.format.duration, closeTo(1.0, 0.0001));
      expect(metadata.format.bitrate, 32000);
      expect(metadata.format.lossless, isTrue);
      expect(metadata.format.hasAudio, isTrue);
      expect(metadata.format.hasVideo, isFalse);

      expect(metadata.common.title, 'Unit Test Title');
      expect(metadata.common.artist, 'Unit Test Artist');
      expect(metadata.common.album, 'Unit Test Album');
      expect(metadata.common.date, '2025-01-02');

      final exifTags = metadata.native['exif'];
      expect(exifTags, isNotNull);
      expect(
        exifTags!.where((t) => t.id == 'INAM').single.value,
        'Unit Test Title',
      );
      expect(
        exifTags.where((t) => t.id == 'IART').single.value,
        'Unit Test Artist',
      );
    });

    test('uses fact chunk for duration and marks ADPCM as lossy', () async {
      final bytes = _buildWaveFile(
        formatTag: 0x0002,
        channels: 1,
        sampleRate: 8000,
        bitsPerSample: 4,
        blockAlign: 2,
        dataSize: 32000,
        factSampleLength: 16000,
        infoTags: const <String, String>{'INAM': 'ADPCM Test'},
      );

      final loader = WaveLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(duration: true),
      );

      expect(metadata.format.codec, 'ADPCM');
      expect(metadata.format.lossless, isFalse);
      expect(metadata.format.numberOfSamples, 16000);
      expect(metadata.format.duration, closeTo(2.0, 0.0001));
      expect(metadata.format.bitrate, 352000);
      expect(metadata.common.title, 'ADPCM Test');
    });

    test('parses embedded ID3v2 chunk', () async {
      final id3Payload = _buildId3v23Tag(title: 'Title From ID3 Chunk');
      final bytes = _buildWaveFile(
        formatTag: 0x0001,
        channels: 2,
        sampleRate: 44100,
        bitsPerSample: 16,
        dataSize: 176400,
        infoTags: const <String, String>{},
        id3Chunk: id3Payload,
      );

      final loader = WaveLoader();
      final metadata = await loader.parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.common.title, 'Title From ID3 Chunk');
      final id3Tags = metadata.native['ID3v2.3'];
      expect(id3Tags, isNotNull);
      expect(
        id3Tags!.where((t) => t.id == 'TIT2').single.value,
        'Title From ID3 Chunk',
      );
    });

    test('parses cue points and adtl labels into format.chapters', () async {
      final bytes = _buildWaveFile(
        formatTag: 0x0001,
        channels: 2,
        sampleRate: 1000,
        bitsPerSample: 16,
        dataSize: 8000,
        infoTags: const <String, String>{},
        cuePoints: const <Map<String, Object>>[
          <String, Object>{'id': 1, 'sampleOffset': 0},
          <String, Object>{'id': 2, 'sampleOffset': 2500},
        ],
        adtlLabels: const <int, String>{1: 'Intro', 2: 'Hook'},
      );

      final metadata = await WaveLoader().parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(includeChapters: true, duration: true),
      );

      expect(metadata.format.chapters, isNotNull);
      expect(metadata.format.chapters, hasLength(2));
      expect(metadata.format.chapters![0].title, 'Intro');
      expect(metadata.format.chapters![0].start, 0);
      expect(metadata.format.chapters![0].end, 2500);
      expect(metadata.format.chapters![1].title, 'Hook');
      expect(metadata.format.chapters![1].start, 2500);
      expect(metadata.format.chapters![1].end, isNull);
    });

    test('throws on unsupported RIFF type', () async {
      final bytes = _buildRiff('NOTW', const <List<int>>[]);
      final loader = WaveLoader();

      await expectLater(
        loader.parse(
          BytesTokenizer(Uint8List.fromList(bytes)),
          const ParseOptions(),
        ),
        throwsA(isA<WaveContentError>()),
      );
    });

    test('loader declares extensions, mime types and seek requirement', () {
      final loader = WaveLoader();

      expect(loader.extension, containsAll(<String>['wav', 'wave']));
      expect(
        loader.mimeType,
        containsAll(<String>['audio/wav', 'audio/x-wav', 'audio/wave']),
      );
      expect(loader.hasRandomAccessRequirements, isTrue);
      expect(loader.supports(_NonSeekTokenizer()), isFalse);
    });
  });
}

List<int> _buildWaveFile({
  required int formatTag,
  required int channels,
  required int sampleRate,
  required int bitsPerSample,
  required int dataSize,
  required Map<String, String> infoTags,
  int? blockAlign,
  int? factSampleLength,
  List<int>? id3Chunk,
  List<Map<String, Object>>? cuePoints,
  Map<int, String>? adtlLabels,
}) {
  final resolvedBlockAlign =
      blockAlign ?? ((channels * bitsPerSample + 7) ~/ 8);
  final avgBytesPerSec = sampleRate * resolvedBlockAlign;

  final chunks = <List<int>>[
    _chunk('fmt ', <int>[
      ..._u16le(formatTag),
      ..._u16le(channels),
      ..._u32le(sampleRate),
      ..._u32le(avgBytesPerSec),
      ..._u16le(resolvedBlockAlign),
      ..._u16le(bitsPerSample),
    ]),
  ];

  if (factSampleLength != null) {
    chunks.add(_chunk('fact', _u32le(factSampleLength)));
  }

  if (infoTags.isNotEmpty) {
    final infoPayload = <int>[...ascii.encode('INFO')];
    for (final entry in infoTags.entries) {
      infoPayload.addAll(_chunk(entry.key, ascii.encode('${entry.value}\x00')));
    }
    chunks.add(_chunk('LIST', infoPayload));
  }

  if (id3Chunk != null) {
    chunks.add(_chunk('ID3 ', id3Chunk));
  }

  if (cuePoints != null && cuePoints.isNotEmpty) {
    chunks.add(_chunk('cue ', _buildCueChunk(cuePoints)));
  }

  if (adtlLabels != null && adtlLabels.isNotEmpty) {
    final adtlPayload = <int>[...ascii.encode('adtl')];
    for (final entry in adtlLabels.entries) {
      adtlPayload.addAll(
        _chunk('labl', <int>[
          ..._u32le(entry.key),
          ...ascii.encode('${entry.value}\x00'),
        ]),
      );
    }
    chunks.add(_chunk('LIST', adtlPayload));
  }

  chunks.add(_chunk('data', List<int>.filled(dataSize, 0)));

  return _buildRiff('WAVE', chunks);
}

List<int> _buildRiff(String type, List<List<int>> chunks) {
  final payload = <int>[
    ...ascii.encode(type),
    for (final chunk in chunks) ...chunk,
  ];
  return <int>[...ascii.encode('RIFF'), ..._u32le(payload.length), ...payload];
}

List<int> _chunk(String id, List<int> payload) {
  final padded = payload.length.isOdd ? <int>[...payload, 0] : payload;
  return <int>[...ascii.encode(id), ..._u32le(payload.length), ...padded];
}

List<int> _buildId3v23Tag({required String title}) {
  final titlePayload = <int>[0x00, ...latin1.encode(title)];
  final frame = <int>[
    ...ascii.encode('TIT2'),
    ..._u32be(titlePayload.length),
    0x00,
    0x00,
    ...titlePayload,
  ];

  return <int>[
    ...ascii.encode('ID3'),
    0x03,
    0x00,
    0x00,
    ..._synchsafe(frame.length),
    ...frame,
  ];
}

List<int> _buildCueChunk(List<Map<String, Object>> points) {
  final payload = <int>[..._u32le(points.length)];
  for (final point in points) {
    final id = point['id']! as int;
    final sampleOffset = point['sampleOffset']! as int;
    payload.addAll(<int>[
      ..._u32le(id),
      ..._u32le(0),
      ...ascii.encode('data'),
      ..._u32le(0),
      ..._u32le(0),
      ..._u32le(sampleOffset),
    ]);
  }
  return payload;
}

List<int> _u16le(int value) => <int>[value & 0xFF, (value >> 8) & 0xFF];

List<int> _u32le(int value) => <int>[
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ];

List<int> _u32be(int value) => <int>[
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];

List<int> _synchsafe(int value) => <int>[
    (value >> 21) & 0x7F,
    (value >> 14) & 0x7F,
    (value >> 7) & 0x7F,
    value & 0x7F,
  ];

class _NonSeekTokenizer extends Tokenizer {
  @override
  bool get canSeek => false;

  @override
  FileInfo? get fileInfo => const FileInfo();

  @override
  int get position => 0;

  @override
  int peekUint8() => throw TokenizerException('peek unsupported');

  @override
  List<int> peekBytes(int length) =>
      throw TokenizerException('peek unsupported');

  @override
  int readUint8() => throw TokenizerException('read unsupported');

  @override
  int readUint16() => throw TokenizerException('read unsupported');

  @override
  int readUint32() => throw TokenizerException('read unsupported');

  @override
  List<int> readBytes(int length) =>
      throw TokenizerException('read unsupported');

  @override
  void seek(int position) => throw TokenizerException('seek unsupported');

  @override
  void skip(int length) => throw TokenizerException('skip unsupported');
}
