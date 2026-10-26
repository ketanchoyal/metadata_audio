/// Tests for ID3v2 involved-person credits (TMCL / TIPL / IPL / IPLS),
/// unsynchronized lyrics (USLT / ULT) and PRIV owner warning alignment
/// (upstream parity, music-metadata v12.3.0 #2860, #2862, #2859).
library;

import 'dart:convert';

import 'package:metadata_audio/src/id3v2/id3v2_loader.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:test/test.dart';

import 'id3_test_utils.dart';

void main() {
  final encoder = Id3v2Loader();

  Future<AudioMetadata> parseTag(
    int majorVersion,
    List<List<int>> frames,
  ) async {
    final tag = buildId3Tag(
      majorVersion: majorVersion,
      revision: 0,
      flags: 0x00,
      payload: [...frames.expand((frame) => frame)],
    );
    return encoder.parse(
      MockTokenizer(data: tag, fileInfo: FileInfo.fromPath('credits.mp3')),
      const ParseOptions(),
    );
  }

  group('ID3v2 involved-person credits', () {
    test('expands v2.4 TIPL role pairs into common roles', () async {
      final tipl = buildId3v24Frame('TIPL', [
        0x03, // UTF-8
        ...utf8.encode('arranger'),
        0x00,
        ...utf8.encode('Toshiko Yonekawa'),
        0x00,
        ...utf8.encode('engineer'),
        0x00,
        ...utf8.encode('Ted Jensen'),
        0x00,
        ...utf8.encode('producer'),
        0x00,
        ...utf8.encode('John'),
        0x00,
        ...utf8.encode('DJ-mix'),
        0x00,
        ...utf8.encode('DJ Spacer'),
        0x00,
        ...utf8.encode('mix'),
        0x00,
        ...utf8.encode('Rick Rubin'),
        0x00,
      ]);
      final metadata = await parseTag(4, [tipl]);
      expect(metadata.common.arranger, equals(['Toshiko Yonekawa']));
      expect(metadata.common.engineer, equals(['Ted Jensen']));
      expect(metadata.common.producer, equals(['John']));
      expect(metadata.common.djmixer, equals(['DJ Spacer']));
      expect(metadata.common.mixer, equals(['Rick Rubin']));
    });

    test(
      'supports the legacy v2.3 slash-separated IPLS without null separator',
      () async {
        final ipls = buildId3v24Frame('IPLS', [
          0x00,
          ...latin1.encode('arranger/John Smith'),
        ]);
        final metadata = await parseTag(3, [ipls]);
        expect(metadata.common.arranger, equals(['John Smith']));
      },
    );

    test('suppresses the null-separator warning for IPLS role pairs', () async {
      final ipls = buildId3v24Frame('IPLS', [
        0x00, // latin1
        ...latin1.encode('arranger'),
        0x00,
        ...latin1.encode('Sakura'),
        0x00,
      ]);
      final metadata = await parseTag(3, [ipls]);
      expect(metadata.common.arranger, equals(['Sakura']));
      expect(
        metadata.quality.warnings.map((warning) => warning.message),
        isNot(contains(containsMatcher('null'))),
      );
    });

    test('expands v2.2 IPL role pairs into common roles', () async {
      // v2.2 frames are latin1 encoded (0x00 encoding byte).
      final ipl = buildId3v22Frame('IPL', [
        0x00,
        ...latin1.encode('producer'),
        0x00,
        ...latin1.encode('George Martin'),
        0x00,
        ...latin1.encode('engineer'),
        0x00,
        ...latin1.encode('Norman Smith'),
        0x00,
      ]);
      final metadata = await parseTag(2, [ipl]);
      expect(metadata.common.producer, equals(['George Martin']));
      expect(metadata.common.engineer, equals(['Norman Smith']));
    });

    test('keeps TMCL musician credits native without common mapping', () async {
      final tmcl = buildId3v24Frame('TMCL', [
        0x03, // UTF-8
        ...utf8.encode('guitar'),
        0x00,
        ...utf8.encode('Slash'),
        0x00,
      ]);
      final metadata = await parseTag(4, [tmcl]);
      expect(metadata.common.arranger, isNull);
      // Overall credits are not mapped to common tags.
      expect(metadata.common.producer, isNull);
      final native = metadata.native['ID3v2.4']!;
      expect(native.where((tag) => tag.id == 'TMCL'), isNotEmpty);
    });

    test('aggregates multiple people under the same role', () async {
      final tipl = buildId3v24Frame('TIPL', [
        0x03, // UTF-8
        ...utf8.encode('producer'),
        0x00,
        ...utf8.encode('George Martin'),
        0x00,
        ...utf8.encode('producer'),
        0x00,
        ...utf8.encode('Phil Spector'),
        0x00,
      ]);
      final metadata = await parseTag(4, [tipl]);
      expect(
        metadata.common.producer,
        equals(['George Martin', 'Phil Spector']),
      );
    });
  });

  group('ID3v2 unsynchronized lyrics', () {
    test('maps v2.4 USLT to common lyrics', () async {
      final uslt = buildId3v24Frame('USLT', [
        0x03, // UTF-8
        ...ascii.encode('eng'),
        ...utf8.encode(''),
        0x00,
        ...utf8.encode('[00:12.00]Line one'),
        0x00,
      ]);
      final metadata = await parseTag(4, [uslt]);
      expect(metadata.common.lyrics, hasLength(1));
      expect(metadata.common.lyrics!.single.text, '[00:12.00]Line one');
      expect(metadata.common.lyrics!.single.language, 'eng');
    });

    test('maps v2.2 ULT to common lyrics', () async {
      final ult = buildId3v22Frame('ULT', [
        0x00, // latin1
        ...ascii.encode('ger'),
        ...latin1.encode('Album'),
        0x00,
        ...latin1.encode('Text der Zeile'),
        0x00,
      ]);
      final metadata = await parseTag(2, [ult]);
      expect(metadata.common.lyrics, hasLength(1));
      expect(metadata.common.lyrics!.single.text, 'Text der Zeile');
      expect(metadata.common.lyrics!.single.descriptor, 'Album');
      expect(metadata.common.lyrics!.single.language, 'ger');
    });
  });

  group('ID3v2 PRIV owner warnings (upstream #2859)', () {
    test('warns and keeps native data for unknown owners', () async {
      final priv = buildId3v24Frame('PRIV', [
        ...ascii.encode('SomethingElse'),
        0x00,
        0x01,
        0x02,
        0x03,
        0x04,
      ]);
      final metadata = await parseTag(4, [priv]);
      expect(
        metadata.quality.warnings.map((warning) => warning.message),
        contains('Unknown PRIV owner-identifier: SomethingElse'),
      );
      final native = metadata.native['ID3v2.4']!;
      expect(
        native.firstWhere((tag) => tag.id == 'PRIV:SomethingElse').value,
        equals(<int>[1, 2, 3, 4]),
      );
    });

    test('caps echoed owner identifiers at 128 characters', () async {
      final longOwner = 'A' * 200;
      final priv = buildId3v24Frame('PRIV', [
        ...ascii.encode(longOwner),
        0x00,
        0x01,
        0x02,
        0x03,
        0x04,
      ]);
      final metadata = await parseTag(4, [priv]);
      expect(
        metadata.quality.warnings.map((warning) => warning.message),
        contains('Unknown PRIV owner-identifier: ${'A' * 128}'),
      );
      // The native key keeps the full owner.
      expect(
        metadata.native['ID3v2.4']!.any((tag) => tag.id == 'PRIV:$longOwner'),
        isTrue,
      );
    });

    test(
      "warns with the owner id when a known owner's level is truncated",
      () async {
        final priv = buildId3v24Frame('PRIV', [
          ...ascii.encode('AverageLevel'),
          0x00,
          0x01, // only 1 data byte, must be 4
        ]);
        final metadata = await parseTag(4, [priv]);
        expect(
          metadata.quality.warnings.map((warning) => warning.message),
          contains('Failed to parse PRIV:AverageLevel'),
        );
      },
    );

    test('still maps PRIV:PeakValue to common peakLevel', () async {
      final priv = buildId3v24Frame('PRIV', [
        ...ascii.encode('PeakValue'),
        0x00,
        0xa5,
        0x05,
        0x00,
        0x00, // little-endian 1445
      ]);
      final metadata = await parseTag(4, [priv]);
      expect(metadata.common.peakLevel, equals(1445));
    });
  });
}

/// A matcher that matches strings containing [needle].
Matcher containsMatcher(String needle) => predicate<String>(
  (value) => value.contains(needle),
  'a string containing "$needle"',
);
