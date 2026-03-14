library;

import 'dart:convert';

import 'package:audio_metadata/src/apev2/apev2_parser.dart';
import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/parse_error.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

class WavPackContentError extends UnexpectedFileContentError {
  WavPackContentError(String message) : super('WavPack', message);
}

class WavPackParser {
  WavPackParser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  static const int _blockHeaderLength = 32;
  static const int _metadataIdLength = 1;

  static const List<int> _sampleRates = <int>[
    6000,
    8000,
    9600,
    11025,
    12000,
    16000,
    22050,
    24000,
    32000,
    44100,
    48000,
    64000,
    88200,
    96000,
    192000,
    -1,
  ];

  int _audioDataSize = 0;

  Future<void> parse() async {
    metadata.setFormat(hasAudio: true, hasVideo: false);
    _audioDataSize = 0;

    await parseWavPackBlocks();

    final apev2 = Apev2Parser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await apev2.tryParseApeHeader();
  }

  Future<void> parseWavPackBlocks() async {
    while (await _isNextBlockWavPack()) {
      final header = _parseBlockHeader(tokenizer.readBytes(_blockHeaderLength));
      if (header.blockId != 'wvpk') {
        throw WavPackContentError('Invalid WavPack Block-ID');
      }

      if (header.blockIndex == 0 && metadata.format.container == null) {
        metadata.setFormat(
          container: 'WavPack',
          lossless: !header.flags.isHybrid,
          bitsPerSample: header.flags.bitsPerSample,
          numberOfChannels: header.flags.isMono ? 1 : 2,
          numberOfSamples: header.totalSamples,
          codec: header.flags.isDsd ? 'DSD' : 'PCM',
        );

        if (!header.flags.isDsd && header.flags.samplingRate > 0) {
          metadata.setFormat(
            sampleRate: header.flags.samplingRate,
            duration: header.totalSamples / header.flags.samplingRate,
          );
        }
      }

      final ignoreBytes = header.blockSize - (_blockHeaderLength - 8);
      if (ignoreBytes < 0) {
        throw WavPackContentError(
          'Invalid WavPack block size: ${header.blockSize}',
        );
      }

      if (header.blockIndex == 0) {
        await _parseMetadataSubBlock(header, ignoreBytes);
      } else {
        tokenizer.skip(ignoreBytes);
      }

      if (header.blockSamples > 0) {
        _audioDataSize += header.blockSize;
      }
    }

    final duration = metadata.format.duration;
    if (duration != null && duration > 0) {
      metadata.setFormat(bitrate: (_audioDataSize * 8 / duration).round());
    }
  }

  Future<bool> _isNextBlockWavPack() async {
    try {
      final blockId = ascii.decode(tokenizer.peekBytes(4), allowInvalid: true);
      return blockId == 'wvpk';
    } on TokenizerException {
      return false;
    }
  }

  Future<void> _parseMetadataSubBlock(
    _WavPackBlockHeader header,
    int remainingLength,
  ) async {
    var remaining = remainingLength;

    while (remaining > _metadataIdLength) {
      final id = _parseMetadataId(tokenizer.readUint8());
      final dataSizeInWords = id.largeBlock
          ? _readUint24Le(tokenizer.readBytes(3), 0)
          : tokenizer.readUint8();

      final dataLength = dataSizeInWords * 2 - (id.isOddSize ? 1 : 0);
      if (dataLength < 0) {
        throw WavPackContentError('Invalid metadata sub-block size');
      }

      final data = tokenizer.readBytes(dataLength);
      switch (id.functionId) {
        case 0x00:
          break;

        case 0x0E:
          if (!header.flags.isDsd) {
            throw WavPackContentError(
              'Only expect DSD block if DSD-flag is set',
            );
          }

          if (data.isEmpty) {
            throw WavPackContentError('Invalid ID_DSD_BLOCK data');
          }

          final multiplier = 1 << data[0];
          final sampleRate = header.flags.samplingRate * multiplier * 8;
          if (sampleRate > 0) {
            metadata.setFormat(
              sampleRate: sampleRate,
              duration: header.totalSamples / sampleRate,
            );
          }
          break;

        case 0x24:
          break;

        case 0x26:
          metadata.setFormat(audioMD5: data);
          break;

        case 0x2F:
          break;

        default:
          break;
      }

      remaining -=
          _metadataIdLength + (id.largeBlock ? 3 : 1) + dataSizeInWords * 2;
      if (id.isOddSize) {
        tokenizer.skip(1);
      }
    }

    if (remaining != 0) {
      throw WavPackContentError(
        'metadata-sub-block should fit remaining length',
      );
    }
  }

  _WavPackBlockHeader _parseBlockHeader(List<int> bytes) {
    if (bytes.length < _blockHeaderLength) {
      throw WavPackContentError('WavPack block header must be 32 bytes');
    }

    final flags = _readUint32Le(bytes, 24);
    var totalSamples = _readUint32Le(bytes, 12);

    final parsedFlags = _WavPackFlags(
      bitsPerSample: (1 + _getBitAlignedNumber(flags, 0, 2)) * 8,
      isMono: _isBitSet(flags, 2),
      isHybrid: _isBitSet(flags, 3),
      samplingRate: _sampleRates[_getBitAlignedNumber(flags, 23, 4)],
      isDsd: _isBitSet(flags, 31),
    );

    if (parsedFlags.isDsd) {
      totalSamples *= 8;
    }

    return _WavPackBlockHeader(
      blockId: ascii.decode(bytes.sublist(0, 4), allowInvalid: true),
      blockSize: _readUint32Le(bytes, 4),
      blockIndex: _readUint32Le(bytes, 16),
      totalSamples: totalSamples,
      blockSamples: _readUint32Le(bytes, 20),
      flags: parsedFlags,
    );
  }

  _WavPackMetadataId _parseMetadataId(int value) {
    return _WavPackMetadataId(
      functionId: _getBitAlignedNumber(value, 0, 6),
      isOptional: _isBitSet(value, 5),
      isOddSize: _isBitSet(value, 6),
      largeBlock: _isBitSet(value, 7),
    );
  }

  bool _isBitSet(int value, int bitOffset) {
    return _getBitAlignedNumber(value, bitOffset, 1) == 1;
  }

  int _getBitAlignedNumber(int value, int bitOffset, int length) {
    return (value >>> bitOffset) & (0xFFFFFFFF >>> (32 - length));
  }

  int _readUint24Le(List<int> bytes, int offset) {
    if (offset < 0 || offset + 3 > bytes.length) {
      throw WavPackContentError('uint24 LE read out of bounds');
    }

    return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
  }

  int _readUint32Le(List<int> bytes, int offset) {
    if (offset < 0 || offset + 4 > bytes.length) {
      throw WavPackContentError('uint32 LE read out of bounds');
    }

    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
}

class _WavPackBlockHeader {
  const _WavPackBlockHeader({
    required this.blockId,
    required this.blockSize,
    required this.blockIndex,
    required this.totalSamples,
    required this.blockSamples,
    required this.flags,
  });

  final String blockId;
  final int blockSize;
  final int blockIndex;
  final int totalSamples;
  final int blockSamples;
  final _WavPackFlags flags;
}

class _WavPackFlags {
  const _WavPackFlags({
    required this.bitsPerSample,
    required this.isMono,
    required this.isHybrid,
    required this.samplingRate,
    required this.isDsd,
  });

  final int bitsPerSample;
  final bool isMono;
  final bool isHybrid;
  final int samplingRate;
  final bool isDsd;
}

class _WavPackMetadataId {
  const _WavPackMetadataId({
    required this.functionId,
    required this.isOptional,
    required this.isOddSize,
    required this.largeBlock,
  });

  final int functionId;
  final bool isOptional;
  final bool isOddSize;
  final bool largeBlock;
}
