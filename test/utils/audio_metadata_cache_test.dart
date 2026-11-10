import 'dart:io';

import 'package:metadata_audio/src/core.dart';
import 'package:metadata_audio/src/utils/audio_metadata_cache.dart';
import 'package:test/test.dart';

void main() {
  late Directory testCacheDir;

  setUpAll(() async {
    testCacheDir = await Directory.systemTemp.createTemp(
      'metadata_audio_cache_unit_',
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
    AudioMetadataCache.enabled = false;
    AudioMetadataCache.overrideHasIoForTesting = null;
    await AudioMetadataCache.clearCache();
  });

  tearDown(() async {
    AudioMetadataCache.enabled = false;
    AudioMetadataCache.overrideHasIoForTesting = null;
    await AudioMetadataCache.clearCache();
  });

  group('AudioMetadataCache general metadata', () {
    test('round-trips metadata for a non-MP4 format (MP3)', () async {
      const path = 'test/samples/mp3/id3v2.3.mp3';

      final first = await parseFile(
        path,
        options: const ParseOptions(useCache: true),
      );

      // Second call should be served from disk cache.
      final second = await parseFile(
        path,
        options: const ParseOptions(useCache: true),
      );

      expect(second.common.title, first.common.title);
      expect(second.format.container, first.format.container);
      expect(second.format.duration, first.format.duration);
      expect(second.quality.warnings.length, first.quality.warnings.length);
    });

    test('IO mode does not store items in memory', () async {
      AudioMetadataCache.overrideHasIoForTesting = true;
      const path = 'test/samples/mp3/id3v2.3.mp3';

      final metadata = await parseFile(path);

      await AudioMetadataCache.putMetadata('io-key', metadata);

      // In IO mode, in-memory caches must remain empty
      expect(AudioMetadataCache.metaMemCacheSize, equals(0));
      expect(AudioMetadataCache.memCacheSize, equals(0));

      // Reading back from cache should still succeed from disk
      final fromDisk = await AudioMetadataCache.getMetadata('io-key');
      expect(fromDisk, isNotNull);
      expect(fromDisk!.common.title, equals(metadata.common.title));

      // After reading, in-memory cache must STILL remain 0
      expect(AudioMetadataCache.metaMemCacheSize, equals(0));
    });

    test('CachedAudioTrack in IO mode does not use in-memory cache', () async {
      AudioMetadataCache.overrideHasIoForTesting = true;
      const testUrl = 'https://example.com/audiobook.m4b';

      const track = CachedAudioTrack(
        trackId: 1,
        timeScale: 44100,
        sampleRate: 44100,
        numberOfChannels: 2,
        sampleSize: 16,
        sampleSizeTable: [],
        timeToSampleTable: [],
        sampleToChunkTable: [],
        chunkOffsetTable: [1000, 2000],
      );

      await AudioMetadataCache.put(testUrl, track);
      expect(AudioMetadataCache.memCacheSize, equals(0));

      final retrieved = await AudioMetadataCache.get(testUrl);
      expect(retrieved, isNotNull);
      expect(retrieved!.trackId, equals(1));
      expect(retrieved.chunkOffsetTable, equals([1000, 2000]));
      expect(AudioMetadataCache.memCacheSize, equals(0));
    });

    test('Web mode (no IO) uses in-memory cache', () async {
      AudioMetadataCache.overrideHasIoForTesting = false;
      expect(AudioMetadataCache.hasIo, isFalse);

      const path = 'test/samples/mp3/id3v2.3.mp3';
      final metadata = await parseFile(path);

      await AudioMetadataCache.putMetadata('test-web-key', metadata);
      expect(AudioMetadataCache.metaMemCacheSize, equals(1));

      final retrieved = await AudioMetadataCache.getMetadata('test-web-key');
      expect(retrieved, isNotNull);
      expect(retrieved!.common.title, equals(metadata.common.title));

      // Track cache in web mode
      const track = CachedAudioTrack(
        trackId: 2,
        timeScale: 48000,
        sampleRate: 48000,
        numberOfChannels: 2,
        sampleSize: 0,
        sampleSizeTable: [100, 200],
        timeToSampleTable: [],
        sampleToChunkTable: [],
        chunkOffsetTable: [5000],
      );

      await AudioMetadataCache.put('https://web.example.com/audio.m4b', track);
      expect(AudioMetadataCache.memCacheSize, equals(1));

      final retrievedTrack = await AudioMetadataCache.get(
        'https://web.example.com/audio.m4b',
      );
      expect(retrievedTrack, isNotNull);
      expect(retrievedTrack!.trackId, equals(2));
      expect(retrievedTrack.sampleSizeTable, equals([100, 200]));

      // getCacheSize is 0 in web mode
      expect(AudioMetadataCache.getCacheSize(), equals(0));

      // clearCache clears in-memory caches
      await AudioMetadataCache.clearCache();
      expect(AudioMetadataCache.metaMemCacheSize, equals(0));
      expect(AudioMetadataCache.memCacheSize, equals(0));
    });

    test(
      'Web mode evicts oldest entry when exceeding maxMemoryCacheEntries',
      () async {
        AudioMetadataCache.overrideHasIoForTesting = false;

        const path = 'test/samples/mp3/id3v2.3.mp3';
        final metadata = await parseFile(path);

        for (var i = 0; i < 105; i++) {
          await AudioMetadataCache.putMetadata('key-$i', metadata);
        }

        expect(AudioMetadataCache.metaMemCacheSize, equals(100));
        // First entries should have been evicted
        expect(await AudioMetadataCache.getMetadata('key-0'), isNull);
        expect(await AudioMetadataCache.getMetadata('key-1'), isNull);
        expect(await AudioMetadataCache.getMetadata('key-104'), isNotNull);
      },
    );

    test('putMetadata respects maxMemoryAllocation cap', () async {
      AudioMetadataCache.overrideHasIoForTesting = false;

      const path = 'test/samples/mp3/id3v2.3.mp3';
      final metadata = await parseFile(path);

      // Attempt to put with very small maxMemoryAllocation (e.g. 10 bytes)
      await AudioMetadataCache.putMetadata(
        'tiny-cap-key',
        metadata,
        maxMemoryAllocation: 10,
      );

      // Payload exceeds 10 bytes, so it should not be stored
      expect(AudioMetadataCache.metaMemCacheSize, equals(0));
      expect(await AudioMetadataCache.getMetadata('tiny-cap-key'), isNull);
    });
  });
}
