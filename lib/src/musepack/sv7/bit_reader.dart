library;

// ignore_for_file: parameter_assignments, public_member_api_docs

import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

class BitReader {
  BitReader(this._tokenizer);

  final Tokenizer _tokenizer;

  int pos = 0;
  int? _dword;

  Future<int> read(int bits) async {
    if (bits == 0) {
      return 0;
    }

    while (_dword == null) {
      _dword = _readUint32Le(_tokenizer.readBytes(4));
    }

    var out = _dword!;
    pos += bits;

    if (pos < 32) {
      out >>>= 32 - pos;
      return out & ((1 << bits) - 1);
    }

    pos -= 32;
    if (pos == 0) {
      _dword = null;
      return out & ((1 << bits) - 1);
    }

    _dword = _readUint32Le(_tokenizer.readBytes(4));
    if (pos > 0) {
      out <<= pos;
      out |= _dword! >>> (32 - pos);
    }
    return out & ((1 << bits) - 1);
  }

  Future<int> ignore(int bits) async {
    var remainingBits = bits;
    if (remainingBits == 0) {
      return 0;
    }

    if (pos > 0) {
      final remaining = 32 - pos;
      _dword = null;
      remainingBits -= remaining;
      pos = 0;
    }

    final remainder = remainingBits % 32;
    final numberOfWords = (remainingBits - remainder) ~/ 32;
    if (numberOfWords > 0) {
      _tokenizer.skip(numberOfWords * 4);
    }
    return read(remainder);
  }

  static int _readUint32Le(List<int> bytes) {
    if (bytes.length != 4) {
      throw TokenizerException('Expected 4 bytes for uint32 little-endian');
    }
    return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  }
}
