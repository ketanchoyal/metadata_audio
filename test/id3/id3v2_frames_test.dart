import 'dart:convert';

import 'package:audio_metadata/src/id3v2/frame_header.dart';
import 'package:audio_metadata/src/id3v2/frame_parser.dart';
import 'package:audio_metadata/src/id3v2/id3v2_token.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:test/test.dart';

void main() {
  group('FrameHeader', () {
    test('parses ID3v2.2 frame header', () {
      final header = FrameHeader.parse([0x54, 0x54, 0x32, 0x00, 0x01, 0x02], 2);

      expect(header.id, equals('TT2'));
      expect(header.length, equals(258));
      expect(header.flags, isNull);
    });

    test('parses ID3v2.3 frame header with flags', () {
      final header = FrameHeader.parse([
        0x54,
        0x49,
        0x54,
        0x32,
        0x00,
        0x00,
        0x00,
        0x10,
        0x40,
        0x81,
      ], 3);

      expect(header.id, equals('TIT2'));
      expect(header.length, equals(16));
      expect(header.flags, isNotNull);
      expect(header.flags!.status.tagAlterPreservation, isTrue);
      expect(header.flags!.status.fileAlterPreservation, isFalse);
      expect(header.flags!.status.readOnly, isFalse);
      expect(header.flags!.format.groupingIdentity, isTrue);
      expect(header.flags!.format.dataLengthIndicator, isTrue);
    });

    test('parses ID3v2.4 frame header with synchsafe length', () {
      final header = FrameHeader.parse([
        0x54,
        0x50,
        0x45,
        0x31,
        0x00,
        0x00,
        0x02,
        0x00,
        0x00,
        0x00,
      ], 4);

      expect(header.id, equals('TPE1'));
      expect(header.length, equals(256));
    });

    test('reports warning on invalid frame id', () {
      final warnings = <String>[];

      FrameHeader.parse(
        [0x20, 0x20, 0x20, 0x00, 0x00, 0x00],
        2,
        warningCollector: warnings.add,
      );

      expect(warnings, isNotEmpty);
      expect(warnings.first, contains('Invalid ID3v2.2 frame header ID'));
    });
  });

  group('ID3v2Token', () {
    test('parses ID3v2 header with synchsafe size', () {
      final header = ID3v2Token.parseHeader([
        0x49,
        0x44,
        0x33,
        0x04,
        0x00,
        0x90,
        0x00,
        0x00,
        0x02,
        0x00,
      ]);

      expect(header.fileIdentifier, equals('ID3'));
      expect(header.version.major, equals(4));
      expect(header.version.revision, equals(0));
      expect(header.flags.unsynchronisation, isTrue);
      expect(header.flags.isExtendedHeader, isFalse);
      expect(header.flags.expIndicator, isFalse);
      expect(header.flags.footer, isTrue);
      expect(header.size, equals(256));
    });

    test('maps text encoding byte', () {
      expect(ID3v2Token.textEncodingFromByte(0x00).encoding, equals('latin1'));
      expect(ID3v2Token.textEncodingFromByte(0x01).encoding, equals('utf16'));
      expect(ID3v2Token.textEncodingFromByte(0x03).encoding, equals('utf8'));
    });
  });

  group('FrameParser', () {
    test('parses common text frame (TIT2)', () {
      const parser = FrameParser(3);
      final payload = <int>[0x00, ...latin1.encode('Song Title')];

      final value = parser.readData(payload, 'TIT2');

      expect(value, equals('Song Title'));
    });

    test('parses multi-value text frame (TPE1) in ID3v2.3', () {
      const parser = FrameParser(3);
      final payload = <int>[0x00, ...latin1.encode('Artist 1/Artist 2')];

      final value = parser.readData(payload, 'TPE1') as List<String>;

      expect(value, equals(['Artist 1', 'Artist 2']));
    });

    test('parses user text frame (TXXX)', () {
      const parser = FrameParser(4);
      final payload = <int>[
        0x03,
        ...utf8.encode('SOURCE'),
        0x00,
        ...utf8.encode('Bandcamp'),
      ];

      final value = parser.readData(payload, 'TXXX') as Map<String, dynamic>;

      expect(value['description'], equals('SOURCE'));
      expect(value['text'], equals(['Bandcamp']));
    });

    test('parses comment frame (COMM) with UTF-16 text', () {
      const parser = FrameParser(3);
      final descriptor = _utf16LeWithBom('desc');
      final text = _utf16LeWithBom('Hello comment');

      final payload = <int>[
        0x01,
        ...ascii.encode('eng'),
        ...descriptor,
        0x00,
        0x00,
        ...text,
      ];

      final value = parser.readData(payload, 'COMM') as Comment;

      expect(value.language, equals('eng'));
      expect(value.descriptor, equals('desc'));
      expect(value.text, equals('Hello comment'));
    });

    test('parses APIC attached picture frame', () {
      const parser = FrameParser(3);
      final payload = <int>[
        0x00,
        ...ascii.encode('image/jpeg'),
        0x00,
        0x03,
        ...latin1.encode('front'),
        0x00,
        0x11,
        0x22,
        0x33,
      ];

      final value = parser.readData(payload, 'APIC') as Picture;

      expect(value.format, equals('image/jpeg'));
      expect(value.type, equals('Cover (front)'));
      expect(value.description, equals('front'));
      expect(value.data, equals([0x11, 0x22, 0x33]));
    });

    test('parses ID3v2.2 PIC frame', () {
      const parser = FrameParser(2);
      final payload = <int>[
        0x00,
        ...ascii.encode('JPG'),
        0x03,
        ...latin1.encode('cover'),
        0x00,
        0xAA,
        0xBB,
      ];

      final value = parser.readData(payload, 'PIC') as Picture;

      expect(value.format, equals('image/jpeg'));
      expect(value.type, equals('Cover (front)'));
      expect(value.description, equals('cover'));
      expect(value.data, equals([0xAA, 0xBB]));
    });
  });
}

List<int> _utf16LeWithBom(String value) {
  final codeUnits = value.codeUnits;
  final bytes = <int>[0xFF, 0xFE];
  for (final unit in codeUnits) {
    bytes.add(unit & 0xFF);
    bytes.add((unit >> 8) & 0xFF);
  }
  return bytes;
}
