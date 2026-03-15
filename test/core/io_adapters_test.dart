import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  group('FileTokenizer', () {
    late Directory tempDir;
    late File testFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('tokenizer_test_');
      testFile = File('${tempDir.path}/test_audio.bin');
      // Create test file with known data
      testFile.writeAsBytesSync([
        0x00,
        0x01,
        0x02,
        0x03,
        0x04,
        0x05,
        0x06,
        0x07,
        0x08,
        0x09,
        0x0A,
        0x0B,
        0x0C,
        0x0D,
        0x0E,
        0x0F,
        0x10,
        0x11,
        0x12,
        0x13,
        0x14,
        0x15,
        0x16,
        0x17,
        0x18,
        0x19,
        0x1A,
        0x1B,
        0x1C,
        0x1D,
        0x1E,
        0x1F,
      ]);
    });

    tearDown(() {
      if (testFile.existsSync()) {
        testFile.deleteSync();
      }
      if (tempDir.existsSync()) {
        tempDir.deleteSync();
      }
    });

    group('Construction', () {
      test('creates from file path', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(tokenizer.position, 0);
        expect(tokenizer.canSeek, true);
        expect(tokenizer.fileInfo, isNotNull);
        expect(tokenizer.fileInfo?.path, testFile.path);
        tokenizer.close();
      });

      test('creates from File object', () {
        final tokenizer = FileTokenizer.fromFile(testFile);
        expect(tokenizer.position, 0);
        expect(tokenizer.canSeek, true);
        expect(tokenizer.fileInfo, isNotNull);
        tokenizer.close();
      });

      test('throws FileSystemException for non-existent file', () {
        expect(
          () => FileTokenizer.fromPath('${tempDir.path}/nonexistent.bin'),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('sets fileInfo with size from existing file', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(tokenizer.fileInfo?.size, 32);
        tokenizer.close();
      });

      test('detects MIME type from file extension', () {
        final mp3File = File('${tempDir.path}/test.mp3');
        mp3File.writeAsBytesSync([0x00, 0x01, 0x02]);
        final tokenizer = FileTokenizer.fromPath(mp3File.path);
        expect(tokenizer.fileInfo?.mimeType, 'audio/mpeg');
        tokenizer.close();
        mp3File.deleteSync();
      });
    });

    group('Basic Reading', () {
      test('readUint8 returns single byte', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(tokenizer.readUint8(), 0x00);
        expect(tokenizer.position, 1);
        expect(tokenizer.readUint8(), 0x01);
        expect(tokenizer.position, 2);
        tokenizer.close();
      });

      test('readUint16 returns big-endian 2-byte value', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(tokenizer.readUint16(), 0x0001);
        expect(tokenizer.position, 2);
        expect(tokenizer.readUint16(), 0x0203);
        expect(tokenizer.position, 4);
        tokenizer.close();
      });

      test('readUint32 returns big-endian 4-byte value', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(tokenizer.readUint32(), 0x00010203);
        expect(tokenizer.position, 4);
        expect(tokenizer.readUint32(), 0x04050607);
        expect(tokenizer.position, 8);
        tokenizer.close();
      });

      test('readBytes returns exact number of bytes', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        final bytes = tokenizer.readBytes(4);
        expect(bytes, [0x00, 0x01, 0x02, 0x03]);
        expect(tokenizer.position, 4);
        tokenizer.close();
      });

      test('readBytes(0) returns empty list', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        final bytes = tokenizer.readBytes(0);
        expect(bytes, isEmpty);
        expect(tokenizer.position, 0);
        tokenizer.close();
      });

      test('throws when reading past EOF', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        tokenizer.readBytes(32);
        expect(tokenizer.readUint8, throwsA(isA<TokenizerException>()));
        tokenizer.close();
      });

      test('throws when reading insufficient bytes', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        tokenizer.readBytes(30);
        expect(
          () => tokenizer.readBytes(5),
          throwsA(isA<TokenizerException>()),
        );
        tokenizer.close();
      });
    });

    group('Peeking', () {
      test('peekUint8 does not advance position', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(tokenizer.peekUint8(), 0x00);
        expect(tokenizer.position, 0);
        expect(tokenizer.peekUint8(), 0x00);
        expect(tokenizer.position, 0);
        tokenizer.close();
      });

      test('peekBytes does not advance position', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        final bytes = tokenizer.peekBytes(4);
        expect(bytes, [0x00, 0x01, 0x02, 0x03]);
        expect(tokenizer.position, 0);
        final bytes2 = tokenizer.peekBytes(4);
        expect(bytes2, [0x00, 0x01, 0x02, 0x03]);
        tokenizer.close();
      });

      test('peekUint8 returns same byte as readUint8', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        final peeked = tokenizer.peekUint8();
        final read = tokenizer.readUint8();
        expect(peeked, read);
        tokenizer.close();
      });

      test('peekBytes(0) returns empty list', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        final bytes = tokenizer.peekBytes(0);
        expect(bytes, isEmpty);
        expect(tokenizer.position, 0);
        tokenizer.close();
      });

      test('throws when peeking past EOF', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        tokenizer.readBytes(32);
        expect(tokenizer.peekUint8, throwsA(isA<TokenizerException>()));
        tokenizer.close();
      });

      test('throws when peeking insufficient bytes', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        tokenizer.readBytes(30);
        expect(
          () => tokenizer.peekBytes(5),
          throwsA(isA<TokenizerException>()),
        );
        tokenizer.close();
      });
    });

    group('Skipping', () {
      test('skip advances position without reading', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        tokenizer.skip(4);
        expect(tokenizer.position, 4);
        expect(tokenizer.readUint8(), 0x04);
        tokenizer.close();
      });

      test('skip(0) does not change position', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        tokenizer.skip(0);
        expect(tokenizer.position, 0);
        tokenizer.close();
      });

      test('throws when skipping past EOF', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(() => tokenizer.skip(40), throwsA(isA<TokenizerException>()));
        tokenizer.close();
      });

      test('skip works with peeked byte', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        final peeked = tokenizer.peekUint8();
        expect(peeked, 0x00);
        tokenizer.skip(1);
        expect(tokenizer.position, 1);
        expect(tokenizer.readUint8(), 0x01);
        tokenizer.close();
      });
    });

    group('Seeking', () {
      test('seek changes position', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        tokenizer.seek(8);
        expect(tokenizer.position, 8);
        expect(tokenizer.readUint8(), 0x08);
        tokenizer.close();
      });

      test('seek to 0 resets position', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        tokenizer.readBytes(10);
        tokenizer.seek(0);
        expect(tokenizer.position, 0);
        expect(tokenizer.readUint8(), 0x00);
        tokenizer.close();
      });

      test('seek to end of file is valid', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        tokenizer.seek(32);
        expect(tokenizer.position, 32);
        expect(tokenizer.readUint8, throwsA(isA<TokenizerException>()));
        tokenizer.close();
      });

      test('throws when seeking to negative position', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(() => tokenizer.seek(-1), throwsA(isA<TokenizerException>()));
        tokenizer.close();
      });

      test('throws when seeking beyond EOF', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(() => tokenizer.seek(100), throwsA(isA<TokenizerException>()));
        tokenizer.close();
      });

      test('clears peeked byte on seek', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(tokenizer.peekUint8(), 0x00);
        tokenizer.seek(4);
        expect(tokenizer.readUint8(), 0x04);
        tokenizer.close();
      });

      test('supports seeking forward and backward', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        tokenizer.seek(8);
        expect(tokenizer.readUint8(), 0x08);
        tokenizer.seek(4);
        expect(tokenizer.readUint8(), 0x04);
        tokenizer.seek(12);
        expect(tokenizer.readUint8(), 0x0C);
        tokenizer.close();
      });
    });

    group('Integration', () {
      test('complex read/peek/seek sequence', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);

        // Read first byte
        expect(tokenizer.readUint8(), 0x00);
        expect(tokenizer.position, 1);

        // Peek ahead
        expect(tokenizer.peekBytes(3), [0x01, 0x02, 0x03]);
        expect(tokenizer.position, 1);

        // Skip some bytes
        tokenizer.skip(2);
        expect(tokenizer.position, 3);

        // Read uint16
        expect(tokenizer.readUint16(), 0x0304);
        expect(tokenizer.position, 5);

        // Seek back
        tokenizer.seek(0);
        expect(tokenizer.position, 0);

        // Read uint32
        expect(tokenizer.readUint32(), 0x00010203);
        expect(tokenizer.position, 4);

        tokenizer.close();
      });

      test('maintains state across multiple operations', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);

        // First block
        tokenizer.readBytes(8);
        final pos1 = tokenizer.position;
        expect(pos1, 8);

        // Peek doesn't affect position
        tokenizer.peekBytes(4);
        expect(tokenizer.position, pos1);

        // Read some more
        tokenizer.readBytes(4);
        expect(tokenizer.position, 12);

        // Seek and verify
        tokenizer.seek(pos1);
        expect(tokenizer.position, pos1);
        expect(tokenizer.readUint8(), 0x08);

        tokenizer.close();
      });

      test('can read entire file sequentially', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        final bytes = <int>[];

        for (var i = 0; i < 32; i++) {
          bytes.add(tokenizer.readUint8());
        }

        expect(bytes, [
          0x00,
          0x01,
          0x02,
          0x03,
          0x04,
          0x05,
          0x06,
          0x07,
          0x08,
          0x09,
          0x0A,
          0x0B,
          0x0C,
          0x0D,
          0x0E,
          0x0F,
          0x10,
          0x11,
          0x12,
          0x13,
          0x14,
          0x15,
          0x16,
          0x17,
          0x18,
          0x19,
          0x1A,
          0x1B,
          0x1C,
          0x1D,
          0x1E,
          0x1F,
        ]);

        tokenizer.close();
      });
    });

    group('Error Handling', () {
      test('readBytes with negative length throws', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(
          () => tokenizer.readBytes(-1),
          throwsA(isA<TokenizerException>()),
        );
        tokenizer.close();
      });

      test('peekBytes with negative length throws', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(
          () => tokenizer.peekBytes(-1),
          throwsA(isA<TokenizerException>()),
        );
        tokenizer.close();
      });

      test('skip with negative length throws', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(() => tokenizer.skip(-1), throwsA(isA<TokenizerException>()));
        tokenizer.close();
      });
    });

    group('FileInfo', () {
      test('contains correct path', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(tokenizer.fileInfo?.path, testFile.path);
        tokenizer.close();
      });

      test('contains correct size', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(tokenizer.fileInfo?.size, 32);
        tokenizer.close();
      });

      test('detects various MIME types', () {
        final mimeTests = {
          'test.mp3': 'audio/mpeg',
          'test.flac': 'audio/flac',
          'test.ogg': 'audio/ogg',
          'test.wav': 'audio/wav',
          'test.m4a': 'audio/mp4',
        };

        for (final entry in mimeTests.entries) {
          final file = File('${tempDir.path}/${entry.key}');
          file.writeAsBytesSync([0x00]);
          final tokenizer = FileTokenizer.fromPath(file.path);
          expect(
            tokenizer.fileInfo?.mimeType,
            entry.value,
            reason: 'MIME type detection failed for ${entry.key}',
          );
          tokenizer.close();
          file.deleteSync();
        }
      });
    });

    group('Compatibility', () {
      test('implements Tokenizer interface', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(tokenizer, isA<Tokenizer>());
        tokenizer.close();
      });

      test('canSeek is always true', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(tokenizer.canSeek, true);
        tokenizer.close();
      });

      test('fileInfo is not null', () {
        final tokenizer = FileTokenizer.fromPath(testFile.path);
        expect(tokenizer.fileInfo, isNotNull);
        tokenizer.close();
      });
    });
  });

  group('BytesTokenizer', () {
    group('Construction', () {
      test('creates tokenizer with Uint8List', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer, isNotNull);
        expect(tokenizer.position, equals(0));
      });

      test('auto-creates FileInfo when not provided', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.fileInfo, isNotNull);
        expect(tokenizer.fileInfo!.size, equals(5));
      });

      test('uses provided FileInfo', () {
        final bytes = Uint8List.fromList([1, 2, 3]);
        const fileInfo = FileInfo(size: 3, path: 'test.bin');
        final tokenizer = BytesTokenizer(bytes, fileInfo: fileInfo);
        expect(tokenizer.fileInfo, equals(fileInfo));
        expect(tokenizer.fileInfo!.path, equals('test.bin'));
      });

      test('canSeek is always true for in-memory buffer', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.canSeek, isTrue);
      });

      test('position starts at 0', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.position, equals(0));
      });

      test('handles empty Uint8List', () {
        final bytes = Uint8List(0);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.fileInfo!.size, equals(0));
        expect(tokenizer.position, equals(0));
      });
    });

    group('Basic Reading - readUint8', () {
      test('reads single byte and advances position', () {
        final bytes = Uint8List.fromList([0xFF, 0x42, 0x00]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.readUint8(), equals(0xFF));
        expect(tokenizer.position, equals(1));
        expect(tokenizer.readUint8(), equals(0x42));
        expect(tokenizer.position, equals(2));
      });

      test('reads all bytes sequentially', () {
        final bytes = Uint8List.fromList([0x10, 0x20, 0x30]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.readUint8(), equals(0x10));
        expect(tokenizer.readUint8(), equals(0x20));
        expect(tokenizer.readUint8(), equals(0x30));
      });

      test('throws when reading past end', () {
        final bytes = Uint8List.fromList([1, 2]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.readUint8();
        tokenizer.readUint8();
        expect(tokenizer.readUint8, throwsA(isA<TokenizerException>()));
      });

      test('throws with descriptive message at end', () {
        final bytes = Uint8List.fromList([1]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.readUint8();
        expect(tokenizer.readUint8, throwsA(isA<TokenizerException>()));
      });
    });

    group('Basic Reading - readUint16', () {
      test('reads 2 bytes as big-endian uint16', () {
        final bytes = Uint8List.fromList([0x12, 0x34, 0x56, 0x78]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.readUint16(), equals(0x1234));
        expect(tokenizer.position, equals(2));
      });

      test('reads multiple uint16 values', () {
        final bytes = Uint8List.fromList([0x11, 0x22, 0x33, 0x44]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.readUint16(), equals(0x1122));
        expect(tokenizer.readUint16(), equals(0x3344));
        expect(tokenizer.position, equals(4));
      });

      test('throws with insufficient data', () {
        final bytes = Uint8List.fromList([0xFF]);
        final tokenizer = BytesTokenizer(bytes);
        expect(
          tokenizer.readUint16,
          throwsA(isA<TokenizerException>()),
        );
      });

      test('throws when reading uint16 at end boundary', () {
        final bytes = Uint8List.fromList([0x12]);
        final tokenizer = BytesTokenizer(bytes);
        expect(
          tokenizer.readUint16,
          throwsA(isA<TokenizerException>()),
        );
      });
    });

    group('Basic Reading - readUint32', () {
      test('reads 4 bytes as big-endian uint32', () {
        final bytes = Uint8List.fromList([0x12, 0x34, 0x56, 0x78, 0x9A]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.readUint32(), equals(0x12345678));
        expect(tokenizer.position, equals(4));
      });

      test('reads multiple uint32 values', () {
        final bytes = Uint8List.fromList([
          0x11,
          0x22,
          0x33,
          0x44,
          0x55,
          0x66,
          0x77,
          0x88,
        ]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.readUint32(), equals(0x11223344));
        expect(tokenizer.readUint32(), equals(0x55667788));
        expect(tokenizer.position, equals(8));
      });

      test('throws with insufficient data', () {
        final bytes = Uint8List.fromList([0xFF, 0xFF, 0xFF]);
        final tokenizer = BytesTokenizer(bytes);
        expect(
          tokenizer.readUint32,
          throwsA(isA<TokenizerException>()),
        );
      });

      test('throws with only 1 byte available', () {
        final bytes = Uint8List.fromList([0xFF]);
        final tokenizer = BytesTokenizer(bytes);
        expect(
          tokenizer.readUint32,
          throwsA(isA<TokenizerException>()),
        );
      });
    });

    group('Basic Reading - readBytes', () {
      test('reads N bytes and advances position', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
        final tokenizer = BytesTokenizer(bytes);
        final result = tokenizer.readBytes(3);
        expect(result, equals([1, 2, 3]));
        expect(tokenizer.position, equals(3));
      });

      test('reads remaining bytes', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.readBytes(2);
        final remaining = tokenizer.readBytes(3);
        expect(remaining, equals([3, 4, 5]));
        expect(tokenizer.position, equals(5));
      });

      test('throws with insufficient data', () {
        final bytes = Uint8List.fromList([1, 2]);
        final tokenizer = BytesTokenizer(bytes);
        expect(
          () => tokenizer.readBytes(5),
          throwsA(isA<TokenizerException>()),
        );
      });

      test('reads 0 bytes successfully', () {
        final bytes = Uint8List.fromList([1, 2, 3]);
        final tokenizer = BytesTokenizer(bytes);
        final result = tokenizer.readBytes(0);
        expect(result, isEmpty);
        expect(tokenizer.position, equals(0));
      });

      test('reads all bytes at once', () {
        final bytes = Uint8List.fromList([10, 20, 30, 40]);
        final tokenizer = BytesTokenizer(bytes);
        final result = tokenizer.readBytes(4);
        expect(result, equals([10, 20, 30, 40]));
        expect(tokenizer.position, equals(4));
      });
    });

    group('Peeking - peekUint8', () {
      test('reads without advancing position', () {
        final bytes = Uint8List.fromList([0xFF, 0x42]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.peekUint8(), equals(0xFF));
        expect(tokenizer.position, equals(0));
        expect(tokenizer.peekUint8(), equals(0xFF));
        expect(tokenizer.position, equals(0));
      });

      test('peek followed by read returns same value', () {
        final bytes = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
        final tokenizer = BytesTokenizer(bytes);
        final peeked = tokenizer.peekUint8();
        final read = tokenizer.readUint8();
        expect(peeked, equals(read));
      });

      test('throws at end of data', () {
        final bytes = Uint8List.fromList([1]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.readUint8();
        expect(tokenizer.peekUint8, throwsA(isA<TokenizerException>()));
      });

      test('throws on empty buffer', () {
        final bytes = Uint8List(0);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.peekUint8, throwsA(isA<TokenizerException>()));
      });
    });

    group('Peeking - peekBytes', () {
      test('reads without advancing position', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        final tokenizer = BytesTokenizer(bytes);
        final bytes1 = tokenizer.peekBytes(2);
        expect(bytes1, equals([1, 2]));
        expect(tokenizer.position, equals(0));

        final bytes2 = tokenizer.peekBytes(2);
        expect(bytes2, equals([1, 2]));
        expect(tokenizer.position, equals(0));
      });

      test('peek followed by read returns same data', () {
        final bytes = Uint8List.fromList([10, 20, 30, 40]);
        final tokenizer = BytesTokenizer(bytes);
        final peeked = tokenizer.peekBytes(3);
        final read = tokenizer.readBytes(3);
        expect(peeked, equals(read));
      });

      test('throws with insufficient data', () {
        final bytes = Uint8List.fromList([1, 2]);
        final tokenizer = BytesTokenizer(bytes);
        expect(
          () => tokenizer.peekBytes(5),
          throwsA(isA<TokenizerException>()),
        );
      });

      test('peeks 0 bytes successfully', () {
        final bytes = Uint8List.fromList([1, 2, 3]);
        final tokenizer = BytesTokenizer(bytes);
        final result = tokenizer.peekBytes(0);
        expect(result, isEmpty);
        expect(tokenizer.position, equals(0));
      });

      test('peeks all bytes', () {
        final bytes = Uint8List.fromList([10, 20, 30]);
        final tokenizer = BytesTokenizer(bytes);
        final result = tokenizer.peekBytes(3);
        expect(result, equals([10, 20, 30]));
        expect(tokenizer.position, equals(0));
      });
    });

    group('Skip Operations', () {
      test('skip advances position without reading', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.skip(2);
        expect(tokenizer.position, equals(2));
        expect(tokenizer.readUint8(), equals(3));
      });

      test('skip multiple times', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.skip(1);
        expect(tokenizer.position, equals(1));
        tokenizer.skip(2);
        expect(tokenizer.position, equals(3));
      });

      test('throws with insufficient data', () {
        final bytes = Uint8List.fromList([1, 2]);
        final tokenizer = BytesTokenizer(bytes);
        expect(() => tokenizer.skip(5), throwsA(isA<TokenizerException>()));
      });

      test('skip 0 bytes does nothing', () {
        final bytes = Uint8List.fromList([1, 2, 3]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.skip(0);
        expect(tokenizer.position, equals(0));
      });

      test('skip to end then read throws', () {
        final bytes = Uint8List.fromList([1, 2, 3]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.skip(3);
        expect(tokenizer.readUint8, throwsA(isA<TokenizerException>()));
      });
    });

    group('Seek Operations', () {
      test('seek changes position', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.seek(2);
        expect(tokenizer.position, equals(2));
        expect(tokenizer.readUint8(), equals(3));
      });

      test('seek(0) resets to beginning', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.readBytes(3);
        expect(tokenizer.position, equals(3));
        tokenizer.seek(0);
        expect(tokenizer.position, equals(0));
        expect(tokenizer.readUint8(), equals(1));
      });

      test('seek to end', () {
        final bytes = Uint8List.fromList([1, 2, 3]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.seek(3);
        expect(tokenizer.position, equals(3));
        expect(tokenizer.readUint8, throwsA(isA<TokenizerException>()));
      });

      test('seek backward', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.readBytes(4);
        tokenizer.seek(1);
        expect(tokenizer.position, equals(1));
        expect(tokenizer.readUint8(), equals(2));
      });

      test('throws with negative position', () {
        final bytes = Uint8List.fromList([1, 2, 3]);
        final tokenizer = BytesTokenizer(bytes);
        expect(() => tokenizer.seek(-1), throwsA(isA<TokenizerException>()));
      });

      test('throws with position beyond data', () {
        final bytes = Uint8List.fromList([1, 2, 3]);
        final tokenizer = BytesTokenizer(bytes);
        expect(() => tokenizer.seek(10), throwsA(isA<TokenizerException>()));
      });

      test('seek and read sequence', () {
        final bytes = Uint8List.fromList([0x11, 0x22, 0x33, 0x44, 0x55]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.seek(2);
        expect(tokenizer.readUint8(), equals(0x33));
        tokenizer.seek(0);
        expect(tokenizer.readUint16(), equals(0x1122));
      });
    });

    group('Integration Scenarios', () {
      test('read, peek, skip sequence', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.readUint8(), equals(1));
        expect(tokenizer.peekUint8(), equals(2));
        expect(tokenizer.position, equals(1));
        tokenizer.skip(2);
        expect(tokenizer.position, equals(3));
        expect(tokenizer.readUint8(), equals(4));
      });

      test('read uint16/uint32 mixed sequence', () {
        final bytes = Uint8List.fromList([
          0x12,
          0x34,
          0x56,
          0x78,
          0x9A,
          0xBC,
          0xDE,
          0xF0,
        ]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.readUint16(), equals(0x1234));
        expect(tokenizer.readUint32(), equals(0x56789ABC));
        expect(tokenizer.readUint16(), equals(0xDEF0));
      });

      test('peek does not affect seek', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.peekBytes(2);
        tokenizer.seek(3);
        expect(tokenizer.readUint8(), equals(4));
      });

      test('fileInfo accessible throughout operations', () {
        final bytes = Uint8List.fromList([1, 2, 3]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.fileInfo!.size, equals(3));
        tokenizer.readBytes(2);
        expect(tokenizer.fileInfo!.size, equals(3));
        tokenizer.seek(0);
        expect(tokenizer.fileInfo!.size, equals(3));
      });

      test('large buffer operations', () {
        final data = Uint8List(1000);
        for (var i = 0; i < 1000; i++) {
          data[i] = i % 256;
        }
        final tokenizer = BytesTokenizer(data);

        final chunk1 = tokenizer.readBytes(100);
        expect(chunk1.length, equals(100));

        final chunk2 = tokenizer.readBytes(100);
        expect(chunk2.length, equals(100));

        expect(tokenizer.position, equals(200));

        tokenizer.seek(0);
        expect(tokenizer.readUint8(), equals(0));
      });

      test('complex seek and read pattern', () {
        final bytes = Uint8List.fromList([
          0x10,
          0x20,
          0x30,
          0x40,
          0x50,
          0x60,
          0x70,
          0x80,
        ]);
        final tokenizer = BytesTokenizer(bytes);

        // Read first value
        final val1 = tokenizer.readUint16();
        expect(val1, equals(0x1020));

        // Skip ahead
        tokenizer.skip(2);
        expect(tokenizer.position, equals(4));

        // Peek at next
        final peeked = tokenizer.peekUint8();
        expect(peeked, equals(0x50));

        // Seek back
        tokenizer.seek(2);
        final val2 = tokenizer.readUint16();
        expect(val2, equals(0x3040));
      });
    });

    group('Edge Cases', () {
      test('empty buffer operations', () {
        final bytes = Uint8List(0);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.fileInfo!.size, equals(0));
        expect(tokenizer.position, equals(0));
        expect(tokenizer.canSeek, isTrue);
        expect(tokenizer.readUint8, throwsA(isA<TokenizerException>()));
      });

      test('single byte buffer', () {
        final bytes = Uint8List.fromList([0xFF]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.readUint8(), equals(0xFF));
        expect(tokenizer.position, equals(1));
        expect(tokenizer.readUint8, throwsA(isA<TokenizerException>()));
      });

      test('buffer with all zeros', () {
        final bytes = Uint8List(10);
        final tokenizer = BytesTokenizer(bytes);
        for (var i = 0; i < 10; i++) {
          expect(tokenizer.readUint8(), equals(0));
        }
      });

      test('buffer with all 0xFF', () {
        final bytes = Uint8List.fromList(List<int>.filled(5, 0xFF));
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.readUint16(), equals(0xFFFF));
        expect(tokenizer.readUint16(), equals(0xFFFF));
        expect(tokenizer.readUint8(), equals(0xFF));
      });

      test('position at boundary', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.seek(3);
        expect(tokenizer.readUint8(), equals(4));
        expect(tokenizer.position, equals(4));
      });

      test('peek at boundary', () {
        final bytes = Uint8List.fromList([1, 2, 3]);
        final tokenizer = BytesTokenizer(bytes);
        tokenizer.seek(2);
        expect(tokenizer.peekUint8(), equals(3));
        expect(tokenizer.position, equals(2));
      });
    });

    group('FileInfo Behavior', () {
      test('fileInfo created with correct size', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final tokenizer = BytesTokenizer(bytes);
        expect(tokenizer.fileInfo!.size, equals(5));
      });

      test('fileInfo with custom path', () {
        final bytes = Uint8List.fromList([1, 2, 3]);
        const fileInfo = FileInfo(size: 3, path: '/path/to/file');
        final tokenizer = BytesTokenizer(bytes, fileInfo: fileInfo);
        expect(tokenizer.fileInfo!.path, equals('/path/to/file'));
      });

      test('fileInfo size matches buffer length', () {
        final sizes = [0, 1, 10, 100, 1000];
        for (final size in sizes) {
          final bytes = Uint8List(size);
          final tokenizer = BytesTokenizer(bytes);
          expect(tokenizer.fileInfo!.size, equals(size));
        }
      });
    });

    group('Compatibility with Tokenizer Contract', () {
      test('implements all Tokenizer interface methods', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        final tokenizer = BytesTokenizer(bytes) as Tokenizer;

        // Verify all required properties and methods exist
        expect(tokenizer.fileInfo, isNotNull);
        expect(tokenizer.position, equals(0));
        expect(tokenizer.canSeek, isTrue);

        // Verify all required methods can be called
        expect(tokenizer.readUint8, returnsNormally);
        expect(tokenizer.position, equals(1));

        expect(tokenizer.peekUint8, returnsNormally);
        expect(() => tokenizer.skip(1), returnsNormally);
        expect(() => tokenizer.seek(0), returnsNormally);
      });

      test('matches FileTokenizer behavior', () {
        final testData = [0x11, 0x22, 0x33, 0x44];
        final bytes = Uint8List.fromList(testData);
        final tokenizer = BytesTokenizer(bytes);

        // Test same sequence as FileTokenizer tests
        expect(tokenizer.readUint8(), equals(0x11));
        expect(tokenizer.peekUint8(), equals(0x22));
        expect(tokenizer.position, equals(1));
        tokenizer.skip(2);
        expect(tokenizer.position, equals(3));
        expect(tokenizer.readUint8(), equals(0x44));
      });
    });
  });
}
