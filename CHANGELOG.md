## 0.7.2

- **Feat**: Enhanced MP4 parsing for large files by adding HTTP prefetching for atom headers and chapter data.

## 0.7.1

- **Fixed**: MP4 chapter extraction now supports `co64` chunk offset tables (64-bit offsets), restoring chapter parsing for large M4B/audiobook files.
- **Fixed**: MP4 track parsing now correctly reads `tkhd` version-1 track IDs, enabling chapter-track linkage in files that use v1 `tkhd` atoms.
- **Fixed**: Post-parse chapter fallback now resolves chapter tracks by absolute offsets after atom traversal, improving reliability when chapter tables are finalized later in the file.
- **Improved**: URL strategy detection and parsing now degrade gracefully to full download when HEAD/range probing is unreliable, reducing false failures on flaky remote hosts.

## 0.7.0

- **Fixed**: Chrome/web builds now compile and run against the package without JS-incompatible 64-bit integer literals in Matroska, Musepack, MP4, DSF, and DSDIFF parsing paths.
- **Fixed**: Matroska chapter timing now preserves large EBML integer values in browser builds, restoring the expected chapter end time behavior.
- **Fixed**: DSF and DSDIFF test fixtures now use browser-safe 64-bit byte encoders instead of `ByteData.setInt64`, so the parser suites run in Chrome.
- **Verified**: Chrome test coverage now passes for MP4, Matroska, Musepack, DSF, and DSDIFF parser suites.

## 0.6.2

- **Fixed**: MP4/M4B parsing now handles version-1 `mvhd` atoms with large 64-bit timestamps without crashing, including the audiobook URL regression case that previously overflowed `DateTime` conversion on some platforms.

## 0.6.1

- **Fixed**: MP3 URL parsing now routes through the MPEG parser instead of the tag-only ID3 loader, restoring duration and bitrate extraction for real-world app usage.
- **Fixed**: Malformed ID3v2.3 frame headers now trigger MPEG resync/fallback instead of leaving MP3 metadata stuck at `null`.
- **Fixed**: MP3 duration now falls back to file-size plus sampled bitrate even when parsing stops before the EOF frame-count heuristic completes, improving URL parsing for malformed or tag-heavy files on mobile.

## 0.6.0

- **Fixed**: `RangeTokenizer.hasCompleteData` now reports `true` when the entire remote file fits inside the initial header fetch.
- **Fixed**: `ProbingRangeTokenizer` now aligns `mp4Optimized` tail fetches to chunk boundaries, preventing chunk-cache misindexing near the end of large MP4/M4A files.
- **Added**: Real URL integration coverage for MP3, FLAC, OGG, M4B, plus 600+ MB FLAC and WAV files.
- **Added**: Lower-level tokenizer smoke tests for FLAC, AIFF, M4A, and WAV sample files.

## 0.5.1

- **Fixed**: `ProbingRangeTokenizer` now correctly splits fetched data into 64KB chunks, fixing metadata parsing failures for MP3 files with large ID3v2 headers when using `ParseStrategy.probe`.
- **Fixed**: ID3v1 parser now gracefully handles missing tail data (e.g., with partial HTTP range requests), preventing crashes when probing MP3 files.

## 0.5.0

- **Feat**: Added `MetadataObserver` support for incremental metadata updates during parsing.
- **Feat**: Observer events now emit typed `format` and `common` IDs using Dart extension types, with support for ad hoc unknown IDs.
- **Feat**: Added live observer coverage for file-backed parsing, including optional chapter-event verification for local audiobook samples.
## 0.4.0

- **Fixed**: MP4 `chpl` (Nero chapter list) parsing now supports audiobook chapter extraction from files that expose chapter timing via chapter time base metadata.
- **Fixed**: Chapter timestamp conversion now infers time base from file timing data instead of relying on a hardcoded scale, restoring full chapter lists (e.g. 73 chapters) for affected M4B files.
- **Fixed**: MP4 parser now reads `chpl` atoms under `udta` and emits normalized chapter ranges (`start`/`end`) in milliseconds.
- **Fixed**: 64-bit MP4 integer parsing overflow guard for large files / version-1 atom fields.
- **Improved**: URL-based MP4 parsing reliability for large files by expanding tail prefetch windows for `moov` discovery in HTTP tokenizers.

## 0.3.0

- **Fixed**: MP4 chapter extraction now works reliably with URL-based tokenizers by prefetching the entire `moov` atom when it exceeds the initial prefetch window.
- **Feat**: Implemented **consolidated HTTP range requests** in `HttpBasedTokenizer`, reducing the number of network requests by up to 90% for large metadata blocks.
- **Feat**: Added **retry logic with exponential backoff** to HTTP tokenizers to handle transient network errors.
- **Fixed**: Improved MP4 chapter timing accuracy by using the chapter track's own Time-to-Sample (STTS) table instead of approximate byte-offset correlation.

## 0.2.0

- **Fixed**: Auto-initialize parser factory to prevent "Field '_parserFactory' has not been initialized" error
- **Added**: `createDefaultParserFactory()` function for creating a factory with all format loaders
- **Added**: Exports for all format loaders (`MpegLoader`, `FlacLoader`, etc.) for custom configurations
- **Docs**: Added initialization section to README documenting auto-init and custom setup

## 0.1.0

- Initial stable release with comprehensive audio metadata support
- Multi-format support: MP3, FLAC, Ogg Vorbis, MP4, WAV, AIFF, APE, ASF, Matroska, Musepack, WavPack, DSF, DSDIFF
- Full ID3 support: ID3v1, ID3v2.2, ID3v2.3, ID3v2.4
- Chapter/track boundary extraction for audiobooks and podcasts
- Smart URL parsing with automatic strategy selection
- Streaming support for remote files
