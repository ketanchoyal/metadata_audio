library;

import 'dart:convert';

import 'package:metadata_audio/src/ogg/ogg_token.dart';

const _defaultMaxMetadataEntries = 100000;

class VorbisIdentificationHeader {
  const VorbisIdentificationHeader({
    required this.version,
    required this.channelMode,
    required this.sampleRate,
    required this.bitrateMax,
    required this.bitrateNominal,
    required this.bitrateMin,
  });

  final int version;
  final int channelMode;
  final int sampleRate;
  final int bitrateMax;
  final int bitrateNominal;
  final int bitrateMin;
}

class VorbisUserComment {
  const VorbisUserComment({required this.key, required this.value});

  final String key;
  final String value;
}

class VorbisCommentHeader {
  const VorbisCommentHeader({required this.vendor, required this.comments});

  final String vendor;
  final List<VorbisUserComment> comments;
}

class VorbisDecoder {
  static const int commonHeaderLength = 7;

  static bool isIdentificationHeader(List<int> data) => data.length >= commonHeaderLength &&
        data[0] == 0x01 &&
        _ascii(data, 1, 6) == 'vorbis';

  static bool isCommentHeader(List<int> data) => data.length >= commonHeaderLength &&
        data[0] == 0x03 &&
        _ascii(data, 1, 6) == 'vorbis';

  static VorbisIdentificationHeader parseIdentificationHeader(List<int> data) {
    if (!isIdentificationHeader(data) ||
        data.length < commonHeaderLength + 23) {
      throw const FormatException('Invalid Vorbis identification header');
    }

    const offset = commonHeaderLength;
    return VorbisIdentificationHeader(
      version: OggToken.uint32Le(data, offset),
      channelMode: data[offset + 4],
      sampleRate: OggToken.uint32Le(data, offset + 5),
      bitrateMax: OggToken.uint32Le(data, offset + 9),
      bitrateNominal: OggToken.uint32Le(data, offset + 13),
      bitrateMin: OggToken.uint32Le(data, offset + 17),
    );
  }

  static VorbisCommentHeader parseCommentHeader(
    List<int> data, {
    int maxComments = _defaultMaxMetadataEntries,
  }) {
    if (!isCommentHeader(data)) {
      throw const FormatException('Invalid Vorbis comment header');
    }

    return parseCommentData(
      data,
      commonHeaderLength,
      maxComments: maxComments,
    );
  }

  static VorbisCommentHeader parseCommentData(
    List<int> data,
    int offset, {
    int maxComments = _defaultMaxMetadataEntries,
  }) {
    final decoder = _VorbisStringDecoder(data, offset);
    final vendor = decoder.readStringUtf8();
    final count = decoder.readInt32();

    final remaining = data.length - decoder.offset;
    if (count > remaining ~/ 4) {
      throw FormatException(
        'Vorbis comment count $count exceeds remaining data',
      );
    }
    if (count > maxComments) {
      throw FormatException(
        'Vorbis comment count $count exceeds entry limit $maxComments',
      );
    }

    final comments = <VorbisUserComment>[];
    for (var i = 0; i < count; i++) {
      final raw = decoder.readStringUtf8();
      final separator = raw.indexOf('=');
      final key = (separator == -1 ? raw : raw.substring(0, separator))
          .toUpperCase();
      final value = separator == -1 ? '' : raw.substring(separator + 1);
      comments.add(VorbisUserComment(key: key, value: value));
    }

    return VorbisCommentHeader(vendor: vendor, comments: comments);
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

class _VorbisStringDecoder {
  _VorbisStringDecoder(this._data, this._offset);

  final List<int> _data;
  int _offset;

  int get offset => _offset;

  int readInt32() {
    _ensureReadable(4);
    final value = OggToken.uint32Le(_data, _offset);
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
      throw const FormatException('Unexpected end of Vorbis comment block');
    }
  }
}
