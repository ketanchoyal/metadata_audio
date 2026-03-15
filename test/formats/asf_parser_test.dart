import 'dart:typed_data';

import 'package:audio_metadata/src/asf/asf_guid.dart';
import 'package:audio_metadata/src/asf/asf_loader.dart';
import 'package:audio_metadata/src/asf/asf_object.dart';
import 'package:audio_metadata/src/asf/asf_util.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/tokenizer/io_tokenizers.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  group('AsfParser / AsfLoader', () {
    test(
      'guid encode/decode and QWORD parser match ASF little-endian format',
      () {
        final headerGuidBytes = <int>[
          0x30,
          0x26,
          0xB2,
          0x75,
          0x8E,
          0x66,
          0xCF,
          0x11,
          0xA6,
          0xD9,
          0x00,
          0xAA,
          0x00,
          0x62,
          0xCE,
          0x6C,
        ];

        expect(AsfGuid.headerObject.toBytes(), equals(headerGuidBytes));
        expect(
          AsfGuid.fromBytes(headerGuidBytes).str,
          AsfGuid.headerObject.str,
        );

        final qWordValue = parseQWordAttr(<int>[
          0xFF,
          0xFF,
          0xFF,
          0xFF,
          0,
          0,
          0,
          0,
        ]);
        expect(qWordValue, BigInt.from(0xFFFFFFFF));
      },
    );

    test(
      'parses ASF header objects, extension metadata, tags, codec, and picture',
      () async {
        final bytes = _buildSyntheticAsf();

        final metadata = await AsfLoader().parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(),
        );

        expect(metadata.format.container, 'ASF/audio');
        expect(metadata.format.codec, 'Windows Media Audio 9.1');
        expect(metadata.format.duration, closeTo(2.0, 0.00001));
        expect(metadata.format.bitrate, 192639);
        expect(metadata.format.hasAudio, isTrue);
        expect(metadata.format.hasVideo, isFalse);

        expect(metadata.common.title, "Don't Bring Me Down");
        expect(metadata.common.artist, 'Electric Light Orchestra');
        expect(metadata.common.albumartist, 'Electric Light Orchestra');
        expect(metadata.common.album, 'Discovery');
        expect(metadata.common.date, '2001');
        expect(metadata.common.track.no, 9);
        expect(metadata.common.genre, equals(<String>['Rock']));

        expect(metadata.common.picture, isNotNull);
        expect(metadata.common.picture, hasLength(1));
        expect(metadata.common.picture!.single.format, 'image/jpeg');
        expect(metadata.common.picture!.single.type, 'Cover (front)');
        expect(
          metadata.common.picture!.single.data,
          equals(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]),
        );

        final native = metadata.native['asf'];
        expect(native, isNotNull);
        expect(
          native!.where((tag) => tag.id == 'WM/AlbumTitle').single.value,
          'Discovery',
        );
      },
    );

    test(
      'throws AsfContentParseError on invalid top-level object GUID',
      () async {
        final invalid = Uint8List.fromList(List<int>.filled(64, 0));

        await expectLater(
          AsfLoader().parse(BytesTokenizer(invalid), const ParseOptions()),
          throwsA(isA<AsfContentParseError>()),
        );
      },
    );

    test('loader declares extension and MIME types', () {
      final loader = AsfLoader();

      expect(loader.extension, equals(<String>['asf', 'wma', 'wmv']));
      expect(
        loader.mimeType,
        containsAll(<String>[
          'audio/x-ms-wma',
          'audio/x-ms-asf',
          'video/x-ms-asf',
          'application/vnd.ms-asf',
        ]),
      );
      expect(loader.hasRandomAccessRequirements, isFalse);
      expect(loader.supports(_NonSeekTokenizer()), isTrue);
    });
  });
}

List<int> _buildSyntheticAsf() {
  final fileProperties = _asfObject(
    AsfGuid.filePropertiesObject,
    _filePropertiesBody(playDuration100ns: 25000000, prerollMs: 500),
  );

  final streamProperties = _asfObject(
    AsfGuid.streamPropertiesObject,
    _streamPropertiesBody(),
  );

  final codecList = _asfObject(AsfGuid.codecListObject, _codecListBody());

  final contentDescription = _asfObject(
    AsfGuid.contentDescriptionObject,
    _contentDescriptionBody(
      title: "Don't Bring Me Down",
      author: 'Electric Light Orchestra',
      copyright: '(C) 2001',
      description: 'Synthetic ASF fixture',
      rating: '',
    ),
  );

  final extContentDescription = _asfObject(
    AsfGuid.extendedContentDescriptionObject,
    _extendedContentDescriptionBody(<_ExtAttr>[
      _ExtAttr(
        'WM/AlbumArtist',
        AsfDataType.unicodeString,
        _utf16('Electric Light Orchestra'),
      ),
      _ExtAttr('WM/TrackNumber', AsfDataType.unicodeString, _utf16('9/12')),
      _ExtAttr('WM/Genre', AsfDataType.unicodeString, _utf16('Rock')),
      _ExtAttr('WM/Year', AsfDataType.unicodeString, _utf16('2001')),
    ]),
  );

  final metadataObject = _asfObject(
    AsfGuid.metadataObject,
    _metadataBody(<_MetadataRecord>[
      _MetadataRecord(
        name: 'WM/AlbumTitle',
        dataType: AsfDataType.unicodeString,
        data: _utf16('Discovery'),
      ),
      _MetadataRecord(
        name: 'WM/Picture',
        dataType: AsfDataType.byteArray,
        data: _wmPicturePayload(),
      ),
    ]),
  );

  final headerExtension = _asfObject(
    AsfGuid.headerExtensionObject,
    _headerExtensionBody(<int>[...metadataObject]),
  );

  final objects = <List<int>>[
    fileProperties,
    streamProperties,
    codecList,
    contentDescription,
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

List<int> _asfObject(AsfGuid guid, List<int> payload) => <int>[...guid.toBytes(), ..._u64le(payload.length + 24), ...payload];

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

List<int> _streamPropertiesBody() => <int>[...AsfGuid.audioMedia.toBytes(), ...List<int>.filled(16, 0)];

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

List<int> _contentDescriptionBody({
  required String title,
  required String author,
  required String copyright,
  required String description,
  required String rating,
}) {
  final values = <List<int>>[
    _utf16(title),
    _utf16(author),
    _utf16(copyright),
    _utf16(description),
    _utf16(rating),
  ];

  final lengths = <int>[for (final v in values) v.length];
  return <int>[
    for (final len in lengths) ..._u16le(len),
    for (final value in values) ...value,
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

List<int> _metadataBody(List<_MetadataRecord> records) => <int>[
    ..._u16le(records.length),
    for (final record in records) ...[
      ..._u16le(0),
      ..._u16le(0),
      ..._u16le(_utf16(record.name).length),
      ..._u16le(record.dataType),
      ..._u32le(record.data.length),
      ..._utf16(record.name),
      ...record.data,
    ],
  ];

List<int> _wmPicturePayload() {
  final imageData = <int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4];
  final format = _utf16('image/jpeg');
  final description = _utf16('Front cover');

  return <int>[
    3,
    ..._u32le(imageData.length),
    ...format,
    0,
    0,
    ...description,
    0,
    0,
    ...imageData,
  ];
}

List<int> _u16le(int value) => <int>[value & 0xFF, (value >> 8) & 0xFF];

List<int> _u32le(int value) => <int>[
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ];

List<int> _u64le(int value) {
  final lower = value & 0xFFFFFFFF;
  final upper = (value >> 32) & 0xFFFFFFFF;
  return <int>[..._u32le(lower), ..._u32le(upper)];
}

List<int> _utf16(String value) {
  final units = value.codeUnits;
  final out = <int>[];
  for (final unit in units) {
    out.add(unit & 0xFF);
    out.add((unit >> 8) & 0xFF);
  }
  return out;
}

class _ExtAttr {
  const _ExtAttr(this.name, this.valueType, this.value);

  final String name;
  final int valueType;
  final List<int> value;
}

class _MetadataRecord {
  const _MetadataRecord({
    required this.name,
    required this.dataType,
    required this.data,
  });

  final String name;
  final int dataType;
  final List<int> data;
}

class _NonSeekTokenizer extends Tokenizer {
  @override
  bool get canSeek => false;

  @override
  FileInfo? get fileInfo => const FileInfo();

  @override
  int get position => 0;

  @override
  int peekUint8() => throw TokenizerException('peek unsupported');

  @override
  List<int> peekBytes(int length) =>
      throw TokenizerException('peek unsupported');

  @override
  int readUint8() => throw TokenizerException('read unsupported');

  @override
  int readUint16() => throw TokenizerException('read unsupported');

  @override
  int readUint32() => throw TokenizerException('read unsupported');

  @override
  List<int> readBytes(int length) =>
      throw TokenizerException('read unsupported');

  @override
  void seek(int position) => throw TokenizerException('seek unsupported');

  @override
  void skip(int length) => throw TokenizerException('skip unsupported');
}
