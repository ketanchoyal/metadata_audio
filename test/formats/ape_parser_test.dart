import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/apev2/apev2_loader.dart';
import 'package:metadata_audio/src/apev2/apev2_parser.dart';
import 'package:metadata_audio/src/apev2/apev2_token.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  group('Apev2Parser / Apev2Loader', () {
    test(
      'parses standalone APEv2 header tag with text and picture items',
      () async {
        final bytes = _buildStandaloneApev2Tag(
          items: <List<int>>[
            _textItem('Title', '07. Shadow On The Sun'),
            _textItem('Artist', 'Audioslave'),
            _textItem('Artists', 'Audioslave\u0000Chris Cornell'),
            _textItem('Album', 'Audioslave'),
            _textItem('Year', '2002'),
            _textItem('Track', '7/14'),
            _textItem('Disc', '3'),
            _textItem('Genre', 'Alternative'),
            _binaryItem('Cover Art (Front)', 'Front cover', _jpegSample()),
          ],
        );

        final metadata = await Apev2Loader().parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(),
        );

        expect(metadata.common.title, '07. Shadow On The Sun');
        expect(metadata.common.artist, 'Audioslave');
        expect(
          metadata.common.artists,
          equals(<String>['Audioslave', 'Chris Cornell']),
        );
        expect(metadata.common.album, 'Audioslave');
        expect(metadata.common.year, 2002);
        expect(metadata.common.track.no, 7);
        expect(metadata.common.disk.no, 3);
        expect(metadata.common.genre, equals(<String>['Alternative']));

        expect(metadata.common.picture, isNotNull);
        expect(metadata.common.picture, hasLength(1));
        expect(metadata.common.picture!.single.format, 'image/jpeg');
        expect(metadata.common.picture!.single.type, 'Cover (front)');

        final native = metadata.native['APEv2'];
        expect(native, isNotNull);
        final nativeCover = native!
            .where((tag) => tag.id == 'Cover Art (Front)')
            .single
            .value;
        expect(nativeCover, isA<ApePicture>());
        expect((nativeCover as ApePicture).data, equals(_jpegSample()));
      },
    );

    test(
      "parses Monkey's Audio header and reads APEv2 footer tag at end",
      () async {
        final bytes = _buildApeFileWithTailTag(
          items: <List<int>>[
            _textItem('Title', 'Tail Title'),
            _textItem('Artist', 'Tail Artist'),
          ],
          sampleRate: 44100,
          channels: 2,
          bitsPerSample: 16,
          totalFrames: 2,
          blocksPerFrame: 73728,
          finalFrameBlocks: 33406,
        );

        final metadata = await Apev2Loader().parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(),
        );

        expect(metadata.format.container, "Monkey's Audio");
        expect(metadata.format.lossless, isTrue);
        expect(metadata.format.sampleRate, 44100);
        expect(metadata.format.numberOfChannels, 2);
        expect(metadata.format.bitsPerSample, 16);
        expect(metadata.format.duration, closeTo(2.4293424, 0.00001));
        expect(metadata.format.hasAudio, isTrue);
        expect(metadata.format.hasVideo, isFalse);
        expect(metadata.common.title, 'Tail Title');
        expect(metadata.common.artist, 'Tail Artist');
      },
    );

    test(
      'adds warning when declared tag item count exceeds available data',
      () async {
        final bytes = _buildStandaloneApev2Tag(
          items: <List<int>>[_textItem('Title', 'Only one item')],
          footerFieldsOverride: 2,
        );

        final metadata = await Apev2Loader().parse(
          BytesTokenizer(
            Uint8List.fromList(bytes),
            fileInfo: FileInfo(size: bytes.length),
          ),
          const ParseOptions(),
        );

        final warningMessages = metadata.quality.warnings
            .map((warning) => warning.message)
            .toList();
        expect(
          warningMessages,
          anyElement(
            contains(
              'APEv2 Tag-header: 1 items remaining, but no more tag data to read.',
            ),
          ),
        );
      },
    );

    test('throws when descriptor does not start with MAC preamble', () async {
      final invalid = Uint8List.fromList(List<int>.filled(64, 0));

      await expectLater(
        Apev2Loader().parse(BytesTokenizer(invalid), const ParseOptions()),
        throwsA(isA<ApeContentError>()),
      );
    });

    test('loader declares extension, MIME types and seek requirement', () {
      final loader = Apev2Loader();

      expect(loader.extension, equals(<String>['ape', 'apev2']));
      expect(loader.mimeType, equals(<String>['audio/ape', 'audio/x-ape']));
      expect(loader.hasRandomAccessRequirements, isTrue);
      expect(loader.supports(_NonSeekTokenizer()), isFalse);
    });
  });
}

List<int> _buildStandaloneApev2Tag({
  required List<List<int>> items,
  int? footerFieldsOverride,
}) {
  final itemsPayload = <int>[for (final item in items) ...item];
  final footer = _apeTagFooter(
    size: itemsPayload.length + Apev2Token.tagFooterLength,
    fields: footerFieldsOverride ?? items.length,
    flags: 1 << 31,
  );
  final header = _apeTagFooter(
    size: itemsPayload.length + Apev2Token.tagFooterLength,
    fields: footerFieldsOverride ?? items.length,
    flags: (1 << 30) | (1 << 29),
  );

  return <int>[...header, ...itemsPayload, ...footer];
}

List<int> _buildApeFileWithTailTag({
  required List<List<int>> items,
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
  required int totalFrames,
  required int blocksPerFrame,
  required int finalFrameBlocks,
}) {
  final descriptor = _descriptor(
    headerBytes: Apev2Token.headerLength,
    apeFrameDataBytes: 8,
  );
  final header = _header(
    compressionLevel: 2000,
    formatFlags: 0,
    blocksPerFrame: blocksPerFrame,
    finalFrameBlocks: finalFrameBlocks,
    totalFrames: totalFrames,
    bitsPerSample: bitsPerSample,
    channels: channels,
    sampleRate: sampleRate,
  );

  final itemsPayload = <int>[for (final item in items) ...item];
  final footer = _apeTagFooter(
    size: itemsPayload.length + Apev2Token.tagFooterLength,
    fields: items.length,
    flags: 0,
  );

  final audioFrames = List<int>.filled(8, 0);

  return <int>[
    ...descriptor,
    ...header,
    ...audioFrames,
    ...itemsPayload,
    ...footer,
  ];
}

List<int> _textItem(String key, String value) {
  final payload = utf8.encode(value);
  return _tagItem(key: key, value: payload, flags: Apev2DataType.textUtf8 << 1);
}

List<int> _binaryItem(String key, String description, List<int> data) {
  final payload = <int>[...utf8.encode(description), 0, ...data];
  return _tagItem(key: key, value: payload, flags: Apev2DataType.binary << 1);
}

List<int> _tagItem({
  required String key,
  required List<int> value,
  required int flags,
}) => <int>[
  ..._u32le(value.length),
  ..._u32le(flags),
  ...ascii.encode(key),
  0,
  ...value,
];

List<int> _descriptor({
  required int headerBytes,
  required int apeFrameDataBytes,
}) => <int>[
  ...ascii.encode('MAC '),
  ..._u32le(3990),
  ..._u32le(Apev2Token.descriptorLength),
  ..._u32le(headerBytes),
  ..._u32le(0),
  ..._u32le(0),
  ..._u32le(apeFrameDataBytes),
  ..._u32le(0),
  ..._u32le(0),
  ...List<int>.filled(16, 0),
];

List<int> _header({
  required int compressionLevel,
  required int formatFlags,
  required int blocksPerFrame,
  required int finalFrameBlocks,
  required int totalFrames,
  required int bitsPerSample,
  required int channels,
  required int sampleRate,
}) => <int>[
  ..._u16le(compressionLevel),
  ..._u16le(formatFlags),
  ..._u32le(blocksPerFrame),
  ..._u32le(finalFrameBlocks),
  ..._u32le(totalFrames),
  ..._u16le(bitsPerSample),
  ..._u16le(channels),
  ..._u32le(sampleRate),
];

List<int> _apeTagFooter({
  required int size,
  required int fields,
  required int flags,
}) => <int>[
  ...ascii.encode(Apev2Token.preamble),
  ..._u32le(2000),
  ..._u32le(size),
  ..._u32le(fields),
  ..._u32le(flags),
  ...List<int>.filled(8, 0),
];

List<int> _u16le(int value) => <int>[value & 0xFF, (value >> 8) & 0xFF];

List<int> _u32le(int value) => <int>[
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

List<int> _jpegSample() => <int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
  0x4A,
  0x46,
  0x49,
  0x46,
];

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
