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
