library;

import 'package:metadata_audio/src/iff/iff_parser.dart';
import 'package:metadata_audio/src/parse_error.dart';

class DsdiffContentError extends UnexpectedFileContentError {
  DsdiffContentError(String message) : super('DSDIFF', message);
}

class DsdiffChunkHeader64 extends IffChunkHeader64 {
  const DsdiffChunkHeader64({required super.chunkId, required super.chunkSize});
}

class DsdiffToken {
  static const int chunkHeader64Length = IffParser.chunkHeader64Length;

  static DsdiffChunkHeader64 parseChunkHeader64(List<int> bytes) {
    final header = IffParser.parseChunkHeader64(bytes);
    return DsdiffChunkHeader64(
      chunkId: header.chunkId,
      chunkSize: header.chunkSize,
    );
  }

  static String parseFourCc(List<int> bytes, [int offset = 0]) =>
      IffParser.decodeFourCc(bytes, offset);

  static int readUint8(List<int> bytes, int offset) {
    if (offset < 0 || offset >= bytes.length) {
      throw const FormatException('uint8 read out of bounds');
    }
    return bytes[offset];
  }

  static int readUint16Be(List<int> bytes, int offset) =>
      IffParser.readUint16Be(bytes, offset);

  static int readUint32Be(List<int> bytes, int offset) =>
      IffParser.readUint32Be(bytes, offset);

  static int readUint32Le(List<int> bytes, int offset) {
    if (offset < 0 || offset + 4 > bytes.length) {
      throw const FormatException('uint32 LE read out of bounds');
    }

    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
}
