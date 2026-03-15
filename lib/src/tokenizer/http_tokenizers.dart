library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/src/core.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parse_error.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

/// Error thrown when downloading a file from URL fails.
class FileDownloadError extends ParseError {
  FileDownloadError(super.message);

  @override
  String get name => 'FileDownloadError';
}

/// Abstract base class for HTTP-based tokenizers.
abstract class HttpBasedTokenizer extends Tokenizer {

  HttpBasedTokenizer({required this.url, required this.fileInfo});
  final String url;
  @override
  final FileInfo? fileInfo;

  /// Close any resources held by the tokenizer.
  void close();
}

/// Tokenizer that downloads the entire file before parsing.
///
/// This is the simplest approach and works with any HTTP server,
/// but can be slow for large files.
class HttpTokenizer extends HttpBasedTokenizer {

  HttpTokenizer({
    required super.url,
    required super.fileInfo,
    required Uint8List bytes,
  }) : _bytes = bytes;
  final Uint8List _bytes;
  int _position = 0;
  bool _isClosed = false;

  @override
  bool get canSeek => true;

  @override
  int get position => _position;

  /// Create an HttpTokenizer by downloading the full file.
  static Future<HttpTokenizer> fromUrl(String url, {Duration? timeout}) async {
    final client = HttpClient();

    try {
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;

      final response = await request.close().timeout(
        timeout ?? const Duration(seconds: 30),
      );

      if (response.statusCode >= 300) {
        throw FileDownloadError(
          'HTTP ${response.statusCode} error downloading from: $url',
        );
      }

      final chunks = await response.toList();
      final bytes = Uint8List.fromList([for (final chunk in chunks) ...chunk]);

      final fileInfo = FileInfo(
        path: url,
        url: url,
        mimeType: response.headers.contentType?.toString(),
        size: bytes.length,
      );

      return HttpTokenizer(url: url, fileInfo: fileInfo, bytes: bytes);
    } on FileDownloadError {
      rethrow;
    } catch (e) {
      throw FileDownloadError('Failed to download from URL: $e');
    } finally {
      client.close();
    }
  }

  @override
  int readUint8() {
    if (_isClosed) throw TokenizerException('Tokenizer is closed');
    if (_position >= _bytes.length) {
      throw TokenizerException('End of data reached');
    }
    return _bytes[_position++];
  }

  @override
  int readUint16() {
    final b1 = readUint8();
    final b2 = readUint8();
    return (b1 << 8) | b2;
  }

  @override
  int readUint32() {
    final b1 = readUint8();
    final b2 = readUint8();
    final b3 = readUint8();
    final b4 = readUint8();
    return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4;
  }

  @override
  List<int> readBytes(int length) {
    if (_position + length > _bytes.length) {
      throw TokenizerException('Not enough bytes available');
    }
    final result = _bytes.sublist(_position, _position + length);
    _position += length;
    return result;
  }

  @override
  int peekUint8() {
    if (_isClosed) throw TokenizerException('Tokenizer is closed');
    if (_position >= _bytes.length) {
      throw TokenizerException('End of data reached');
    }
    return _bytes[_position];
  }

  @override
  List<int> peekBytes(int length) {
    if (_position + length > _bytes.length) {
      throw TokenizerException('Not enough bytes available');
    }
    return _bytes.sublist(_position, _position + length);
  }

  @override
  void skip(int length) {
    _position += length;
  }

  @override
  void seek(int newPosition) {
    if (newPosition < 0 || newPosition > _bytes.length) {
      throw TokenizerException('Invalid seek position: $newPosition');
    }
    _position = newPosition;
  }

  @override
  void close() {
    _isClosed = true;
  }
}

/// Tokenizer that downloads only a header chunk using Range requests.
///
/// Efficient for formats where metadata is at the beginning of the file.
/// Falls back to full download if Range requests aren't supported.
class RangeTokenizer extends HttpBasedTokenizer {

  RangeTokenizer({
    required super.url,
    required super.fileInfo,
    required Uint8List bytes,
    int? totalSize,
  }) : _bytes = bytes,
       _totalSize = totalSize;
  final Uint8List _bytes;
  int _position = 0;
  bool _isClosed = false;
  final int? _totalSize;

  @override
  bool get canSeek => true;

  @override
  int get position => _position;

  /// Create a RangeTokenizer by downloading header only.
  static Future<RangeTokenizer> fromUrl(
    String url, {
    Duration? timeout,
    int headerSize = 262144, // 256KB default
  }) async {
    final client = HttpClient();

    try {
      // First, try HEAD to get file info
      final headRequest = await client.headUrl(Uri.parse(url));
      headRequest.followRedirects = true;
      final headResponse = await headRequest.close().timeout(
        timeout ?? const Duration(seconds: 30),
      );

      if (headResponse.statusCode >= 300) {
        throw FileDownloadError(
          'HTTP ${headResponse.statusCode} error accessing URL: $url',
        );
      }

      final totalSize = headResponse.contentLength > 0
          ? headResponse.contentLength
          : null;

      // Try Range request
      final request = await client.getUrl(Uri.parse(url));
      final endByte = totalSize != null && totalSize < headerSize
          ? totalSize - 1
          : headerSize - 1;
      request.headers.add('Range', 'bytes=0-$endByte');

      final response = await request.close().timeout(
        timeout ?? const Duration(seconds: 30),
      );

      if (response.statusCode != 206) {
        // Range not supported, fall back to full
        throw FileDownloadError('Range requests not supported');
      }

      final chunks = await response.toList();
      final bytes = Uint8List.fromList([for (final chunk in chunks) ...chunk]);

      final fileInfo = FileInfo(
        path: url,
        url: url,
        mimeType: response.headers.contentType?.toString(),
        size: totalSize ?? bytes.length,
      );

      return RangeTokenizer(
        url: url,
        fileInfo: fileInfo,
        bytes: bytes,
        totalSize: totalSize,
      );
    } on FileDownloadError {
      rethrow;
    } catch (e) {
      throw FileDownloadError('Failed to download header: $e');
    } finally {
      client.close();
    }
  }

  @override
  int readUint8() {
    if (_isClosed) throw TokenizerException('Tokenizer is closed');
    if (_position >= _bytes.length) {
      throw TokenizerException(
        'End of header data at position $_position. '
        'Total file size may be larger than downloaded header.',
      );
    }
    return _bytes[_position++];
  }

  @override
  int readUint16() {
    final b1 = readUint8();
    final b2 = readUint8();
    return (b1 << 8) | b2;
  }

  @override
  int readUint32() {
    final b1 = readUint8();
    final b2 = readUint8();
    final b3 = readUint8();
    final b4 = readUint8();
    return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4;
  }

  @override
  List<int> readBytes(int length) {
    if (_position + length > _bytes.length) {
      throw TokenizerException(
        'Header too small: need $length bytes at position $_position, '
        'header size ${_bytes.length}',
      );
    }
    final result = _bytes.sublist(_position, _position + length);
    _position += length;
    return result;
  }

  @override
  int peekUint8() {
    if (_isClosed) throw TokenizerException('Tokenizer is closed');
    if (_position >= _bytes.length) {
      throw TokenizerException('End of header data');
    }
    return _bytes[_position];
  }

  @override
  List<int> peekBytes(int length) {
    if (_position + length > _bytes.length) {
      throw TokenizerException('Header too small for peek');
    }
    return _bytes.sublist(_position, _position + length);
  }

  @override
  void skip(int length) {
    _position += length;
  }

  @override
  void seek(int newPosition) {
    if (newPosition < 0 || newPosition > _bytes.length) {
      throw TokenizerException('Invalid seek position: $newPosition');
    }
    _position = newPosition;
  }

  @override
  void close() {
    _isClosed = true;
  }

  /// Get the total file size if known.
  int? get totalSize => _totalSize;

  /// Get the downloaded header size.
  int get headerSize => _bytes.length;
}

/// Tokenizer that provides true random access via on-demand Range requests.
///
/// This is the most efficient for large files as it only fetches data
/// that is actually read by the parser. It caches fetched chunks.
class RandomAccessTokenizer extends HttpBasedTokenizer {

  RandomAccessTokenizer({
    required super.url,
    required super.fileInfo,
    required HttpClient client,
    required Duration timeout,
    required int chunkSize,
    int? totalSize,
  }) : _client = client,
       _timeout = timeout,
       _chunkSize = chunkSize,
       _totalSize = totalSize;
  final HttpClient _client;
  final Duration _timeout;
  final int? _totalSize;
  final int _chunkSize;

  final Map<int, Uint8List> _cache = {};
  int _position = 0;
  bool _isClosed = false;
  int _totalBytesFetched = 0;

  @override
  bool get canSeek => true;

  @override
  int get position => _position;

  /// Total bytes fetched from server so far.
  int get totalBytesFetched => _totalBytesFetched;

  /// Create a RandomAccessTokenizer.
  static Future<RandomAccessTokenizer> fromUrl(
    String url, {
    Duration? timeout,
    int chunkSize = 65536, // 64KB chunks
  }) async {
    final client = HttpClient();

    try {
      final headRequest = await client.headUrl(Uri.parse(url));
      headRequest.followRedirects = true;
      final headResponse = await headRequest.close().timeout(
        timeout ?? const Duration(seconds: 30),
      );

      if (headResponse.statusCode >= 300) {
        throw FileDownloadError(
          'HTTP ${headResponse.statusCode} error accessing URL: $url',
        );
      }

      final totalSize = headResponse.contentLength > 0
          ? headResponse.contentLength
          : null;

      final fileInfo = FileInfo(
        path: url,
        url: url,
        mimeType: headResponse.headers.contentType?.toString(),
        size: totalSize,
      );

      return RandomAccessTokenizer(
        url: url,
        fileInfo: fileInfo,
        client: client,
        timeout: timeout ?? const Duration(seconds: 30),
        chunkSize: chunkSize,
        totalSize: totalSize,
      );
    } on FileDownloadError {
      client.close();
      rethrow;
    } catch (e) {
      client.close();
      throw FileDownloadError('Failed to initialize: $e');
    }
  }

  /// Fetch a chunk from the server.
  Future<void> _fetchChunk(int chunkIndex) async {
    final start = chunkIndex * _chunkSize;
    final totalSize = _totalSize;
    final end = totalSize != null
        ? (start + _chunkSize < totalSize
              ? start + _chunkSize - 1
              : totalSize - 1)
        : start + _chunkSize - 1;

    try {
      final request = await _client.getUrl(Uri.parse(url));
      request.headers.add('Range', 'bytes=$start-$end');

      final response = await request.close().timeout(_timeout);

      if (response.statusCode != 206 && response.statusCode != 200) {
        throw FileDownloadError('Range request failed: ${response.statusCode}');
      }

      final chunks = await response.toList();
      final bytes = Uint8List.fromList([for (final chunk in chunks) ...chunk]);

      _cache[chunkIndex] = bytes;
      _totalBytesFetched += bytes.length;
    } catch (e) {
      throw FileDownloadError('Failed to fetch chunk $chunkIndex: $e');
    }
  }

  @override
  int readUint8() {
    final chunkIndex = _position ~/ _chunkSize;
    final offset = _position % _chunkSize;

    final chunk = _cache[chunkIndex];
    if (chunk == null || offset >= chunk.length) {
      throw TokenizerException(
        'Data not available at position $_position. '
        'Use prefetchRange() before reading.',
      );
    }

    _position++;
    return chunk[offset];
  }

  @override
  int readUint16() {
    final b1 = readUint8();
    final b2 = readUint8();
    return (b1 << 8) | b2;
  }

  @override
  int readUint32() {
    final b1 = readUint8();
    final b2 = readUint8();
    final b3 = readUint8();
    final b4 = readUint8();
    return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4;
  }

  @override
  List<int> readBytes(int length) {
    final result = Uint8List(length);
    for (var i = 0; i < length; i++) {
      result[i] = readUint8();
    }
    return result;
  }

  @override
  int peekUint8() {
    final saved = _position;
    final byte = readUint8();
    _position = saved;
    return byte;
  }

  @override
  List<int> peekBytes(int length) {
    final saved = _position;
    final result = readBytes(length);
    _position = saved;
    return result;
  }

  @override
  void skip(int length) {
    _position += length;
  }

  @override
  void seek(int newPosition) {
    if (newPosition < 0) {
      throw TokenizerException('Invalid seek position');
    }
    final totalSize = _totalSize;
    if (totalSize != null && newPosition > totalSize) {
      throw TokenizerException('Seek beyond file size');
    }
    _position = newPosition;
  }

  @override
  void close() {
    _isClosed = true;
    _client.close();
    _cache.clear();
  }

  /// Prefetch a range of bytes asynchronously.
  Future<void> prefetchRange(int start, int end) async {
    if (_isClosed) return;

    final startChunk = start ~/ _chunkSize;
    final endChunk = end ~/ _chunkSize;

    final futures = <Future<void>>[];
    for (var i = startChunk; i <= endChunk; i++) {
      if (!_cache.containsKey(i)) {
        futures.add(_fetchChunk(i));
      }
    }

    await Future.wait(futures);
  }
}

/// Strategy for URL parsing.
enum ParseStrategy {
  /// Download full file - works with any server
  fullDownload,

  /// Download header only - fastest for most files
  headerOnly,

  /// Random access with on-demand fetching - most efficient for large files
  randomAccess,
}

/// Result of strategy detection.
class StrategyInfo {

  StrategyInfo({
    required this.strategy,
    required this.fileSize,
    required this.supportsRange,
  });
  final ParseStrategy strategy;
  final int? fileSize;
  final bool supportsRange;
}

/// Detect the best parsing strategy for a URL.
///
/// Returns a [StrategyInfo] with the recommended strategy.
Future<StrategyInfo> detectStrategy(
  String url, {
  Duration? timeout,
  int largeFileThreshold = 5 * 1024 * 1024, // 5MB
}) async {
  final client = HttpClient();

  try {
    final headRequest = await client.headUrl(Uri.parse(url));
    headRequest.followRedirects = true;
    final headResponse = await headRequest.close().timeout(
      timeout ?? const Duration(seconds: 10),
    );

    if (headResponse.statusCode >= 300) {
      throw FileDownloadError('HTTP ${headResponse.statusCode} error');
    }

    final fileSize = headResponse.contentLength > 0
        ? headResponse.contentLength
        : null;

    final acceptRanges = headResponse.headers.value('accept-ranges');
    final supportsRange =
        acceptRanges?.toLowerCase().contains('bytes') ?? false;

    // Decision logic
    ParseStrategy strategy;
    if (fileSize == null) {
      // Unknown size, use full download to be safe
      strategy = ParseStrategy.fullDownload;
    } else if (fileSize <= largeFileThreshold) {
      // Small file, full download is fine
      strategy = ParseStrategy.fullDownload;
    } else if (supportsRange) {
      // Large file with Range support
      // For very large files, random access is best
      // For medium files, header-only is fastest
      if (fileSize > 50 * 1024 * 1024) {
        strategy = ParseStrategy.randomAccess;
      } else {
        strategy = ParseStrategy.headerOnly;
      }
    } else {
      // Large file without Range support
      strategy = ParseStrategy.fullDownload;
    }

    return StrategyInfo(
      strategy: strategy,
      fileSize: fileSize,
      supportsRange: supportsRange,
    );
  } finally {
    client.close();
  }
}

/// Smart URL parser that automatically selects the best strategy.
///
/// Analyzes the URL and server capabilities to choose:
/// - [HttpTokenizer] for small files or non-Range servers
/// - [RangeTokenizer] for large files with Range support
/// - [RandomAccessTokenizer] for very large files
///
/// Parameters:
/// - [url]: The URL to parse
/// - [options]: Parse options
/// - [timeout]: HTTP timeout
/// - [strategy]: Force a specific strategy (default: auto-detect)
/// - [onStrategySelected]: Callback when strategy is selected (for debugging)
///
/// Example:
/// ```dart
/// final metadata = await parseUrl('https://example.com/audio.m4a');
/// ```
Future<AudioMetadata> parseUrl(
  String url, {
  ParseOptions? options,
  Duration? timeout,
  ParseStrategy? strategy,
  void Function(ParseStrategy strategy, String reason)? onStrategySelected,
}) async {
  options ??= const ParseOptions();
  final effectiveTimeout = timeout ?? const Duration(seconds: 30);

  // If strategy not specified, detect it
  StrategyInfo? info;
  if (strategy == null) {
    info = await detectStrategy(url, timeout: effectiveTimeout);
    strategy = info.strategy;
  }

  // Log strategy selection
  String reason;
  if (info != null) {
    reason =
        'File size: ${info.fileSize != null ? "${info.fileSize! ~/ 1024}KB" : "unknown"}, '
        'Range support: ${info.supportsRange}';
  } else {
    reason = 'User-specified';
  }
  onStrategySelected?.call(strategy, reason);

  // Execute the selected strategy
  switch (strategy) {
    case ParseStrategy.fullDownload:
      return _parseWithFullDownload(url, effectiveTimeout, options);

    case ParseStrategy.headerOnly:
      return _parseWithHeaderOnly(url, effectiveTimeout, options);

    case ParseStrategy.randomAccess:
      return _parseWithRandomAccess(url, effectiveTimeout, options);
  }
}

/// Parse using full download.
Future<AudioMetadata> _parseWithFullDownload(
  String url,
  Duration timeout,
  ParseOptions options,
) async {
  final tokenizer = await HttpTokenizer.fromUrl(url, timeout: timeout);
  try {
    return await parseFromTokenizer(tokenizer, options: options);
  } finally {
    tokenizer.close();
  }
}

/// Parse using header-only download.
Future<AudioMetadata> _parseWithHeaderOnly(
  String url,
  Duration timeout,
  ParseOptions options,
) async {
  try {
    final tokenizer = await RangeTokenizer.fromUrl(url, timeout: timeout);
    try {
      return await parseFromTokenizer(tokenizer, options: options);
    } finally {
      tokenizer.close();
    }
  } on FileDownloadError {
    // Header-only failed, fall back to full download
    return _parseWithFullDownload(url, timeout, options);
  }
}

/// Parse using random access.
Future<AudioMetadata> _parseWithRandomAccess(
  String url,
  Duration timeout,
  ParseOptions options,
) async {
  final tokenizer = await RandomAccessTokenizer.fromUrl(url, timeout: timeout);

  try {
    // For random access, we need to prefetch chunks as the parser reads
    // This is handled by wrapping the tokenizer
    return await _parseWithPrefetching(tokenizer, options);
  } finally {
    tokenizer.close();
  }
}

/// Parse with automatic prefetching for RandomAccessTokenizer.
Future<AudioMetadata> _parseWithPrefetching(
  RandomAccessTokenizer tokenizer,
  ParseOptions options,
) async {
  // Prefetch initial header (first 256KB)
  await tokenizer.prefetchRange(0, 262144);

  try {
    return await parseFromTokenizer(tokenizer, options: options);
  } catch (e) {
    // If parsing fails due to missing data, try with full download
    if (e is TokenizerException && e.toString().contains('not available')) {
      rethrow; // Can't recover without full download
    }
    rethrow;
  }
}
