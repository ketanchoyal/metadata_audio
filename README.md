# metadata_audio [![Pub](https://img.shields.io/pub/v/metadata_audio)](https://pub.dev/packages/metadata_audio)

[![Buy Me A Coffee](https://img.shields.io/badge/Buy_Me_A_Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/ketanchoyal)

A Dart-native audio metadata parser library that provides comprehensive metadata extraction for various audio formats. This package is a port of the TypeScript [music-metadata](https://github.com/Borewit/music-metadata) library, maintaining architecture parity with a Dart-first TDD approach.

## Features

- **Multi-format support**: MP3, FLAC, Ogg Vorbis, MP4, WAV, AIFF, APE, ASF, Matroska, and more
- **Comprehensive metadata**: ID3, Vorbis comments, iTunes tags, and other metadata standards
- **Chapter/Track boundaries**: Extract embedded chapter markers, cue points, and track boundaries (MP4, FLAC, Ogg, WAV, Matroska)
- **Live metadata observation**: Receive incremental `format`, `common`, and chapter updates while parsing is still in progress
- **Smart URL parsing**: Automatically selects optimal download strategy for remote files
- **Streaming support**: Parse metadata without loading entire files into memory
- **Type-safe**: Full Dart type safety with comprehensive error handling
- **Well-tested**: Extensive test suite with TDD principles
- **Web platform support**: Works in browsers via `parseWebFile()`, `parseBytes()`, and `parseUrl()`
- **TypeScript parity**: Ported from [music-metadata](https://github.com/Borewit/music-metadata) with exact output compatibility

## Getting started

### Install

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  metadata_audio: any
```

Then run:

```bash
dart pub get
```

### Prerequisites

- Dart SDK 3.10.7 or higher

## Usage

### Initialization

The library auto-initializes with all format loaders on first use. No manual setup required.

```dart
import 'package:metadata_audio/metadata_audio.dart';

// Just use it - auto-initializes on first call
final metadata = await parseFile('/path/to/audio.mp3');
```

#### Custom Initialization (Optional)

For custom configurations, you can initialize manually:

```dart
import 'package:metadata_audio/metadata_audio.dart';

// Create a custom registry with only specific formats
final registry = ParserRegistry()
  ..register(MpegLoader())
  ..register(FlacLoader());

initializeParserFactory(ParserFactory(registry));

// Now parsing will only use registered formats
final metadata = await parseFile('/path/to/audio.mp3');
```

### Parse Local Files

```dart
import 'package:metadata_audio/metadata_audio.dart';

// Parse a file
final metadata = await parseFile('/path/to/audio.mp3');

// Access common metadata
print('Title: ${metadata.common.title}');
print('Artist: ${metadata.common.artist}');
print('Album: ${metadata.common.album}');
print('Duration: ${metadata.format.duration}');
```

### Parse from URL (Smart)

The `parseUrl()` function automatically selects the best strategy based on file size and server capabilities:

```dart
// Small files (< 5MB): Full download
// Medium files (5-50MB): Header-only download (~256KB)
// Large files (> 50MB): Random access with on-demand fetching

final metadata = await parseUrl('https://example.com/audio.m4a');

// With callback to see selected strategy
final metadata = await parseUrl(
  'https://example.com/large-audio.m4a',
  onStrategySelected: (strategy, reason) {
    print('Using $strategy because $reason');
  },
);
```

### Parse Bytes

```dart
final bytes = await File('/path/to/audio.flac').readAsBytes();
final metadata = await parseBytes(
  bytes,
  fileInfo: FileInfo(mimeType: 'audio/flac'),
);
```

### Web Platform (Flutter Web / dart2js)

On the web, `parseFile()` throws `UnsupportedError` because browsers cannot access files by path. Use `parseWebFile()`, `parseBytes()`, or `parseUrl()` instead.

#### Using `parseWebFile()` (recommended — accepts `web.File` directly)

```dart
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:metadata_audio/metadata_audio.dart';

// With <input type="file"> or drag-and-drop:
final file = input.files!.item(0)!;  // web.File from browser
final metadata = await parseWebFile(file);
print('Title: ${metadata.common.title}');
```

#### Using a file picker (Flutter Web)

```dart
import 'package:file_picker/file_picker.dart';
import 'package:metadata_audio/metadata_audio.dart';

final result = await FilePicker.platform.pickFiles(type: FileType.audio);
if (result != null) {
  final bytes = result.files.single.bytes!;
  final metadata = await parseBytes(
    bytes,
    fileInfo: FileInfo(path: result.files.single.name),
  );
  print('Title: ${metadata.common.title}');
}
```

#### Parsing remote audio on the web

```dart
// parseUrl() works on web — uses the browser's fetch API with Range headers
final metadata = await parseUrl('https://example.com/audio.mp3');
```

> **Note:** On web, `parseUrl()` uses `package:http` which delegates to the browser's `fetch()` API. Range requests require the server to support CORS and `Accept-Ranges`. `parseWebFile()` works offline since it reads from a local browser file.

### Chapter Extraction

```dart
final metadata = await parseFile(
  '/path/to/audiobook.m4a',
  options: const ParseOptions(includeChapters: true),
);

if (metadata.format.chapters != null) {
  for (final chapter in metadata.format.chapters!) {
    print('${chapter.title}: ${chapter.start}ms - ${chapter.end}ms');
  }
}
```

### Observe Metadata While Parsing

Use `ParseOptions.observer` to receive incremental updates while parsing is still running.

```dart
final metadata = await parseFile(
  '/path/to/audiobook.m4b',
  options: ParseOptions(
    includeChapters: true,
    observer: (event) {
      final tag = event.tag;
      if (tag == null) return;

      if (tag.id == MetadataFormatId.container) {
        print('Container discovered: ${tag.value}');
      }

      if (tag.id == MetadataCommonId.title) {
        print('Title discovered: ${tag.value}');
      }

      if (tag.id == MetadataFormatId.chapters) {
        final chapters = tag.value as List<Chapter>?;
        print('Chapter count so far: ${chapters?.length ?? 0}');
      }
    },
  ),
);
```

Observer events include a snapshot of the accumulated metadata at that point:

```dart
ParseOptions(
  observer: (event) {
    final snapshot = event.metadata;
    print('Current title: ${snapshot?.common.title}');
    print('Current duration: ${snapshot?.format.duration}');
  },
);
```

IDs are extension types, so you can use built-in constants for known fields or create your own dynamically for unknown upstream keys:

```dart
const titleId = MetadataCommonId.title;
const customId = MetadataCommonId<Object?>('my-custom-tag');

print(titleId == const MetadataCommonId<Object?>('title')); // true
print(customId.path); // my-custom-tag
```

## Supported Formats

| Format | Status | Notes |
|--------|--------|-------|
| MP3    | ✅ Complete | ID3v1, ID3v2.2/2.3/2.4, MPEG audio, Lyrics3, ID3v2 chapters (CHAP/CTOC) |
| FLAC   | ✅ Complete | Vorbis comments, picture metadata, CUESHEET block → chapters |
| OGG    | ✅ Complete | Vorbis, Opus, Speex, FLAC-in-Ogg, Vorbis chapter tags (CHAPTER###) |
| MP4/M4A| ✅ Complete | iTunes atoms, chapter tracks (chap/tref), QuickTime chapters |
| WAV    | ✅ Complete | RIFF, LIST-INFO, BWF, cue points + adtl labels, ltxt chunks |
| AIFF   | ✅ Complete | AIFF-C, ID3, chunks |
| APE    | ✅ Complete | APEv2 tags, Monkey's Audio header |
| ASF/WMA| ✅ Complete | Windows Media metadata |
| Matroska| ✅ Complete | MKV, WebM tags, EditionEntry chapters |
| Musepack| ✅ Complete | SV7, SV8 |
| WavPack| ✅ Complete | APEv2 tags |
| DSD    | ✅ Complete | DSF, DSDIFF |

## URL Parsing Strategies

When parsing from URLs, the library automatically selects the most efficient strategy:

| Strategy | File Size | Method | Use Case |
|----------|-----------|--------|----------|
| `fullDownload` | ≤ 5MB | Download entire file | Small files, any server |
| `headerOnly` | 5-50MB | Download first 256KB | Medium files with Range support |
| `randomAccess` | > 50MB | On-demand chunk fetching | Large files with Range support |

### Manual Strategy Selection

```dart
import 'package:metadata_audio/metadata_audio.dart';

// Force specific strategy
final metadata = await parseUrl(
  url,
  strategy: ParseStrategy.headerOnly, // or fullDownload, randomAccess
);

// Detect strategy without parsing
final info = await detectStrategy(url);
print('Strategy: ${info.strategy}');
print('File size: ${info.fileSize}');
print('Range support: ${info.supportsRange}');
```

### HTTP Tokenizers

For advanced use cases, you can use the underlying tokenizers directly:

```dart
// Full download - works with any server
final tokenizer = await HttpTokenizer.fromUrl(url);

// Header-only - requires Range support
final tokenizer = await RangeTokenizer.fromUrl(url);

// Random access - on-demand fetching
final tokenizer = await RandomAccessTokenizer.fromUrl(url);
```

## Chapter/Boundary Extraction

The library supports extracting embedded track/disk boundaries and chapter markers from various audio formats. This is particularly useful for audiobooks, podcasts, DJ mixes, and live recordings.

### Supported Chapter Sources

| Format | Source | Description |
|--------|--------|-------------|
| **MP3** | ID3v2 CHAP/CTOC | ID3v2.3/2.4 chapter frames |
| **MP4/M4A** | Chapter track | QuickTime `chap` track reference with sample tables |
| **MP4/M4A** | iTunes chapters | Text track chapters in M4B audiobooks |
| **FLAC** | CUESHEET | FLAC native CUESHEET metadata block |
| **FLAC** | Vorbis comments | `CHAPTER###` and `CHAPTER###NAME` tags |
| **Ogg** | Vorbis comments | `CHAPTER###` timestamp tags |
| **WAV** | RIFF cue + adtl | `cue ` chunk with `labl`/`ltxt` in `LIST/adtl` |
| **Matroska** | EditionEntry | MKV chapter atoms (EditionEntry) |

### Chapter Model

```dart
class Chapter {
  final String? id;
  final String title;
  final int start;        // Start time in milliseconds
  final int? end;         // End time in milliseconds
  final int? sampleOffset;// Sample-accurate position
  final int timeScale;    // Time scale (typically 1000 for ms)
}
```

## Development

For information on contributing to this package, see [CONTRIBUTING.md](CONTRIBUTING.md).

### Development Setup

```bash
# Get dependencies
dart pub get

# Run tests
dart test

# Run analysis
dart analyze

# Format code
dart format lib/ test/
```

## License

MIT - See LICENSE file for details

## Upstream Compatibility

This package is a Dart port of the TypeScript [music-metadata](https://github.com/Borewit/music-metadata) library, maintaining exact output compatibility. The goal is 1:1 parity with the upstream library for all supported formats.

### TypeScript Parity Status

| Feature | Status | Notes |
|---------|--------|-------|
| Core metadata extraction | ✅ Complete | All formats match upstream output |
| Chapter extraction | ✅ Complete | All chapter sources supported |
| Metadata observer events | ✅ Complete | Incremental format/common/chapter updates during parsing |
| Tag mapping | ✅ Complete | Common tag normalization |
| Duration calculation | ✅ Complete | MPEG Xing/Info, format-specific logic |
| Bitrate calculation | ✅ Complete | Float precision matches upstream |
| Picture extraction | ✅ Complete | Cover art from all formats |
| URL parsing | ✅ Complete | Smart strategy selection |

To verify parity, run the comparison tool:

```bash
dart tool/compare_metadata.dart > comparison/output_dart.json
cd comparison && npm run compare
```

## Additional Information

- **Issues**: [Report issues on GitHub](https://github.com/ketanchoyal/audio-metadata/issues)
- **Contributing**: See [CONTRIBUTING.md](CONTRIBUTING.md)
- **Repository**: [github.com/ketanchoyal/audio-metadata](https://github.com/ketanchoyal/audio-metadata)

---

For detailed architecture and design decisions, see the project documentation in `/docs`.
