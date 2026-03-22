import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

/// Mock tokenizer for testing the interface contract
class MockTokenizer implements Tokenizer {
  MockTokenizer(this._data, {bool canSeek = true}) : _canSeek = canSeek;
  final List<int> _data;
  int _position = 0;
  final bool _canSeek;

  @override
  FileInfo? get fileInfo => FileInfo(size: _data.length);

  @override
  int get position => _position;

  @override
  bool get canSeek => _canSeek;

  @override
  int readUint8() {
    if (_position >= _data.length) {
      throw TokenizerException('End of data reached');
    }
    return _data[_position++];
  }

  @override
  int readUint16() {
    if (_position + 1 >= _data.length) {
      throw TokenizerException('Insufficient data to read uint16');
    }
    final value = (_data[_position] << 8) | _data[_position + 1];
    _position += 2;
    return value;
  }

  @override
  int readUint32() {
    if (_position + 3 >= _data.length) {
      throw TokenizerException('Insufficient data to read uint32');
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
      throw TokenizerException('Insufficient data to read $length bytes');
    }
    final result = _data.sublist(_position, _position + length);
    _position += length;
    return result;
  }

  @override
  int peekUint8() {
    if (_position >= _data.length) {
      throw TokenizerException('End of data reached');
    }
    return _data[_position];
  }

  @override
  List<int> peekBytes(int length) {
    if (_position + length > _data.length) {
      throw TokenizerException('Insufficient data to peek $length bytes');
    }
    return _data.sublist(_position, _position + length);
  }

  @override
  void skip(int length) {
    if (_position + length > _data.length) {
      throw TokenizerException('Cannot skip $length bytes');
    }
    _position += length;
  }

  @override
  void seek(int position) {
    if (!canSeek) {
      throw TokenizerException('Tokenizer does not support seeking');
    }
    if (position < 0 || position > _data.length) {
      throw TokenizerException('Invalid seek position: $position');
    }
    _position = position;
  }
}

void main() {
  group('Tokenizer Contract', () {
    group('Basic Properties', () {
      test('fileInfo is accessible', () {
        final tokenizer = MockTokenizer([1, 2, 3, 4]);
        expect(tokenizer.fileInfo, isNotNull);
        expect(tokenizer.fileInfo!.size, equals(4));
      });

      test('position starts at 0', () {
        final tokenizer = MockTokenizer([1, 2, 3, 4]);
        expect(tokenizer.position, equals(0));
      });

      test('canSeek indicates random access capability', () {
        final seekable = MockTokenizer([1, 2, 3]);
        expect(seekable.canSeek, isTrue);

        final nonSeekable = MockTokenizer([1, 2, 3], canSeek: false);
        expect(nonSeekable.canSeek, isFalse);
      });
    });

    group('Read Operations', () {
      test('readUint8() reads single byte and advances position', () {
        final tokenizer = MockTokenizer([0xFF, 0x42, 0x00]);
        expect(tokenizer.readUint8(), equals(0xFF));
        expect(tokenizer.position, equals(1));
        expect(tokenizer.readUint8(), equals(0x42));
        expect(tokenizer.position, equals(2));
      });

      test('readUint16() reads 2 bytes as big-endian uint16', () {
        final tokenizer = MockTokenizer([0x12, 0x34, 0x56, 0x78]);
        expect(tokenizer.readUint16(), equals(0x1234));
        expect(tokenizer.position, equals(2));
      });

      test('readUint32() reads 4 bytes as big-endian uint32', () {
        final tokenizer = MockTokenizer([0x12, 0x34, 0x56, 0x78, 0x9A]);
        expect(tokenizer.readUint32(), equals(0x12345678));
        expect(tokenizer.position, equals(4));
      });

      test('readBytes() reads N bytes and advances position', () {
        final tokenizer = MockTokenizer([1, 2, 3, 4, 5, 6]);
        final bytes = tokenizer.readBytes(3);
        expect(bytes, equals([1, 2, 3]));
        expect(tokenizer.position, equals(3));
      });

      test('readUint8() throws at end of data', () {
        final tokenizer = MockTokenizer([1]);
        tokenizer.readUint8();
        expect(tokenizer.readUint8, throwsA(isA<TokenizerException>()));
      });

      test('readUint16() throws with insufficient data', () {
        final tokenizer = MockTokenizer([0xFF]);
        expect(tokenizer.readUint16, throwsA(isA<TokenizerException>()));
      });

      test('readUint32() throws with insufficient data', () {
        final tokenizer = MockTokenizer([0xFF, 0xFF, 0xFF]);
        expect(tokenizer.readUint32, throwsA(isA<TokenizerException>()));
      });

      test('readBytes() throws with insufficient data', () {
        final tokenizer = MockTokenizer([1, 2]);
        expect(
          () => tokenizer.readBytes(5),
          throwsA(isA<TokenizerException>()),
        );
      });
    });

    group('Peek Operations', () {
      test('peekUint8() reads without advancing position', () {
        final tokenizer = MockTokenizer([0xFF, 0x42]);
        expect(tokenizer.peekUint8(), equals(0xFF));
        expect(tokenizer.position, equals(0));
        expect(tokenizer.peekUint8(), equals(0xFF));
        expect(tokenizer.position, equals(0));
      });

      test('peekBytes() reads without advancing position', () {
        final tokenizer = MockTokenizer([1, 2, 3, 4]);
        final bytes1 = tokenizer.peekBytes(2);
        expect(bytes1, equals([1, 2]));
        expect(tokenizer.position, equals(0));

        final bytes2 = tokenizer.peekBytes(2);
        expect(bytes2, equals([1, 2]));
        expect(tokenizer.position, equals(0));
      });

      test('peekUint8() throws at end of data', () {
        final tokenizer = MockTokenizer([1]);
        tokenizer.readUint8();
        expect(tokenizer.peekUint8, throwsA(isA<TokenizerException>()));
      });

      test('peekBytes() throws with insufficient data', () {
        final tokenizer = MockTokenizer([1, 2]);
        expect(
          () => tokenizer.peekBytes(5),
          throwsA(isA<TokenizerException>()),
        );
      });

      test('peek followed by read returns same data', () {
        final tokenizer = MockTokenizer([0xAA, 0xBB, 0xCC]);
        final peeked = tokenizer.peekUint8();
        final read = tokenizer.readUint8();
        expect(peeked, equals(read));
      });
    });

    group('Skip and Seek Operations', () {
      test('skip() advances position without reading', () {
        final tokenizer = MockTokenizer([1, 2, 3, 4, 5]);
        tokenizer.skip(2);
        expect(tokenizer.position, equals(2));
        expect(tokenizer.readUint8(), equals(3));
      });

      test('skip() throws with insufficient data', () {
        final tokenizer = MockTokenizer([1, 2]);
        expect(() => tokenizer.skip(5), throwsA(isA<TokenizerException>()));
      });

      test('seek() changes position on seekable tokenizer', () {
        final tokenizer = MockTokenizer([1, 2, 3, 4]);
        tokenizer.seek(2);
        expect(tokenizer.position, equals(2));
        expect(tokenizer.readUint8(), equals(3));
      });

      test('seek() throws on non-seekable tokenizer', () {
        final tokenizer = MockTokenizer([1, 2, 3], canSeek: false);
        expect(() => tokenizer.seek(1), throwsA(isA<TokenizerException>()));
      });

      test('seek() throws with negative position', () {
        final tokenizer = MockTokenizer([1, 2, 3]);
        expect(() => tokenizer.seek(-1), throwsA(isA<TokenizerException>()));
      });

      test('seek() throws with position beyond data', () {
        final tokenizer = MockTokenizer([1, 2, 3]);
        expect(() => tokenizer.seek(10), throwsA(isA<TokenizerException>()));
      });

      test('seek(0) resets to beginning', () {
        final tokenizer = MockTokenizer([1, 2, 3, 4]);
        tokenizer.readBytes(3);
        expect(tokenizer.position, equals(3));
        tokenizer.seek(0);
        expect(tokenizer.position, equals(0));
        expect(tokenizer.readUint8(), equals(1));
      });
    });

    group('Integration Scenarios', () {
      test('read, peek, skip sequence', () {
        final tokenizer = MockTokenizer([1, 2, 3, 4, 5]);
        expect(tokenizer.readUint8(), equals(1));
        expect(tokenizer.peekUint8(), equals(2));
        expect(tokenizer.position, equals(1));
        tokenizer.skip(2);
        expect(tokenizer.position, equals(3));
        expect(tokenizer.readUint8(), equals(4));
      });

      test('seek and read on seekable tokenizer', () {
        final tokenizer = MockTokenizer([0x11, 0x22, 0x33, 0x44, 0x55]);
        tokenizer.seek(2);
        expect(tokenizer.readUint8(), equals(0x33));
        tokenizer.seek(0);
        expect(tokenizer.readUint16(), equals(0x1122));
      });

      test('peek does not affect subsequent seek', () {
        final tokenizer = MockTokenizer([1, 2, 3, 4, 5]);
        tokenizer.peekBytes(2);
        tokenizer.seek(3);
        expect(tokenizer.readUint8(), equals(4));
      });

      test('fileInfo accessible throughout stream', () {
        final tokenizer = MockTokenizer([1, 2, 3]);
        expect(tokenizer.fileInfo!.size, equals(3));
        tokenizer.readBytes(2);
        expect(tokenizer.fileInfo!.size, equals(3));
        tokenizer.seek(0);
        expect(tokenizer.fileInfo!.size, equals(3));
      });
    });

    group('Edge Cases', () {
      test('empty tokenizer', () {
        final tokenizer = MockTokenizer([]);
        expect(tokenizer.readUint8, throwsA(isA<TokenizerException>()));
        expect(tokenizer.peekUint8, throwsA(isA<TokenizerException>()));
        expect(tokenizer.canSeek, isTrue);
      });

      test('seek to end then read throws', () {
        final tokenizer = MockTokenizer([1, 2, 3]);
        tokenizer.seek(3);
        expect(tokenizer.readUint8, throwsA(isA<TokenizerException>()));
      });

      test('large data read in chunks', () {
        final data = List<int>.generate(1000, (i) => i % 256);
        final tokenizer = MockTokenizer(data);

        final chunk1 = tokenizer.readBytes(100);
        expect(chunk1.length, equals(100));

        final chunk2 = tokenizer.readBytes(100);
        expect(chunk2.length, equals(100));

        expect(tokenizer.position, equals(200));
      });
    });
  });
}
