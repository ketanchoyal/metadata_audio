---
name: metadata-audio
description: >-
  Use this skill when building or debugging Dart or Flutter code that uses the
  `metadata_audio` package to parse audio metadata from local files, in-memory
  bytes, or HTTP URLs, read artwork/chapters/stream info, configure incremental
  metadata caching, or extract standalone playable `.m4a` / `.mp3` chapters.
---

# Using `metadata_audio`

`package:metadata_audio` is a pure-Dart audio metadata parser and chapter slicer
supporting MP3, MP4/M4A/M4B/MOV, FLAC, Ogg (Vorbis/Opus/Speex/FLAC), WAV/BWF,
AIFF, ASF/WMA, APE, Matroska/WebM, Musepack, WavPack, DSD (DSF/DSDIFF), and CAF.

## 1. Choose the Right Entrypoint

| Source / Goal | Call | Platform Notes |
| :--- | :--- | :--- |
| Local file path | `await parseFile(path, options: ...)` | IO only (Desktop, CLI, iOS, Android) |
| In-memory bytes (`Uint8List`) | `await parseBytes(bytes, fileInfo: ..., options: ...)` | All platforms including Web / Wasm |
| Remote HTTP/HTTPS URL | `await parseUrl(url, options: ..., strategy: ..., onStrategySelected: ...)` | Range-aware streaming when server allows |
| Byte stream (sequential) | `await parseStream(stream, fileInfo: ..., options: ...)` | Only formats not requiring random access |
| Extract chapter/range to disk | `await ChapterDownloader.downloadChapter(...)` | IO only; accepts URL **or** local path |
| Extract chapter/range in memory | `await ChapterDownloader.extractChapterBytes(...)` | Web / Wasm / in-memory; returns `Uint8List` |

Single import:

```dart
import 'package:metadata_audio/metadata_audio.dart';
```

See [API Reference](./references/api_reference.md) for full `Format`,
`CommonTags`, `Chapter`, `ParseOptions`, error classes, and JSON helpers.

---

## 2. Parse Audio Metadata

### Local File (`dart:io` platforms)

```dart
final metadata = await parseFile(
  '/path/to/audiobook.m4b',
  options: const ParseOptions(
    includeChapters: true,
    duration: true,
  ),
);

print('${metadata.common.title} by ${metadata.common.artist}');
print('${metadata.format.container} · ${metadata.format.codec}');
print('Duration: ${metadata.format.duration}s');

final cover = selectCover(metadata.common.picture); // Picture? (bytes + MIME)
```

### In-Memory Bytes (Web / Wasm / FilePicker `withData: true`)

```dart
final metadata = await parseBytes(
  bytes,
  fileInfo: const FileInfo(mimeType: 'audio/mp4'), // optional hint
  options: const ParseOptions(includeChapters: true, duration: true),
);
```

### Remote URL (`parseUrl`)

`parseUrl` probes HTTP Range support and file size and picks `fullDownload`,
`headerOnly`, `probe`, or `randomAccess` automatically:

```dart
final metadata = await parseUrl(
  'https://example.com/audiobook.m4b',
  options: const ParseOptions(includeChapters: true),
  timeout: const Duration(seconds: 30),
  onStrategySelected: (strategy, reason) {
    print('Strategy: ${strategy.name} ($reason)');
  },
);
```

To probe first without parsing, call `await detectStrategy(url)`.

---

## 3. Caching & Incremental `ParseOptions` Reuse

Enable caching globally or per call:

```dart
// Global toggle across parseUrl, parseFile, parseBytes, parseStream, parseFromTokenizer:
cacheEnabled = true; // mirrors AudioMetadataCache.enabled

// Pass 1: fast parse without chapters or covers
final basic = await parseUrl(
  url,
  options: const ParseOptions(includeChapters: false, skipCovers: true),
);

// Pass 2 on the same URL/path: reuses cached data and fetches only missing parts
final full = await parseUrl(
  url,
  options: const ParseOptions(includeChapters: true, skipCovers: false),
);
```

Rules for caching:
- Cache keys are derived from the normalized **URL or file path** (or explicit
  `ParseOptions(cacheKey: '...')`), not from option flags, so enabling new
  `ParseOptions` (`includeChapters`, `duration`, `skipCovers: false`,
  `skipPostHeaders: false`, `mkvUseIndex`) later merges newly fetched data into
  the existing cache entry.
- Per-call caching without enabling globally: `ParseOptions(useCache: true)`.
- Management: `await AudioMetadataCache.evict(urlOrKey)`,
  `await AudioMetadataCache.clearCache()`, `AudioMetadataCache.getCacheSize()`.
- On Web, cache falls back automatically from disk temp storage to an in-memory
  LRU cache (`AudioMetadataCache.maxMemoryCacheEntries`).

---

## 4. Chapters & Standalone Slicing (`ChapterDownloader`)

### Reading Chapters

Enable `ParseOptions(includeChapters: true)` and inspect
`metadata.format.chapters`:

```dart
for (final ch in metadata.format.chapters ?? const <Chapter>[]) {
  // start / end are in milliseconds; byteOffset / endByteOffset mark audio byte range
  print('${ch.title}: ${ch.start}ms..${ch.end}ms (${ch.byteOffset}..${ch.endByteOffset})');
}
```

### Downloading a Chapter to Disk (Remote URL **or** Local File)

`ChapterDownloader.downloadChapter` supports MP4/M4B/M4A/MOV (writes playable
`.m4a`, or raw ADTS `.aac` if `outputPath` ends with `.aac`) and MP3 (writes
aligned `.mp3`):

```dart
final result = await ChapterDownloader.downloadChapter(
  originalUrl: sourceUrlOrLocalPath, // HTTP(S) URL or local file path
  chapterStartMs: chapter.start,
  chapterEndMs: chapter.end!,
  outputPath: '/path/to/chapter_1.m4a',
  includeMetadata: true, // keeps cover art & safe tags; strips chapters/TLEN/seek tables
  metadata: metadata,    // optional fallback if MP4 lacks udta/meta box
  parallelChunks: 4,
  onPhase: (phase) => print(phase),
  onProgress: (p) => print('${(p * 100).round()}%'),
);
```

### Extracting Chapter Bytes in Memory (Web / Browser Blob / Buffers)

```dart
final result = await ChapterDownloader.extractChapterBytes(
  sourceBytes: audioBytes,
  chapterStartMs: chapter.start,
  chapterEndMs: chapter.end!,
  fileName: 'audiobook.m4b',
  includeMetadata: true,
  metadata: metadata,
);
if (result.isSuccess) {
  // result.bytes (Uint8List), result.extension ('m4a' | 'mp3' | 'aac'), result.mimeType
}
```

---

## 5. Common Pitfalls

1. **Expecting chapters or duration by default**: `ParseOptions()` defaults to
   `includeChapters: false` and `duration: false` (MP3 VBR/EOF scan). Pass
   `includeChapters: true` and/or `duration: true` when you need them.
2. **MP3 `APIC` vs `common.picture`**: MP4/FLAC/Vorbis/ASF/APE map artwork into
   `metadata.common.picture` (use `selectCover(metadata.common.picture)`), while
   ID3v2 frames preserve `Picture` objects in `metadata.native['ID3v2.3']` /
   `'ID3v2.4'` under frame id `'APIC'`/`'PIC'`.
3. **JSON serialization types**: `audioMetadataToJson(metadata)` returns
   `Map<String, dynamic>`, and `audioMetadataFromJson(map)` accepts
   `Map<String, dynamic>` — wrap with `jsonEncode`/`jsonDecode` when storing strings.
4. **`parseStream` on seeking formats**: Formats such as MP4 (`moov` at EOF),
   APE, or Matroska require seeking; use `parseFile`, `parseBytes`, or `parseUrl`.
5. **Untrusted large files**: Adjust `ParseOptions(maxMemoryAllocation: ..., maxMetadataEntries: ..., maxChapterCount: ...)` if parsing unusually huge chapter tables or artwork, or catch `BufferSizeError` / `ParseError`.
