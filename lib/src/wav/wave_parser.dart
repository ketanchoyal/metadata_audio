library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/id3v2/id3v2_parser.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/riff/riff_chunk.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';
import 'package:audio_metadata/src/wav/wave_chunk.dart';

class WaveParser {
  WaveParser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  FactChunk? _fact;
  int _blockAlign = 0;

  Future<void> parse() async {
    final riffHeader = RiffChunk.parseHeader(
      tokenizer.readBytes(RiffChunk.headerLength),
    );
    if (riffHeader.chunkId != 'RIFF') {
      throw WaveContentError('Invalid RIFF chunk identifier');
    }

    metadata.setFormat(hasAudio: true, hasVideo: false);
    final fileSize = tokenizer.fileInfo?.size;
    var riffSize = riffHeader.chunkSize;
    if (fileSize != null) {
      final maxReadable = fileSize - RiffChunk.headerLength;
      if (riffSize > maxReadable) {
        metadata.addWarning('RIFF chunk size exceeds file size');
        riffSize = maxReadable;
      }
    }
    try {
      await _parseRiffChunk(riffSize);
    } on TokenizerException {
      metadata.addWarning('Unexpected end of RIFF/WAVE data');
    }
  }

  Future<void> _parseRiffChunk(int chunkSize) async {
    final type = _decodeAscii(tokenizer.readBytes(4));
    metadata.setFormat(container: type);

    switch (type) {
      case 'WAVE':
        await _readWaveChunks(chunkSize - 4);
      default:
        throw WaveContentError('Unsupported RIFF format: RIFF/$type');
    }
  }

  Future<void> _readWaveChunks(int remaining) async {
    var bytesRemaining = remaining;

    while (bytesRemaining >= RiffChunk.headerLength) {
      final header = RiffChunk.parseHeader(
        tokenizer.readBytes(RiffChunk.headerLength),
      );
      bytesRemaining -= RiffChunk.headerLength;

      final declaredSize = header.chunkSize;
      var readableSize = declaredSize;
      if (readableSize < 0) {
        metadata.addWarning('Ignore malformed negative RIFF chunk size');
        break;
      }
      if (readableSize > bytesRemaining) {
        metadata.addWarning('Data chunk size exceeds file size');
        readableSize = bytesRemaining;
      }

      await _parseChunk(header.chunkId, readableSize);

      bytesRemaining -= readableSize;

      if (declaredSize.isOdd && bytesRemaining > 0) {
        tokenizer.skip(1);
        bytesRemaining -= 1;
      }
    }
  }

  Future<void> _parseChunk(String chunkId, int chunkSize) async {
    switch (chunkId) {
      case 'LIST':
        await _parseListTag(chunkSize);
        return;
      case 'fact':
        metadata.setFormat(lossless: false);
        _fact = FactChunk.fromBytes(tokenizer.readBytes(chunkSize));
        return;
      case 'fmt ':
        _parseFmtChunk(tokenizer.readBytes(chunkSize));
        return;
      case 'id3 ':
      case 'ID3 ':
        await _parseId3Chunk(tokenizer.readBytes(chunkSize));
        return;
      case 'data':
        _parseDataChunk(chunkSize);
        tokenizer.skip(chunkSize);
        return;
      case 'bext':
        tokenizer.skip(chunkSize);
        return;
      case '\x00\x00\x00\x00':
        metadata.addWarning('Ignore chunk: RIFF/$chunkId');
        tokenizer.skip(chunkSize);
        return;
      default:
        metadata.addWarning('Ignore chunk: RIFF/$chunkId');
        tokenizer.skip(chunkSize);
        return;
    }
  }

  Future<void> _parseListTag(int listChunkSize) async {
    if (listChunkSize < 4) {
      tokenizer.skip(listChunkSize);
      metadata.addWarning('Ignore malformed RIFF LIST chunk');
      return;
    }

    final listType = _decodeAscii(tokenizer.readBytes(4));
    final payloadSize = listChunkSize - 4;

    if (listType == 'INFO') {
      await _parseRiffInfoTags(payloadSize);
      return;
    }

    metadata.addWarning('Ignore chunk: RIFF/WAVE/LIST/$listType');
    tokenizer.skip(payloadSize);
  }

  Future<void> _parseRiffInfoTags(int chunkSize) async {
    var remaining = chunkSize;

    while (remaining >= RiffChunk.headerLength) {
      final header = RiffChunk.parseHeader(
        tokenizer.readBytes(RiffChunk.headerLength),
      );
      final valueToken = ListInfoTagValue(header);

      if (valueToken.paddedLength > remaining - RiffChunk.headerLength) {
        throw WaveContentError('Illegal remaining size: $remaining');
      }

      final valueBytes = tokenizer.readBytes(header.chunkSize);
      final value = _stripNulls(valueToken.parse(valueBytes));
      metadata.addNativeTag('exif', header.chunkId, value);

      if (valueToken.paddedLength > header.chunkSize) {
        tokenizer.skip(valueToken.paddedLength - header.chunkSize);
      }

      remaining -= RiffChunk.headerLength + valueToken.paddedLength;
    }

    if (remaining != 0) {
      throw WaveContentError('Illegal remaining size: $remaining');
    }
  }

  void _parseFmtChunk(List<int> bytes) {
    final fmt = WaveFormatChunk.fromBytes(bytes);
    final codec =
        waveFormatNameMap[fmt.formatTag] ?? 'non-PCM (${fmt.formatTag})';

    metadata.setFormat(
      codec: codec,
      bitsPerSample: fmt.bitsPerSample,
      sampleRate: fmt.samplesPerSec,
      numberOfChannels: fmt.channels,
      bitrate: fmt.blockAlign * fmt.samplesPerSec * 8,
    );
    _blockAlign = fmt.blockAlign;
  }

  Future<void> _parseId3Chunk(List<int> bytes) async {
    final id3Tokenizer = BytesTokenizer(
      Uint8List.fromList(bytes),
      fileInfo: FileInfo(size: bytes.length),
    );
    final id3v2 = Id3v2Parser(
      metadata: metadata,
      tokenizer: id3Tokenizer,
      options: options,
    );
    await id3v2.parse();
  }

  void _parseDataChunk(int chunkSize) {
    if (metadata.format.lossless != false) {
      metadata.setFormat(lossless: true);
    }

    if (_blockAlign <= 0) {
      return;
    }

    final computedSamples =
        _fact?.sampleLength.toDouble() ??
        (chunkSize == 0xFFFFFFFF ? null : chunkSize / _blockAlign);
    if (computedSamples != null) {
      if (computedSamples == computedSamples.roundToDouble()) {
        metadata.setFormat(numberOfSamples: computedSamples.round());
      }
      final sampleRate = metadata.format.sampleRate;
      if (sampleRate != null && sampleRate > 0) {
        metadata.setFormat(duration: computedSamples / sampleRate);
      }
    }

    if (metadata.format.codec == 'ADPCM') {
      metadata.setFormat(bitrate: 352000);
      return;
    }

    final sampleRate = metadata.format.sampleRate;
    if (sampleRate != null && sampleRate > 0) {
      metadata.setFormat(bitrate: _blockAlign * sampleRate * 8);
    }
  }

  static String _decodeAscii(List<int> bytes) {
    return ascii.decode(bytes, allowInvalid: true);
  }

  static String _stripNulls(String value) {
    return value.replaceAll(RegExp(r'\x00+$'), '');
  }
}
