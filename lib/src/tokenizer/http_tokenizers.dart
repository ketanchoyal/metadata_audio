library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
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

  /// Prefetch a range of bytes asynchronously.
  ///
  /// For tokenizers that support on-demand fetching (RandomAccessTokenizer,
  /// ProbingRangeTokenizer), this fetches the data from the server.
  /// For tokenizers that already have all data (HttpTokenizer, RangeTokenizer),
  /// this is a no-op.
  Future<void> prefetchRange(int start, int end) async {
    // Default: no-op for tokenizers that already have data
  }
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
  bool get hasCompleteData =>
      _totalSize != null && _bytes.length >= _totalSize!;

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

/// Probing strategy for fetching scattered metadata across the file.
enum ProbeStrategy {
  /// Standard: Header only (0-256KB)
  headerOnly,

  /// Tail probe: Header + last 64KB (for ID3v1, etc.)
  headerAndTail,

  /// Scatter probe: Multiple random chunks throughout the file
  scatter,

  /// MP4 optimized: Header + moov atom detection
  mp4Optimized,

  /// Full: Download everything (fallback)
  full,
}

/// Tokenizer that probes multiple locations in the file for scattered metadata.
///
/// This is useful for formats where metadata may be at different locations:
/// - ID3v1 tags at the end of MP3 files
/// - MP4 moov atom at the end
/// - Cuesheets in the middle of FLAC files
class ProbingRangeTokenizer extends HttpBasedTokenizer {
  ProbingRangeTokenizer({
    required super.url,
    required super.fileInfo,
    required HttpClient client,
    required Duration timeout,
    required int totalSize,
    required Map<int, Uint8List> chunks,
    required this.probeStrategy,
  }) : _client = client,
       _timeout = timeout,
       _totalSize = totalSize,
       _chunks = chunks,
       _chunkSize = 65536; // 64KB chunks

  final HttpClient _client;
  final Duration _timeout;
  final int _totalSize;
  final int _chunkSize;
  final Map<int, Uint8List> _chunks;
  int _position = 0;
  bool _isClosed = false;

  /// The probing strategy used for this tokenizer.
  final ProbeStrategy probeStrategy;

  /// Total bytes fetched from server so far.
  int totalBytesFetched = 0;

  @override
  bool get canSeek => true;

  @override
  bool get hasCompleteData => false;

  @override
  int get position => _position;

  /// Create a ProbingRangeTokenizer with scatter-gather pattern.
  static Future<ProbingRangeTokenizer> fromUrl(
    String url, {
    Duration? timeout,
    ProbeStrategy probeStrategy = ProbeStrategy.scatter,
  }) async {
    final client = HttpClient();
    final effectiveTimeout = timeout ?? const Duration(seconds: 30);

    try {
      // HEAD request to get file size
      final headRequest = await client.headUrl(Uri.parse(url));
      headRequest.followRedirects = true;
      final headResponse = await headRequest.close().timeout(effectiveTimeout);

      if (headResponse.statusCode >= 300) {
        throw FileDownloadError(
          'HTTP ${headResponse.statusCode} error accessing URL: $url',
        );
      }

      final totalSize = headResponse.contentLength;
      if (totalSize <= 0) {
        throw FileDownloadError('Could not determine file size');
      }

      final acceptRanges = headResponse.headers.value('accept-ranges');
      final supportsRange =
          acceptRanges?.toLowerCase().contains('bytes') ?? false;

      if (!supportsRange) {
        throw FileDownloadError('Server does not support Range requests');
      }

      // Determine which ranges to fetch based on strategy
      final ranges = _calculateRanges(totalSize, probeStrategy);

      // Fetch all ranges in parallel and split into 64KB chunks
      final chunks = <int, Uint8List>{};
      var totalBytes = 0;

      await Future.wait(
        ranges.map((range) async {
          final chunk = await _fetchRange(url, client, effectiveTimeout, range);
          // Split fetched data into 64KB chunks stored at correct indices
          final startChunkIndex = range.start ~/ 65536;
          var offset = 0;
          var chunkIndex = startChunkIndex;
          while (offset < chunk.length) {
            final chunkEnd = min(offset + 65536, chunk.length);
            chunks[chunkIndex] = Uint8List.fromList(
              chunk.sublist(offset, chunkEnd),
            );
            offset = chunkEnd;
            chunkIndex++;
          }
          totalBytes += chunk.length;
        }),
      );

      final fileInfo = FileInfo(
        path: url,
        url: url,
        mimeType: headResponse.headers.contentType?.toString(),
        size: totalSize,
      );

      return ProbingRangeTokenizer(
        url: url,
        fileInfo: fileInfo,
        client: client,
        timeout: effectiveTimeout,
        totalSize: totalSize,
        chunks: chunks,
        probeStrategy: probeStrategy,
      )..totalBytesFetched = totalBytes;
    } on FileDownloadError {
      client.close();
      rethrow;
    } catch (e) {
      client.close();
      throw FileDownloadError('Failed to initialize: $e');
    }
  }

  /// Calculate byte ranges to fetch based on probe strategy.
  ///
  /// All range start positions are aligned down to [chunkSize] boundaries so
  /// that the fetched data maps correctly onto the internal chunk cache.
  static List<_ByteRange> _calculateRanges(
    int totalSize,
    ProbeStrategy strategy,
  ) {
    final ranges = <_ByteRange>[];
    const chunkSize = 65536; // 64KB

    // Align a byte offset down to the nearest chunk boundary.
    int alignDown(int pos) => (pos ~/ chunkSize) * chunkSize;

    switch (strategy) {
      case ProbeStrategy.headerOnly:
        // Just the first 256KB
        ranges.add(_ByteRange(0, min(262144, totalSize)));

      case ProbeStrategy.headerAndTail:
        // Header (256KB) + tail (64KB)
        ranges.add(_ByteRange(0, min(262144, totalSize)));
        if (totalSize > 262144) {
          final tailStart = alignDown(max(0, totalSize - chunkSize));
          ranges.add(_ByteRange(tailStart, totalSize));
        }

      case ProbeStrategy.scatter:
        // Header + middle + tail + random samples
        // 1. Header (256KB)
        ranges.add(_ByteRange(0, min(262144, totalSize)));

        // 2. Tail (64KB) - for ID3v1, etc.
        if (totalSize > 262144) {
          final tailStart = alignDown(max(0, totalSize - chunkSize));
          ranges.add(_ByteRange(tailStart, totalSize));
        }

        // 3. Middle probe (64KB at 50%)
        if (totalSize > 524288) {
          final middleStart = alignDown((totalSize ~/ 2) - 32768);
          ranges.add(_ByteRange(middleStart, middleStart + chunkSize));
        }

        // 4. Random probes (2x 64KB chunks)
        if (totalSize > 1048576) {
          final random = Random();
          for (var i = 0; i < 2; i++) {
            final start = alignDown(
              random.nextInt(totalSize - 131072) + chunkSize,
            );
            ranges.add(_ByteRange(start, start + chunkSize));
          }
        }

      case ProbeStrategy.mp4Optimized:
        // MP4 files often have moov atom at end
        // 1. Header (256KB) - ftyp, moov (if at start)
        ranges.add(_ByteRange(0, min(262144, totalSize)));

        // 2. Tail (up to 16MB) - moov often at end, and can be very large
        // for audiobooks with many chapters (5-10MB+)
        const maxTailSize = 16 * 1024 * 1024; // 16MB
        if (totalSize > maxTailSize) {
          final tailStart = alignDown(max(0, totalSize - maxTailSize));
          ranges.add(_ByteRange(tailStart, totalSize));
        } else {
          ranges.add(_ByteRange(0, totalSize));
        }

        // 3. Look for moov atom in middle
        if (totalSize > 524288) {
          // Try at 25%, 50%, 75%
          for (final pct in [0.25, 0.5, 0.75]) {
            final start = ((totalSize * pct).toInt() ~/ chunkSize) * chunkSize;
            ranges.add(_ByteRange(start, min(start + chunkSize, totalSize)));
          }
        }

      case ProbeStrategy.full:
        // Full download - shouldn't use this tokenizer for this
        ranges.add(_ByteRange(0, totalSize));
    }

    // Merge overlapping ranges
    return _mergeRanges(ranges);
  }

  /// Merge overlapping byte ranges to minimize requests.
  static List<_ByteRange> _mergeRanges(List<_ByteRange> ranges) {
    if (ranges.isEmpty) return ranges;

    // Sort by start position
    ranges.sort((a, b) => a.start.compareTo(b.start));

    final merged = <_ByteRange>[ranges.first];

    for (var i = 1; i < ranges.length; i++) {
      final current = ranges[i];
      final last = merged.last;

      if (current.start <= last.end) {
        // Overlapping or adjacent, merge them
        merged[merged.length - 1] = _ByteRange(
          last.start,
          max(last.end, current.end),
        );
      } else {
        merged.add(current);
      }
    }

    return merged;
  }

  /// Fetch a specific byte range from the server with retry logic.
  static Future<Uint8List> _fetchRange(
    String url,
    HttpClient client,
    Duration timeout,
    _ByteRange range,
  ) async {
    const maxRetries = 3;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.add('Range', 'bytes=${range.start}-${range.end - 1}');

        final response = await request.close().timeout(timeout);

        if (response.statusCode != 206 && response.statusCode != 200) {
          throw FileDownloadError(
            'Range request failed with status ${response.statusCode}',
          );
        }

        final chunks = await response.toList();
        return Uint8List.fromList([for (final chunk in chunks) ...chunk]);
      } on FileDownloadError {
        rethrow;
      } catch (e) {
        if (attempt < maxRetries - 1) {
          await Future<void>.delayed(
            Duration(milliseconds: 200 * (attempt + 1)),
          );
          continue;
        }
        throw FileDownloadError(
          'Failed to fetch range ${range.start}-${range.end}: $e',
        );
      }
    }
    // Should never reach here, but Dart needs a return
    throw FileDownloadError('Failed to fetch range after retries');
  }

  /// Get the chunk index for a given position.
  int _getChunkIndex(int position) => position ~/ _chunkSize;

  @override
  int readUint8() {
    final chunkIndex = _getChunkIndex(_position);
    final offset = _position % _chunkSize;

    final chunk = _chunks[chunkIndex];
    if (chunk == null || offset >= chunk.length) {
      throw TokenizerException(
        'Data not available at position $_position. '
        'Use prefetchRange() or ensure chunk is loaded.',
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
    if (newPosition > _totalSize) {
      throw TokenizerException('Seek beyond file size');
    }
    _position = newPosition;
  }

  @override
  void close() {
    _isClosed = true;
    _client.close();
    _chunks.clear();
  }

  /// Prefetch a range of bytes asynchronously.
  ///
  /// Uses consolidated HTTP range requests when possible, fetching
  /// large contiguous spans in a single request rather than many
  /// individual chunk requests.
  @override
  Future<void> prefetchRange(int start, int end) async {
    if (_isClosed) return;

    final startChunk = start ~/ _chunkSize;
    final endChunk = end ~/ _chunkSize;

    final missingChunks = <int>[];
    for (var i = startChunk; i <= endChunk; i++) {
      if (!_chunks.containsKey(i)) {
        missingChunks.add(i);
      }
    }

    if (missingChunks.isEmpty) return;

    // Group contiguous missing chunks into consolidated ranges
    final ranges = _groupContiguousChunks(missingChunks);

    // Fetch consolidated ranges in batches
    const maxConcurrency = 4;
    for (var i = 0; i < ranges.length; i += maxConcurrency) {
      final batch = ranges.skip(i).take(maxConcurrency);
      await Future.wait(batch.map((range) => _fetchAndSplitRange(range)));
    }
  }

  /// Group contiguous chunk indices into (startChunk, endChunk) ranges.
  List<(int, int)> _groupContiguousChunks(List<int> chunks) {
    if (chunks.isEmpty) return [];
    final ranges = <(int, int)>[];
    var rangeStart = chunks.first;
    var rangeEnd = chunks.first;
    for (var i = 1; i < chunks.length; i++) {
      if (chunks[i] == rangeEnd + 1) {
        rangeEnd = chunks[i];
      } else {
        ranges.add((rangeStart, rangeEnd));
        rangeStart = chunks[i];
        rangeEnd = chunks[i];
      }
    }
    ranges.add((rangeStart, rangeEnd));
    return ranges;
  }

  /// Fetch a consolidated range and split into individual chunks.
  Future<void> _fetchAndSplitRange((int, int) chunkRange) async {
    final startByte = chunkRange.$1 * _chunkSize;
    final endByte = min((chunkRange.$2 + 1) * _chunkSize, _totalSize);

    final data = await _fetchRange(
      url,
      _client,
      _timeout,
      _ByteRange(startByte, endByte),
    );

    // Split into chunk-sized pieces for the cache
    var offset = 0;
    for (
      var i = chunkRange.$1;
      i <= chunkRange.$2 && offset < data.length;
      i++
    ) {
      final chunkEnd = min(offset + _chunkSize, data.length);
      _chunks[i] = Uint8List.fromList(data.sublist(offset, chunkEnd));
      offset = chunkEnd;
    }
    totalBytesFetched += data.length;
  }

  /// Get information about which ranges have been fetched.
  Map<String, dynamic> get fetchedRanges {
    final ranges = _chunks.keys.toList()..sort();
    return {
      'chunks': ranges.length,
      'bytes': totalBytesFetched,
      'coverage':
          '${(totalBytesFetched / _totalSize * 100).toStringAsFixed(1)}%',
    };
  }
}

/// Simple byte range class.
class _ByteRange {
  _ByteRange(this.start, this.end);
  final int start;
  final int end;

  @override
  String toString() => '$start-$end';
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

  /// Total bytes fetched from server so far.
  int totalBytesFetched = 0;

  @override
  bool get canSeek => true;

  @override
  bool get hasCompleteData => false;

  /// Get the total file size if known.
  int? get totalSize => _totalSize;

  @override
  int get position => _position;

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
  ///
  /// Uses consolidated HTTP range requests when possible, fetching
  /// large contiguous spans in a single request rather than many
  /// individual chunk requests.
  @override
  Future<void> prefetchRange(int start, int end) async {
    if (_isClosed) return;

    final startChunk = start ~/ _chunkSize;
    final endChunk = end ~/ _chunkSize;

    final missingChunks = <int>[];
    for (var i = startChunk; i <= endChunk; i++) {
      if (!_cache.containsKey(i)) {
        missingChunks.add(i);
      }
    }

    if (missingChunks.isEmpty) return;

    // Group contiguous missing chunks into consolidated ranges
    final ranges = _groupContiguousChunks(missingChunks);

    // Fetch consolidated ranges in batches
    const maxConcurrency = 4;
    for (var i = 0; i < ranges.length; i += maxConcurrency) {
      final batch = ranges.skip(i).take(maxConcurrency);
      await Future.wait(batch.map((range) => _fetchAndSplitRange(range)));
    }
  }

  /// Group contiguous chunk indices into (startChunk, endChunk) ranges.
  List<(int, int)> _groupContiguousChunks(List<int> chunks) {
    if (chunks.isEmpty) return [];
    final ranges = <(int, int)>[];
    var rangeStart = chunks.first;
    var rangeEnd = chunks.first;
    for (var i = 1; i < chunks.length; i++) {
      if (chunks[i] == rangeEnd + 1) {
        rangeEnd = chunks[i];
      } else {
        ranges.add((rangeStart, rangeEnd));
        rangeStart = chunks[i];
        rangeEnd = chunks[i];
      }
    }
    ranges.add((rangeStart, rangeEnd));
    return ranges;
  }

  /// Fetch a consolidated range and split into individual chunks.
  Future<void> _fetchAndSplitRange((int, int) chunkRange) async {
    final startByte = chunkRange.$1 * _chunkSize;
    final totalSize = _totalSize;
    final endByte = totalSize != null
        ? min((chunkRange.$2 + 1) * _chunkSize, totalSize)
        : (chunkRange.$2 + 1) * _chunkSize;

    const maxRetries = 3;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final request = await _client.getUrl(Uri.parse(url));
        request.headers.add('Range', 'bytes=$startByte-${endByte - 1}');

        final response = await request.close().timeout(_timeout);

        if (response.statusCode != 206 && response.statusCode != 200) {
          throw FileDownloadError(
            'Range request failed: ${response.statusCode}',
          );
        }

        final responseChunks = await response.toList();
        final data = Uint8List.fromList([
          for (final chunk in responseChunks) ...chunk,
        ]);

        // Split into chunk-sized pieces for the cache
        var offset = 0;
        for (
          var i = chunkRange.$1;
          i <= chunkRange.$2 && offset < data.length;
          i++
        ) {
          final chunkEnd = min(offset + _chunkSize, data.length);
          _cache[i] = Uint8List.fromList(data.sublist(offset, chunkEnd));
          offset = chunkEnd;
        }
        totalBytesFetched += data.length;
        return;
      } on FileDownloadError {
        rethrow;
      } catch (e) {
        if (attempt < maxRetries - 1) {
          await Future<void>.delayed(
            Duration(milliseconds: 200 * (attempt + 1)),
          );
          continue;
        }
        throw FileDownloadError(
          'Failed to fetch range $startByte-$endByte: $e',
        );
      }
    }
  }
}

/// Strategy for URL parsing.
enum ParseStrategy {
  /// Download full file - works with any server
  fullDownload,

  /// Download header only - fastest for most files
  headerOnly,

  /// Probe multiple locations - for scattered metadata
  probe,

  /// Random access with on-demand fetching - most efficient for large files
  randomAccess,
}

// ---------------------------------------------------------------------------
// Internal helpers for format-aware strategy selection
// ---------------------------------------------------------------------------

/// Coarse audio format categories used only for strategy selection.
enum _AudioFormatCategory {
  /// MP4 / M4A / M4B – the moov atom can be anywhere in the file.
  mp4,

  /// MPEG / MP3 / AAC – ID3v2 at the start, optional ID3v1 at the end.
  mpeg,

  /// Formats that store all metadata exclusively at the start of the file
  /// (FLAC, Ogg, WAV, AIFF, Matroska, ASF/WMA, DSF, etc.).
  headerOnly,

  /// Unrecognised format; use a safe default.
  unknown,
}

/// Extract the file extension from a URL, ignoring query strings and fragments.
///
/// Returns the lowercase extension without the leading dot, or `null` if none
/// is found.
///
/// Examples:
/// - `https://example.com/audio.mp3` → `mp3`
/// - `https://example.com/audio.mp3?token=x` → `mp3`
/// - `https://example.com/stream` → `null`
String? _extractUrlExtension(String url) {
  try {
    final path = Uri.parse(url).path;
    final lastSlash = path.lastIndexOf('/');
    final filename = lastSlash >= 0 ? path.substring(lastSlash + 1) : path;
    final lastDot = filename.lastIndexOf('.');
    if (lastDot <= 0 || lastDot == filename.length - 1) return null;
    return filename.substring(lastDot + 1).toLowerCase();
  } catch (_) {
    return null;
  }
}

/// Classify the audio format from an HTTP Content-Type header and URL.
///
/// [mimeType] (from the HTTP `Content-Type` header) takes precedence over the
/// URL path extension.  Only the path component of [url] is inspected –
/// query strings and fragments are ignored.
///
/// Returns the most specific [_AudioFormatCategory] that can be determined, or
/// [_AudioFormatCategory.unknown] when the format cannot be identified.
_AudioFormatCategory _detectAudioFormatCategory({
  String? mimeType,
  required String url,
}) {
  final mime = mimeType?.toLowerCase() ?? '';
  final ext = _extractUrlExtension(url) ?? '';

  // --- MP4 / M4A family ---
  const _mp4Exts = {'mp4', 'm4a', 'm4b', 'm4p', 'm4r', 'm4v'};
  if (mime.contains('/mp4') ||
      mime.contains('m4a') ||
      mime.contains('m4b') ||
      _mp4Exts.contains(ext)) {
    return _AudioFormatCategory.mp4;
  }

  // --- MPEG / MP3 / AAC family ---
  const _mpegExts = {'mp3', 'mp2', 'mp1', 'aac', 'm2a', 'mpa', 'aacp'};
  if (mime.contains('mpeg') ||
      mime.contains('mp3') ||
      mime.contains('/aac') ||
      mime.contains('aacp') ||
      _mpegExts.contains(ext)) {
    return _AudioFormatCategory.mpeg;
  }

  // --- Header-only formats (metadata always at the start) ---
  const _headerOnlyExts = {
    'flac',
    'ogg',
    'oga',
    'ogv',
    'opus',
    'wav',
    'wave',
    'aiff',
    'aif',
    'mkv',
    'mka',
    'webm',
    'mpc',
    'mpp',
    'wv',
    'wvp',
    'ape',
    'dsf',
    'dff',
    'asf',
    'wma',
    'wmv',
  };
  if (mime.contains('flac') ||
      mime.contains('ogg') ||
      mime.contains('vorbis') ||
      mime.contains('opus') ||
      mime.contains('wav') ||
      mime.contains('aiff') ||
      mime.contains('matroska') ||
      mime.contains('webm') ||
      mime.contains('musepack') ||
      mime.contains('wavpack') ||
      mime.contains('dsf') ||
      mime.contains('dsdiff') ||
      mime.contains('asf') ||
      mime.contains('wma') ||
      _headerOnlyExts.contains(ext)) {
    return _AudioFormatCategory.headerOnly;
  }

  return _AudioFormatCategory.unknown;
}

// ---------------------------------------------------------------------------

/// Result of strategy detection.
class StrategyInfo {
  StrategyInfo({
    required this.strategy,
    required this.fileSize,
    required this.supportsRange,
    this.probeStrategy = ProbeStrategy.scatter,
    this.detectedFormat,
  });

  final ParseStrategy strategy;
  final int? fileSize;
  final bool supportsRange;

  /// The probe strategy recommended for this URL and file type.
  ///
  /// Only relevant when [strategy] is [ParseStrategy.probe].
  final ProbeStrategy probeStrategy;

  /// A human-readable label for the detected audio format category, e.g.
  /// `'mp4'`, `'mpeg'`, `'flac'`, or `'unknown'`.  Useful for logging.
  final String? detectedFormat;
}

/// Returns the best [ProbeStrategy] for the given format category.
///
/// This value is always set on [StrategyInfo], even for small files that use
/// [ParseStrategy.fullDownload], so callers can inspect the ideal probe
/// strategy independently of the overall fetch strategy.
ProbeStrategy _probeStrategyForCategory(_AudioFormatCategory category) =>
    switch (category) {
      _AudioFormatCategory.mp4 => ProbeStrategy.mp4Optimized,
      _AudioFormatCategory.mpeg => ProbeStrategy.headerAndTail,
      _AudioFormatCategory.headerOnly => ProbeStrategy.headerOnly,
      _AudioFormatCategory.unknown => ProbeStrategy.scatter,
    };

/// Detect the best parsing strategy for a URL.
///
/// Takes into account the HTTP server capabilities (file size, Range support)
/// **and** the audio format inferred from the Content-Type header and the URL
/// path extension.  This allows choosing both the most efficient
/// [ParseStrategy] and the most targeted [ProbeStrategy] for each format:
///
/// | Format | Probe strategy used |
/// |--------|---------------------|
/// | MP4 / M4A | [ProbeStrategy.mp4Optimized] |
/// | MP3 / MPEG / AAC | [ProbeStrategy.headerAndTail] |
/// | FLAC, OGG, WAV, AIFF … | [ParseStrategy.headerOnly] (no probe needed) |
/// | Unknown | [ProbeStrategy.scatter] |
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

    // Detect audio format from Content-Type and URL extension.
    final mimeType = headResponse.headers.contentType?.mimeType;
    final formatCategory = _detectAudioFormatCategory(
      mimeType: mimeType,
      url: url,
    );
    final detectedFormat = switch (formatCategory) {
      _AudioFormatCategory.mp4 => 'mp4',
      _AudioFormatCategory.mpeg => 'mpeg',
      _AudioFormatCategory.headerOnly => 'header-only',
      _AudioFormatCategory.unknown => 'unknown',
    };

    // Small files and servers without Range support always get a full download.
    if (fileSize == null || fileSize <= largeFileThreshold || !supportsRange) {
      return StrategyInfo(
        strategy: ParseStrategy.fullDownload,
        fileSize: fileSize,
        supportsRange: supportsRange,
        probeStrategy: _probeStrategyForCategory(formatCategory),
        detectedFormat: detectedFormat,
      );
    }

    // Large file with Range support: choose strategy and probe based on format.
    final ParseStrategy strategy;

    switch (formatCategory) {
      case _AudioFormatCategory.mp4:
        // moov atom can be anywhere – probe with mp4-optimised ranges.
        strategy = fileSize > 50 * 1024 * 1024
            ? ParseStrategy.randomAccess
            : ParseStrategy.probe;

      case _AudioFormatCategory.mpeg:
        // ID3v2 at start, ID3v1 at end – a header+tail probe covers both.
        strategy = fileSize > 50 * 1024 * 1024
            ? ParseStrategy.randomAccess
            : ParseStrategy.probe;

      case _AudioFormatCategory.headerOnly:
        // All metadata is at the very start – a header-only fetch is fastest.
        strategy = ParseStrategy.headerOnly;

      case _AudioFormatCategory.unknown:
        // Fall back to the previous generic size-based heuristic.
        strategy = fileSize > 50 * 1024 * 1024
            ? ParseStrategy.randomAccess
            : ParseStrategy.probe;
    }

    return StrategyInfo(
      strategy: strategy,
      fileSize: fileSize,
      supportsRange: supportsRange,
      probeStrategy: _probeStrategyForCategory(formatCategory),
      detectedFormat: detectedFormat,
    );
  } finally {
    client.close();
  }
}

/// Smart URL parser that automatically selects the best strategy.
///
/// Analyses the URL, server capabilities, and audio format to choose:
/// - [HttpTokenizer] for small files or non-Range servers
/// - [RangeTokenizer] for formats whose metadata is entirely at the start
///   (FLAC, OGG, WAV, AIFF, …)
/// - [ProbingRangeTokenizer] for formats with metadata at known locations
///   (MP3 → header+tail, MP4 → mp4-optimised probe)
/// - [RandomAccessTokenizer] for very large files (> 50 MB)
///
/// Parameters:
/// - [url]: The URL to parse
/// - [options]: Parse options
/// - [timeout]: HTTP timeout
/// - [strategy]: Force a specific strategy (default: auto-detect)
/// - [probeStrategy]: Override the probe strategy.  When `null` (the default),
///   the best [ProbeStrategy] for the detected audio format is used
///   automatically.  Only relevant when [strategy] is [ParseStrategy.probe].
/// - [onStrategySelected]: Callback when strategy is selected (for debugging).
///   The `reason` string includes detected format, file size, and Range support.
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
  ProbeStrategy? probeStrategy,
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

  // Resolve effective probe strategy: explicit override → auto-detected → scatter.
  final effectiveProbeStrategy =
      probeStrategy ?? info?.probeStrategy ?? ProbeStrategy.scatter;

  // Log strategy selection
  String reason;
  if (info != null) {
    reason =
        'Format: ${info.detectedFormat ?? "unknown"}, '
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

    case ParseStrategy.probe:
      return _parseWithProbe(
        url,
        effectiveTimeout,
        options,
        effectiveProbeStrategy,
      );

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

/// Parse using probing strategy for scattered metadata.
Future<AudioMetadata> _parseWithProbe(
  String url,
  Duration timeout,
  ParseOptions options,
  ProbeStrategy probeStrategy,
) async {
  final tokenizer = await ProbingRangeTokenizer.fromUrl(
    url,
    timeout: timeout,
    probeStrategy: probeStrategy,
  );

  try {
    return await parseFromTokenizer(tokenizer, options: options);
  } finally {
    tokenizer.close();
  }
}

/// Parse using random access.
Future<AudioMetadata> _parseWithRandomAccess(
  String url,
  Duration timeout,
  ParseOptions options,
) async {
  final tokenizer = await RandomAccessTokenizer.fromUrl(url, timeout: timeout);
  final totalSize = tokenizer.totalSize;

  try {
    // For random access, we need to prefetch chunks as the parser reads
    // Prefetch initial header (first 256KB)
    await tokenizer.prefetchRange(0, 262144);

    // For MP4/M4A files with chapters, also prefetch the tail region
    // as moov atom is often at the end of streaming-optimized files.
    // Audiobooks can have very large moov atoms (5-10MB+) due to chapter data.
    if (totalSize != null && totalSize > 0) {
      // Prefetch up to 16MB at the tail (or entire file if smaller)
      final tailSize = totalSize < 16 * 1024 * 1024
          ? totalSize
          : 16 * 1024 * 1024;
      final tailStart = totalSize - tailSize;
      await tokenizer.prefetchRange(tailStart, totalSize);
    }

    return await parseFromTokenizer(tokenizer, options: options);
  } finally {
    tokenizer.close();
  }
}
