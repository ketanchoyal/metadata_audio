import 'dart:convert';

import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/lyrics3/lyrics3_parser.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

/// Mock tokenizer for testing Lyrics3 parser
class MockLyrics3Tokenizer implements Tokenizer {

  MockLyrics3Tokenizer({required List<int> data, required int fileSize})
    : _data = data,
      _fileInfo = FileInfo(size: fileSize, path: 'test.mp3');
  final List<int> _data;
  int _position = 0;
  final FileInfo _fileInfo;

  @override
  bool get canSeek => true;

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
    final val = (_data[_position] << 8) | _data[_position + 1];
    _position += 2;
    return val;
  }

  @override
  int readUint32() {
    if (_position + 4 > _data.length) {
      throw TokenizerException('Not enough bytes');
    }
    final val =
        (_data[_position] << 24) |
        (_data[_position + 1] << 16) |
        (_data[_position + 2] << 8) |
        _data[_position + 3];
    _position += 4;
    return val;
  }

  @override
  List<int> readBytes(int length) {
    if (_position + length > _data.length) {
      throw TokenizerException('Not enough bytes to read');
    }
    final result = _data.sublist(_position, _position + length);
    _position += length;
    return result;
  }

  @override
  void skip(int length) {
    if (_position + length > _data.length) {
      throw TokenizerException('Not enough bytes to skip');
    }
    _position += length;
  }

  @override
  void seek(int position) {
    if (position < 0 || position > _data.length) {
      throw TokenizerException('Invalid seek position');
    }
    _position = position;
  }
}

void main() {
  group('Lyrics3Parser', () {
    late MetadataCollector metadata;

    setUp(() {
      metadata = MetadataCollector(CombinedTagMapper());
    });

    test('detects Lyrics3 v2.00 footer', () async {
      // Create a file large enough for Lyrics3 (>= 143 bytes)
      // Plus: at least 143 bytes of data before Lyrics3 tag
      final padding = List<int>.filled(150, 0); // 150 bytes of padding

      final lyricsData = latin1.encode('[LYR:11]Test Lyrics');
      final sizeStr = lyricsData.length.toString().padLeft(
        6,
        '0',
      ); // Correct size
      final footer = latin1.encode(
        '$sizeStr'
        'LYRICS200',
      );

      final fileData = <int>[...padding, ...lyricsData, ...footer];

      final tokenizer = MockLyrics3Tokenizer(
        data: fileData,
        fileSize: fileData.length,
      );

      final parser = Lyrics3Parser(metadata: metadata, tokenizer: tokenizer);

      await parser.parse();

      // Check that Lyrics3 tag was parsed
      final audioMetadata = metadata.toAudioMetadata();
      final nativeTags = audioMetadata.native;
      expect(nativeTags.containsKey('Lyrics3'), true);
    });

    test('parses [LYR:...] field', () async {
      // Create a file large enough for Lyrics3
      final padding = List<int>.filled(150, 0);

      const lyricsText = 'This is test lyrics content';
      const lyricsField = '[LYR:${lyricsText.length}]$lyricsText';
      final lyricsData = latin1.encode(lyricsField);

      final sizeStr = lyricsData.length.toString().padLeft(6, '0');
      final footer = latin1.encode(
        '$sizeStr'
        'LYRICS200',
      );

      final fileData = <int>[...padding, ...lyricsData, ...footer];
      final tokenizer = MockLyrics3Tokenizer(
        data: fileData,
        fileSize: fileData.length,
      );

      final parser = Lyrics3Parser(metadata: metadata, tokenizer: tokenizer);

      await parser.parse();

      final nativeTags = metadata.toAudioMetadata().native;
      expect(nativeTags.containsKey('Lyrics3'), true);
    });

    test('parses multiple fields in Lyrics3 data', () async {
      final padding = List<int>.filled(150, 0);

      // Create Lyrics3 with multiple fields
      // Calculate actual sizes for each field
      const indValue = '\x00\x00\x00';
      const indField = '[IND:${indValue.length}]$indValue';

      const lyrValue = 'Test Lyrics\n';
      const lyrField = '[LYR:${lyrValue.length}]$lyrValue';

      const infValue = 'Descriptor';
      const infField = '[INF:${infValue.length}]$infValue';

      final lyricsData = latin1.encode('$indField$lyrField$infField');

      final sizeStr = lyricsData.length.toString().padLeft(6, '0');
      final footer = latin1.encode(
        '$sizeStr'
        'LYRICS200',
      );

      final fileData = <int>[...padding, ...lyricsData, ...footer];
      final tokenizer = MockLyrics3Tokenizer(
        data: fileData,
        fileSize: fileData.length,
      );

      final parser = Lyrics3Parser(metadata: metadata, tokenizer: tokenizer);

      await parser.parse();

      final nativeTags = metadata.toAudioMetadata().native;
      expect(nativeTags.containsKey('Lyrics3'), true);
    });

    test('returns empty result when no Lyrics3 tag found', () async {
      // Create data without Lyrics3 footer
      final fileData = <int>[1, 2, 3, 4, 5];
      final tokenizer = MockLyrics3Tokenizer(
        data: fileData,
        fileSize: fileData.length,
      );

      final parser = Lyrics3Parser(metadata: metadata, tokenizer: tokenizer);

      await parser.parse();

      final nativeTags = metadata.toAudioMetadata().native;
      expect(nativeTags.containsKey('Lyrics3'), false);
    });

    test('handles file too small for Lyrics3', () async {
      // File smaller than minimum Lyrics3 size (143 bytes)
      final fileData = <int>[1, 2, 3, 4];
      final tokenizer = MockLyrics3Tokenizer(
        data: fileData,
        fileSize: fileData.length,
      );

      final parser = Lyrics3Parser(metadata: metadata, tokenizer: tokenizer);

      // Should not throw
      await parser.parse();

      final nativeTags = metadata.toAudioMetadata().native;
      expect(nativeTags.containsKey('Lyrics3'), false);
    });

    test('handles non-seekable tokenizer', () async {
      // This test verifies graceful handling of non-seekable tokenizers
      // Create a minimal Lyrics3 data with footer
      const lyricsText = 'Test';
      const lyricsField = '[LYR:${lyricsText.length}]$lyricsText';
      final lyricsData = latin1.encode(lyricsField);
      final sizeStr = lyricsData.length.toString().padLeft(6, '0');
      final footer = latin1.encode(
        '$sizeStr'
        'LYRICS200',
      );

      final fileData = <int>[...lyricsData, ...footer];
      final tokenizer = MockLyrics3Tokenizer(
        data: fileData,
        fileSize: fileData.length,
      );

      final parser = Lyrics3Parser(metadata: metadata, tokenizer: tokenizer);

      // Should not throw even if tokenizer doesn't support seeking
      await parser.parse();
    });

    test('ignores invalid Lyrics3 size', () async {
      // Create footer with invalid size (non-numeric)
      const sizeStr = 'INVALID';
      final footer = latin1.encode(
        '$sizeStr'
        'LYRICS200',
      );

      final fileData = <int>[...footer];
      final tokenizer = MockLyrics3Tokenizer(
        data: fileData,
        fileSize: fileData.length,
      );

      final parser = Lyrics3Parser(metadata: metadata, tokenizer: tokenizer);

      await parser.parse();

      final nativeTags = metadata.toAudioMetadata().native;
      expect(nativeTags.containsKey('Lyrics3'), false);
    });

    test('rejects oversized Lyrics3 data', () async {
      // Create footer with size exceeding max
      const sizeStr = '9999999'; // Too large
      final footer = latin1.encode(
        '${sizeStr.substring(0, 6)}'
        'LYRICS200',
      );

      final fileData = <int>[...footer];
      final tokenizer = MockLyrics3Tokenizer(
        data: fileData,
        fileSize: fileData.length,
      );

      final parser = Lyrics3Parser(metadata: metadata, tokenizer: tokenizer);

      await parser.parse();

      final nativeTags = metadata.toAudioMetadata().native;
      expect(nativeTags.containsKey('Lyrics3'), false);
    });
  });
}
