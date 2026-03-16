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
