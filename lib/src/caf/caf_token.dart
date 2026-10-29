/// CAF (Core Audio File) tokens, ported 1:1 from upstream
/// `lib/caf/CafToken.ts` (Borewit/music-metadata).
///
/// CAF is fully big-endian. The file header is `'caff'` + 2-byte version +
/// 2-byte flags. Every chunk is a latin1 4CC type plus a signed 64-bit body
/// size, where only the Audio Data chunk may declare `-1` ("runs to end of
/// file").
library;

import 'dart:convert';
import 'dart:typed_data';

import '../parse_error.dart';

class CafContentError extends UnexpectedFileContentError {
  CafContentError(String message) : super('CAF', message);
}

/// Application defined identifiers need not be printable ASCII; CAF 4CCs are
/// decoded as latin1, not via a strict FourCC validator.
String _decodeFourCC(List<int> bytes, int offset) =>
    latin1.decode(bytes.sublist(offset, offset + 4), allowInvalid: true);

class CafFileHeader {
  const CafFileHeader({
    required this.fileType,
    required this.fileVersion,
    required this.fileFlags,
  });

  final String fileType;
  final int fileVersion;
  final int fileFlags;

  /// 8 bytes: 4CC + UINT16_BE + UINT16_BE.
  static const int length = 8;

  static CafFileHeader parse(List<int> bytes) {
    _expectLength(bytes, length, 'CAF file header');
    return CafFileHeader(
      fileType: _decodeFourCC(bytes, 0),
      fileVersion: _readUint16Be(bytes, 4),
      fileFlags: _readUint16Be(bytes, 6),
    );
  }
}

class CafChunkHeader {
  const CafChunkHeader({required this.chunkType, required this.chunkSize});

  final String chunkType;

  /// Size of the data section, -1 if the Audio Data chunk runs to the end
  /// of file.
  final int chunkSize;

  /// 12 bytes: 4CC + INT64_BE.
  static const int length = 12;

  static CafChunkHeader parse(List<int> bytes) {
    _expectLength(bytes, length, 'CAF chunk header');
    final view = ByteData.sublistView(Uint8List.fromList(bytes));
    return CafChunkHeader(
      chunkType: _decodeFourCC(bytes, 0),
      chunkSize: view.getInt64(4, Endian.big),
    );
  }
}

class AudioDescription {
  const AudioDescription({
    required this.sampleRate,
    required this.formatId,
    required this.formatFlags,
    required this.bytesPerPacket,
    required this.framesPerPacket,
    required this.channelsPerFrame,
    required this.bitsPerChannel,
  });

  final double sampleRate;
  final String formatId;
  final int formatFlags;
  final int bytesPerPacket;
  final int framesPerPacket;
  final int channelsPerFrame;
  final int bitsPerChannel;

  /// CAF Audio Format: Float64_BE mSampleRate followed by six UINT32 fields.
  static const int length = 32;

  static AudioDescription parse(List<int> bytes) {
    _expectLength(bytes, length, 'CAF Audio Description');
    final view = ByteData.sublistView(Uint8List.fromList(bytes));
    return AudioDescription(
      sampleRate: view.getFloat64(0, Endian.big),
      formatId: _decodeFourCC(bytes, 8),
      formatFlags: view.getUint32(12, Endian.big),
      bytesPerPacket: view.getUint32(16, Endian.big),
      framesPerPacket: view.getUint32(20, Endian.big),
      channelsPerFrame: view.getUint32(24, Endian.big),
      bitsPerChannel: view.getUint32(28, Endian.big),
    );
  }
}

class PacketTableHeader {
  const PacketTableHeader({
    required this.numberPackets,
    required this.numberValidFrames,
    required this.primingFrames,
    required this.remainderFrames,
  });

  final int numberPackets;
  final int numberValidFrames;
  final int primingFrames;
  final int remainderFrames;

  /// Fixed 24-byte part of a Packet Table chunk.
  static const int length = 24;

  static PacketTableHeader parse(List<int> bytes) {
    _expectLength(bytes, length, 'CAF Packet Table header');
    final view = ByteData.sublistView(Uint8List.fromList(bytes));
    return PacketTableHeader(
      numberPackets: view.getInt64(0, Endian.big),
      numberValidFrames: view.getInt64(8, Endian.big),
      primingFrames: view.getInt32(16, Endian.big),
      remainderFrames: view.getInt32(20, Endian.big),
    );
  }
}

/// A variable bytes or frames per packet value contributes one var-int entry
/// per packet.
int _varIntsPerPacket(AudioDescription desc) =>
    (desc.bytesPerPacket == 0 ? 1 : 0) + (desc.framesPerPacket == 0 ? 1 : 0);

/// Validates the base-128 MSB-first variable-length integers that follow a
/// Packet Table header (high bit set means the number continues in the next
/// byte).
///
/// Returns the number of bytes occupied by the entries.
int decodePacketTableEntries(
  List<int> body,
  AudioDescription desc,
  int numberPackets,
) {
  final expected = numberPackets * _varIntsPerPacket(desc);
  if (expected == 0) {
    return 0;
  }

  // Each entry needs at least one byte; checked up front to bound the loop.
  if (expected > body.length) {
    throw CafContentError(
      'Packet Table data section holds ${body.length} byte(s) for $expected '
      'packet table entries',
    );
  }

  var offset = 0;
  for (var i = 0; i < expected; ++i) {
    var byte = 0;
    do {
      if (offset >= body.length) {
        throw CafContentError(
          'Packet Table data section ends in the middle of a variable '
          'length integer',
        );
      }
      byte = body[offset++];
    } while ((byte & 0x80) != 0);
  }

  return offset;
}

class ChannelLayoutHeader {
  const ChannelLayoutHeader({
    required this.channelLayoutTag,
    required this.channelBitmap,
    required this.numberChannelDescriptions,
  });

  final int channelLayoutTag;
  final int channelBitmap;
  final int numberChannelDescriptions;

  /// Leading 12 bytes of a Channel Layout chunk.
  static const int length = 12;

  static ChannelLayoutHeader parse(List<int> bytes) {
    _expectLength(bytes, length, 'CAF Channel Layout header');
    final view = ByteData.sublistView(Uint8List.fromList(bytes));
    return ChannelLayoutHeader(
      channelLayoutTag: view.getUint32(0, Endian.big),
      channelBitmap: view.getUint32(4, Endian.big),
      numberChannelDescriptions: view.getUint32(8, Endian.big),
    );
  }
}

class ChannelDescription {
  const ChannelDescription({
    required this.channelLabel,
    required this.channelFlags,
    required this.coordinates,
  });

  final int channelLabel;
  final int channelFlags;
  final List<double> coordinates;
}

/// Each CAFChannelDescription has a UInt32 label, UInt32 flags and three
/// Float32 coordinates.
const int channelDescriptionLength = 20;

List<ChannelDescription> parseChannelDescriptions(List<int> body, int count) {
  if (count * channelDescriptionLength > body.length) {
    throw CafContentError(
      'Channel Layout chunk declares $count description(s) for '
      '${body.length} byte(s)',
    );
  }
  final view = ByteData.sublistView(Uint8List.fromList(body));
  final descriptions = <ChannelDescription>[];
  for (var i = 0; i < count; ++i) {
    final offset = i * channelDescriptionLength;
    descriptions.add(
      ChannelDescription(
        channelLabel: view.getUint32(offset, Endian.big),
        channelFlags: view.getUint32(offset + 4, Endian.big),
        coordinates: <double>[
          view.getFloat32(offset + 8, Endian.big),
          view.getFloat32(offset + 12, Endian.big),
          view.getFloat32(offset + 16, Endian.big),
        ],
      ),
    );
  }
  return descriptions;
}

class CafInfoEntry {
  const CafInfoEntry({required this.key, required this.value});

  final String key;
  final String value;
}

/// Reads the NUL-terminated UTF-8 key/value pairs of an Information chunk.
/// The declared entry count at offset 0 is authoritative.
List<CafInfoEntry> parseInfoEntries(List<int> body) {
  if (body.length < 4) {
    throw CafContentError('Information chunk is too small to hold mNumEntries');
  }

  final view = ByteData.sublistView(Uint8List.fromList(body));
  final numEntries = view.getUint32(0, Endian.big);

  /// Reads a NUL-terminated UTF-8 string starting at [from] and returns the
  /// decoded string plus the offset just past its terminator.
  (String, int) readString(int from) {
    final end = body.indexOf(0, from);
    if (end < 0) {
      throw CafContentError('Information chunk contains an unterminated string');
    }
    final value = utf8.decode(body.sublist(from, end), allowMalformed: true);
    return (value, end + 1);
  }

  final entries = <CafInfoEntry>[];
  var offset = 4;

  for (var i = 0; i < numEntries; ++i) {
    final (key, keyNext) = readString(offset);
    final (value, valueNext) = readString(keyNext);
    entries.add(CafInfoEntry(key: key, value: value));
    offset = valueNext;
  }

  return entries;
}

int _readUint16Be(List<int> bytes, int offset) =>
    (bytes[offset] << 8) | bytes[offset + 1];

void _expectLength(List<int> bytes, int length, String what) {
  if (bytes.length < length) {
    throw CafContentError(
      'Insufficient bytes for $what: required $length, available '
      '${bytes.length}',
    );
  }
}
