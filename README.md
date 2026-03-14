# audio_metadata

A Dart-native audio metadata parser library that provides comprehensive metadata extraction for various audio formats. This package is a port of the TypeScript [music-metadata](https://github.com/Borewit/music-metadata) library, maintaining architecture parity with a Dart-first TDD approach.

## Features

- **Multi-format support**: MP3, FLAC, Ogg Vorbis, MP4, WAV, AIFF, APE, ASF, Matroska, and more
- **Comprehensive metadata**: ID3, Vorbis comments, iTunes tags, and other metadata standards
- **Streaming support**: Parse metadata without loading entire files into memory
- **Type-safe**: Full Dart type safety with comprehensive error handling
- **Well-tested**: Extensive test suite with TDD principles

## Getting started

### Install

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  audio_metadata: ^0.1.0
```

Then run:

```bash
dart pub get
```

### Prerequisites

- Dart SDK 3.10.7 or higher

## Usage

```dart
import 'package:audio_metadata/audio_metadata.dart';

// Parse a file
final metadata = await parseFile('/path/to/audio.mp3');

// Access common metadata
print('Title: ${metadata.common.title}');
print('Artist: ${metadata.common.artist}');
print('Album: ${metadata.common.album}');
print('Duration: ${metadata.format.duration}');

// Parse bytes
final bytes = await File('/path/to/audio.flac').readAsBytes();
final meta = await parseBytes(bytes, fileInfo: FileInfo(mimeType: 'audio/flac'));
```

For more examples, see the [test directory](test/) for comprehensive usage examples across all supported formats.

## Supported Formats

| Format | Status | Notes |
|--------|--------|-------|
| MP3    | ✅ Complete | ID3v1, ID3v2.2/2.3/2.4, MPEG audio, Lyrics3 |
| FLAC   | ✅ Complete | Vorbis comments, picture metadata |
| OGG    | ✅ Complete | Vorbis, Opus, Speex, FLAC-in-Ogg |
| MP4/M4A| ✅ Complete | iTunes atoms, chapters |
| WAV    | ✅ Complete | RIFF, LIST-INFO, BWF |
| AIFF   | ✅ Complete | AIFF-C, ID3, chunks |
| APE    | ✅ Complete | APEv2 tags |
| ASF/WMA| ✅ Complete | Windows Media metadata |
| Matroska| ✅ Complete | MKV, WebM tags |
| Musepack| ✅ Complete | SV7, SV8 |
| WavPack| ✅ Complete | APEv2 tags |
| DSD    | ✅ Complete | DSF, DSDIFF |

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

## Upstream

This package is ported from the TypeScript [music-metadata](https://github.com/Borewit/music-metadata) library.

## Additional Information

- **Issues**: [Report issues on GitHub](https://github.com/ketanchoyal/audio-metadata-dart/issues)
- **Contributing**: See [CONTRIBUTING.md](CONTRIBUTING.md)
- **Repository**: [github.com/ketanchoyal/audio-metadata-dart](https://github.com/ketanchoyal/audio-metadata-dart)

---

For detailed architecture and design decisions, see the project documentation in `/docs`.
