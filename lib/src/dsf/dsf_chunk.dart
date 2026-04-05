library;

import 'dart:typed_data';

import 'package:metadata_audio/src/parse_error.dart';

class DsdContentError extends UnexpectedFileContentError {
  DsdContentError(String message) : super('DSD', message);
}

class DsfChunkHeader {
  const DsfChunkHeader({required this.id, required this.size});

  static const int length = 12;

  final String id;
  final BigInt size;

  static DsfChunkHeader fromBytes(List<int> bytes, [int offset = 0]) {
    _expectLength(bytes, offset, length, 'DSF chunk header');
    return DsfChunkHeader(
      id: String.fromCharCodes(bytes.sublist(offset, offset + 4)),
      size: _readUint64Le(bytes, offset + 4),
    );
  }
}

class DsfDsdChunk {
  const DsfDsdChunk({required this.fileSize, required this.metadataPointer});

  static const int length = 16;

  final BigInt fileSize;
  final BigInt metadataPointer;

  static DsfDsdChunk fromBytes(List<int> bytes, [int offset = 0]) {
    _expectLength(bytes, offset, length, 'DSF DSD chunk');
    return DsfDsdChunk(
      fileSize: _readInt64Le(bytes, offset),
      metadataPointer: _readInt64Le(bytes, offset + 8),
    );
  }
}

class DsfFormatChunk {
  const DsfFormatChunk({
    required this.formatVersion,
    required this.formatId,
    required this.channelType,
    required this.channelNum,
    required this.samplingFrequency,
    required this.bitsPerSample,
    required this.sampleCount,
    required this.blockSizePerChannel,
  });

  static const int length = 40;

  final int formatVersion;
  final int formatId;
  final int channelType;
  final int channelNum;
  final int samplingFrequency;
  final int bitsPerSample;
  final BigInt sampleCount;
  final int blockSizePerChannel;

  static DsfFormatChunk fromBytes(List<int> bytes, [int offset = 0]) {
    _expectLength(bytes, offset, length, 'DSF format chunk');
    return DsfFormatChunk(
      formatVersion: _readInt32Le(bytes, offset),
      formatId: _readInt32Le(bytes, offset + 4),
      channelType: _readInt32Le(bytes, offset + 8),
      channelNum: _readInt32Le(bytes, offset + 12),
      samplingFrequency: _readInt32Le(bytes, offset + 16),
      bitsPerSample: _readInt32Le(bytes, offset + 20),
      sampleCount: _readInt64Le(bytes, offset + 24),
      blockSizePerChannel: _readInt32Le(bytes, offset + 32),
    );
  }
}

int _readInt32Le(List<int> bytes, int offset) {
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  return view.getInt32(offset, Endian.little);
}

BigInt _readInt64Le(List<int> bytes, int offset) {
  final value = _readUint64Le(bytes, offset);
  final signBit = BigInt.one << 63;
  if ((value & signBit) != BigInt.zero) {
    return value - (BigInt.one << 64);
  }
  return value;
}

BigInt _readUint64Le(List<int> bytes, int offset) {
  _expectLength(bytes, offset, 8, 'unsigned 64-bit integer (LE)');
  final lo = _readUint32Le(bytes, offset);
  final hi = _readUint32Le(bytes, offset + 4);
  return (BigInt.from(hi) << 32) | BigInt.from(lo);
}

int _readUint32Le(List<int> bytes, int offset) {
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  return view.getUint32(offset, Endian.little);
}

void _expectLength(List<int> bytes, int offset, int length, String what) {
  if (offset < 0 || length < 0 || offset + length > bytes.length) {
    throw RangeError(
      'Insufficient bytes for $what: required ${offset + length}, available ${bytes.length}',
    );
  }
}
