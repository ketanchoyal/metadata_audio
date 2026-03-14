library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/flac/flac_token.dart';
import 'package:audio_metadata/src/id3v2/id3v2_parser.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/parse_error.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

class FlacContentError extends UnexpectedFileContentError {
  FlacContentError(String message) : super('FLAC', message);
}

class FlacParser {
  FlacParser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  Future<void> parse() async {
    await _parseId3v2Prefix();

    final signature = tokenizer.readBytes(4);
    if (ascii.decode(signature, allowInvalid: true) != 'fLaC') {
      throw FlacContentError('Invalid FLAC preamble');
    }

    FlacBlockHeader blockHeader;
    do {
      blockHeader = FlacToken.parseBlockHeader(
        tokenizer.readBytes(FlacToken.blockHeaderLength),
      );
      await _parseDataBlock(blockHeader);
    } while (!blockHeader.lastBlock);

    final fileSize = tokenizer.fileInfo?.size;
    final duration = metadata.format.duration;
    if (fileSize != null && duration != null && duration > 0) {
      final dataSize = fileSize - tokenizer.position;
      if (dataSize > 0) {
        metadata.setFormat(bitrate: (8 * dataSize / duration).round());
      }
    }
  }

  Future<void> _parseId3v2Prefix() async {
    final id3v2 = Id3v2Parser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    );
    await id3v2.parse();
  }

  Future<void> _parseDataBlock(FlacBlockHeader blockHeader) async {
    switch (blockHeader.type) {
      case FlacBlockType.streamInfo:
        await _readStreamInfo(blockHeader.length);
      case FlacBlockType.vorbisComment:
        await _readVorbisComment(blockHeader.length);
      case FlacBlockType.picture:
        await _readPicture(blockHeader.length);
      case FlacBlockType.padding:
      case FlacBlockType.application:
      case FlacBlockType.seekTable:
      case FlacBlockType.cueSheet:
      case FlacBlockType.unknown:
        metadata.addWarning('Unknown or unsupported FLAC block type');
        tokenizer.skip(blockHeader.length);
    }
  }

  Future<void> _readStreamInfo(int dataLength) async {
    if (dataLength != FlacToken.blockStreamInfoLength) {
      throw FlacContentError('Unexpected STREAMINFO block length: $dataLength');
    }

    final streamInfo = FlacToken.parseStreamInfo(
      tokenizer.readBytes(dataLength),
    );
    metadata.setFormat(
      container: 'flac',
      codec: 'FLAC',
      hasAudio: true,
      hasVideo: false,
      lossless: true,
      sampleRate: streamInfo.sampleRate,
      numberOfChannels: streamInfo.channels,
      bitsPerSample: streamInfo.bitsPerSample,
      numberOfSamples: streamInfo.totalSamples > 0
          ? streamInfo.totalSamples
          : null,
      audioMD5: streamInfo.audioMd5,
    );

    if (streamInfo.totalSamples > 0 && streamInfo.sampleRate > 0) {
      metadata.setFormat(
        duration: streamInfo.totalSamples / streamInfo.sampleRate,
      );
    }
  }

  Future<void> _readVorbisComment(int dataLength) async {
    final commentData = tokenizer.readBytes(dataLength);
    _parseVorbisComment(Uint8List.fromList(commentData));
  }

  Future<void> _readPicture(int dataLength) async {
    if (options.skipCovers) {
      tokenizer.skip(dataLength);
      return;
    }

    final picture = FlacToken.parsePicture(tokenizer.readBytes(dataLength));
    metadata.addNativeTag('vorbis', 'METADATA_BLOCK_PICTURE', picture);
  }

  void _parseVorbisComment(Uint8List data) {
    final decoder = _VorbisCommentDecoder(data);

    final vendor = decoder.readStringUtf8();
    if (vendor.isNotEmpty) {
      metadata.setFormat(tool: vendor);
    }

    final commentCount = decoder.readInt32();
    for (var i = 0; i < commentCount; i++) {
      final comment = decoder.readStringUtf8();
      final separatorIndex = comment.indexOf('=');
      final key =
          (separatorIndex == -1
                  ? comment
                  : comment.substring(0, separatorIndex))
              .toUpperCase();
      final value = separatorIndex == -1
          ? ''
          : comment.substring(separatorIndex + 1);

      if (key == 'ENCODER' && value.isNotEmpty) {
        metadata.setFormat(tool: value);
      }

      if (key == 'METADATA_BLOCK_PICTURE' && value.isNotEmpty) {
        if (options.skipCovers) {
          continue;
        }

        try {
          final pictureData = base64.decode(value);
          final picture = FlacToken.parsePicture(pictureData);
          metadata.addNativeTag('vorbis', key, picture);
        } on FormatException {
          metadata.addWarning('Invalid METADATA_BLOCK_PICTURE payload');
        }
        continue;
      }

      metadata.addNativeTag('vorbis', key, value);
    }
  }
}

class _VorbisCommentDecoder {
  _VorbisCommentDecoder(this._data);

  final Uint8List _data;
  int _offset = 0;

  int readInt32() {
    _ensureReadable(4);
    final value = FlacToken.uint32Le(_data, _offset);
    _offset += 4;
    return value;
  }

  String readStringUtf8() {
    final length = readInt32();
    _ensureReadable(length);
    final value = utf8.decode(
      _data.sublist(_offset, _offset + length),
      allowMalformed: true,
    );
    _offset += length;
    return value;
  }

  void _ensureReadable(int length) {
    if (length < 0 || _offset + length > _data.length) {
      throw FlacContentError('Unexpected end of Vorbis comment block');
    }
  }
}
