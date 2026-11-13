library;

import 'dart:convert';

import 'package:metadata_audio/src/apev2/apev2_parser.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parse_error.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

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
  int _sampleRate = 0;
  int _dsdMultiplier = 1;
  bool _physicalEof = false;

  Future<void> parse() async {
    metadata.setFormat(hasAudio: true, hasVideo: false);
    _audioDataSize = 0;

    await parseWavPackBlocks();
    if (_physicalEof) {
      return;
    }

    final apev2 = Apev2Parser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await apev2.tryParseApeHeader();
  }

  Future<void> parseWavPackBlocks() async {
    int? totalSamples;
    var sampleExtent = 0;
    int? groupIndex;
    var groupSamples = 0;
    var complete = true;
    var isDsd = false;

    while (await _isNextBlockWavPack()) {
      final header = _parseBlockHeader(tokenizer.readBytes(_blockHeaderLength));
      if (header.blockId != 'wvpk') {
        break;
      }

      if (header.blockIndex == 0 && metadata.format.container == null) {
        metadata.setFormat(
          container: 'WavPack',
          lossless: !header.flags.isHybrid,
          bitsPerSample: header.flags.bitsPerSample,
          numberOfChannels: header.flags.isMono ? 1 : 2,
          codec: header.flags.isDsd ? 'DSD' : 'PCM',
        );
        _sampleRate = header.flags.samplingRate;
        isDsd = header.flags.isDsd;
        totalSamples = header.totalSamples > 0 ? header.totalSamples : null;
      }

      final ignoreBytes = header.blockSize - (_blockHeaderLength - 8);
      final fileSize = tokenizer.fileInfo?.size;
      if (ignoreBytes < 0 ||
          (fileSize != null && ignoreBytes > fileSize - tokenizer.position)) {
        throw WavPackContentError('WavPack block exceeds available input');
      }

      if (header.blockIndex == 0) {
        await _parseMetadataSubBlock(header, ignoreBytes);
      } else {
        tokenizer.skip(ignoreBytes);
      }

      if (header.blockSamples > 0) {
        // Channel blocks share an index and sample count; advance only when the group is complete.
        if (header.flags.isInitialBlock) {
          complete = complete &&
              groupIndex == null &&
              header.blockIndex == sampleExtent;
          groupIndex = header.blockIndex;
          groupSamples = header.blockSamples;
        }
        complete = complete &&
            groupIndex == header.blockIndex &&
            groupSamples == header.blockSamples &&
            isDsd == header.flags.isDsd;
        if (header.flags.isFinalBlock) {
          sampleExtent = header.blockIndex + header.blockSamples;
          groupIndex = null;
        }
        _audioDataSize += header.blockSize;
      }
    }

    if (totalSamples == null &&
        complete &&
        groupIndex == null &&
        sampleExtent > 0) {
      totalSamples = sampleExtent * (isDsd ? 8 : 1);
    } else if (totalSamples == null && (!complete || groupIndex != null)) {
      metadata.addWarning(
        'Cannot determine WavPack duration from incomplete or non-contiguous blocks',
      );
    }

    final samplingRate = _sampleRate * _dsdMultiplier;
    if (samplingRate > 0) {
      metadata.setFormat(sampleRate: samplingRate);
    }

    if (totalSamples != null) {
      metadata.setFormat(numberOfSamples: totalSamples);
      final rate = metadata.format.sampleRate;
      if (rate != null && rate > 0) {
        metadata.setFormat(duration: totalSamples / rate);
      }
    }

    final duration = metadata.format.duration;
    if (duration != null && duration > 0) {
      metadata.setFormat(bitrate: (_audioDataSize * 8 / duration).round());
    }
  }

  Future<bool> _isNextBlockWavPack() async {
    try {
      final peek = tokenizer.peekBytes(4);
      if (peek.length < 4) {
        _physicalEof = true;
        return false;
      }
      final blockId = ascii.decode(peek, allowInvalid: true);
      return blockId == 'wvpk';
    } on TokenizerException {
      _physicalEof = true;
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
            throw WavPackContentError('Truncated WavPack DSD metadata');
          }

          final multiplier = 1 << data[0];
          _dsdMultiplier = multiplier * 8;
          break;

        case 0x27:
          if (data.length < 3) {
            throw WavPackContentError('Truncated WavPack sample rate');
          }
          _sampleRate = _readUint24Le(data, 0);
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
    final rawTotalSamples = _readUint32Le(bytes, 12);
    // The low-word sentinel is unknown regardless of the high byte; the total uses radix 0xffffffff.
    var totalSamples = rawTotalSamples == 0xFFFFFFFF
        ? -1
        : rawTotalSamples + bytes[11] * 0xFFFFFFFF;
    final blockIndex = _readUint32Le(bytes, 16) + bytes[10] * 0x100000000;

    final parsedFlags = _WavPackFlags(
      bitsPerSample: (1 + _getBitAlignedNumber(flags, 0, 2)) * 8,
      isMono: _isBitSet(flags, 2),
      isHybrid: _isBitSet(flags, 3),
      samplingRate: _sampleRates[_getBitAlignedNumber(flags, 23, 4)],
      isDsd: _isBitSet(flags, 31),
      isInitialBlock: _isBitSet(flags, 11),
      isFinalBlock: _isBitSet(flags, 12),
    );

    if (parsedFlags.isDsd && totalSamples >= 0) {
      totalSamples *= 8;
    }

    return _WavPackBlockHeader(
      blockId: ascii.decode(bytes.sublist(0, 4), allowInvalid: true),
      blockSize: _readUint32Le(bytes, 4),
      blockIndex: blockIndex,
      totalSamples: totalSamples,
      blockSamples: _readUint32Le(bytes, 20),
      flags: parsedFlags,
    );
  }

  _WavPackMetadataId _parseMetadataId(int value) => _WavPackMetadataId(
    functionId: _getBitAlignedNumber(value, 0, 6),
    isOptional: _isBitSet(value, 5),
    isOddSize: _isBitSet(value, 6),
    largeBlock: _isBitSet(value, 7),
  );

  bool _isBitSet(int value, int bitOffset) =>
      _getBitAlignedNumber(value, bitOffset, 1) == 1;

  int _getBitAlignedNumber(int value, int bitOffset, int length) =>
      (value >>> bitOffset) & (0xFFFFFFFF >>> (32 - length));

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
    required this.isInitialBlock,
    required this.isFinalBlock,
  });

  final int bitsPerSample;
  final bool isMono;
  final bool isHybrid;
  final int samplingRate;
  final bool isDsd;
  final bool isInitialBlock;
  final bool isFinalBlock;
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
