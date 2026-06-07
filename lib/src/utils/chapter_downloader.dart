import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/mp4/mp4_parser.dart';
import 'package:metadata_audio/src/mpeg/mpeg_parser.dart';
import 'package:metadata_audio/src/mpeg/xing_tag.dart';

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

  /// Whether the download completed successfully.
  final bool isSuccess;

  /// The output file path on success, `null` on failure.
  final String? outputPath;

  /// A human-readable error message on failure, `null` on success.
  final String? error;
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
      final isRemote =
          originalUrl.startsWith('http://') ||
          originalUrl.startsWith('https://');

      var isMp3 =
          originalUrl.toLowerCase().endsWith('.mp3') ||
          originalUrl.toLowerCase().contains('.mp3?') ||
          originalUrl.toLowerCase().contains('/mp3/');

      if (!isMp3 && isRemote) {
        try {
          final strategyInfo = await detectStrategy(originalUrl);
          if (strategyInfo.detectedFormat == 'mpeg') {
            isMp3 = true;
          }
        } catch (_) {}
      }

      if (!isMp3 && !isRemote) {
        try {
          final file = File(originalUrl);
          final raf = await file.open();
          try {
            final magic = await raf.read(4);
            if (magic.length >= 3 &&
                magic[0] == 0x49 &&
                magic[1] == 0x44 &&
                magic[2] == 0x33) {
              isMp3 = true;
            } else if (magic.length >= 2 &&
                magic[0] == 0xFF &&
                (magic[1] & 0xE0) == 0xE0) {
              isMp3 = true;
            }
          } finally {
            await raf.close();
          }
        } catch (_) {}
      }

      var finalPath = outputPath;
      if (isMp3) {
        if (!finalPath.toLowerCase().endsWith('.mp3')) {
          finalPath += '.mp3';
        }
      } else {
        if (!finalPath.toLowerCase().endsWith('.aac')) {
          finalPath += '.aac';
        }
      }

      if (isMp3) {
        return _downloadMp3Chapter(
          originalUrl: originalUrl,
          chapterStartMs: chapterStartMs,
          chapterEndMs: chapterEndMs,
          outputPath: finalPath,
          isRemote: isRemote,
          httpClient: httpClient,
          onProgress: onProgress,
          onPhase: onPhase,
          parallelChunks: parallelChunks,
        );
      }

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
        final audioTrack = tracks.where((t) => t.isAudio).firstOrNull;
        if (audioTrack == null) {
          return const ChapterDownloadResult.failure(
            'No audio track found in the original audiobook.',
          );
        }

        onPhase?.call(ChapterDownloadPhase.resolvingSamples);
        final timeScale = audioTrack.timeScale ?? 1000;
        final startOffsetUnits = (chapterStartMs * timeScale) ~/ 1000;
        final endOffsetUnits = (chapterEndMs * timeScale) ~/ 1000;

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
        final samplingFreqIndex = _getSamplingFrequencyIndex(sampleRate);

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
          await for (final chunk in localFile.openRead(rangeStart, rangeEnd)) {
            builder.add(chunk);
            readBytes += chunk.length;
            if (onProgress != null && downloadSize > 0) {
              onProgress((readBytes / downloadSize).clamp(0.0, 1.0));
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
          if (audioTrack.sampleSize != null && audioTrack.sampleSize! > 0) {
            size = audioTrack.sampleSize!;
          } else if (i < audioTrack.sampleSizeTable.length) {
            size = audioTrack.sampleSizeTable[i];
          } else {
            break;
          }

          if (relativeOffset + size > payloadBytes.length) break;

          outputBuilder.add(
            _buildAdtsHeader(
              profile: 1, // AAC-LC
              samplingFrequencyIndex: samplingFreqIndex,
              channelConfig: channels,
              frameLength: size + 7,
            ),
          );
          outputBuilder.add(
            payloadBytes.sublist(relativeOffset, relativeOffset + size),
          );
        }

        await File(finalPath).writeAsBytes(outputBuilder.takeBytes());
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
        return await _downloadSingleRange(
          client: client,
          url: url,
          rangeStart: rangeStart,
          rangeEnd: rangeStart + totalSize - 1,
          onProgress: onProgress,
        );
      }

      final chunkSize = totalSize ~/ numChunks;
      final downloadedPerChunk = List<int>.filled(numChunks, 0);

      final futures = List<Future<Uint8List>>.generate(numChunks, (i) {
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
            downloadedPerChunk[i] = (expectedChunkSize * chunkProgress).round();
            if (onProgress != null) {
              final totalDownloaded = downloadedPerChunk.fold<int>(
                0,
                (a, b) => a + b,
              );
              onProgress((totalDownloaded / totalSize).clamp(0.0, 1.0));
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
      onProgress?.call((received / expectedSize).clamp(0.0, 1.0));
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
    header[2] =
        ((profile & 3) << 6) |
        ((samplingFrequencyIndex & 0x0F) << 2) |
        ((channelConfig >> 2) & 1);
    header[3] = ((channelConfig & 3) << 6) | ((frameLength >> 11) & 3);
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

  static Future<ChapterDownloadResult> _downloadMp3Chapter({
    required String originalUrl,
    required int chapterStartMs,
    required int chapterEndMs,
    required String outputPath,
    required bool isRemote,
    HttpClient? httpClient,
    void Function(double progress)? onProgress,
    void Function(ChapterDownloadPhase phase)? onPhase,
    int parallelChunks = 4,
  }) async {
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

    try {
      onPhase?.call(ChapterDownloadPhase.analyzing);
      final mpegOffset = await _findMpegAudioOffset(tokenizer);

      final header = await _findFirstMpegFrame(tokenizer, mpegOffset);
      if (header == null) {
        return const ChapterDownloadResult.failure(
          'Could not parse first MPEG frame header in MP3 file.',
        );
      }

      final xingInfo = await _findXingHeader(tokenizer, header, mpegOffset);

      onPhase?.call(ChapterDownloadPhase.resolvingSamples);
      int startByte;
      int endByte;

      final frameDurationMs =
          (header.samplesPerFrame * 1000) / header.sampleRate;
      if (xingInfo != null &&
          xingInfo.toc != null &&
          xingInfo.streamSize != null &&
          xingInfo.numFrames != null) {
        final totalDurationMs =
            (xingInfo.numFrames! * header.samplesPerFrame * 1000) /
            header.sampleRate;

        final startPercent = (chapterStartMs / totalDurationMs) * 100;
        final endPercent = (chapterEndMs / totalDurationMs) * 100;

        final startOffsetNormalized = _interpolateToc(
          xingInfo.toc!,
          startPercent,
        );
        final endOffsetNormalized = _interpolateToc(xingInfo.toc!, endPercent);

        startByte =
            mpegOffset +
            ((startOffsetNormalized / 256.0) * xingInfo.streamSize!).round();
        endByte =
            mpegOffset +
            ((endOffsetNormalized / 256.0) * xingInfo.streamSize!).round();
      } else {
        final startFrame = chapterStartMs ~/ frameDurationMs;
        final endFrame = (chapterEndMs / frameDurationMs).ceil();
        startByte = mpegOffset + startFrame * header.frameLength;
        endByte = mpegOffset + endFrame * header.frameLength;
      }

      final fileSize = tokenizer.fileInfo?.size;
      if (fileSize != null) {
        startByte = startByte.clamp(mpegOffset, fileSize);
        endByte = endByte.clamp(mpegOffset, fileSize);
      }

      if (xingInfo != null && startByte == mpegOffset) {
        startByte = (startByte + header.frameLength).clamp(
          mpegOffset,
          fileSize ?? (startByte + header.frameLength),
        );
      }

      final downloadSize = endByte - startByte;
      if (downloadSize <= 0) {
        return const ChapterDownloadResult.failure(
          'Calculated download byte size is zero.',
        );
      }

      onPhase?.call(ChapterDownloadPhase.downloading);
      final Uint8List payloadBytes;
      if (isRemote) {
        payloadBytes = await _downloadRangeParallel(
          url: originalUrl,
          rangeStart: startByte,
          totalSize: downloadSize,
          parallelChunks: parallelChunks,
          httpClient: httpClient,
          onProgress: onProgress,
        );
      } else {
        final localFile = File(originalUrl);
        final builder = BytesBuilder(copy: false);
        var readBytes = 0;
        await for (final chunk in localFile.openRead(startByte, endByte)) {
          builder.add(chunk);
          readBytes += chunk.length;
          if (onProgress != null && downloadSize > 0) {
            onProgress((readBytes / downloadSize).clamp(0.0, 1.0));
          }
        }
        payloadBytes = builder.takeBytes();
      }

      onPhase?.call(ChapterDownloadPhase.writing);

      // Find the first valid MPEG frame syncword in the downloaded bytes to align the start
      var alignedStart = 0;
      while (alignedStart < payloadBytes.length - 4) {
        if (payloadBytes[alignedStart] == 0xFF &&
            (payloadBytes[alignedStart + 1] & 0xE0) == 0xE0) {
          final sync = payloadBytes.sublist(alignedStart, alignedStart + 4);
          if (!MpegFrameHeader.isAdtsHeader(sync)) {
            final header = MpegFrameHeader.parse(sync);
            if (header != null) {
              break;
            }
          }
        }
        alignedStart++;
      }

      final slicedBytes = alignedStart < payloadBytes.length
          ? payloadBytes.sublist(alignedStart)
          : payloadBytes;

      await File(outputPath).writeAsBytes(slicedBytes);
      return ChapterDownloadResult.success(outputPath);
    } catch (e) {
      return ChapterDownloadResult.failure(e.toString());
    } finally {
      if (isRemote) {
        (tokenizer as RandomAccessTokenizer).close();
      } else {
        (tokenizer as FileTokenizer).close();
      }
    }
  }

  static Future<int> _findMpegAudioOffset(Tokenizer tokenizer) async {
    var offset = 0;
    while (true) {
      try {
        if (tokenizer is HttpBasedTokenizer) {
          await tokenizer.prefetchRange(offset, offset + 10);
        }
        final bytes = tokenizer.peekBytes(10);
        if (bytes.length < 10) break;
        final tag = String.fromCharCodes(bytes.sublist(0, 3));
        if (tag == 'ID3') {
          final sizeBytes = bytes.sublist(6, 10);
          final size =
              (sizeBytes[0] << 21) |
              (sizeBytes[1] << 14) |
              (sizeBytes[2] << 7) |
              sizeBytes[3];
          final hasFooter = (bytes[5] & 0x10) != 0;
          final totalTagSize = 10 + size + (hasFooter ? 10 : 0);
          if (tokenizer is HttpBasedTokenizer) {
            await tokenizer.prefetchRange(offset, offset + totalTagSize);
          }
          tokenizer.skip(totalTagSize);
          offset += totalTagSize;
        } else {
          break;
        }
      } catch (_) {
        break;
      }
    }
    return offset;
  }

  static Future<MpegFrameHeader?> _findFirstMpegFrame(
    Tokenizer tokenizer,
    int mpegOffset,
  ) async {
    tokenizer.seek(mpegOffset);
    var pos = mpegOffset;
    if (tokenizer is HttpBasedTokenizer) {
      await tokenizer.prefetchRange(pos, pos + 4096);
    }
    while (true) {
      try {
        final sync = tokenizer.peekBytes(4);
        if (sync.length < 4) return null;
        if (sync[0] == 0xFF && (sync[1] & 0xE0) == 0xE0) {
          if (!MpegFrameHeader.isAdtsHeader(sync)) {
            final header = MpegFrameHeader.parse(sync);
            if (header != null) return header;
          }
        }
        tokenizer.skip(1);
        pos++;
        if (pos % 4096 == 0 && tokenizer is HttpBasedTokenizer) {
          await tokenizer.prefetchRange(pos, pos + 4096);
        }
      } catch (_) {
        return null;
      }
    }
  }

  static Future<XingInfoTag?> _findXingHeader(
    Tokenizer tokenizer,
    MpegFrameHeader header,
    int mpegOffset,
  ) async {
    try {
      if (tokenizer is HttpBasedTokenizer) {
        await tokenizer.prefetchRange(
          mpegOffset,
          mpegOffset + header.frameLength,
        );
      }
      tokenizer.seek(mpegOffset);
      final frameData = tokenizer.peekBytes(header.frameLength);
      if (frameData.length < header.frameLength) return null;

      var offset = 4;
      if (header.isProtectedByCrc) {
        offset += 2;
      }

      final sideInfoLength = header.sideInformationLength;
      if (sideInfoLength == null) return null;
      offset += sideInfoLength;

      if (offset + 4 > frameData.length) return null;
      final tag = String.fromCharCodes(frameData.sublist(offset, offset + 4));
      if (tag == 'Xing' || tag == 'Info') {
        return parseXingHeader(frameData, offset + 4);
      }
    } catch (_) {}
    return null;
  }

  static double _interpolateToc(List<int> toc, double percent) {
    if (percent <= 0) return 0;
    if (percent >= 100) return 255;

    final index = percent.floor().clamp(0, 98);
    final fraction = percent - index;

    final val1 = toc[index] & 0xFF;
    final val2 = toc[index + 1] & 0xFF;

    return val1 + (val2 - val1) * fraction;
  }
}
