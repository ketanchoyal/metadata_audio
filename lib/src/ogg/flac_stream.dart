library;

import 'dart:convert';

import 'package:metadata_audio/src/flac/flac_token.dart';

class OggFlacMetadataBlock {
  const OggFlacMetadataBlock({
    required this.lastBlock,
    required this.type,
    this.streamInfo,
    this.comments,
    this.picture,
    this.cueSheet,
  });

  final bool lastBlock;
  final FlacBlockType type;
  final FlacStreamInfo? streamInfo;
  final List<String>? comments;
  final FlacPicture? picture;
  final FlacCueSheet? cueSheet;
}

class OggFlacStream {
  static bool isFirstPage(List<int> data) => data.length >= 13 &&
        data[0] == 0x7F &&
        _ascii(data, 1, 4) == 'FLAC' &&
        _ascii(data, 9, 4) == 'fLaC';

  static OggFlacMetadataBlock parseFirstPage(List<int> data) {
    if (!isFirstPage(data)) {
      throw const FormatException('Invalid Ogg-FLAC first page');
    }

    return parseMetadataBlock(data.sublist(13));
  }

  static OggFlacMetadataBlock parseMetadataBlock(List<int> data) {
    if (data.length < FlacToken.blockHeaderLength) {
      throw const FormatException('Invalid Ogg-FLAC metadata block');
    }

    final header = FlacToken.parseBlockHeader(data);
    const payloadOffset = FlacToken.blockHeaderLength;
    if (payloadOffset + header.length > data.length) {
      throw const FormatException('Unexpected end of Ogg-FLAC metadata block');
    }
    final payload = data.sublist(payloadOffset, payloadOffset + header.length);

    switch (header.type) {
      case FlacBlockType.streamInfo:
        return OggFlacMetadataBlock(
          lastBlock: header.lastBlock,
          type: header.type,
          streamInfo: FlacToken.parseStreamInfo(payload),
        );
      case FlacBlockType.vorbisComment:
        return OggFlacMetadataBlock(
          lastBlock: header.lastBlock,
          type: header.type,
          comments: _parseVorbisComments(payload),
        );
      case FlacBlockType.picture:
        return OggFlacMetadataBlock(
          lastBlock: header.lastBlock,
          type: header.type,
          picture: FlacToken.parsePicture(payload),
        );
      case FlacBlockType.cueSheet:
        return OggFlacMetadataBlock(
          lastBlock: header.lastBlock,
          type: header.type,
          cueSheet: FlacToken.parseCueSheet(payload),
        );
      case FlacBlockType.padding:
      case FlacBlockType.application:
      case FlacBlockType.seekTable:
      case FlacBlockType.unknown:
        return OggFlacMetadataBlock(
          lastBlock: header.lastBlock,
          type: header.type,
        );
    }
  }

  static List<String> _parseVorbisComments(List<int> data) {
    var offset = 0;
    _ensureReadable(data, offset, 4);
    final vendorLength = FlacToken.uint32Le(data, offset);
    offset += 4;
    _ensureReadable(data, offset, vendorLength);
    offset += vendorLength;

    _ensureReadable(data, offset, 4);
    final commentCount = FlacToken.uint32Le(data, offset);
    offset += 4;

    final comments = <String>[];
    for (var i = 0; i < commentCount; i++) {
      _ensureReadable(data, offset, 4);
      final length = FlacToken.uint32Le(data, offset);
      offset += 4;
      _ensureReadable(data, offset, length);
      comments.add(
        utf8.decode(
          data.sublist(offset, offset + length),
          allowMalformed: true,
        ),
      );
      offset += length;
    }

    return comments;
  }

  static void _ensureReadable(List<int> data, int offset, int needed) {
    if (offset < 0 || offset + needed > data.length) {
      throw const FormatException('Unexpected end of Ogg-FLAC block');
    }
  }

  static String _ascii(List<int> data, int offset, int length) {
    if (offset < 0 || offset + length > data.length) {
      return '';
    }

    return ascii.decode(
      data.sublist(offset, offset + length),
      allowInvalid: true,
    );
  }
}
