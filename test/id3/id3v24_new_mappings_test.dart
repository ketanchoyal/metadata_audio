/// Tests for ID3v2.4 extended mappings with upstream-parity camelCase
/// common-tag ids: PCNT (playCounter), MVNM (movement), MVIN
/// (movementIndex), TGID/PCS (podcastId), TDES/TCAT/TKWD, WFED, TDRL and
/// PRIV:AverageLevel / PRIV:PeakValue (Windows Media Player levels).
library;

import 'dart:convert';

import 'package:metadata_audio/src/id3v2/id3v2_loader.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:test/test.dart';

import 'id3_test_utils.dart';

void main() {
  final encoder = Id3v2Loader();

  Future<AudioMetadata> parseTag(List<List<int>> frames) async {
    final tag = buildId3Tag(
      majorVersion: 4,
      revision: 0,
      flags: 0x00,
      payload: [...frames.expand((frame) => frame)],
    );
    return encoder.parse(
      MockTokenizer(data: tag, fileInfo: FileInfo.fromPath('playcounter.mp3')),
      const ParseOptions(),
    );
  }

  List<int> frameText(String text) => utf8.encode(text);

  group('ID3v2.4 extended common-tag mappings', () {
    test('parses PCNT into common.playCounter', () async {
      final tag = buildId3v24Frame('PCNT', [
        0x68,
        0x10,
        0x00,
        0x00, // little-endian 4200
      ]);
      final metadata = await parseTag([tag]);
      expect(metadata.common.playCounter, equals(4200));
    });

    test('parses MVNM into common.movement', () async {
      final tag = buildId3v24Frame('MVNM', [0x03, ...frameText('Overture')]);
      final metadata = await parseTag([tag]);
      expect(metadata.common.movement, equals('Overture'));
    });

    test('parses MVIN into common.movementIndex', () async {
      final tag = buildId3v24Frame('MVIN', [0x03, ...frameText('3')]);
      final metadata = await parseTag([tag]);
      expect(metadata.common.movementIndex.no, equals(3));
    });

    test('parses TGID and PCS into common.podcastId', () async {
      final tgid = buildId3v24Frame('TGID', [0x03, ...frameText('pod.2026')]);
      final metadata = await parseTag([tgid]);
      expect(metadata.common.podcastId, equals('pod.2026'));

      // PCS is an ID3v2.2 frame (3-character id).
      final tag = buildId3Tag(
        majorVersion: 2,
        revision: 0,
        flags: 0x00,
        payload: [
          ...buildId3v22Frame('PCS', [0x03, ...frameText('pod.2')]),
        ],
      );
      final metadata2 = await encoder.parse(
        MockTokenizer(data: tag, fileInfo: FileInfo.fromPath('podcast.mp3')),
        const ParseOptions(),
      );
      expect(metadata2.common.podcastId, equals('pod.2'));
    });

    test('parses TDES/TCAT/TKWD itunes list frames', () async {
      final payload = [
        buildId3v24Frame('TDES', [0x03, ...frameText('Episode notes')]),
        buildId3v24Frame('TCAT', [0x03, ...frameText('Technology')]),
        buildId3v24Frame('TKWD', [0x03, ...frameText('metadata dart')]),
      ];
      final metadata = await parseTag(payload);
      expect(metadata.common.description ?? [], contains('Episode notes'));
      expect(metadata.common.category ?? [], contains('Technology'));
      expect(metadata.common.keywords ?? [], contains('metadata dart'));
    });

    test('parses WFED podcaster URL and TDRL release date', () async {
      final payload = [
        buildId3v24Frame('WFED', frameText('https://example.com/feed')),
        buildId3v24Frame('TDRL', [0x03, ...frameText('2026-01-02')]),
      ];
      final metadata = await parseTag(payload);
      expect(metadata.common.podcasturl, equals('https://example.com/feed'));
      expect(metadata.common.releasedate, equals('2026-01-02'));
    });

    test('parses PRIV:AverageLevel and PRIV:PeakValue levels', () async {
      final average = buildId3v24Frame('PRIV', [
        ...ascii.encode('AverageLevel'),
        0x00,
        0x0f,
        0x00,
        0x00,
        0x00, // little-endian 15
      ]);
      final peak = buildId3v24Frame('PRIV', [
        ...ascii.encode('PeakValue'),
        0x00,
        0xa5,
        0x05,
        0x00,
        0x00, // little-endian 1445
      ]);
      final metadata = await parseTag([average, peak]);
      expect(metadata.common.averageLevel, equals(15));
      expect(metadata.common.peakLevel, equals(1445));
    });

    test('ignores PRIV frames with unknown owner', () async {
      final unknown = buildId3v24Frame('PRIV', [
        ...ascii.encode('SomethingElse'),
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
      ]);
      final metadata = await parseTag([unknown]);
      expect(metadata.common.averageLevel, isNull);
      expect(metadata.common.peakLevel, isNull);
    });
  });

  group('mapTags casing parity', () {
    test('unknown owner PRIV data shorter than 4 bytes is ignored', () async {
      final short = buildId3v24Frame('PRIV', [
        ...ascii.encode('AverageLevel'),
        0x00,
        0x01, // invalid length — should be dropped, not crash
      ]);
      final metadata = await parseTag([short]);
      expect(metadata.common.averageLevel, isNull);
    });
  });
}
