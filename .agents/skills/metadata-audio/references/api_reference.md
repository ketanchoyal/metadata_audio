# `metadata_audio` API Reference

All symbols below are exported from `package:metadata_audio/metadata_audio.dart`.

## `ParseOptions`

```dart
const ParseOptions({
  bool skipCovers = false,
  bool skipPostHeaders = false,
  bool includeChapters = false,
  bool duration = false,
  MetadataObserver? observer,
  int maxMemoryAllocation = 67108864, // 64 MiB per metadata read/block
  int? maxMetadataEntries,          // default: 100,000
  int? maxChapterCount,             // default: 1,000
  bool mkvUseIndex = false,
  String? cacheKey,
  bool useCache = false,
})
```

Factories:
- `ParseOptions.all(...)` — sets `includeChapters: true`, `duration: true`.
- `ParseOptions.minimal(...)` — fast mode (`skipCovers: true`, `skipPostHeaders: true`).

## Global Cache & Cache API

- `bool get cacheEnabled` / `set cacheEnabled(bool enabled)`
- `AudioMetadataCache.enabled` (bool, mirrors `cacheEnabled`)
- `AudioMetadataCache.maxMemoryCacheEntries` (in-memory Web / LRU bound)
- `Future<void> AudioMetadataCache.evict(String urlOrKey)`
- `Future<void> AudioMetadataCache.clearCache()`
- `int AudioMetadataCache.getCacheSize()` (total bytes on disk; `0` on Web)

Incremental cache coverage:
- Reuses cached fields on subsequent calls with the same URL/path/`cacheKey`.
- Automatically performs delta parsing/fetching when any previously skipped
  capability is newly enabled (`includeChapters`, `duration`, `skipCovers: false`,
  `skipPostHeaders: false`, `mkvUseIndex`, or a higher `maxChapterCount`).

## URL Strategy API

- `enum ParseStrategy { fullDownload, headerOnly, probe, randomAccess }`
- `enum ProbeStrategy { mp4, mpeg, auto }`
- `Future<StrategyInfo> detectStrategy(String url, {Duration timeout = const Duration(seconds: 10)})`
  - Fields on `StrategyInfo`: `strategy`, `supportsRange`, `fileSize`, `mimeType`,
    `detectedFormat`, `reason`.

## Core Model Properties (`AudioMetadata`)

- `metadata.format`:
  - `container`, `tagTypes`, `codec`, `codecProfile`, `duration` (seconds),
    `containerDuration`, `bitrate`, `overallBitrate`, `sampleRate`,
    `bitsPerSample`, `numberOfChannels`, `lossless`, `hasAudio`, `hasVideo`,
    `trackInfo` (`List<TrackInfo>`), `chapters` (`List<Chapter>?`), `tool`,
    `trackGain`, `trackPeakLevel`, `albumGain`.
- `metadata.common`:
  - `title`, `artist`, `artists`, `album`, `albumartist`, `albumartists`,
    `year`, `date`, `originaldate`, `genre`, `track` (`TrackNo`), `disk` (`TrackNo`),
    `movement`, `movementIndex` (`TrackNo`), `picture` (`List<Picture>?`),
    `comment` (`List<Comment>?`), `rating` (`List<Rating>?`), `lyrics`,
    `composer`, `publisher`, `description`, `podcast`, `podcastId`, `playCounter`,
    ReplayGain / level fields.
- `metadata.native`: `Map<String, List<Tag>>` keyed by tag format (e.g. `'iTunes'`,
  `'ID3v2.3'`, `'ID3v2.4'`, `'ID3v1'`, `'vorbis'`, `'APEv2'`, `'ASF'`).
- `metadata.quality`: `QualityInformation` containing parser `warnings`.

## Chapter Slicing (`ChapterDownloader`)

Supported containers: MP4 / M4B / M4A / MOV (produces `.m4a` or ADTS `.aac`) and
MP3 / MPEG (produces `.mp3`).

- `ChapterDownloader.downloadChapter(...) -> Future<ChapterDownloadResult>`
  - Params: `originalUrl` (HTTP/HTTPS URL or local file path), `chapterStartMs`,
    `chapterEndMs`, `outputPath`, `httpClient`, `onProgress`, `onPhase`
    (`ChapterDownloadPhase`: `connecting`, `analyzing`, `resolvingSamples`,
    `downloading`, `writing`), `parallelChunks = 4`, `includeMetadata = true`,
    `metadata` (optional fallback `AudioMetadata`).
- `ChapterDownloader.extractChapterBytes(...) -> Future<ChapterBytesResult>`
  - Params: `sourceBytes` (`Uint8List`), `chapterStartMs`, `chapterEndMs`,
    `fileName`, `wantsAac = false`, `onProgress`, `onPhase`,
    `includeMetadata = true`, `metadata`.
  - Result: `isSuccess`, `bytes` (`Uint8List?`), `extension` (`'m4a' | 'aac' | 'mp3'`),
    `mimeType` (`'audio/mp4' | 'audio/aac' | 'audio/mpeg'`), `error`.

Both slicing methods preserve cover art and safe metadata while stripping
whole-file chapters (`chpl`, `CHAP`, `CTOC`), whole-file durations (`TLEN`, `TLE`),
and seek/gapless tables (`iTunSMPB`, `pgap`, `MLLT`, `ASPI`, `SYLT`, `ETCO`,
`OverDrive MediaMarkers`).

## Helpers & Exceptions

Helpers:
- `Picture? selectCover(List<Picture>? pictures)`
- `int? ratingToStars(double? normalizedRating)` (returns `1`..`5` or `null`)
- `Map<String, List<dynamic>> orderTags(List<Tag> tags)`
- `List<String> getSupportedMimeTypes()`
- `Map<String, dynamic> audioMetadataToJson(AudioMetadata meta)`
- `AudioMetadata audioMetadataFromJson(Map<String, dynamic> map)`

Exceptions (`lib/src/parse_error.dart` and `lib/src/tokenizer/tokenizer.dart`):
- `ParseError` (base)
  - `CouldNotDetermineFileTypeError`
  - `UnsupportedFileTypeError`
  - `UnexpectedFileContentError` (`fileType`, `message`)
  - `FieldDecodingError`
  - `NotRegularFileError`
  - `InternalParserError`
- `TokenizerException`
  - `BufferSizeError` (`requestedSize`, `maxBufferSize`)
