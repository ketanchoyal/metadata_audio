library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/common/allocation.dart';
import 'package:metadata_audio/src/common/js_safe_numbers.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/dsdiff/dsdiff_token.dart';
import 'package:metadata_audio/src/id3v2/id3v2_parser.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class DsdiffParser {
  DsdiffParser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;
  List<int>? _channelPositions;

  Future<void> parse() async {
    final header = DsdiffToken.parseChunkHeader64(
      tokenizer.readBytes(DsdiffToken.chunkHeader64Length),
    );
    if (header.chunkId != 'FRM8') {
      throw DsdiffContentError("Invalid Chunk-ID, expected 'FRM8'");
    }

    metadata.setFormat(hasAudio: true, hasVideo: false);

    final type = DsdiffToken.parseFourCc(tokenizer.readBytes(4)).trimRight();
    switch (type) {
      case 'DSD':
        metadata.setFormat(container: 'DSDIFF/$type', lossless: true);
        await _readFrm8Chunks(header.chunkSize - BigInt.from(4));
        final format = metadata.format;
        if (format.sampleRate != null && format.numberOfChannels != null) {
          metadata.addStreamInfo(
            TrackInfo(
              type: 'audio',
              codecName: format.codec ?? 'DSD',
              duration: format.duration,
              bitrate: format.bitrate?.toDouble(),
              lossless: format.lossless,
              audio: AudioTrack(
                samplingFrequency: format.sampleRate,
                channels: format.numberOfChannels,
                channelPositions: _channelPositions,
                bitDepth: format.bitsPerSample,
                numberOfSamples: format.numberOfSamples,
              ),
            ),
          );
        }
        return;
      default:
        throw DsdiffContentError('Unsupported DSDIFF type: $type');
    }
  }

  Future<void> _readFrm8Chunks(BigInt remainingSize) async {
    var bytesRemaining = remainingSize;

    while (bytesRemaining >= BigInt.from(DsdiffToken.chunkHeader64Length)) {
      final chunkHeader = DsdiffToken.parseChunkHeader64(
        tokenizer.readBytes(DsdiffToken.chunkHeader64Length),
      );

      await _readData(chunkHeader);

      bytesRemaining -= BigInt.from(DsdiffToken.chunkHeader64Length);
      bytesRemaining -= chunkHeader.chunkSize;

      if (chunkHeader.chunkSize.isOdd && bytesRemaining > BigInt.zero) {
        tokenizer.skip(1);
        bytesRemaining -= BigInt.one;
      }
    }
  }

  Future<void> _readData(DsdiffChunkHeader64 header) async {
    final start = tokenizer.position;

    switch (header.chunkId.trim()) {
      case 'FVER':
        if (header.chunkSize >= BigInt.from(4)) {
          DsdiffToken.readUint32Le(tokenizer.readBytes(4), 0);
        }
        break;

      case 'PROP':
        final propType = DsdiffToken.parseFourCc(tokenizer.readBytes(4));
        if (propType != 'SND ') {
          throw DsdiffContentError('Unexpected PROP-chunk ID: $propType');
        }
        await _handleSoundPropertyChunks(header.chunkSize - BigInt.from(4));
        break;

      case 'ID3':
        final size = _safeToInt(header.chunkSize);
        validateAllocation(size, options, DsdiffContentError.new);
        final id3Data = tokenizer.readBytes(size);
        final id3Tokenizer = BytesTokenizer(
          Uint8List.fromList(id3Data),
          fileInfo: FileInfo(size: id3Data.length),
        );
        final id3v2 = Id3v2Parser(
          metadata: metadata,
          tokenizer: id3Tokenizer,
          options: options,
        );
        await id3v2.parse();
        break;

      case 'DSD':
        final channels = metadata.format.numberOfChannels;
        if (channels != null && channels > 0) {
          final numberOfSamples =
              (header.chunkSize * BigInt.from(8) ~/ BigInt.from(channels))
                  .toInt();
          metadata.setFormat(numberOfSamples: numberOfSamples);
        }
        final numberOfSamples = metadata.format.numberOfSamples;
        final sampleRate = metadata.format.sampleRate;
        if (numberOfSamples != null && sampleRate != null && sampleRate > 0) {
          metadata.setFormat(duration: numberOfSamples / sampleRate);
        }
        break;

      case 'COMT':
        _readCommentChunk(_safeToInt(header.chunkSize));
        break;

      default:
        break;
    }

    final consumed = tokenizer.position - start;
    final remaining = header.chunkSize - BigInt.from(consumed);
    if (remaining > BigInt.zero) {
      tokenizer.skip(_safeToInt(remaining));
    }
  }

  Future<void> _handleSoundPropertyChunks(BigInt remainingSize) async {
    var bytesRemaining = remainingSize;

    while (bytesRemaining > BigInt.zero) {
      final sndPropHeader = DsdiffToken.parseChunkHeader64(
        tokenizer.readBytes(DsdiffToken.chunkHeader64Length),
      );

      final start = tokenizer.position;
      switch (sndPropHeader.chunkId.trim()) {
        case 'FS':
          final sampleRate = DsdiffToken.readUint32Be(
            tokenizer.readBytes(4),
            0,
          );
          metadata.setFormat(sampleRate: sampleRate);
          break;

        case 'CHNL':
          final numChannels = DsdiffToken.readUint16Be(
            tokenizer.readBytes(2),
            0,
          );
          metadata.setFormat(numberOfChannels: numChannels);
          final channelIds = _handleChannelChunks(
            sndPropHeader.chunkSize - BigInt.from(2),
          );
          _channelPositions = _mapDsdiffChannelPositions(channelIds);
          break;

        case 'CMPR':
          final compressionIdCode = DsdiffToken.parseFourCc(
            tokenizer.readBytes(4),
          ).trimRight();
          final nameLength = DsdiffToken.readUint8(tokenizer.readBytes(1), 0);
          final compressionName = ascii.decode(
            tokenizer.readBytes(nameLength),
            allowInvalid: true,
          );

          if (compressionIdCode == 'DSD') {
            metadata.setFormat(lossless: true, bitsPerSample: 1);
          }
          metadata.setFormat(codec: '$compressionIdCode ($compressionName)');
          break;

        case 'ABSS':
          tokenizer.readBytes(8);
          break;

        case 'LSCO':
          tokenizer.readBytes(2);
          break;

        default:
          tokenizer.skip(_safeToInt(sndPropHeader.chunkSize));
      }

      final consumed = tokenizer.position - start;
      final remaining = sndPropHeader.chunkSize - BigInt.from(consumed);
      if (remaining > BigInt.zero) {
        tokenizer.skip(_safeToInt(remaining));
      }

      bytesRemaining -= BigInt.from(DsdiffToken.chunkHeader64Length);
      bytesRemaining -= sndPropHeader.chunkSize;

      if (sndPropHeader.chunkSize.isOdd && bytesRemaining > BigInt.zero) {
        tokenizer.skip(1);
        bytesRemaining -= BigInt.one;
      }
    }

    final format = metadata.format;
    if ((format.lossless ?? false) &&
        format.sampleRate != null &&
        format.numberOfChannels != null &&
        format.bitsPerSample != null) {
      final bitrate =
          format.sampleRate! * format.numberOfChannels! * format.bitsPerSample!;
      metadata.setFormat(bitrate: bitrate);
    }
  }

  List<String> _handleChannelChunks(BigInt remainingSize) {
    var bytesRemaining = remainingSize;
    final channels = <String>[];

    while (bytesRemaining >= BigInt.from(4)) {
      final channel = DsdiffToken.parseFourCc(tokenizer.readBytes(4));
      channels.add(channel);
      bytesRemaining -= BigInt.from(4);
    }

    return channels;
  }

  void _readCommentChunk(int chunkSize) {
    validateAllocation(chunkSize, options, DsdiffContentError.new);
    final bytes = tokenizer.readBytes(chunkSize);
    if (bytes.length < 2) {
      return;
    }

    final commentCount = DsdiffToken.readUint16Be(bytes, 0);
    var offset = 2;
    final comments = <String>[];

    for (var i = 0; i < commentCount; i++) {
      if (offset + 8 > bytes.length) {
        break;
      }

      final textLength = DsdiffToken.readUint16Be(bytes, offset + 6);
      offset += 8;
      if (offset + textLength > bytes.length) {
        break;
      }

      final text = ascii
          .decode(
            bytes.sublist(offset, offset + textLength),
            allowInvalid: true,
          )
          .trim();
      if (text.isNotEmpty) {
        comments.add(text);
      }
      offset += textLength;
    }

    if (comments.isNotEmpty) {
      metadata.addNativeTag('DSDIFF', 'COMT', comments);
    }
  }

  static List<int>? _mapDsdiffChannelPositions(List<String> channelIds) {
    if (channelIds.isEmpty) return null;
    final positions = <int>[];
    for (final id in channelIds) {
      final pos = _mapDsdiffChannelId(id);
      if (pos != null) positions.add(pos);
    }
    return positions.isEmpty ? null : positions;
  }

  static int? _mapDsdiffChannelId(String fourCc) {
    switch (fourCc.trim().toUpperCase()) {
      case 'SLFT':
      case 'MLFT':
        return 0x01; // Front Left
      case 'SRGT':
      case 'MRGT':
        return 0x02; // Front Right
      case 'C':
        return 0x04; // Front Center
      case 'LFE':
        return 0x08; // LFE
      case 'LS':
      case 'SBL':
        return 0x10; // Surround/Back Left
      case 'RS':
      case 'SBR':
        return 0x20; // Surround/Back Right
      default:
        return null;
    }
  }

  /// Maps DSDIFF 4CC channel IDs to human-readable speaker layout names.
  static List<String>? channelNames(List<String> channelIds) {
    if (channelIds.isEmpty) return null;
    final names = <String>[];
    for (final id in channelIds) {
      switch (id.trim().toUpperCase()) {
        case 'SLFT':
        case 'MLFT':
          names.add('front-left');
          break;
        case 'SRGT':
        case 'MRGT':
          names.add('front-right');
          break;
        case 'C':
          names.add('front-center');
          break;
        case 'LFE':
          names.add('lfe');
          break;
        case 'LS':
        case 'SBL':
          names.add('rear-left');
          break;
        case 'RS':
        case 'SBR':
          names.add('rear-right');
          break;
      }
    }
    return names.isEmpty ? null : names;
  }

  int _safeToInt(BigInt value) {
    if (value < BigInt.zero || value > maxSignedInt64) {
      throw DsdiffContentError('Chunk size out of supported range: $value');
    }
    return value.toInt();
  }
}
