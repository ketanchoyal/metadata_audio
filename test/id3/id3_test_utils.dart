import 'dart:convert';

import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

class MockTokenizer implements Tokenizer {

  MockTokenizer({
    required List<int> data,
    bool canSeek = true,
    FileInfo? fileInfo,
  }) : _data = data,
       _canSeek = canSeek,
       _fileInfo = fileInfo;
  final List<int> _data;
  int _position = 0;
  final bool _canSeek;
  final FileInfo? _fileInfo;

  @override
  bool get canSeek => _canSeek;

  @override
  FileInfo? get fileInfo => _fileInfo;

  @override
  int get position => _position;

  @override
  int peekUint8() {
    if (_position >= _data.length) {
      throw TokenizerException('EOF reached');
    }
    return _data[_position];
  }

  @override
  List<int> peekBytes(int length) {
    if (_position + length > _data.length) {
      throw TokenizerException('Not enough bytes to peek');
    }
    return _data.sublist(_position, _position + length);
  }

  @override
  int readUint8() {
    if (_position >= _data.length) {
      throw TokenizerException('EOF reached');
    }
    return _data[_position++];
  }

  @override
  int readUint16() {
    if (_position + 2 > _data.length) {
      throw TokenizerException('Not enough bytes');
    }
    final value = (_data[_position] << 8) | _data[_position + 1];
    _position += 2;
    return value;
  }

  @override
  int readUint32() {
    if (_position + 4 > _data.length) {
      throw TokenizerException('Not enough bytes');
    }
    final value =
        (_data[_position] << 24) |
        (_data[_position + 1] << 16) |
        (_data[_position + 2] << 8) |
        _data[_position + 3];
    _position += 4;
    return value;
  }

  @override
  List<int> readBytes(int length) {
    if (_position + length > _data.length) {
      throw TokenizerException('Not enough bytes');
    }
    final bytes = _data.sublist(_position, _position + length);
    _position += length;
    return bytes;
  }

  @override
  void seek(int position) {
    if (!_canSeek) {
      throw TokenizerException('Seeking not supported');
    }
    if (position < 0 || position > _data.length) {
      throw TokenizerException('Seek position out of bounds');
    }
    _position = position;
  }

  @override
  void skip(int length) {
    if (_position + length > _data.length) {
      throw TokenizerException('Not enough bytes to skip');
    }
    _position += length;
  }
}

List<int> encodeSynchsafeInt(int value) => [
  (value >> 21) & 0x7F,
  (value >> 14) & 0x7F,
  (value >> 7) & 0x7F,
  value & 0x7F,
];

List<int> buildId3v22Frame(String id, List<int> payload) => [
    ...ascii.encode(id),
    (payload.length >> 16) & 0xFF,
    (payload.length >> 8) & 0xFF,
    payload.length & 0xFF,
    ...payload,
  ];

List<int> buildId3v23Frame(
  String id,
  List<int> payload, {
  int flags1 = 0,
  int flags2 = 0,
}) => [
    ...ascii.encode(id),
    (payload.length >> 24) & 0xFF,
    (payload.length >> 16) & 0xFF,
    (payload.length >> 8) & 0xFF,
    payload.length & 0xFF,
    flags1,
    flags2,
    ...payload,
  ];

List<int> buildId3v24Frame(
  String id,
  List<int> payload, {
  int flags1 = 0,
  int flags2 = 0,
}) => [
    ...ascii.encode(id),
    ...encodeSynchsafeInt(payload.length),
    flags1,
    flags2,
    ...payload,
  ];

List<int> buildId3Tag({
  required int majorVersion,
  required int revision,
  required int flags,
  required List<int> payload,
}) => [
    ...ascii.encode('ID3'),
    majorVersion,
    revision,
    flags,
    ...encodeSynchsafeInt(payload.length),
    ...payload,
  ];
