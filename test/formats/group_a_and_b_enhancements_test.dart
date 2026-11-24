import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/mpeg/vbri_tag.dart';
import 'package:test/test.dart';

void main() {
  group('Group A: Upstream Parser Enhancements', () {
    group('MP3 Fraunhofer VBRI Header Parsing', () {
      test('parseVbriHeader parses valid 26-byte header payload', () {
        // Construct a synthetic 26-byte VBRI header
        final bytes = <int>[
          // Magic 'VBRI'
          0x56, 0x42, 0x52, 0x49,
          // Version = 1
          0x00, 0x01,
          // Delay = 120
          0x00, 0x78,
          // Quality = 75
          0x00, 0x4B,
          // Stream Bytes = 1,048,576
          0x00, 0x10, 0x00, 0x00,
          // Stream Frames = 2,000
          0x00, 0x00, 0x07, 0xD0,
          // TOC entries = 100
          0x00, 0x64,
          // TOC scale = 1
          0x00, 0x01,
          // TOC entry size = 2
          0x00, 0x02,
          // Frames per TOC entry = 20
          0x00, 0x14,
        ];

        final vbri = parseVbriHeader(bytes, 0);
        expect(vbri, isNotNull);
        expect(vbri!.version, equals(1));
        expect(vbri.delay, equals(120));
        expect(vbri.quality, equals(75));
        expect(vbri.streamBytes, equals(1048576));
        expect(vbri.numFrames, equals(2000));
        expect(vbri.tocEntries, equals(100));
        expect(vbri.tocScale, equals(1));
        expect(vbri.tocEntrySize, equals(2));
        expect(vbri.tocFramesPerEntry, equals(20));
      });

      test('parseVbriHeader returns null on insufficient length or wrong tag', () {
        // Short buffer
        expect(parseVbriHeader([0x56, 0x42, 0x52, 0x49], 0), isNull);

        // Wrong magic
        final wrongMagic = List<int>.filled(30, 0);
        wrongMagic[0] = 0x58; // 'X'
        wrongMagic[1] = 0x69; // 'i'
        wrongMagic[2] = 0x6E; // 'n'
        wrongMagic[3] = 0x67; // 'g'
        expect(parseVbriHeader(wrongMagic, 0), isNull);
      });

      test('recovers duration, VBR profile, and bitrate from VBRI frame', () async {
        // Build an MPEG 1 Layer 3 frame with VBRI header at offset 36 from frame start
        // Frame header: 0xFF, 0xFB, 0x90, 0x64 -> MPEG 1 Layer 3, 128 kbps, 44100 Hz, stereo
        // Frame length = 144 * 128000 / 44100 = 417 bytes
        final frameBytes = List<int>.filled(417, 0);
        frameBytes[0] = 0xFF;
        frameBytes[1] = 0xFB;
        frameBytes[2] = 0x90;
        frameBytes[3] = 0x64;

        // VBRI header at offset 36 from frame start (offset 32 of frame payload):
        const vbriOffset = 36;
        frameBytes[vbriOffset + 0] = 0x56; // 'V'
        frameBytes[vbriOffset + 1] = 0x42; // 'B'
        frameBytes[vbriOffset + 2] = 0x52; // 'R'
        frameBytes[vbriOffset + 3] = 0x49; // 'I'
        // Version = 1
        frameBytes[vbriOffset + 5] = 0x01;
        // Stream bytes = 400,000 (0x00061A80)
        frameBytes[vbriOffset + 10] = 0x00;
        frameBytes[vbriOffset + 11] = 0x06;
        frameBytes[vbriOffset + 12] = 0x1A;
        frameBytes[vbriOffset + 13] = 0x80;
        // Stream frames = 1,000 (0x000003E8)
        frameBytes[vbriOffset + 14] = 0x00;
        frameBytes[vbriOffset + 15] = 0x00;
        frameBytes[vbriOffset + 16] = 0x03;
        frameBytes[vbriOffset + 17] = 0xE8;

        final metadata = await parseBytes(
          Uint8List.fromList(frameBytes),
          fileInfo: const FileInfo(mimeType: 'audio/mpeg'),
          options: const ParseOptions(duration: true),
        );

        expect(metadata.format.codecProfile, equals('VBR'));
        // 1000 frames * 1152 samples / 44100 Hz = 26.122448979591837 seconds
        expect(metadata.format.duration, isNotNull);
        expect(
          metadata.format.duration,
          closeTo((1000 * 1152) / 44100, 0.001),
        );
        // Bitrate: 400000 bytes * 8 / duration = ~122499 bps
        expect(metadata.format.bitrate, isNotNull);
        expect(
          metadata.format.bitrate,
          closeTo((400000 * 8) / metadata.format.duration!, 1.0),
        );
      });
    });

    group('MP4 xHE-AAC Codec Detection', () {
      test('identifies xHE-AAC (USAC Audio Object Type 42) in MP4 container', () async {
        final file = File('test/samples/mp4/usac-alac.m4a');
        expect(file.existsSync(), isTrue);

        final metadata = await parseFile(file.path);
        expect(metadata.format.container, contains('M4A'));
        expect(metadata.format.codec, equals('xHE-AAC'));
        expect(metadata.format.sampleRate, equals(44100));
        expect(metadata.format.numberOfChannels, equals(1));
        expect(metadata.format.lossless, isFalse);
      });
    });

    group('WebM Streamed Cluster Duration Recovery', () {
      test('recovers duration from cluster timestamps when duration is true', () async {
        final file = File('test/samples/matroska/no-duration.webm');
        expect(file.existsSync(), isTrue);

        final metadata = await parseFile(
          file.path,
          options: const ParseOptions(duration: true),
        );

        expect(metadata.format.container, equals('EBML/webm'));
        expect(metadata.format.codec, equals('OPUS'));
        expect(metadata.format.duration, isNotNull);
        // Recovered from the final simpleBlock timestamp (25439 ms)
        expect(metadata.format.duration!, closeTo(25.439, 0.05));
        expect(metadata.format.bitrate, isNotNull);
        expect(metadata.format.bitrate!, greaterThan(0));
      });

      test('leaves duration null when duration option is false', () async {
        final file = File('test/samples/matroska/no-duration.webm');
        expect(file.existsSync(), isTrue);

        final metadata = await parseFile(file.path);

        expect(metadata.format.container, equals('EBML/webm'));
        expect(metadata.format.codec, equals('OPUS'));
        expect(metadata.format.duration, isNull);
      });
    });

    group('MPEG Xing False Sync Protection', () {
      test('parses MPEG file with false sync inside Info frame without error', () async {
        final file = File('test/samples/mp3/ffmpeg-info-false-sync.mp3');
        expect(file.existsSync(), isTrue);

        final metadata = await parseFile(
          file.path,
          options: const ParseOptions(duration: true),
        );

        expect(metadata.format.container, equals('MPEG'));
        expect(metadata.format.codec, equals('MPEG 1 Layer 3'));
        expect(metadata.format.bitrate, equals(128000));
        expect(metadata.format.duration, isNotNull);
        expect(metadata.format.duration!, closeTo(1.044, 0.05));
      });
    });
  });

  group('Group B: ID3v2 Frames (SYLT & POPM)', () {
    group('Synchronized Lyrics (SYLT)', () {
      test('parses native SYLT frames from test sample', () async {
        final file = File('test/samples/mp3/menu-sash.mp3');
        expect(file.existsSync(), isTrue);

        final metadata = await parseFile(file.path);
        final lyrics = metadata.common.lyrics;
        expect(lyrics, isNotNull);
        expect(lyrics!.length, greaterThanOrEqualTo(3));

        // Find the captions SYLT frame
        final captions = lyrics.firstWhere(
          (l) => l.descriptor == 'captions',
        );
        expect(captions.contentType, equals('text_transcription'));
        expect(captions.timeStampFormat, equals('milliseconds'));
        expect(captions.language, equals('eng'));
        expect(captions.syncText.length, equals(1));
        expect(captions.syncText.first.text, equals('Check out your sash!'));
        expect(captions.syncText.first.timestamp, equals(9));

        // Find the lipsync SYLT frame
        final lipsync = lyrics.firstWhere(
          (l) => l.descriptor == 'lipsync',
        );
        expect(lipsync.contentType, equals('other'));
        expect(lipsync.timeStampFormat, equals('milliseconds'));
        expect(lipsync.language, equals('eng'));
        expect(lipsync.syncText.length, equals(8));
        expect(lipsync.syncText[0].text, equals('X'));
        expect(lipsync.syncText[0].timestamp, equals(0));
        expect(lipsync.syncText[1].text, equals('F'));
        expect(lipsync.syncText[1].timestamp, equals(110));
        expect(lipsync.syncText[7].text, equals('X'));
        expect(lipsync.syncText[7].timestamp, equals(1120));
      });

      test('parses synthetic SYLT frame with UTF-8 encoding and mpeg_frames timestamp format', () async {
        // Construct an ID3v2.4 tag with a SYLT frame
        final syltPayload = <int>[
          // Encoding: 3 (UTF-8)
          0x03,
          // Language: 'eng'
          0x65, 0x6E, 0x67,
          // Timestamp format: 1 (mpeg_frames)
          0x01,
          // Content type: 1 (lyrics)
          0x01,
          // Descriptor: 'karaoke\0'
          ...utf8.encode('karaoke'), 0x00,
          // Entry 1: 'Line one\0' + timestamp 1200
          ...utf8.encode('Line one'), 0x00,
          0x00, 0x00, 0x04, 0xB0,
          // Entry 2: 'Line two\0' + timestamp 2400
          ...utf8.encode('Line two'), 0x00,
          0x00, 0x00, 0x09, 0x60,
        ];

        final syltFrameSize = syltPayload.length;
        final id3v2Tag = <int>[
          // ID3 header
          0x49, 0x44, 0x33, // 'ID3'
          0x04, 0x00,       // version 2.4
          0x00,             // flags
          // Tag size (synchsafe uint32: 10 byte frame header + syltFrameSize)
          0x00, 0x00, 0x00, (10 + syltFrameSize) & 0x7F,
          // SYLT frame header
          0x53, 0x59, 0x4C, 0x54, // 'SYLT'
          // Frame size (synchsafe uint32 in v2.4)
          0x00, 0x00, 0x00, syltFrameSize & 0x7F,
          0x00, 0x00, // flags
          // Payload
          ...syltPayload,
        ];

        final metadata = await parseBytes(
          Uint8List.fromList(id3v2Tag),
          fileInfo: const FileInfo(mimeType: 'audio/mpeg'),
        );
        final lyrics = metadata.common.lyrics;
        expect(lyrics, isNotNull);
        expect(lyrics!.length, equals(1));

        final tag = lyrics.first;
        expect(tag.descriptor, equals('karaoke'));
        expect(tag.contentType, equals('lyrics'));
        expect(tag.timeStampFormat, equals('mpeg_frames'));
        expect(tag.language, equals('eng'));
        expect(tag.syncText.length, equals(2));
        expect(tag.syncText[0].text, equals('Line one'));
        expect(tag.syncText[0].timestamp, equals(1200));
        expect(tag.syncText[1].text, equals('Line two'));
        expect(tag.syncText[1].timestamp, equals(2400));
        expect(tag.text, equals('Line one\nLine two'));
      });
    });

    group('Popularimeter (POPM & Rating)', () {
      test('parses ratings from 1-star to 5-star sample files', () async {
        final expectedStars = <int, double>{
          1: 0.0,
          2: 63.0 / 254.0,
          3: 127.0 / 254.0,
          4: 195.0 / 254.0,
          5: 1.0,
        };

        for (var star = 1; star <= 5; star++) {
          final file = File('test/samples/rating/testcase-${star}star.mp3');
          expect(file.existsSync(), isTrue);

          final metadata = await parseFile(file.path);
          final ratings = metadata.common.rating;
          expect(ratings, isNotNull, reason: 'Rating missing for $star star');
          expect(ratings!.length, equals(1));

          final r = ratings.first;
          expect(r.source, equals('rating@winamp.com'));
          expect(r.rating, isNotNull);
          expect(
            r.rating!,
            closeTo(expectedStars[star]!, 0.01),
            reason: 'Normalized rating mismatch for $star star',
          );

          // Verify ratingToStars maps to the expected integer star count
          final computedStars = ratingToStars(r.rating);
          expect(
            computedStars,
            equals(star),
            reason: 'Star mapping mismatch for $star star',
          );
        }
      });

      test('parses synthetic POPM frame with play counter', () async {
        final popmPayload = <int>[
          // Email: 'player@music.com\0'
          ...latin1.encode('player@music.com'), 0x00,
          // Rating: 196 (4 stars)
          196,
          // Counter: 4 bytes big-endian (42 plays)
          0x00, 0x00, 0x00, 0x2A,
        ];

        final frameSize = popmPayload.length;
        final id3v2Tag = <int>[
          // ID3 header
          0x49, 0x44, 0x33, // 'ID3'
          0x03, 0x00,       // version 2.3
          0x00,             // flags
          0x00, 0x00, 0x00, (10 + frameSize) & 0x7F,
          // POPM frame header
          0x50, 0x4F, 0x50, 0x4D, // 'POPM'
          // Frame size (big-endian uint32 in v2.3)
          0x00, 0x00, 0x00, frameSize,
          0x00, 0x00, // flags
          ...popmPayload,
        ];

        final metadata = await parseBytes(
          Uint8List.fromList(id3v2Tag),
          fileInfo: const FileInfo(mimeType: 'audio/mpeg'),
        );
        final ratings = metadata.common.rating;
        expect(ratings, isNotNull);
        expect(ratings!.length, equals(1));
        expect(ratings.first.source, equals('player@music.com'));
        expect(ratingToStars(ratings.first.rating), equals(4));

        // Verify playCounter extracted
        expect(metadata.common.playCounter, equals(42));
      });
    });
  });
}
