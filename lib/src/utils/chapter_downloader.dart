import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/mp4/mp4_parser.dart';

/// The current phase of the chapter download process.
enum ChapterDownloadPhase {
  /// Connecting to the source (remote URL or local file).
  connecting,

  /// Parsing the MP4/M4B container structure.
  analyzing,

  /// Resolving chapter timestamps to audio sample boundaries.
  resolvingSamples,

  /// Downloading the raw audio payload (remote) or reading it (local).
  downloading,

  /// Wrapping samples with ADTS headers and writing the output file.
  writing,
}

/// The result of a [ChapterDownloader.downloadChapter] operation.
class ChapterDownloadResult {
  /// Whether the download completed successfully.
  final bool isSuccess;

  /// The output file path on success, `null` on failure.
  final String? outputPath;

  /// A human-readable error message on failure, `null` on success.
  final String? error;

  const ChapterDownloadResult._({
    required this.isSuccess,
    this.outputPath,
    this.error,
  });

  /// Creates a successful result with the given [outputPath].
  const ChapterDownloadResult.success(String outputPath)
      : this._(isSuccess: true, outputPath: outputPath);

  /// Creates a failed result with the given [error] message.
  const ChapterDownloadResult.failure(String error)
      : this._(isSuccess: false, error: error);
}

/// A utility class for downloading playable chapter files
/// from audiobook range requests.
class ChapterDownloader {
  ChapterDownloader._();

  /// Downloads or extracts a specific MP4/M4B audiobook chapter
  /// directly to [outputPath] as a playable standalone ADTS AAC file.
  ///
  /// This extracts the audio track sample boundaries using
  /// [Mp4Parser], downloads or reads only the specific sample range
  /// for the chapter, and adds ADTS headers to each frame.
  /// The resulting file is extremely lightweight, starts playing
  /// immediately at 0:00, and shows the correct playback progress.
  ///
  /// Returns a [ChapterDownloadResult] indicating success or failure.
  ///
  /// [originalUrl] can be a remote URL or a local file path.
  /// [chapterStartMs] / [chapterEndMs] are chapter boundaries in ms.
  /// [outputPath] is the destination (`.aac` appended if missing).
  /// [httpClient] is an optional custom [HttpClient] for remote URLs.
  /// [onProgress] is called with 0.0–1.0 during the download phase.
  /// [onPhase] is called with a [ChapterDownloadPhase] enum value
  /// each time the operation transitions to a new phase.
  /// [parallelChunks] controls the number of parallel HTTP
  /// connections for remote downloads (default: 4).
  static Future<ChapterDownloadResult> downloadChapter({
    required String originalUrl,
    required int chapterStartMs,
    required int chapterEndMs,
    required String outputPath,
    HttpClient? httpClient,
    void Function(double progress)? onProgress,
    void Function(ChapterDownloadPhase phase)? onPhase,
    int parallelChunks = 4,
  }) async {
    try {
      var finalPath = outputPath;
      if (!finalPath.toLowerCase().endsWith('.aac')) {
        finalPath += '.aac';
      }

      final isRemote = originalUrl.startsWith('http://') ||
          originalUrl.startsWith('https://');
      final Tokenizer tokenizer;

      onPhase?.call(ChapterDownloadPhase.connecting);
      if (isRemote) {
        tokenizer = await RandomAccessTokenizer.fromUrl(originalUrl);
      } else {
        final file = File(originalUrl);
        if (!await file.exists()) {
          return ChapterDownloadResult.failure(
            'Original local file not found at $originalUrl',
          );
        }
        tokenizer = FileTokenizer.fromFile(file);
      }

      final mapper = CombinedTagMapper();
      final collector = MetadataCollector(
        mapper,
        const ParseOptions(includeChapters: true),
      );
      final parser = Mp4Parser(
        metadata: collector,
        tokenizer: tokenizer,
        options: const ParseOptions(includeChapters: true),
      );

      try {
        onPhase?.call(ChapterDownloadPhase.analyzing);
        await parser.parse();
        final tracks = parser.getTrackInfos();
        final audioTrack =
            tracks.where((t) => t.isAudio).firstOrNull;
        if (audioTrack == null) {
          return const ChapterDownloadResult.failure(
            'No audio track found in the original audiobook.',
          );
        }

        onPhase?.call(ChapterDownloadPhase.resolvingSamples);
        final timeScale = audioTrack.timeScale ?? 1000;
        final startOffsetUnits =
            (chapterStartMs * timeScale) ~/ 1000;
        final endOffsetUnits =
            (chapterEndMs * timeScale) ~/ 1000;

        final startSampleIndex = parser.getSampleIndexForTime(
          audioTrack.trackId,
          startOffsetUnits,
        );
        final endSampleIndex = parser.getSampleIndexForTime(
          audioTrack.trackId,
          endOffsetUnits,
        );

        if (startSampleIndex == null || endSampleIndex == null) {
          return const ChapterDownloadResult.failure(
            'Could not map chapter timestamps to audio samples.',
          );
        }

        final startByteOffset = parser.getByteOffsetForSample(
          audioTrack.trackId,
          startSampleIndex,
        );
        if (startByteOffset == null) {
          return const ChapterDownloadResult.failure(
            'Could not resolve starting byte offset for chapter.',
          );
        }

        final rangeStart = startByteOffset;
        final lastSampleIndex = endSampleIndex - 1;
        final lastSampleByteOffset = parser.getByteOffsetForSample(
          audioTrack.trackId,
          lastSampleIndex,
        );
        if (lastSampleByteOffset == null) {
          return const ChapterDownloadResult.failure(
            'Could not resolve ending byte offset for chapter.',
          );
        }
        int lastSampleSize;
        if (audioTrack.sampleSize != null && audioTrack.sampleSize! > 0) {
          lastSampleSize = audioTrack.sampleSize!;
        } else if (lastSampleIndex < audioTrack.sampleSizeTable.length) {
          lastSampleSize = audioTrack.sampleSizeTable[lastSampleIndex];
        } else {
          return const ChapterDownloadResult.failure(
            'Could not resolve ending sample size.',
          );
        }
        final rangeEnd = lastSampleByteOffset + lastSampleSize;
        final downloadSize = rangeEnd - rangeStart;

        if (downloadSize <= 0) {
          return const ChapterDownloadResult.failure(
            'Chapter does not contain any audio samples.',
          );
        }

        final sampleRate = audioTrack.sampleRate ?? 44100;
        final channels = audioTrack.numberOfChannels ?? 2;
        final samplingFreqIndex =
            _getSamplingFrequencyIndex(sampleRate);

        // Fetch the raw payload bytes (including any interleaved gaps/non-audio bytes)
        final Uint8List payloadBytes;
        if (isRemote) {
          onPhase?.call(ChapterDownloadPhase.downloading);
          payloadBytes = await _downloadRangeParallel(
            url: originalUrl,
            rangeStart: rangeStart,
            totalSize: downloadSize,
            parallelChunks: parallelChunks,
            httpClient: httpClient,
            onProgress: onProgress,
          );
        } else {
          onPhase?.call(ChapterDownloadPhase.downloading);
          final localFile = File(originalUrl);
          final builder = BytesBuilder(copy: false);
          var readBytes = 0;
          await for (final chunk in localFile.openRead(
            rangeStart,
            rangeEnd,
          )) {
            builder.add(chunk);
            readBytes += chunk.length;
            if (onProgress != null && downloadSize > 0) {
              onProgress(
                (readBytes / downloadSize).clamp(0.0, 1.0),
              );
            }
          }
          payloadBytes = builder.takeBytes();
        }

        // Build ADTS-wrapped output in memory, write in one shot
        onPhase?.call(ChapterDownloadPhase.writing);
        final outputBuilder = BytesBuilder();
        for (var i = startSampleIndex; i < endSampleIndex; i++) {
          final sampleOffset = parser.getByteOffsetForSample(
            audioTrack.trackId,
            i,
          );
          if (sampleOffset == null) break;
          final relativeOffset = sampleOffset - rangeStart;

          int size;
          if (audioTrack.sampleSize != null &&
              audioTrack.sampleSize! > 0) {
            size = audioTrack.sampleSize!;
          } else if (i < audioTrack.sampleSizeTable.length) {
            size = audioTrack.sampleSizeTable[i];
          } else {
            break;
          }

          if (relativeOffset + size > payloadBytes.length) break;

          outputBuilder.add(_buildAdtsHeader(
            profile: 1, // AAC-LC
            samplingFrequencyIndex: samplingFreqIndex,
            channelConfig: channels,
            frameLength: size + 7,
          ));
          outputBuilder.add(
            payloadBytes.sublist(relativeOffset, relativeOffset + size),
          );
        }

        await File(finalPath).writeAsBytes(
          outputBuilder.takeBytes(),
        );
        return ChapterDownloadResult.success(finalPath);
      } finally {
        if (isRemote) {
          (tokenizer as RandomAccessTokenizer).close();
        } else {
          (tokenizer as FileTokenizer).close();
        }
      }
    } catch (e) {
      return ChapterDownloadResult.failure(e.toString());
    }
  }

  /// Downloads a byte range using parallel HTTP connections.
  ///
  /// Splits the total range into [parallelChunks] segments and
  /// downloads them concurrently via [Future.wait]. Falls back to
  /// a single request for payloads smaller than 512 KB.
  static Future<Uint8List> _downloadRangeParallel({
    required String url,
    required int rangeStart,
    required int totalSize,
    required int parallelChunks,
    HttpClient? httpClient,
    void Function(double progress)? onProgress,
  }) async {
    // Don't bother parallelising tiny payloads
    const minChunkSize = 256 * 1024; // 256 KB
    var numChunks = parallelChunks.clamp(1, 8);
    if (totalSize < minChunkSize * 2) {
      numChunks = 1;
    } else if (totalSize ~/ numChunks < minChunkSize) {
      numChunks = totalSize ~/ minChunkSize;
      if (numChunks < 1) numChunks = 1;
    }

    final client = httpClient ?? HttpClient();
    final shouldCloseClient = httpClient == null;

    try {
      if (numChunks <= 1) {
        return _downloadSingleRange(
          client: client,
          url: url,
          rangeStart: rangeStart,
          rangeEnd: rangeStart + totalSize - 1,
          onProgress: onProgress,
        );
      }

      final chunkSize = totalSize ~/ numChunks;
      final downloadedPerChunk =
          List<int>.filled(numChunks, 0);

      final futures =
          List<Future<Uint8List>>.generate(numChunks, (i) {
        final start = rangeStart + (i * chunkSize);
        final end = (i == numChunks - 1)
            ? rangeStart + totalSize - 1
            : start + chunkSize - 1;
        final expectedChunkSize = end - start + 1;

        return _downloadSingleRange(
          client: client,
          url: url,
          rangeStart: start,
          rangeEnd: end,
          onProgress: (chunkProgress) {
            downloadedPerChunk[i] =
                (expectedChunkSize * chunkProgress).round();
            if (onProgress != null) {
              final totalDownloaded = downloadedPerChunk
                  .fold<int>(0, (a, b) => a + b);
              onProgress(
                (totalDownloaded / totalSize).clamp(0.0, 1.0),
              );
            }
          },
        );
      });

      final results = await Future.wait(futures);
      final combined = BytesBuilder(copy: false);
      for (final chunk in results) {
        combined.add(chunk);
      }
      return combined.takeBytes();
    } finally {
      if (shouldCloseClient) client.close();
    }
  }

  /// Downloads a single byte range via an HTTP Range request.
  static Future<Uint8List> _downloadSingleRange({
    required HttpClient client,
    required String url,
    required int rangeStart,
    required int rangeEnd,
    void Function(double progress)? onProgress,
  }) async {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.add('Range', 'bytes=$rangeStart-$rangeEnd');
    final response = await request.close();

    if (response.statusCode >= 400) {
      throw HttpException(
        'Failed to download chunk: HTTP ${response.statusCode}',
      );
    }

    final expectedSize = rangeEnd - rangeStart + 1;
    final builder = BytesBuilder(copy: false);
    var received = 0;

    await for (final chunk in response) {
      builder.add(chunk);
      received += chunk.length;
      onProgress?.call(
        (received / expectedSize).clamp(0.0, 1.0),
      );
    }

    return builder.takeBytes();
  }

  static List<int> _buildAdtsHeader({
    required int profile,
    required int samplingFrequencyIndex,
    required int channelConfig,
    required int frameLength,
  }) {
    final header = Uint8List(7);
    header[0] = 0xFF;
    header[1] = 0xF1;
    header[2] = ((profile & 3) << 6) |
        ((samplingFrequencyIndex & 0x0F) << 2) |
        ((channelConfig >> 2) & 1);
    header[3] =
        ((channelConfig & 3) << 6) | ((frameLength >> 11) & 3);
    header[4] = (frameLength >> 3) & 0xFF;
    header[5] = ((frameLength & 7) << 5) | 0x1F;
    header[6] = 0xFC;
    return header;
  }

  static int _getSamplingFrequencyIndex(int sampleRate) {
    switch (sampleRate) {
      case 96000:
        return 0;
      case 88200:
        return 1;
      case 64000:
        return 2;
      case 48000:
        return 3;
      case 44100:
        return 4;
      case 32000:
        return 5;
      case 24000:
        return 6;
      case 22050:
        return 7;
      case 16000:
        return 8;
      case 12000:
        return 9;
      case 11025:
        return 10;
      case 8000:
        return 11;
      case 7350:
        return 12;
      default:
        return 4;
    }
  }
}
