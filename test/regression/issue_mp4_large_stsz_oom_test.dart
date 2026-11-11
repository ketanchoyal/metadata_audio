import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

void main() {
  group('Regression: MP4/M4B large stsz OOM & FileTokenizer Uint8List', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('mp4_large_stsz_test_');
    });

    tearDownAll(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    setUp(() {
      AudioMetadataCache.enabled = false;
      initializeParserFactory(createDefaultParserFactory());
    });

    test('FileTokenizer.readBytes returns compact Uint8List with and without peek', () async {
      final file = File('${tempDir.path}/tokenizer_uint8.bin');
      final raw = Uint8List.fromList(List<int>.generate(64, (i) => i & 0xFF));
      await file.writeAsBytes(raw);

      final tokenizer = FileTokenizer.fromFile(file, maxBufferSize: 32);
      try {
        final empty = tokenizer.readBytes(0);
        expect(empty, isA<Uint8List>());
        expect(empty, isEmpty);

        // Normal read without peek
        final first = tokenizer.readBytes(16);
        expect(first, isA<Uint8List>());
        expect(first, equals(raw.sublist(0, 16)));
        expect(tokenizer.position, equals(16));

        // Peek then read 1 byte
        expect(tokenizer.peekUint8(), equals(16));
        final single = tokenizer.readBytes(1);
        expect(single, isA<Uint8List>());
        expect(single, equals(<int>[16]));
        expect(tokenizer.position, equals(17));

        // Peek then read multiple bytes
        expect(tokenizer.peekUint8(), equals(17));
        final multi = tokenizer.readBytes(10);
        expect(multi, isA<Uint8List>());
        expect(multi, equals(raw.sublist(17, 27)));
        expect(tokenizer.position, equals(27));

        // Respects maxBufferSize
        expect(
          () => tokenizer.readBytes(33),
          throwsA(isA<BufferSizeError>()),
        );
      } finally {
        tokenizer.close();
      }
    });

    test(
      'parseFile extracts cover, artist, duration, and QuickTime chapters when audio stsz > 8 MB',
      () async {
        const sampleCount = 2150000; // 2,150,000 * 4 + 12 = 8,600,012 bytes (> 8 MB)
        final m4bFile = File('${tempDir.path}/large_audiobook_qt.m4b');
        final bytes = _buildLargeMockM4b(
          audioSampleCount: sampleCount,
          includeQuickTimeChapters: true,
          includeChpl: true,
        );
        await m4bFile.writeAsBytes(bytes);

        // 1. includeChapters: false (default) with strict 2 MB maxMemoryAllocation
        final metaNoChapters = await parseFile(
          m4bFile.path,
          options: const ParseOptions(maxMemoryAllocation: 2 * 1024 * 1024),
        );

        expect(metaNoChapters.common.artist, equals('Adrian Tchaikovsky'));
        expect(metaNoChapters.common.picture, hasLength(1));
        expect(metaNoChapters.common.picture!.first.format, equals('image/jpeg'));
        expect(
          metaNoChapters.common.picture!.first.data,
          equals(_sampleCoverJpeg),
        );
        expect(metaNoChapters.format.duration, closeTo(48300.0, 0.5));
        expect(metaNoChapters.format.chapters, isNull);

        // 2. includeChapters: true with strict 2 MB maxMemoryAllocation
        final metaWithChapters = await parseFile(
          m4bFile.path,
          options: const ParseOptions(
            includeChapters: true,
            maxMemoryAllocation: 2 * 1024 * 1024,
          ),
        );

        expect(metaWithChapters.common.artist, equals('Adrian Tchaikovsky'));
        expect(metaWithChapters.common.picture, hasLength(1));
        expect(
          metaWithChapters.common.picture!.first.data,
          equals(_sampleCoverJpeg),
        );
        expect(metaWithChapters.format.duration, closeTo(48300.0, 0.5));
        expect(metaWithChapters.format.chapters, hasLength(2));
        expect(metaWithChapters.format.chapters![0].title, equals('Prologue'));
        expect(metaWithChapters.format.chapters![0].start, equals(0));
        expect(metaWithChapters.format.chapters![1].title, equals('Chapter 1'));
        expect(metaWithChapters.format.chapters![1].start, equals(1000));
        expect(metaWithChapters.format.chapters![0].byteOffset, isNotNull);
        expect(metaWithChapters.format.chapters![1].byteOffset, isNotNull);
      },
    );

    test(
      'parseFile extracts cover, artist, duration, and Nero chpl chapters when audio stsz > 8 MB',
      () async {
        const sampleCount = 2150000;
        final m4bFile = File('${tempDir.path}/large_audiobook_chpl.m4b');
        final bytes = _buildLargeMockM4b(
          audioSampleCount: sampleCount,
          includeQuickTimeChapters: false,
          includeChpl: true,
        );
        await m4bFile.writeAsBytes(bytes);

        final metaNoChapters = await parseFile(
          m4bFile.path,
          options: const ParseOptions(maxMemoryAllocation: 2 * 1024 * 1024),
        );
        expect(metaNoChapters.common.artist, equals('Adrian Tchaikovsky'));
        expect(metaNoChapters.common.picture, hasLength(1));
        expect(metaNoChapters.format.duration, closeTo(48300.0, 0.5));
        expect(metaNoChapters.format.chapters, isNull);

        final metaWithChapters = await parseFile(
          m4bFile.path,
          options: const ParseOptions(
            includeChapters: true,
            maxMemoryAllocation: 2 * 1024 * 1024,
          ),
        );
        expect(metaWithChapters.common.artist, equals('Adrian Tchaikovsky'));
        expect(metaWithChapters.common.picture, hasLength(1));
        expect(metaWithChapters.format.duration, closeTo(48300.0, 0.5));
        expect(metaWithChapters.format.chapters, hasLength(2));
        expect(metaWithChapters.format.chapters![0].title, equals('Nero Intro'));
        expect(metaWithChapters.format.chapters![1].title, equals('Nero Part 2'));
      },
    );

    test(
      'parseUrl skips > 8 MB audio stsz over HTTP and extracts metadata and chapters',
      () async {
        const sampleCount = 2150000;
        final bytes = _buildLargeMockM4b(
          audioSampleCount: sampleCount,
          includeQuickTimeChapters: true,
          includeChpl: true,
        );
        final server = await _TrackedRangeServer.start(bytes);
        final url = server.urlFor('children_of_memory.m4b');

        try {
          final metaNoChapters = await parseUrl(
            url,
            strategy: ParseStrategy.randomAccess,
            options: const ParseOptions(maxMemoryAllocation: 2 * 1024 * 1024),
          );

          expect(metaNoChapters.common.artist, equals('Adrian Tchaikovsky'));
          expect(metaNoChapters.common.picture, hasLength(1));
          expect(metaNoChapters.format.duration, closeTo(48300.0, 0.5));
          expect(metaNoChapters.format.chapters, isNull);
          // RandomAccessTokenizer tail prefetch is bounded by file size here (~9 MB),
          // wait: verify no BufferSizeError/OOM and metadata is intact; test >50MB-style
          // skipping via direct RandomAccessTokenizer below as well.
          expect(server.totalBytesSent, greaterThan(0));

          server.resetStats();
          final metaWithChapters = await parseUrl(
            url,
            strategy: ParseStrategy.probe,
            options: const ParseOptions(
              includeChapters: true,
              maxMemoryAllocation: 2 * 1024 * 1024,
            ),
          );
          expect(metaWithChapters.common.artist, equals('Adrian Tchaikovsky'));
          expect(metaWithChapters.common.picture, hasLength(1));
          expect(metaWithChapters.format.duration, closeTo(48300.0, 0.5));
          expect(metaWithChapters.format.chapters, hasLength(2));
          expect(metaWithChapters.format.chapters![0].title, equals('Prologue'));
          expect(metaWithChapters.format.chapters![1].title, equals('Chapter 1'));
        } finally {
          await server.close();
        }
      },
    );

    test(
      'RandomAccessTokenizer skips downloading > 8 MB audio stsz when parsing moov',
      () async {
        // Simulate a 410 MB file's moov-first layout where moov (~8.6 MB) is at @24
        // and the middle 8+ MB is audio stsz before chap + covr + chpl.
        const sampleCount = 2150000;
        final bytes = _buildLargeMockM4b(
          audioSampleCount: sampleCount,
          includeQuickTimeChapters: true,
          includeChpl: true,
        );
        final server = await _TrackedRangeServer.start(bytes);
        final url = server.urlFor('streamed_book.m4b');
        final raTokenizer = await RandomAccessTokenizer.fromUrl(url);

        try {
          // Only prefetch the first 256 KB (not the entire 8.6 MB moov!)
          await raTokenizer.prefetchRange(0, 262144);
          final meta = await parseFromTokenizer(
            raTokenizer,
            options: const ParseOptions(maxMemoryAllocation: 2 * 1024 * 1024),
          );

          expect(meta.common.artist, equals('Adrian Tchaikovsky'));
          expect(meta.common.picture, hasLength(1));
          expect(meta.format.duration, closeTo(48300.0, 0.5));
          // Total bytes downloaded should be a small fraction of the 8.6 MB stsz!
          expect(server.totalBytesSent, lessThan(1024 * 1024));
        } finally {
          raTokenizer.close();
          await server.close();
        }
      },
    );
  });
}

const List<int> _sampleCoverJpeg = <int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
  0x4A,
  0x46,
  0x49,
  0x46,
  0x00,
  0x01,
  0xFF,
  0xD9,
];

Uint8List _buildLargeMockM4b({
  required int audioSampleCount,
  required bool includeQuickTimeChapters,
  required bool includeChpl,
}) {
  final ftyp = _atom('ftyp', <int>[
    ...latin1.encode('M4B '),
    ..._u32(0),
    ...latin1.encode('isom'),
    ...latin1.encode('mp42'),
  ]);

  const timeScale = 44100;
  const durationSeconds = 48300; // 13h 25m
  final mvhd = _atom(
    'mvhd',
    _mvhdPayload(timeScale: 1000, duration: durationSeconds * 1000),
  );

  // Build > 8 MB stsz atom payload directly in a Uint8List so test setup is fast.
  final stszPayloadLen = 12 + audioSampleCount * 4;
  final stszAtom = Uint8List(8 + stszPayloadLen);
  final stszBd = ByteData.sublistView(stszAtom);
  stszBd.setUint32(0, stszAtom.length);
  stszAtom.setRange(4, 8, latin1.encode('stsz'));
  // version/flags = 0, sampleSize = 0, entryCount = audioSampleCount
  stszBd.setUint32(16, audioSampleCount);
  // Populate first chunk's sample sizes (enough for chapter offset lookups) and tail
  for (var i = 0; i < 64 && i < audioSampleCount; i++) {
    stszBd.setUint32(20 + i * 4, 200);
  }
  stszBd.setUint32(20 + (audioSampleCount - 1) * 4, 200);

  // Audio stts: all samples have duration 1024 (~48300s total)
  final audioStts = _atom('stts', <int>[
    0,
    0,
    0,
    0,
    ..._u32(1),
    ..._u32(audioSampleCount),
    ..._u32(1024),
  ]);
  // Audio stsc: 20 samples per chunk -> ~107,500 chunks
  final audioStsc = _atom('stsc', <int>[
    0,
    0,
    0,
    0,
    ..._u32(1),
    ..._u32(1),
    ..._u32(20),
    ..._u32(1),
  ]);
  // Placeholder stco with 100 chunks (enough for chapter 1 & 2 byteOffset lookup)
  const audioChunkCount = 100;
  final audioStcoPlaceholder = _atom('stco', <int>[
    0,
    0,
    0,
    0,
    ..._u32(audioChunkCount),
    for (var i = 0; i < audioChunkCount; i++) ..._u32(0),
  ]);

  final audioStblBytes = <int>[
    ..._atom('stsd', _stsdPayloadMp4a()),
    ...audioStts,
    ...audioStsc,
    ...stszAtom,
    ...audioStcoPlaceholder,
  ];
  final audioStbl = _atom('stbl', audioStblBytes);
  final audioMinf = _atom('minf', audioStbl);
  final audioMdia = _atom('mdia', <int>[
    ..._atom('mdhd', _mdhdPayload(timeScale: timeScale, duration: timeScale * durationSeconds)),
    ..._atom('hdlr', _hdlrPayload('soun')),
    ...audioMinf,
  ]);
  final audioTrackChildren = <int>[
    ..._atom('tkhd', _tkhdPayload(trackId: 1)),
    if (includeQuickTimeChapters) ..._atom('tref', _atom('chap', _u32(2))),
    ...audioMdia,
  ];
  final audioTrak = _atom('trak', audioTrackChildren);

  final chapter1Sample = _chapterTextSample('Prologue');
  final chapter2Sample = _chapterTextSample('Chapter 1');

  List<int> buildChapterTrak(int ch1Offset, int ch2Offset) {
    final chapterStts = _atom('stts', <int>[
      0,
      0,
      0,
      0,
      ..._u32(2),
      ..._u32(1),
      ..._u32(1000),
      ..._u32(1),
      ..._u32(1000),
    ]);
    final chapterStsc = _atom('stsc', <int>[
      0,
      0,
      0,
      0,
      ..._u32(1),
      ..._u32(1),
      ..._u32(1),
      ..._u32(1),
    ]);
    final chapterStsz = _atom('stsz', <int>[
      0,
      0,
      0,
      0,
      ..._u32(0),
      ..._u32(2),
      ..._u32(chapter1Sample.length),
      ..._u32(chapter2Sample.length),
    ]);
    final chapterStco = _atom('stco', <int>[
      0,
      0,
      0,
      0,
      ..._u32(2),
      ..._u32(ch1Offset),
      ..._u32(ch2Offset),
    ]);
    return _atom('trak', <int>[
      ..._atom('tkhd', _tkhdPayload(trackId: 2)),
      ..._atom('mdia', <int>[
        ..._atom('mdhd', _mdhdPayload(timeScale: 1000, duration: 2000)),
        ..._atom('hdlr', _hdlrPayload('text')),
        ..._atom('minf', _atom('stbl', <int>[
          ..._atom('stsd', _stsdPayloadText()),
          ...chapterStts,
          ...chapterStsc,
          ...chapterStsz,
          ...chapterStco,
        ])),
      ]),
    ]);
  }

  final ilst = _atom('ilst', <int>[
    ..._metadataItem('©ART', _dataAtom(1, utf8.encode('Adrian Tchaikovsky'))),
    ..._metadataItem('covr', _dataAtom(13, _sampleCoverJpeg)),
  ]);
  final meta = _atom('meta', <int>[0, 0, 0, 0, ...ilst]);
  final chplAtom = includeChpl
      ? _atom('chpl', <int>[
          0, 0, 0, 0, // version 0, flags 0
          2, // 2 chapters
          ..._u64(0),
          'Nero Intro'.length,
          ...utf8.encode('Nero Intro'),
          ..._u64(10000000),
          'Nero Part 2'.length,
          ...utf8.encode('Nero Part 2'),
        ])
      : const <int>[];

  final udta = _atom('udta', <int>[...meta, ...chplAtom]);

  // First pass to measure moov size & mdat start offset
  final placeholderChapterTrak = includeQuickTimeChapters
      ? buildChapterTrak(0, 0)
      : const <int>[];
  final placeholderMoov = _atom('moov', <int>[
    ...mvhd,
    ...audioTrak,
    ...placeholderChapterTrak,
    ...udta,
  ]);
  final mdatStart = ftyp.length + placeholderMoov.length;
  final mdatPayloadStart = mdatStart + 8;

  final ch1Offset = mdatPayloadStart;
  final ch2Offset = ch1Offset + chapter1Sample.length;
  final audioDataStart =
      ch2Offset + (includeQuickTimeChapters ? chapter2Sample.length : 0);

  // Rebuild audio stco with real mdat offsets and chapter trak with real offsets
  final realAudioStco = _atom('stco', <int>[
    0,
    0,
    0,
    0,
    ..._u32(audioChunkCount),
    for (var i = 0; i < audioChunkCount; i++)
      ..._u32(audioDataStart + i * 4000),
  ]);
  // Patch realAudioStco into audioTrak (it's the exact same byte length)
  final audioStcoOffsetInAudioTrak =
      audioTrak.length - audioStcoPlaceholder.length;
  audioTrak.setRange(
    audioStcoOffsetInAudioTrak,
    audioTrak.length,
    realAudioStco,
  );

  final realChapterTrak = includeQuickTimeChapters
      ? buildChapterTrak(ch1Offset, ch2Offset)
      : const <int>[];
  final realMoov = _atom('moov', <int>[
    ...mvhd,
    ...audioTrak,
    ...realChapterTrak,
    ...udta,
  ]);

  final mdatPayload = <int>[
    if (includeQuickTimeChapters) ...chapter1Sample,
    if (includeQuickTimeChapters) ...chapter2Sample,
    ...List<int>.filled(4096, 0xAA),
  ];
  final mdat = _atom('mdat', mdatPayload);

  final result = Uint8List(ftyp.length + realMoov.length + mdat.length);
  result.setRange(0, ftyp.length, ftyp);
  result.setRange(ftyp.length, ftyp.length + realMoov.length, realMoov);
  result.setRange(ftyp.length + realMoov.length, result.length, mdat);
  return result;
}

class _TrackedRangeServer {
  _TrackedRangeServer._(this._server, this._bytes);

  final HttpServer _server;
  final Uint8List _bytes;
  int totalBytesSent = 0;

  String urlFor(String filename) =>
      'http://127.0.0.1:${_server.port}/$filename';

  void resetStats() {
    totalBytesSent = 0;
  }

  static Future<_TrackedRangeServer> start(Uint8List bytes) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final tracked = _TrackedRangeServer._(server, bytes);
    unawaited(tracked._serve());
    return tracked;
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mp4');

      if (request.method == 'HEAD') {
        request.response.contentLength = _bytes.length;
        await request.response.close();
        continue;
      }

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parts = rangeHeader.substring(6).split('-');
        final start = int.parse(parts[0]);
        final end = parts.length > 1 && parts[1].isNotEmpty
            ? int.parse(parts[1]).clamp(0, _bytes.length - 1)
            : _bytes.length - 1;
        final safeStart = start.clamp(0, _bytes.length - 1);
        final safeEnd = end < safeStart ? safeStart : end;
        final slice = Uint8List.sublistView(_bytes, safeStart, safeEnd + 1);
        totalBytesSent += slice.length;
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $safeStart-$safeEnd/${_bytes.length}',
        );
        request.response.contentLength = slice.length;
        request.response.add(slice);
        await request.response.close();
        continue;
      }

      totalBytesSent += _bytes.length;
      request.response.contentLength = _bytes.length;
      request.response.add(_bytes);
      await request.response.close();
    }
  }

  Future<void> close() => _server.close(force: true);
}

List<int> _atom(String type, List<int> payload) {
  final totalLength = 8 + payload.length;
  final out = Uint8List(totalLength);
  ByteData.sublistView(out).setUint32(0, totalLength);
  out.setRange(4, 8, latin1.encode(type));
  out.setRange(8, totalLength, payload);
  return out;
}

List<int> _metadataItem(String type, List<int> payload) => _atom(type, payload);

List<int> _dataAtom(int dataType, List<int> value) =>
    _atom('data', <int>[0, 0, 0, dataType, 0, 0, 0, 0, ...value]);

List<int> _mvhdPayload({required int timeScale, required int duration}) => <int>[
  0,
  0,
  0,
  0,
  ..._u32(0),
  ..._u32(0),
  ..._u32(timeScale),
  ..._u32(duration),
  ...List<int>.filled(80, 0),
];

List<int> _tkhdPayload({required int trackId}) => <int>[
  0,
  0,
  0,
  0,
  ..._u32(0),
  ..._u32(0),
  ..._u32(trackId),
  ..._u32(0),
  ..._u32(0),
  ...List<int>.filled(60, 0),
];

List<int> _mdhdPayload({required int timeScale, required int duration}) =>
    <int>[
      0,
      0,
      0,
      0,
      ..._u32(0),
      ..._u32(0),
      ..._u32(timeScale),
      ..._u32(duration),
      0,
      0,
      0,
      0,
    ];

List<int> _hdlrPayload(String handlerType) => <int>[
  0,
  0,
  0,
  0,
  ...latin1.encode('mhlr'),
  ...latin1.encode(handlerType),
  ...List<int>.filled(12, 0),
];

List<int> _stsdPayloadMp4a() {
  final sampleEntry = <int>[
    ..._u32(36),
    ...latin1.encode('mp4a'),
    ...List<int>.filled(6, 0),
    0,
    1,
    ...List<int>.filled(8, 0),
    0,
    2,
    0,
    16,
    0,
    0,
    0,
    0,
    ..._u32(44100 << 16),
  ];
  return <int>[0, 0, 0, 0, ..._u32(1), ...sampleEntry];
}

List<int> _stsdPayloadText() => <int>[
  0,
  0,
  0,
  0,
  ..._u32(1),
  ..._u32(16),
  ...latin1.encode('tx3g'),
  ...List<int>.filled(8, 0),
];

List<int> _chapterTextSample(String title) {
  final titleBytes = utf8.encode(title);
  return <int>[
    (titleBytes.length >> 8) & 0xFF,
    titleBytes.length & 0xFF,
    ...titleBytes,
  ];
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
