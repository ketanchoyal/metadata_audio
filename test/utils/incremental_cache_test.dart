import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

import '../id3/id3_test_utils.dart';

class _TrackedRangeServer {
  _TrackedRangeServer._(this._server, this._bytes);

  final HttpServer _server;
  final Uint8List _bytes;
  final List<({String method, String? range})> requests = [];

  int get port => _server.port;
  String get url => 'http://127.0.0.1:$port/audio.bin';

  static Future<_TrackedRangeServer> start(
    List<int> bytes, {
    String? pathSuffix,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final tracked = _TrackedRangeServer._(server, Uint8List.fromList(bytes));
    unawaited(tracked._serve(pathSuffix ?? '/audio.bin'));
    return tracked;
  }

  String urlFor(String filename) => 'http://127.0.0.1:$port/$filename';

  Future<void> _serve(String expectedPath) async {
    await for (final request in _server) {
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      requests.add((method: request.method, range: rangeHeader));

      final ext = request.uri.path.split('.').last.toLowerCase();
      final contentType = switch (ext) {
        'mp3' => 'audio/mpeg',
        'm4b' || 'm4a' || 'mp4' => 'audio/mp4',
        _ => 'application/octet-stream',
      };

      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);

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
        final slice = _bytes.sublist(safeStart, safeEnd + 1);
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

      request.response.contentLength = _bytes.length;
      request.response.add(_bytes);
      await request.response.close();
    }
  }

  Future<void> close() => _server.close(force: true);
}

void main() {
  late Directory testCacheDir;

  setUpAll(() async {
    testCacheDir = await Directory.systemTemp.createTemp(
      'metadata_audio_incremental_cache_',
    );
    AudioMetadataCache.overrideDirForTesting = testCacheDir;
  });

  tearDownAll(() async {
    AudioMetadataCache.overrideDirForTesting = null;
    if (testCacheDir.existsSync()) {
      await testCacheDir.delete(recursive: true);
    }
  });

  setUp(() async {
    cacheEnabled = false;
    AudioMetadataCache.overrideHasIoForTesting = null;
    await AudioMetadataCache.clearCache();
  });

  tearDown(() async {
    cacheEnabled = false;
    AudioMetadataCache.overrideHasIoForTesting = null;
    await AudioMetadataCache.clearCache();
  });

  group('Global cache option', () {
    test('cacheEnabled enables caching across parseFile without useCache', () async {
      expect(cacheEnabled, isFalse);
      cacheEnabled = true;
      expect(cacheEnabled, isTrue);
      expect(AudioMetadataCache.enabled, isTrue);

      const path = 'test/samples/mp4/sample.m4a';
      final first = await parseFile(
        path,
        options: const ParseOptions(includeChapters: true),
      );

      // Even with a fresh ParseOptions() (useCache: false), second call hits cache.
      final second = await parseFile(
        path,
        options: const ParseOptions(includeChapters: true),
      );

      expect(second.common.title, equals(first.common.title));
      expect(second.format.duration, equals(first.format.duration));
      expect(AudioMetadataCache.getCacheSize(), greaterThan(0));
    });

    test('cacheEnabled works across parseUrl, parseBytes, parseStream, and respects toggling off', () async {
      final bytes = await File('test/samples/mp3/id3v2.3.mp3').readAsBytes();
      final server = await _TrackedRangeServer.start(bytes);
      final url = server.urlFor('global.mp3');
      try {
        cacheEnabled = true;

        // 1. parseUrl caches without ParseOptions.useCache
        final urlFirst = await parseUrl(url);
        expect(server.requests, isNotEmpty);
        server.requests.clear();
        final urlSecond = await parseUrl(url);
        expect(server.requests, isEmpty);
        expect(urlSecond.common.title, equals(urlFirst.common.title));

        // 2. parseBytes caches under FileInfo url/path
        final bytesFirst = await parseBytes(
          bytes,
          fileInfo: FileInfo.fromUrl('https://example.com/bytes-global.mp3'),
        );
        final cachedEntry = await AudioMetadataCache.getEntry(
          'url:https://example.com/bytes-global.mp3',
        );
        expect(cachedEntry, isNotNull);
        expect(cachedEntry!.metadata.common.title, equals(bytesFirst.common.title));

        // 3. parseStream caches under FileInfo path
        final streamFirst = await parseStream(
          Stream.value(bytes),
          fileInfo: FileInfo.fromPath('virtual/stream-global.mp3'),
        );
        final cachedStream = await AudioMetadataCache.getEntry(
          'path:virtual/stream-global.mp3',
        );
        expect(cachedStream, isNotNull);
        expect(
          cachedStream!.metadata.common.title,
          equals(streamFirst.common.title),
        );

        // 4. Toggling cacheEnabled off stops automatic caching for new URLs
        cacheEnabled = false;
        server.requests.clear();
        final uncachedUrl = server.urlFor('uncached.mp3');
        await parseUrl(uncachedUrl);
        final firstReqCount = server.requests.length;
        expect(firstReqCount, greaterThan(0));
        server.requests.clear();
        await parseUrl(uncachedUrl);
        expect(server.requests, isNotEmpty);
      } finally {
        await server.close();
      }
    });
  });

  group('URL-only cache key and incremental ParseOptions fetching', () {
    test('MP4 URL: includeChapters=false then true fetches ONLY chapter samples', () async {
      final fileBytes = await File('test/samples/mp4/video_chapters.mp4').readAsBytes();
      final server = await _TrackedRangeServer.start(fileBytes);
      final url = server.urlFor('book.mp4');
      try {
        cacheEnabled = true;

        // Run 1: chapters disabled
        final m1 = await parseUrl(url);
        expect(m1.format.chapters, isNull);
        expect(m1.format.hasAudio, isTrue);
        final run1Requests = server.requests.length;
        expect(run1Requests, greaterThan(0));

        // Run 2: chapters enabled on same URL
        server.requests.clear();
        final m2 = await parseUrl(
          url,
          options: const ParseOptions(includeChapters: true),
        );
        expect(m2.format.chapters, isNotNull);
        expect(m2.format.chapters, isNotEmpty);
        expect(m2.format.hasAudio, isTrue);

        // Should NOT do a HEAD or full-file GET; either 0 requests (if chpl)
        // or targeted Range requests only.
        for (final req in server.requests) {
          expect(req.method, equals('GET'));
          expect(req.range, isNotNull);
        }

        // Run 3: repeat with chapters enabled -> 0 HTTP requests!
        server.requests.clear();
        final m3 = await parseUrl(
          url,
          options: const ParseOptions(includeChapters: true),
        );
        expect(server.requests, isEmpty);
        expect(m3.format.chapters!.length, equals(m2.format.chapters!.length));

        // Run 4: request with includeChapters=false -> 0 HTTP requests, chapters null!
        server.requests.clear();
        final m4 = await parseUrl(url);
        expect(server.requests, isEmpty);
        expect(m4.format.chapters, isNull);
      } finally {
        await server.close();
      }
    });

    test('MP4 URL (Nero chpl): includeChapters=false then true needs 0 HTTP requests', () async {
      final chplBytes = _buildSyntheticChplMp4();
      final server = await _TrackedRangeServer.start(chplBytes);
      final url = server.urlFor('nero.m4b');
      try {
        cacheEnabled = true;

        final m1 = await parseUrl(url);
        expect(m1.format.chapters, isNull);
        expect(m1.common.title, equals('Nero Book'));

        server.requests.clear();
        final m2 = await parseUrl(
          url,
          options: const ParseOptions(includeChapters: true),
        );
        expect(server.requests, isEmpty);
        expect(m2.format.chapters, hasLength(2));
        expect(m2.format.chapters!.first.title, equals('Chapter One'));
        expect(m2.common.title, equals('Nero Book'));
      } finally {
        await server.close();
      }
    });

    test('MP4 URL: skipCovers=true then false fetches moov only and preserves chapters', () async {
      final mp4Bytes = _buildSyntheticChplMp4(includeCover: true);
      final server = await _TrackedRangeServer.start(mp4Bytes);
      final url = server.urlFor('cover.m4a');
      try {
        cacheEnabled = true;

        // Run 1: skipCovers=true, includeChapters=true
        final m1 = await parseUrl(
          url,
          options: const ParseOptions(skipCovers: true, includeChapters: true),
        );
        expect(m1.common.picture, isNull);
        expect(m1.format.chapters, hasLength(2));

        // Run 2: skipCovers=false
        server.requests.clear();
        final m2 = await parseUrl(
          url,
          options: const ParseOptions(includeChapters: true),
        );
        expect(m2.common.picture, isNotNull);
        expect(m2.common.picture!.first.data, equals([1, 2, 3, 4]));
        expect(m2.format.chapters, hasLength(2));
        for (final req in server.requests) {
          expect(req.method, equals('GET'));
          expect(req.range, isNotNull);
        }

        // Run 3: skipCovers=true again -> 0 HTTP requests & picture omitted in view
        server.requests.clear();
        final m3 = await parseUrl(
          url,
          options: const ParseOptions(skipCovers: true),
        );
        expect(server.requests, isEmpty);
        expect(m3.common.picture, isNull);
      } finally {
        await server.close();
      }
    });

    test('MP3 URL: skipPostHeaders=true then false fetches only last 128 bytes', () async {
      final mp3Bytes = <int>[
        ...buildId3Tag(
          majorVersion: 3,
          revision: 0,
          flags: 0x00,
          payload: buildId3v23Frame('TIT2', [0x03, ...utf8.encode('ID3v2 Title')]),
        ),
        ..._buildMpegFrame(includeXing: true),
        ..._buildId3v1(title: 'ID3v1 Title', album: 'Tail Album'),
      ];
      final server = await _TrackedRangeServer.start(mp3Bytes);
      final url = server.urlFor('track.mp3');
      try {
        cacheEnabled = true;

        final m1 = await parseUrl(
          url,
          options: const ParseOptions(skipPostHeaders: true),
        );
        expect(m1.common.title, equals('ID3v2 Title'));
        expect(m1.common.album, isNull);

        server.requests.clear();
        final m2 = await parseUrl(url);
        expect(server.requests, hasLength(1));
        expect(
          server.requests.first.range,
          equals('bytes=${mp3Bytes.length - 128}-${mp3Bytes.length - 1}'),
        );
        // ID3v2 priority kept for title; ID3v1 fills album!
        expect(m2.common.title, equals('ID3v2 Title'));
        expect(m2.common.album, equals('Tail Album'));
      } finally {
        await server.close();
      }
    });

    test('MP3 URL: chapters & covers incrementally fetched from ID3v2 header only, then duration=true', () async {
      final id3 = buildId3Tag(
        majorVersion: 4,
        revision: 0,
        flags: 0x00,
        payload: [
          ...buildId3v24Frame('TIT2', [0x03, ...utf8.encode('Podcast Ep')]),
          ..._buildChapFrame(1, startTime: 0, endTime: 1000, title: 'Intro'),
          ..._buildChapFrame(2, startTime: 1000, endTime: 2000, title: 'Main'),
          ...buildId3v24Frame('APIC', [
            0x00, // latin1
            ...ascii.encode('image/jpeg'),
            0x00,
            0x03, // front cover
            0x00,
            1, 2, 3, 4,
          ]),
        ],
      );
      final mp3Bytes = <int>[
        ...id3,
        ..._buildMpegFrame(),
        ..._buildMpegFrame(bitrateIndex: 11),
        ..._buildMpegFrame(bitrateIndex: 10),
        ..._buildMpegFrame(),
        ..._buildMpegFrame(bitrateIndex: 11),
      ];
      final server = await _TrackedRangeServer.start(mp3Bytes);
      final url = server.urlFor('podcast.mp3');
      try {
        cacheEnabled = true;

        // Run 1: minimal options
        final m1 = await parseUrl(
          url,
          options: const ParseOptions(skipCovers: true),
        );
        expect(m1.common.title, equals('Podcast Ep'));
        expect(m1.format.chapters, isNull);
        expect(m1.common.picture, isNull);
        expect(m1.format.numberOfSamples, isNull);

        // Run 2: enable chapters -> fetches only ID3v2 header range!
        server.requests.clear();
        final m2 = await parseUrl(
          url,
          options: const ParseOptions(
            includeChapters: true,
            skipCovers: true,
          ),
        );
        expect(server.requests, hasLength(1));
        expect(server.requests.first.range, equals('bytes=0-${id3.length - 1}'));
        expect(m2.format.chapters, hasLength(2));
        expect(
          m2.native['ID3v2.4']!.any((t) => t.id == 'APIC'),
          isFalse,
        );

        // Run 3: enable covers -> fetches only ID3v2 header range, keeps chapters!
        server.requests.clear();
        final m3 = await parseUrl(
          url,
          options: const ParseOptions(includeChapters: true),
        );
        expect(server.requests, hasLength(1));
        expect(server.requests.first.range, equals('bytes=0-${id3.length - 1}'));
        final apicTag = m3.native['ID3v2.4']!.firstWhere(
          (t) => t.id == 'APIC',
        );
        expect((apicTag.value as Picture).data, equals([1, 2, 3, 4]));
        expect(m3.format.chapters, hasLength(2));

        // Run 4: enable duration -> computes exact numberOfSamples, keeps chapters!
        final m4 = await parseUrl(
          url,
          options: const ParseOptions(
            includeChapters: true,
            duration: true,
          ),
        );
        expect(m4.format.numberOfSamples, equals(5 * 1152));
        expect(m4.format.chapters, hasLength(2));
      } finally {
        await server.close();
      }
    });
  });

  group('Incremental cache for maxChapterCount, observer, and web mode', () {
    test('maxChapterCount expands when higher limit is requested', () async {
      final tag = buildId3Tag(
        majorVersion: 4,
        revision: 0,
        flags: 0x00,
        payload: [
          for (var i = 0; i < 4; i++)
            ..._buildChapFrame(
              i,
              startTime: i * 1000,
              endTime: (i + 1) * 1000,
              title: 'Ch $i',
            ),
        ],
      );
      final bytes = Uint8List.fromList(<int>[...tag, ..._buildMpegFrame()]);

      cacheEnabled = true;
      final first = await parseBytes(
        bytes,
        fileInfo: FileInfo.fromUrl('https://example.com/4ch.mp3'),
        options: const ParseOptions(includeChapters: true, maxChapterCount: 2),
      );
      expect(first.format.chapters, hasLength(2));

      final second = await parseBytes(
        bytes,
        fileInfo: FileInfo.fromUrl('https://example.com/4ch.mp3'),
        options: const ParseOptions(includeChapters: true, maxChapterCount: 10),
      );
      expect(second.format.chapters, hasLength(4));

      // Shrinking back slices from cache without re-parsing
      final third = await parseBytes(
        bytes,
        fileInfo: FileInfo.fromUrl('https://example.com/4ch.mp3'),
        options: const ParseOptions(includeChapters: true, maxChapterCount: 1),
      );
      expect(third.format.chapters, hasLength(1));
    });

    test('observer receives metadata events on cache hit and web mode works incrementally', () async {
      AudioMetadataCache.overrideHasIoForTesting = false;
      cacheEnabled = true;

      const path = 'test/samples/mp4/video_chapters.mp4';
      await parseFile(path);

      final events = <MetadataEvent>[];
      final second = await parseFile(
        path,
        options: ParseOptions(
          includeChapters: true,
          observer: events.add,
        ),
      );

      expect(second.format.chapters, isNotEmpty);
      expect(events, isNotEmpty);
    });

    test('ParseOptions.minimal -> ParseOptions.all escalates cleanly on single URL key', () async {
      final id3 = buildId3Tag(
        majorVersion: 4,
        revision: 0,
        flags: 0x00,
        payload: [
          ...buildId3v24Frame('TIT2', [0x03, ...utf8.encode('Escalate Title')]),
          ..._buildChapFrame(1, startTime: 0, endTime: 1000, title: 'Part 1'),
          ...buildId3v24Frame('APIC', [
            0x00,
            ...ascii.encode('image/jpeg'),
            0x00,
            0x03,
            0x00,
            7, 8, 9,
          ]),
        ],
      );
      final mp3Bytes = <int>[
        ...id3,
        ..._buildMpegFrame(),
        ..._buildMpegFrame(bitrateIndex: 11),
        ..._buildMpegFrame(bitrateIndex: 10),
        ..._buildMpegFrame(),
        ..._buildMpegFrame(bitrateIndex: 11),
        ..._buildId3v1(title: 'Ignored V1', album: 'V1 Album'),
      ];
      final server = await _TrackedRangeServer.start(mp3Bytes);
      final url = server.urlFor('escalate.mp3');
      try {
        cacheEnabled = true;

        final minRes = await parseUrl(url, options: ParseOptions.minimal());
        expect(minRes.common.title, equals('Escalate Title'));
        expect(minRes.format.chapters, isNull);
        expect(minRes.common.album, isNull);
        expect(
          minRes.native['ID3v2.4']!.any((t) => t.id == 'APIC'),
          isFalse,
        );

        final allRes = await parseUrl(url, options: ParseOptions.all());
        expect(allRes.common.title, equals('Escalate Title'));
        expect(allRes.common.album, equals('V1 Album'));
        expect(allRes.format.chapters, hasLength(1));
        expect(allRes.format.chapters!.first.title, equals('Part 1'));
        expect(allRes.format.numberOfSamples, equals(5 * 1152));
        expect(
          allRes.native['ID3v2.4']!.any((t) => t.id == 'APIC'),
          isTrue,
        );

        // Next call with ParseOptions.all() makes 0 HTTP requests
        server.requests.clear();
        final cachedAll = await parseUrl(url, options: ParseOptions.all());
        expect(server.requests, isEmpty);
        expect(cachedAll.format.chapters, hasLength(1));
        expect(cachedAll.common.album, equals('V1 Album'));
      } finally {
        await server.close();
      }
    });

    test('non-truncated maxChapterCount, non-MPEG skipPostHeaders/duration make 0 HTTP calls', () async {
      final chplBytes = _buildSyntheticChplMp4();
      final server = await _TrackedRangeServer.start(chplBytes);
      final url = server.urlFor('non_trunc.m4b');
      try {
        cacheEnabled = true;

        // File has 2 chapters, ask for up to 5 (not truncated) with
        // skipPostHeaders=true and duration=false.
        final first = await parseUrl(
          url,
          options: const ParseOptions(
            includeChapters: true,
            maxChapterCount: 5,
            skipPostHeaders: true,
          ),
        );
        expect(first.format.chapters, hasLength(2));

        // Increasing maxChapterCount=100, skipPostHeaders=false, duration=true
        // on MP4 requires 0 extra HTTP calls.
        server.requests.clear();
        final second = await parseUrl(
          url,
          options: const ParseOptions(
            includeChapters: true,
            maxChapterCount: 100,
            duration: true,
          ),
        );
        expect(server.requests, isEmpty);
        expect(second.format.chapters, hasLength(2));
      } finally {
        await server.close();
      }
    });

    test('custom cacheKey, maxMetadataEntries, evict, and mkvUseIndex work incrementally', () async {
      final id3 = buildId3Tag(
        majorVersion: 4,
        revision: 0,
        flags: 0x00,
        payload: [
          ...buildId3v24Frame('TIT2', [0x03, ...utf8.encode('Custom Key Song')]),
          ..._buildChapFrame(1, startTime: 0, endTime: 500, title: 'Chapter A'),
        ],
      );
      final bytes = Uint8List.fromList(<int>[...id3, ..._buildMpegFrame()]);

      // 1. Custom cacheKey reuses partial parse incrementally without useCache=true
      const customKey = 'my-custom-audio-key';
      final r1 = await parseBytes(
        bytes,
        options: const ParseOptions(cacheKey: customKey, maxMetadataEntries: 5),
      );
      expect(r1.common.title, equals('Custom Key Song'));
      expect(r1.format.chapters, isNull);

      final r2 = await parseBytes(
        bytes,
        options: const ParseOptions(
          cacheKey: customKey,
          includeChapters: true,
          maxMetadataEntries: 50,
        ),
      );
      expect(r2.format.chapters, hasLength(1));
      expect(r2.format.chapters!.first.title, equals('Chapter A'));

      // Evicting removes the entry cleanly
      await AudioMetadataCache.evict(customKey);
      expect(await AudioMetadataCache.getEntry(customKey), isNull);

      // 2. Matroska mkvUseIndex=true -> false -> true and skipCovers=true -> false
      cacheEnabled = true;
      final mkvBytes = Uint8List.fromList(_buildMatroskaSample());
      final mkvInfo = FileInfo.fromUrl('https://example.com/sample.mkv');
      final mkv1 = await parseBytes(
        mkvBytes,
        fileInfo: mkvInfo,
        options: const ParseOptions(mkvUseIndex: true, skipCovers: true),
      );
      expect(mkv1.common.picture, isNull);
      expect(mkv1.format.chapters, isNull);

      final mkv2 = await parseBytes(
        mkvBytes,
        fileInfo: mkvInfo,
        options: const ParseOptions(includeChapters: true),
      );
      expect(mkv2.format.chapters, hasLength(1));
      expect(mkv2.format.chapters!.first.title, equals('Intro'));
      expect(mkv2.common.picture, hasLength(1));
    });
  });
}

List<int> _buildChapFrame(
  int index, {
  required int startTime,
  required int endTime,
  required String title,
}) {
  final sub = buildId3v24Frame('TIT2', [0x03, ...utf8.encode(title)]);
  final payload = <int>[
    ...utf8.encode('ch$index'),
    0x00,
    (startTime >> 24) & 0xFF,
    (startTime >> 16) & 0xFF,
    (startTime >> 8) & 0xFF,
    startTime & 0xFF,
    (endTime >> 24) & 0xFF,
    (endTime >> 16) & 0xFF,
    (endTime >> 8) & 0xFF,
    endTime & 0xFF,
    0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF, 0xFF,
    ...sub,
  ];
  return buildId3v24Frame('CHAP', payload);
}

List<int> _buildMpegFrame({int bitrateIndex = 9, bool includeXing = false}) {
  const sampleRate = 44100;
  const samplesPerFrame = 1152;
  const table = <int, int>{
    9: 128,
    10: 160,
    11: 192,
  };
  final bitrate = (table[bitrateIndex] ?? 128) * 1000;
  final frameLength = (samplesPerFrame / 8 * bitrate / sampleRate).floor();
  final header = <int>[0xFF, 0xFB, bitrateIndex << 4, 0x40];
  final payload = List<int>.filled(frameLength - 4, 0);
  if (includeXing) {
    payload.setRange(32, 36, 'Xing'.codeUnits);
    payload.setRange(36, 40, const [0x00, 0x00, 0x00, 0x01]); // frames flag
    payload.setRange(40, 44, const [0x00, 0x00, 0x00, 0x64]); // 100 frames
  }
  return <int>[...header, ...payload];
}

List<int> _buildId3v1({required String title, required String album}) {
  final tag = List<int>.filled(128, 0);
  tag[0] = 0x54;
  tag[1] = 0x41;
  tag[2] = 0x47;
  final tBytes = ascii.encode(title);
  for (var i = 0; i < tBytes.length && i < 30; i++) {
    tag[3 + i] = tBytes[i];
  }
  final aBytes = ascii.encode(album);
  for (var i = 0; i < aBytes.length && i < 30; i++) {
    tag[63 + i] = aBytes[i];
  }
  return tag;
}

List<int> _u32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

List<int> _atom(String name, List<int> payload) => [
  ..._u32(8 + payload.length),
  ...latin1.encode(name),
  ...payload,
];

List<int> _buildSyntheticChplMp4({bool includeCover = false}) {
  final ftyp = _atom('ftyp', [
    ...latin1.encode('M4B '),
    ...latin1.encode('isom'),
  ]);
  final mvhd = _atom('mvhd', [
    0, 0, 0, 0,
    ..._u32(0), ..._u32(0),
    ..._u32(1000), ..._u32(4000),
    ...List<int>.filled(80, 0),
  ]);
  final titleData = _atom('data', [0, 0, 0, 1, 0, 0, 0, 0, ...utf8.encode('Nero Book')]);
  final ilstChildren = <int>[..._atom('©nam', titleData)];
  if (includeCover) {
    final covrData = _atom('data', [0, 0, 0, 13, 0, 0, 0, 0, 1, 2, 3, 4]);
    ilstChildren.addAll(_atom('covr', covrData));
  }
  final ilst = _atom('ilst', ilstChildren);
  final meta = _atom('meta', [0, 0, 0, 0, ...ilst]);

  List<int> chplEntry(int ms, String title) {
    final ticks = ms * 10000;
    final tBytes = utf8.encode(title);
    return [
      0, 0, 0, 0,
      (ticks >> 24) & 0xFF,
      (ticks >> 16) & 0xFF,
      (ticks >> 8) & 0xFF,
      ticks & 0xFF,
      tBytes.length,
      ...tBytes,
    ];
  }

  final chpl = _atom('chpl', [
    0x01, 0, 0, 0, // version 1
    0, 0, 0, 0, // reserved
    2, // 2 chapters
    ...chplEntry(0, 'Chapter One'),
    ...chplEntry(2000, 'Chapter Two'),
  ]);

  final udta = _atom('udta', [...meta, ...chpl]);
  final moov = _atom('moov', [...mvhd, ...udta]);
  return [...ftyp, ...moov];
}

List<int> _ebmlElement(List<int> id, List<int> payload) => <int>[
  ...id,
  ..._ebmlSize(payload.length),
  ...payload,
];

List<int> _ebmlUint(int value) {
  if (value == 0) return const <int>[0x00];
  final bytes = <int>[];
  var remaining = value;
  while (remaining > 0) {
    bytes.insert(0, remaining & 0xFF);
    remaining >>= 8;
  }
  return bytes;
}

List<int> _ebmlSize(int value) {
  if (value <= 0x7F) return <int>[0x80 | value];
  if (value <= 0x3FFF) return <int>[0x40 | ((value >> 8) & 0x3F), value & 0xFF];
  throw ArgumentError('Unsupported EBML size: $value');
}

List<int> _buildMatroskaSample() {
  final ebmlHeader = _ebmlElement(const [0x1A, 0x45, 0xDF, 0xA3], const []);
  final f64 = (ByteData(8)..setFloat64(0, 5000)).buffer.asUint8List();
  final f32 = (ByteData(4)..setFloat32(0, 48000)).buffer.asUint8List();

  final info = _ebmlElement(const [0x15, 0x49, 0xA9, 0x66], [
    ..._ebmlElement(const [0x2A, 0xD7, 0xB1], _ebmlUint(1000000)),
    ..._ebmlElement(const [0x44, 0x89], f64),
  ]);
  final tracks = _ebmlElement(
    const [0x16, 0x54, 0xAE, 0x6B],
    _ebmlElement(const [0xAE], [
      ..._ebmlElement(const [0xD7], _ebmlUint(1)),
      ..._ebmlElement(const [0x83], _ebmlUint(2)),
      ..._ebmlElement(const [0x86], utf8.encode('A_OPUS')),
      ..._ebmlElement(const [0xE1], [
        ..._ebmlElement(const [0xB5], f32),
        ..._ebmlElement(const [0x9F], _ebmlUint(2)),
      ]),
    ]),
  );
  final attachments = _ebmlElement(
    const [0x19, 0x41, 0xA4, 0x69],
    _ebmlElement(const [0x61, 0xA7], [
      ..._ebmlElement(const [0x46, 0x6E], utf8.encode('cover.jpg')),
      ..._ebmlElement(const [0x46, 0x60], utf8.encode('image/jpeg')),
      ..._ebmlElement(const [0x46, 0x5C], const [0x11, 0x22, 0x33]),
    ]),
  );
  final chapterAtom = _ebmlElement(const [0xB6], [
    ..._ebmlElement(const [0x73, 0xC4], const [0x01]),
    ..._ebmlElement(const [0x91], _ebmlUint(0)),
    ..._ebmlElement(const [0x92], _ebmlUint(5000000000)),
    ..._ebmlElement(
      const [0x8F],
      _ebmlElement(
        const [0x80],
        _ebmlElement(const [0x85], utf8.encode('Intro')),
      ),
    ),
  ]);
  final chapters = _ebmlElement(
    const [0x10, 0x43, 0xA7, 0x70],
    _ebmlElement(const [0x45, 0xB9], chapterAtom),
  );
  final segment = _ebmlElement(
    const [0x18, 0x53, 0x80, 0x67],
    [...info, ...tracks, ...attachments, ...chapters],
  );
  return [...ebmlHeader, ...segment];
}
