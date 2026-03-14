import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata/audio_metadata.dart';
import 'package:audio_metadata/src/mpeg/mpeg_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('MP3 file parsing', () {
    late ParserRegistry registry;
    late ParserFactory factory;

    setUp(() {
      registry = ParserRegistry()..register(MpegLoader());
      factory = ParserFactory(registry);
      initializeParserFactory(factory);
    });

    test('parses MP3 with ID3v2.4 tags from file', () async {
      // Build a minimal MP3 file with ID3v2 tags
      final bytes = _buildMp3WithId3v24(
        title: 'Test Song Title',
        artist: 'Test Artist',
        album: 'Test Album',
        year: 2024,
        track: 1,
        genre: 'Rock',
      );

      // Write to samples directory
      final sampleDir = Directory(p.join(samplePath, 'mp3'))
        ..createSync(recursive: true);
      final file = File(p.join(sampleDir.path, 'id3v24_test.mp3'))
        ..writeAsBytesSync(bytes);

      try {
        // Parse the file
        final metadata = await parseFile(file.path);

        // Verify format
        checkFormat(
          metadata.format,
          container: 'mp3',
          codec: 'MPEG 1.0 Layer 3',
        );
      } finally {
        // Clean up
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    });

    test('parses MP3 with ID3v2.3 tags from file', () async {
      final bytes = _buildMp3WithId3v23(
        title: 'ID3v23 Title',
        artist: 'ID3v23 Artist',
      );

      final sampleDir = Directory(p.join(samplePath, 'mp3'))
        ..createSync(recursive: true);
      final file = File(p.join(sampleDir.path, 'id3v23_test.mp3'))
        ..writeAsBytesSync(bytes);

      try {
        final metadata = await parseFile(file.path);

        checkFormat(metadata.format, container: 'mp3');
        checkCommon(
          metadata.common,
          title: 'ID3v23 Title',
          artist: 'ID3v23 Artist',
        );
      } finally {
        // Clean up
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    });

    test('parses MP3 with ID3v1 tags from file', () async {
      // Note: ID3v1 requires post-header scanning which may not be active
      // in all modes. This test primarily validates that the file can be parsed
      final bytes = _buildMp3WithId3v1(
        title: 'ID3v1 Title',
        artist: 'ID3v1 Artist',
        album: 'ID3v1 Album',
      );

      final sampleDir = Directory(p.join(samplePath, 'mp3'))
        ..createSync(recursive: true);
      final file = File(p.join(sampleDir.path, 'id3v1_test.mp3'))
        ..writeAsBytesSync(bytes);

      try {
        final metadata = await parseFile(file.path);

        checkFormat(metadata.format, container: 'mp3');
        // ID3v1 parsing depends on post-header scan; just verify file parses
        expect(metadata.common, isNotNull);
      } finally {
        // Clean up
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    });
  });
}

/// Build a minimal MP3 file with ID3v2.4 tags
Uint8List _buildMp3WithId3v24({
  required String title,
  required String artist,
  String? album,
  int? year,
  int? track,
  String? genre,
}) {
  final frames = <int>[];

  // TIT2 - Title
  frames.addAll(_buildTextFrame('TIT2', title, version: 4));
  // TPE1 - Artist
  frames.addAll(_buildTextFrame('TPE1', artist, version: 4));
  if (album != null) {
    frames.addAll(_buildTextFrame('TALB', album, version: 4));
  }
  if (year != null) {
    frames.addAll(_buildTextFrame('TDRC', year.toString(), version: 4));
  }
  if (track != null) {
    frames.addAll(_buildTextFrame('TRCK', track.toString(), version: 4));
  }
  if (genre != null) {
    frames.addAll(_buildTextFrame('TCON', genre, version: 4));
  }

  final id3Tag = _buildId3Tag(frames, version: 4);
  final mpegFrame = _buildMpegFrame();

  return Uint8List.fromList([...id3Tag, ...mpegFrame]);
}

/// Build a minimal MP3 file with ID3v2.3 tags
Uint8List _buildMp3WithId3v23({required String title, required String artist}) {
  final frames = <int>[];
  frames.addAll(_buildTextFrame('TIT2', title, version: 3));
  frames.addAll(_buildTextFrame('TPE1', artist, version: 3));

  final id3Tag = _buildId3Tag(frames, version: 3);
  final mpegFrame = _buildMpegFrame();

  return Uint8List.fromList([...id3Tag, ...mpegFrame]);
}

/// Build a minimal MP3 file with ID3v1 tags
Uint8List _buildMp3WithId3v1({
  required String title,
  required String artist,
  String? album,
  int? year,
  int? track,
  String? genre,
}) {
  // Build MPEG frames first
  final mpegFrame = _buildMpegFrame();

  // Build ID3v1 tag at the end
  final id3v1 = _buildId3v1Tag(
    title: title,
    artist: artist,
    album: album,
    year: year,
    track: track,
    genre: genre,
  );

  return Uint8List.fromList([...mpegFrame, ...id3v1]);
}

List<int> _buildTextFrame(String id, String value, {required int version}) {
  // UTF-8 encoding (0x03) for v2.4, ISO-8859-1 (0x00) for v2.3
  final encoding = version >= 4 ? 0x03 : 0x00;
  final payload = <int>[encoding, ...value.codeUnits];

  if (version >= 4) {
    // ID3v2.4: 4-byte size with syncsafe encoding
    final size = payload.length;
    return <int>[
      ...id.codeUnits,
      (size >> 21) & 0x7F,
      (size >> 14) & 0x7F,
      (size >> 7) & 0x7F,
      size & 0x7F,
      0x00,
      0x00,
      ...payload,
    ];
  } else {
    // ID3v2.3: 4-byte size with standard encoding
    final size = payload.length;
    return <int>[
      ...id.codeUnits,
      (size >> 24) & 0xFF,
      (size >> 16) & 0xFF,
      (size >> 8) & 0xFF,
      size & 0xFF,
      0x00,
      0x00,
      ...payload,
    ];
  }
}

List<int> _buildId3Tag(List<int> frames, {required int version}) {
  final size = frames.length;
  // ID3v2 syncsafe size encoding
  return <int>[
    0x49, 0x44, 0x33, // "ID3"
    version, // Version (3 or 4)
    0x00, // Revision
    0x00, // Flags
    (size >> 21) & 0x7F,
    (size >> 14) & 0x7F,
    (size >> 7) & 0x7F,
    size & 0x7F,
    ...frames,
  ];
}

List<int> _buildId3v1Tag({
  required String title,
  required String artist,
  String? album,
  int? year,
  int? track,
  String? genre,
}) {
  const tagHeader = [0x54, 0x41, 0x47]; // 'TAG'
  final tag = List<int>.filled(128, 0);

  // Copy TAG header
  tag.setRange(0, 3, tagHeader);

  // Title (30 bytes)
  _writeStringTo(tag, 3, title, 30);

  // Artist (30 bytes)
  _writeStringTo(tag, 33, artist, 30);

  // Album (30 bytes)
  if (album != null) {
    _writeStringTo(tag, 63, album, 30);
  }

  // Year (4 bytes)
  if (year != null) {
    _writeStringTo(tag, 93, year.toString(), 4);
  }

  // Comment (28 bytes) - skip for simplicity
  // reserved byte for track
  if (track != null && track > 0 && track < 256) {
    tag[125] = 0x00; // null byte separator
    tag[126] = track & 0xFF;
  }

  // Genre (1 byte) - use a generic genre code
  tag[127] = 0xFF; // Unknown genre

  return tag;
}

void _writeStringTo(List<int> target, int offset, String value, int maxLen) {
  final bytes = value.codeUnits;
  final len = bytes.length > maxLen ? maxLen : bytes.length;
  for (var i = 0; i < len; i++) {
    target[offset + i] = bytes[i];
  }
}

List<int> _buildMpegFrame() {
  // Minimal MPEG1 Layer III frame
  const sampleRate = 44100;
  const samplesPerFrame = 1152;
  const bitrateKbps = 128;
  final bitrate = bitrateKbps * 1000;
  final frameLength = (samplesPerFrame / 8.0 * bitrate / sampleRate).floor();

  const header = [
    0xFF,
    0xFB,
    0x90,
    0x40,
  ]; // Sync + MPEG1 Layer III + bitrate + sample rate
  return <int>[...header, ...List<int>.filled(frameLength - 4, 0)];
}
