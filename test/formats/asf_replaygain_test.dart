/// Tests for ASF ReplayGain and track-total attribute mapping
/// (upstream parity, music-metadata v12.3.0 #2863).
///
/// `REPLAYGAIN_TRACK_GAIN` / `REPLAYGAIN_TRACK_PEAK` /
/// `REPLAYGAIN_ALBUM_GAIN` / `REPLAYGAIN_ALBUM_PEAK` (both upper and lower
/// case) map onto the common `replaygain_*` tags, `TotalTracks` maps onto
/// `totaltracks`, and invalid ReplayGain values keep the tag native while
/// emitting the upstream `Invalid ASF ReplayGain value for <id>` warning.
library;

import 'dart:typed_data';

import 'package:metadata_audio/src/asf/asf_guid.dart';
import 'package:metadata_audio/src/asf/asf_loader.dart';
import 'package:metadata_audio/src/asf/asf_util.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:test/test.dart';

void main() {
  group('ASF ReplayGain and track totals', () {
    test(
      'maps REPLAYGAIN_* attributes and TotalTracks to common tags',
      () async {
        final bytes = _buildAsf(<_ExtAttr>[
          _ExtAttr(
            'REPLAYGAIN_TRACK_GAIN',
            AsfDataType.unicodeString,
            _utf16('-7.54 dB'),
          ),
          _ExtAttr(
            'REPLAYGAIN_TRACK_PEAK',
            AsfDataType.unicodeString,
            _utf16('0.912'),
          ),
          _ExtAttr(
            'REPLAYGAIN_ALBUM_GAIN',
            AsfDataType.unicodeString,
            _utf16('-8.01 dB'),
          ),
          _ExtAttr(
            'replaygain_album_peak',
            AsfDataType.unicodeString,
            _utf16('0.988'),
          ),
          _ExtAttr('TotalTracks', AsfDataType.unicodeString, _utf16('12')),
        ]);

        final metadata = await AsfLoader().parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(),
        );

        expect(metadata.common.replaygain_track_gain, isNotNull);
        expect(
          metadata.common.replaygain_track_gain!.ratio,
          closeTo(0.41976, 1e-4),
        );
        expect(metadata.common.replaygain_track_gain!.dB, closeTo(-7.54, 1e-9));
        expect(
          metadata.common.replaygain_track_peak!.ratio,
          closeTo(0.912, 1e-9),
        );
        expect(metadata.common.replaygain_track_peak!.dB, isNull);
        expect(metadata.common.replaygain_album_gain!.dB, closeTo(-8.01, 1e-9));
        expect(
          metadata.common.replaygain_album_peak!.ratio,
          closeTo(0.988, 1e-9),
        );
        expect(metadata.common.track.of, 12);
        expect(metadata.common.totaltracks, '12');
      },
    );

    test('keeps invalid ReplayGain values native with a warning', () async {
      final bytes = _buildAsf(<_ExtAttr>[
        _ExtAttr(
          'REPLAYGAIN_TRACK_GAIN',
          AsfDataType.unicodeString,
          _utf16('loud'), // invalid numeric value
        ),
        _ExtAttr(
          'REPLAYGAIN_TRACK_PEAK',
          AsfDataType.unicodeString,
          _utf16('-7.54 dB'), // valid, must remain mapped
        ),
      ]);

      final metadata = await AsfLoader().parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(
        metadata.quality.warnings.map((warning) => warning.message),
        contains('Invalid ASF ReplayGain value for REPLAYGAIN_TRACK_GAIN'),
      );
      expect(metadata.common.replaygain_track_gain, isNull);
      expect(metadata.common.replaygain_track_peak, isNotNull);

      // The invalid attribute stays native.
      final native = metadata.native['asf']!;
      final nativeGain = native
          .where((tag) => tag.id == 'REPLAYGAIN_TRACK_GAIN')
          .map((tag) => tag.value)
          .toList();
      expect(nativeGain, isNotEmpty);
    });

    test('normalizes whitespace and mixed-case dB suffix', () async {
      final bytes = _buildAsf(<_ExtAttr>[
        _ExtAttr(
          'replaygain_track_gain',
          AsfDataType.unicodeString,
          _utf16('  +6.5db'),
        ),
      ]);

      final metadata = await AsfLoader().parse(
        BytesTokenizer(
          Uint8List.fromList(bytes),
          fileInfo: FileInfo(size: bytes.length),
        ),
        const ParseOptions(),
      );

      expect(metadata.common.replaygain_track_gain, isNotNull);
      expect(metadata.common.replaygain_track_gain!.dB, closeTo(6.5, 1e-9));
      expect(
        metadata.common.replaygain_track_gain!.ratio,
        closeTo(2.1135, 1e-4),
      );
    });
  });
}

class _ExtAttr {
  const _ExtAttr(this.name, this.valueType, this.value);

  final String name;
  final int valueType;
  final List<int> value;
}

/// Builds a minimal synthetic ASF file (header with file properties, stream
/// properties, codec list, and an extended content description object).
List<int> _buildAsf(List<_ExtAttr> attrs) {
  final fileProperties = _asfObject(
    AsfGuid.filePropertiesObject,
    _filePropertiesBody(playDuration100ns: 25000000, prerollMs: 500),
  );
  final streamProperties = _asfObject(
    AsfGuid.streamPropertiesObject,
    _streamPropertiesBody(),
  );
  final codecList = _asfObject(AsfGuid.codecListObject, _codecListBody());
  final extContentDescription = _asfObject(
    AsfGuid.extendedContentDescriptionObject,
    _extendedContentDescriptionBody(attrs),
  );
  final headerExtension = _asfObject(
    AsfGuid.headerExtensionObject,
    _headerExtensionBody(<int>[]),
  );

  final objects = <List<int>>[
    fileProperties,
    streamProperties,
    codecList,
    extContentDescription,
    headerExtension,
  ];

  final payload = <int>[for (final obj in objects) ...obj];
  final topSize = 30 + payload.length;

  return <int>[
    ...AsfGuid.headerObject.toBytes(),
    ..._u64le(topSize),
    ..._u32le(objects.length),
    0x01,
    0x02,
    ...payload,
  ];
}

List<int> _asfObject(AsfGuid guid, List<int> payload) => <int>[
  ...guid.toBytes(),
  ..._u64le(payload.length + 24),
  ...payload,
];

List<int> _filePropertiesBody({
  required int playDuration100ns,
  required int prerollMs,
}) => <int>[
  ...List<int>.filled(16, 0),
  ..._u64le(0),
  ..._u64le(0),
  ..._u64le(0),
  ..._u64le(playDuration100ns),
  ..._u64le(0),
  ..._u64le(prerollMs),
  ..._u32le(0),
  ..._u32le(0),
  ..._u32le(0),
  ..._u32le(192639),
];

List<int> _streamPropertiesBody() => <int>[
  ...AsfGuid.audioMedia.toBytes(),
  // Audio Spread error-correction GUID (75B22636-668E-11CF-A6D9-00AA0062CE6C)
  ...const AsfGuid('75B22636-668E-11CF-A6D9-00AA0062CE6C').toBytes(),
  ...List<int>.filled(8, 0), // time offset
  ..._u32le(16), // type-specific size
  ..._u32le(0), // correction size
  ..._u16le(1), // flags: stream number 1
  ...List<int>.filled(4, 0), // reserved
  ..._u16le(0x0161), // format tag: Windows Media Audio 9.1
  ..._u16le(2), // channels
  ..._u32le(44100), // samples/sec
  ..._u32le(24080), // avg bytes/sec
  ..._u16le(2000), // block align
  ..._u16le(16), // bits per sample
  ..._u16le(10), // codec-specific data size
  ...List<int>.filled(10, 0),
];

List<int> _codecListBody() {
  final codecName = _utf16('Windows Media Audio 9.1');
  final description = _utf16('Audio codec');

  return <int>[
    ...List<int>.filled(16, 0),
    ..._u16le(1),
    ..._u16le(0),
    ..._u16le(0x0002),
    ..._u16le(codecName.length ~/ 2),
    ...codecName,
    ..._u16le(description.length ~/ 2),
    ...description,
    ..._u16le(0),
  ];
}

List<int> _extendedContentDescriptionBody(List<_ExtAttr> attrs) => <int>[
  ..._u16le(attrs.length),
  for (final attr in attrs) ...[
    ..._u16le(_utf16(attr.name).length),
    ..._utf16(attr.name),
    ..._u16le(attr.valueType),
    ..._u16le(attr.value.length),
    ...attr.value,
  ],
];

List<int> _headerExtensionBody(List<int> extensionObjects) => <int>[
  ...AsfGuid.headerObject.toBytes(),
  ..._u16le(6),
  ..._u32le(extensionObjects.length),
  ...extensionObjects,
];

List<int> _u16le(int value) => <int>[value & 0xFF, (value >> 8) & 0xFF];

List<int> _u32le(int value) => <int>[
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

List<int> _u64le(int value) => <int>[
  for (var i = 0; i < 8; i++) (value >> (8 * i)) & 0xFF,
];

List<int> _utf16(String value) => utf16Bytes(value);

/// Encodes as UTF-16LE including the null terminator, matching the ASF
/// attribute layout used by `_extendedContentDescriptionBody`.
List<int> utf16Bytes(String value) {
  final units = <int>[];
  for (final codeUnit in value.codeUnits) {
    units.add(codeUnit & 0xFF);
    units.add((codeUnit >> 8) & 0xFF);
  }
  return units;
}
