/// Integration tests for RIFF LIST/INFO tag character encoding.
///
/// Matches upstream music-metadata behaviour:
/// - Default decoding is ISO 8859-1 (Latin-1), not ASCII/Windows-1252.
/// - A `CSET` chunk overrides the encoding for the whole file, including
///   INFO chunks that precede it (they are queued until the code page is
///   known).
/// - Supported encodings: 28591/0/absent → latin1, 1252 → windows-1252,
///   65001 → utf-8; any other code page is omitted with a warning.
/// - Values truncate at the first NUL.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

void main() {
  group('WAV LIST/INFO character encoding', () {
    test('latin1 is the default when no CSET chunk is present', () async {
      final wav = _buildWav(
        infoEntries: [('INAM', [0x4D, 0xF6, 0x74, 0x6C, 0x65, 0x79])],
      );

      final metadata = await parseBytes(wav);
      expect(metadata.common.title, equals('Mötley'));
    });

    test('value truncates at the first NUL', () async {
      final wav = _buildWav(
        infoEntries: [
          (
            'INAM',
            <int>[0x4D, 0xF6, 0x74, 0x6C, 0x65, 0x79, 0x00, 0x61, 0x6C],
          ),
        ],
      );

      final metadata = await parseBytes(wav);
      expect(metadata.common.title, equals('Mötley'));
    });

    test('UTF-8 via CSET code page 65001 after INFO', () async {
      // UTF-8 bytes of '音楽 – Mötley'
      final titleBytes = utf8.encode('音楽 – Mötley');
      final wav = _buildWav(
        infoEntries: [('INAM', titleBytes)],
        csetCodePage: 65001,
        csetFirst: true,
      );

      final metadata = await parseBytes(wav);
      expect(metadata.common.title, equals('音楽 – Mötley'));
    });

    test('windows-1252 via CSET code page 1252', () async {
      // '“Mötley” – 10 €' in Windows-1252: 0x93 0x94 0x96 0x80 high bytes.
      final wav = _buildWav(
        infoEntries: [
          (
            'INAM',
            <int>[
              0x93, 0x4D, 0xF6, 0x74, 0x6C, 0x65, 0x79, 0x94, // “Mötley”
              0x20, 0x96, 0x20, // “ – ”
              0x31, 0x30, 0x20, 0x80, // 10 €
            ],
          ),
        ],
        csetCodePage: 1252,
        csetFirst: true,
      );

      final metadata = await parseBytes(wav);
      expect(metadata.common.title, equals('“Mötley” – 10 €'));
    });

    test('unsupported CSET code page omits INFO tags with a warning', () async {
      final wav = _buildWav(
        infoEntries: [('INAM', [0x4D, 0xF6, 0x74, 0x6C, 0x65, 0x79])],
        csetCodePage: 1251,
        csetFirst: true,
      );

      final metadata = await parseBytes(wav);
      expect(metadata.common.title, isNull);
      expect(
        metadata.quality.warnings.any(
          (w) => w.message.contains('Unsupported RIFF CSET code page: 1251'),
        ),
        isTrue,
        reason: 'Expected an unsupported-code-page warning',
      );
    });

    test('explicit latin1 CSET code page 28591 keeps latin1', () async {
      final wav = _buildWav(
        infoEntries: [('INAM', [0x4D, 0xF6, 0x74, 0x6C, 0x65, 0x79])],
        csetCodePage: 28591,
        csetFirst: true,
      );

      final metadata = await parseBytes(wav);
      expect(metadata.common.title, equals('Mötley'));
    });

    test('INFO before CSET is decoded with the CSET encoding', () async {
      // Queued INFO value decodes with the CSET encoding once the code page
      // is known (upstream cest_utf8-after-info behaviour): send UTF-8 bytes
      // before the CSET chunk declares code page 65001.
      final wav = _buildWav(
        infoEntries: [('INAM', utf8.encode('Mötley'))],
        csetCodePage: 65001,
        csetFirst: false,
      );

      final metadata = await parseBytes(wav);
      expect(metadata.common.title, equals('Mötley'));
    });
  });
}

/// Builds a minimal PCM WAV byte stream with an optional CSET chunk and
/// LIST/INFO tags.
///
/// [infoEntries]: (fourCC, raw value bytes) pairs.
Uint8List _buildWav({
  required List<(String, List<int>)> infoEntries,
  int? csetCodePage,
  bool csetFirst = false,
}) {
  final fmt = <int>[
    ..._ascii('fmt '),
    ..._u32le(16),
    ..._u16le(1), // PCM
    ..._u16le(1), // mono
    ..._u32le(44100), // sample rate
    ..._u32le(44100), // byte rate
    ..._u16le(1), // block align
    ..._u16le(8), // bits per sample
  ];
  final data = <int>[
    ..._ascii('data'),
    ..._u32le(2),
    0x00,
    0x00,
  ];

  final infoSubChunks = <int>[];
  for (final (id, valueBytes) in infoEntries) {
    infoSubChunks.addAll(_ascii(id));
    infoSubChunks.addAll(_u32le(valueBytes.length));
    infoSubChunks.addAll(valueBytes);
    if (valueBytes.length.isOdd) {
      infoSubChunks.add(0x00);
    }
  }
  final infoChunk = <int>[
    ..._ascii('LIST'),
    ..._u32le(4 + infoSubChunks.length),
    ..._ascii('INFO'),
    ...infoSubChunks,
  ];

  final csetChunk = csetCodePage == null
      ? <int>[]
      : <int>[
          ..._ascii('CSET'),
          ..._u32le(8),
          ..._u16le(csetCodePage), // code page ((UINT16_LE) at offset 0)
          ..._u16le(0), // country code
          ..._u16le(0), // language
          ..._u16le(0), // dialect
        ];

  final chunks = <int>[];
  if (csetCodePage != null && csetFirst) {
    chunks.addAll(csetChunk);
  }
  chunks.addAll(fmt);
  if (csetCodePage != null && !csetFirst) {
    chunks.addAll(csetChunk);
  }
  chunks.addAll(infoChunk);
  chunks.addAll(data);

  return Uint8List.fromList(<int>[
    ..._ascii('RIFF'),
    ..._u32le(4 + chunks.length),
    ..._ascii('WAVE'),
    ...chunks,
  ]);
}

List<int> _ascii(String value) => value.codeUnits;

List<int> _u16le(int value) => <int>[value & 0xFF, (value >> 8) & 0xFF];

List<int> _u32le(int value) => <int>[
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];
