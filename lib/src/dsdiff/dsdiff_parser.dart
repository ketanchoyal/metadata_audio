library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/dsdiff/dsdiff_token.dart';
import 'package:audio_metadata/src/id3v2/id3v2_parser.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

class DsdiffParser {
  DsdiffParser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

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
        final id3Data = tokenizer.readBytes(_safeToInt(header.chunkSize));
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
          _handleChannelChunks(sndPropHeader.chunkSize - BigInt.from(2));
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

  int _safeToInt(BigInt value) {
    if (value < BigInt.zero || value > BigInt.from(0x7FFFFFFFFFFFFFFF)) {
      throw DsdiffContentError('Chunk size out of supported range: $value');
    }
    return value.toInt();
  }
}
