library;

import 'dart:convert';

import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parse_error.dart';

enum FlacBlockType {
  streamInfo(0),
  padding(1),
  application(2),
  seekTable(3),
  vorbisComment(4),
  cueSheet(5),
  picture(6),
  unknown(-1);

  const FlacBlockType(this.value);

  final int value;

  static FlacBlockType fromValue(int value) {
    for (final type in FlacBlockType.values) {
      if (type.value == value) {
        return type;
      }
    }
    return FlacBlockType.unknown;
  }
}

class FlacBlockHeader {
  const FlacBlockHeader({
    required this.lastBlock,
    required this.type,
    required this.length,
  });

  final bool lastBlock;
  final FlacBlockType type;
  final int length;
}

class FlacStreamInfo {
  const FlacStreamInfo({
    required this.minimumBlockSize,
    required this.maximumBlockSize,
    required this.minimumFrameSize,
    required this.maximumFrameSize,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.totalSamples,
    required this.audioMd5,
  });

  final int minimumBlockSize;
  final int maximumBlockSize;
  final int minimumFrameSize;
  final int maximumFrameSize;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int totalSamples;
  final List<int> audioMd5;
}

class FlacPicture {
  const FlacPicture({
    required this.type,
    required this.format,
    required this.description,
    required this.width,
    required this.height,
    required this.colourDepth,
    required this.indexedColor,
    required this.data,
  });

  final String type;
  final String format;
  final String description;
  final int width;
  final int height;
  final int colourDepth;
  final int indexedColor;
  final List<int> data;
}

class FlacCueSheetIndex {
  const FlacCueSheetIndex({required this.offset, required this.number});

  final int offset;
  final int number;
}

class FlacCueSheetTrack {
  const FlacCueSheetTrack({
    required this.offset,
    required this.number,
    required this.indices,
  });

  final int offset;
  final int number;
  final List<FlacCueSheetIndex> indices;

  bool get isLeadOut => number == 0xAA || number == 0xFF;
}

class FlacCueSheet {
  const FlacCueSheet({required this.leadInSamples, required this.tracks});

  final int leadInSamples;
  final List<FlacCueSheetTrack> tracks;
}

class FlacToken {
  static const int blockHeaderLength = 4;
  static const int blockStreamInfoLength = 34;

  static const Map<int, String> attachedPictureType = {
    0: 'Other',
    1: "32x32 pixels 'file icon' (PNG only)",
    2: 'Other file icon',
    3: 'Cover (front)',
    4: 'Cover (back)',
    5: 'Leaflet page',
    6: 'Media (e.g. label side of CD)',
    7: 'Lead artist/lead performer/soloist',
    8: 'Artist/performer',
    9: 'Conductor',
    10: 'Band/Orchestra',
    11: 'Composer',
    12: 'Lyricist/text writer',
    13: 'Recording Location',
    14: 'During recording',
    15: 'During performance',
    16: 'Movie/video screen capture',
    17: 'A bright coloured fish',
    18: 'Illustration',
    19: 'Band/artist logotype',
    20: 'Publisher/Studio logotype',
  };

  static FlacBlockHeader parseBlockHeader(List<int> bytes, [int offset = 0]) {
    _expectLength(bytes, offset, blockHeaderLength, 'FLAC block header');

    final firstByte = bytes[offset];
    return FlacBlockHeader(
      lastBlock: (firstByte & 0x80) != 0,
      type: FlacBlockType.fromValue(firstByte & 0x7F),
      length: uint24Be(bytes, offset + 1),
    );
  }

  static FlacStreamInfo parseStreamInfo(List<int> bytes, [int offset = 0]) {
    _expectLength(bytes, offset, blockStreamInfoLength, 'FLAC stream info');

    final sampleRate = uint24Be(bytes, offset + 10) >> 4;
    final channels = ((bytes[offset + 12] >> 1) & 0x07) + 1;
    final bitsPerSample =
        (((bytes[offset + 12] & 0x01) << 4) |
            ((bytes[offset + 13] >> 4) & 0x0F)) +
        1;
    final totalSamples =
        ((bytes[offset + 13] & 0x0F) << 32) |
        (bytes[offset + 14] << 24) |
        (bytes[offset + 15] << 16) |
        (bytes[offset + 16] << 8) |
        bytes[offset + 17];

    return FlacStreamInfo(
      minimumBlockSize: uint16Be(bytes, offset),
      maximumBlockSize: uint16Be(bytes, offset + 2),
      minimumFrameSize: uint24Be(bytes, offset + 4),
      maximumFrameSize: uint24Be(bytes, offset + 7),
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      totalSamples: totalSamples,
      audioMd5: bytes.sublist(offset + 18, offset + 34),
    );
  }

  static FlacPicture parsePicture(List<int> bytes, [int offset = 0]) {
    _expectLength(bytes, offset, 32, 'FLAC picture header');

    var cursor = offset;
    final pictureTypeValue = uint32Be(bytes, cursor);
    cursor += 4;

    final mimeLength = uint32Be(bytes, cursor);
    cursor += 4;
    _expectLength(bytes, cursor, mimeLength, 'FLAC picture MIME type');
    final format = utf8.decode(bytes.sublist(cursor, cursor + mimeLength));
    cursor += mimeLength;

    final descriptionLength = uint32Be(bytes, cursor);
    cursor += 4;
    _expectLength(bytes, cursor, descriptionLength, 'FLAC picture description');
    final description = utf8.decode(
      bytes.sublist(cursor, cursor + descriptionLength),
      allowMalformed: true,
    );
    cursor += descriptionLength;

    _expectLength(
      bytes,
      cursor,
      20,
      'FLAC picture dimensions and payload size',
    );
    final width = uint32Be(bytes, cursor);
    cursor += 4;
    final height = uint32Be(bytes, cursor);
    cursor += 4;
    final colourDepth = uint32Be(bytes, cursor);
    cursor += 4;
    final indexedColor = uint32Be(bytes, cursor);
    cursor += 4;
    final dataLength = uint32Be(bytes, cursor);
    cursor += 4;

    _expectLength(bytes, cursor, dataLength, 'FLAC picture data');
    final data = bytes.sublist(cursor, cursor + dataLength);

    return FlacPicture(
      type: attachedPictureType[pictureTypeValue] ?? 'Other',
      format: format,
      description: description,
      width: width,
      height: height,
      colourDepth: colourDepth,
      indexedColor: indexedColor,
      data: data,
    );
  }

  static FlacCueSheet parseCueSheet(List<int> bytes, [int offset = 0]) {
    _expectLength(bytes, offset, 396, 'FLAC cuesheet header');

    var cursor = offset + 128;
    final leadInSamples = readUint64Be(bytes, cursor);
    cursor += 8;
    cursor += 1; // flags byte
    cursor += 258; // reserved bytes

    _expectLength(bytes, cursor, 1, 'FLAC cuesheet track count');
    final trackCount = bytes[cursor++];
    final tracks = <FlacCueSheetTrack>[];

    for (var i = 0; i < trackCount; i++) {
      _expectLength(bytes, cursor, 36, 'FLAC cuesheet track header');
      final trackOffset = readUint64Be(bytes, cursor);
      cursor += 8;
      final trackNumber = bytes[cursor++];
      cursor += 12; // ISRC
      cursor += 1; // flags
      cursor += 13; // reserved
      final indexCount = bytes[cursor++];

      final indices = <FlacCueSheetIndex>[];
      for (var j = 0; j < indexCount; j++) {
        _expectLength(bytes, cursor, 12, 'FLAC cuesheet index');
        indices.add(
          FlacCueSheetIndex(
            offset: readUint64Be(bytes, cursor),
            number: bytes[cursor + 8],
          ),
        );
        cursor += 12;
      }

      tracks.add(
        FlacCueSheetTrack(
          offset: trackOffset,
          number: trackNumber,
          indices: indices,
        ),
      );
    }

    return FlacCueSheet(leadInSamples: leadInSamples, tracks: tracks);
  }

  static int uint16Be(List<int> bytes, int offset) {
    _expectLength(bytes, offset, 2, 'uint16');
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  static int uint24Be(List<int> bytes, int offset) {
    _expectLength(bytes, offset, 3, 'uint24');
    return (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
  }

  static int readUint64Be(List<int> bytes, int offset) {
    _expectLength(bytes, offset, 8, 'uint64');
    final value =
        (BigInt.from(bytes[offset]) << 56) |
        (BigInt.from(bytes[offset + 1]) << 48) |
        (BigInt.from(bytes[offset + 2]) << 40) |
        (BigInt.from(bytes[offset + 3]) << 32) |
        (BigInt.from(bytes[offset + 4]) << 24) |
        (BigInt.from(bytes[offset + 5]) << 16) |
        (BigInt.from(bytes[offset + 6]) << 8) |
        BigInt.from(bytes[offset + 7]);
    if (value > BigInt.from(0x7FFFFFFF)) {
      throw UnexpectedFileContentError(
        'FLAC',
        '64-bit integer overflow for parser runtime',
      );
    }
    return value.toInt();
  }

  static int uint32Be(List<int> bytes, int offset) {
    _expectLength(bytes, offset, 4, 'uint32');
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  static int uint32Le(List<int> bytes, int offset) {
    _expectLength(bytes, offset, 4, 'uint32');
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  static Picture toCommonPicture(FlacPicture picture) => Picture(
    format: picture.format,
    data: picture.data,
    description: picture.description,
    type: picture.type,
  );

  static void _expectLength(
    List<int> bytes,
    int offset,
    int needed,
    String label,
  ) {
    if (offset < 0 || offset + needed > bytes.length) {
      throw FormatException(
        'Insufficient bytes for $label: need $needed at offset $offset, have ${bytes.length - offset}',
      );
    }
  }
}
