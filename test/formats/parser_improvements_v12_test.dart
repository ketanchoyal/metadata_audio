import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/asf/asf_tag_map.dart';
import 'package:metadata_audio/src/caf/caf_loader.dart';
import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/id3v1/id3v1_tag_map.dart';
import 'package:metadata_audio/src/id3v2/id3v2_tag_map.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/mp4/mp4_tag_mapper.dart';
import 'package:metadata_audio/src/mpeg/mpeg_parser.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:metadata_audio/src/wav/wave_chunk.dart';
import 'package:metadata_audio/src/wav/wave_loader.dart';
import 'package:metadata_audio/src/wavpack/wavpack_loader.dart';
import 'package:metadata_audio/src/wavpack/wavpack_parser.dart';
import 'package:test/test.dart';

void main() {
  group('WAV WAVE_FORMAT_EXTENSIBLE and Lossless Detection', () {
    List<int> buildExtensibleWave({
      required int subFormatTag,
      int cbSize = 22,
      bool standardGuid = true,
      int validBits = 24,
      int containerBits = 24,
      bool includeFact = false,
      String? copyright,
    }) {
      final fmtPayload = <int>[
        // wFormatTag: 0xFFFE (EXTENSIBLE)
        ..._u16le(0xFFFE),
        // nChannels: 1
        ..._u16le(1),
        // nSamplesPerSec: 8000
        ..._u32le(8000),
        // nAvgBytesPerSec: 8000 * 3
        ..._u32le(8000 * (containerBits ~/ 8)),
        // nBlockAlign: 3
        ..._u16le(containerBits ~/ 8),
        // wBitsPerSample
        ..._u16le(containerBits),
      ];

      if (cbSize >= 0) {
        fmtPayload.addAll(_u16le(cbSize));
        if (cbSize >= 22) {
          // wValidBitsPerSample
          fmtPayload.addAll(_u16le(validBits));
          // dwChannelMask
          fmtPayload.addAll(_u32le(0x04));
          // SubFormat GUID (16 bytes):
          // First 2 bytes: subFormatTag
          // Remaining 14 bytes: waveFormatExtensibleSubFormatSuffix
          fmtPayload.addAll(_u16le(subFormatTag));
          if (standardGuid) {
            fmtPayload.addAll(waveFormatExtensibleSubFormatSuffix);
          } else {
            fmtPayload.addAll(List.filled(14, 0x00));
          }
        }
      }

      final chunks = <int>[];

      // 'fmt ' chunk
      chunks.addAll(ascii.encode('fmt '));
      chunks.addAll(_u32le(fmtPayload.length));
      chunks.addAll(fmtPayload);
      if (fmtPayload.length.isOdd) chunks.add(0);

      // Optional 'fact' chunk
      if (includeFact) {
        chunks.addAll(ascii.encode('fact'));
        chunks.addAll(_u32le(4));
        chunks.addAll(_u32le(800)); // 800 samples
      }

      // 'data' chunk (800 samples = 2400 bytes)
      const dataSize = 2400;
      chunks.addAll(ascii.encode('data'));
      chunks.addAll(_u32le(dataSize));
      chunks.addAll(Uint8List(dataSize));

      // Optional LIST/INFO chunk with ICOP
      if (copyright != null) {
        final icopBytes = ascii.encode('$copyright\x00');
        final infoPayload = <int>[
          ...ascii.encode('INFO'),
          ...ascii.encode('ICOP'),
          ..._u32le(icopBytes.length),
          ...icopBytes,
          if (icopBytes.length.isOdd) 0,
        ];
        chunks.addAll(ascii.encode('LIST'));
        chunks.addAll(_u32le(infoPayload.length));
        chunks.addAll(infoPayload);
        if (infoPayload.length.isOdd) chunks.add(0);
      }

      final riff = <int>[
        ...ascii.encode('RIFF'),
        ..._u32le(4 + chunks.length),
        ...ascii.encode('WAVE'),
        ...chunks,
      ];

      return riff;
    }

    test('resolves PCM and validBitsPerSample in 24-bit container', () async {
      final wav = buildExtensibleWave(
        subFormatTag: WaveFormat.pcm,
        validBits: 20,
      );
      final loader = WaveLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wav)),
        const ParseOptions(duration: true),
      );

      expect(res.format.container, 'WAVE');
      expect(res.format.codec, 'PCM');
      expect(res.format.lossless, isTrue);
      expect(res.format.bitsPerSample, 20);
      expect(res.format.numberOfSamples, 800);
      expect(res.format.duration, closeTo(0.1, 0.001));
    });

    test('retains container bits when validBits is 0 or excessive', () async {
      final wavZero = buildExtensibleWave(
        subFormatTag: WaveFormat.pcm,
        validBits: 0,
      );
      final loader = WaveLoader();
      final resZero = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wavZero)),
        const ParseOptions(duration: true),
      );
      expect(resZero.format.bitsPerSample, 24);

      final wavExcess = buildExtensibleWave(
        subFormatTag: WaveFormat.pcm,
        validBits: 32,
      );
      final resExcess = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wavExcess)),
        const ParseOptions(duration: true),
      );
      expect(resExcess.format.bitsPerSample, 24);
    });

    test('resolves IEEE_FLOAT from SubFormat GUID as lossless', () async {
      final wav = buildExtensibleWave(
        subFormatTag: WaveFormat.ieeeFloat,
        validBits: 32,
        containerBits: 32,
        includeFact: true,
      );
      final loader = WaveLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wav)),
        const ParseOptions(duration: true),
      );

      expect(res.format.codec, 'IEEE_FLOAT');
      expect(res.format.lossless, isTrue);
      expect(res.format.numberOfSamples, 800);
    });

    test('resolves lossy ALAW SubFormat as lossy', () async {
      final wav = buildExtensibleWave(
        subFormatTag: WaveFormat.alaw,
        validBits: 8,
        containerBits: 8,
      );
      final loader = WaveLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wav)),
        const ParseOptions(duration: true),
      );

      expect(res.format.codec, 'ALAW');
      expect(res.format.lossless, isFalse);
    });

    test('falls back to non-PCM (65534) for non-standard GUID', () async {
      final wav = buildExtensibleWave(
        subFormatTag: WaveFormat.pcm,
        standardGuid: false,
      );
      final loader = WaveLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wav)),
        const ParseOptions(duration: true),
      );

      expect(res.format.codec, 'non-PCM (65534)');
      expect(res.format.lossless, isFalse);
    });

    test('fact chunk does not mark standard PCM lossy', () async {
      final wav = buildExtensibleWave(
        subFormatTag: WaveFormat.pcm,
        validBits: 16,
        containerBits: 16,
        includeFact: true,
      );
      final loader = WaveLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wav)),
        const ParseOptions(duration: true),
      );

      expect(res.format.codec, 'PCM');
      expect(res.format.lossless, isTrue);
      expect(res.format.numberOfSamples, 800);
    });

    test('maps RIFF INFO ICOP to common.copyright', () async {
      final wav = buildExtensibleWave(
        subFormatTag: WaveFormat.pcm,
        validBits: 16,
        containerBits: 16,
        copyright: '(C) 2026 Test Studio Records',
      );
      final loader = WaveLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wav)),
        const ParseOptions(duration: true),
      );

      expect(res.common.copyright, '(C) 2026 Test Studio Records');
    });
  });

  group('Boolean Tag Handling', () {
    test('ASF mapper accepts native boolean true for WM/IsCompilation', () {
      final mapper = AsfTagMapper();
      final mapped = mapper.mapTags({'WM/IsCompilation': true});
      expect(mapped['compilation'], isTrue);

      final mappedFalse = mapper.mapTags({'WM/IsCompilation': false});
      expect(mappedFalse['compilation'], isFalse);

      final mappedList = mapper.mapTags({
        'WM/IsCompilation': [true]
      });
      expect(mappedList['compilation'], isTrue);
    });

    test('ID3v2 mapper maps TCP / TCMP to compilation boolean', () {
      final mapper = Id3v2TagMapper();
      final mapped = mapper.mapTags({'TCMP': '1'});
      expect(mapped['compilation'], isTrue);

      final mappedZero = mapper.mapTags({'TCMP': '0'});
      expect(mappedZero['compilation'], isFalse);
    });
  });

  group('Lyrics Normalization', () {
    test('normalizes raw string lyrics to typed LyricsTag', () {
      final mapper = CombinedTagMapper()
        ..registerMapper('iTunes', Mp4TagMapper());
      final collector = MetadataCollector(mapper);
      collector.addNativeTag('iTunes', '©lyr', 'Verse 1: Hello World');
      final meta = collector.toAudioMetadata();

      expect(meta.common.lyrics, isNotNull);
      expect(meta.common.lyrics!.length, 1);
      final lyric = meta.common.lyrics!.first;
      expect(lyric.text, 'Verse 1: Hello World');
      expect(lyric.contentType, 'lyrics');
      expect(lyric.timeStampFormat, 'none');
      expect(lyric.syncText, isEmpty);
    });

    test('normalizes Comment object with language and descriptor to LyricsTag', () {
      final mapper = CombinedTagMapper()
        ..registerMapper('ID3v2.4', Id3v2TagMapper());
      final collector = MetadataCollector(mapper);
      collector.addNativeTag(
        'ID3v2.4',
        'USLT',
        const Comment(
          language: 'eng',
          descriptor: 'Translation',
          text: 'Some song lyrics',
        ),
      );
      final meta = collector.toAudioMetadata();

      expect(meta.common.lyrics, isNotNull);
      final lyric = meta.common.lyrics!.first;
      expect(lyric.text, 'Some song lyrics');
      expect(lyric.language, 'eng');
      expect(lyric.descriptor, 'Translation');
      expect(lyric.contentType, 'lyrics');
      expect(lyric.timeStampFormat, 'none');
    });
  });

  group('CAF Unknown-Size Duration Recovery', () {
    List<int> buildCafUnknownSizeStream({required int payloadBytes}) {
      final fileHeader = <int>[
        ...ascii.encode('caff'),
        ..._u16be(1), // mFileVersion
        ..._u16be(0), // mFileFlags
      ];

      // 'desc' chunk (32 bytes)
      final desc = ByteData(32);
      desc.setFloat64(0, 44100); // mSampleRate
      final formatIdBytes = ascii.encode('lpcm');
      for (var i = 0; i < 4; i++) {
        desc.setUint8(8 + i, formatIdBytes[i]);
      }
      desc.setUint32(12, 0); // mFormatFlags
      desc.setUint32(16, 4); // mBytesPerPacket = 4
      desc.setUint32(20, 2); // mFramesPerPacket = 2
      desc.setUint32(24, 1); // mChannelsPerFrame = 1
      desc.setUint32(28, 16); // mBitsPerChannel = 16

      final descChunk = <int>[
        ...ascii.encode('desc'),
        ..._u64be(32),
        ...desc.buffer.asUint8List(),
      ];

      // 'data' chunk with chunkSize = -1 (runs to physical EOF)
      final dataHeader = <int>[
        ...ascii.encode('data'),
        ..._u64be(-1),
        ..._u32be(1), // mEditCount
      ];
      final audioPayload = Uint8List(payloadBytes);

      return <int>[
        ...fileHeader,
        ...descChunk,
        ...dataHeader,
        ...audioPayload,
      ];
    }

    test('derives duration from complete fixed packets in unknown-size stream', () async {
      // 10 payload bytes: each packet is 4 bytes, covering 2 complete packets (8 bytes = 4 frames)
      final cafBytes = buildCafUnknownSizeStream(payloadBytes: 10);
      final loader = CafLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(cafBytes), fileInfo: const FileInfo()),
        const ParseOptions(duration: true),
      );

      expect(res.format.container, 'CAF');
      expect(res.format.numberOfSamples, 4);
      expect(res.format.duration, closeTo(4 / 44100.0, 0.0001));
    });

    test('skips duration derivation when duration option is false', () async {
      final cafBytes = buildCafUnknownSizeStream(payloadBytes: 10);
      final loader = CafLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(cafBytes), fileInfo: const FileInfo()),
        const ParseOptions(),
      );

      expect(res.format.numberOfSamples, isNull);
      expect(res.format.duration, isNull);
    });
  });

  group('WavPack Unknown Total Samples Recovery', () {
    List<int> buildWavPackBlock({
      required int blockIndex,
      required int blockSamples,
      required int totalSamples,
      required bool isInitial,
      required bool isFinal,
    }) {
      var flags = 0;
      // bitsPerSample: 16 (0 in bits 0..1 => (1+0)*8 = 8, 1 => 16 bits)
      flags |= 1 << 0;
      // samplingRate: 44100 (index 9 in SampleRates table)
      flags |= 9 << 23;
      if (isInitial) flags |= 1 << 11;
      if (isFinal) flags |= 1 << 12;

      final block = ByteData(32);
      final wvpk = ascii.encode('wvpk');
      for (var i = 0; i < 4; i++) {
        block.setUint8(i, wvpk[i]);
      }
      block.setUint32(4, 24, Endian.little); // blockSize = 32 - 8 = 24
      block.setUint16(8, 0x410, Endian.little); // version
      block.setUint8(10, 0); // blockIndex high byte
      block.setUint8(11, 0); // totalSamples high byte
      block.setUint32(12, totalSamples, Endian.little);
      block.setUint32(16, blockIndex, Endian.little);
      block.setUint32(20, blockSamples, Endian.little);
      block.setUint32(24, flags, Endian.little);
      block.setUint32(28, 0, Endian.little); // crc

      return block.buffer.asUint8List();
    }

    test('derives sample total when header declares unknown total samples (0xFFFFFFFF)', () async {
      // Two blocks of 1000 samples each:
      final block1 = buildWavPackBlock(
        blockIndex: 0,
        blockSamples: 1000,
        totalSamples: 0xFFFFFFFF,
        isInitial: true,
        isFinal: true,
      );
      final block2 = buildWavPackBlock(
        blockIndex: 1000,
        blockSamples: 1000,
        totalSamples: 0xFFFFFFFF,
        isInitial: true,
        isFinal: true,
      );

      final wvpkBytes = <int>[...block1, ...block2];
      final loader = WavPackLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wvpkBytes)),
        const ParseOptions(duration: true),
      );

      expect(res.format.container, 'WavPack');
      expect(res.format.numberOfSamples, 2000);
      expect(res.format.sampleRate, 44100);
      expect(res.format.duration, closeTo(2000 / 44100.0, 0.0001));
    });

    test('rejects truncated DSD metadata sub-block', () async {
      final header = buildWavPackBlock(
        blockIndex: 0,
        blockSamples: 0,
        totalSamples: 1000,
        isInitial: true,
        isFinal: true,
      );
      // Modify flag to set isDsd (bit 31)
      final modifiedHeader = Uint8List.fromList(header);
      final bd = ByteData.sublistView(modifiedHeader);
      final flags = bd.getUint32(24, Endian.little) | (1 << 31);
      bd.setUint32(24, flags, Endian.little);

      // Add subblock 0x0E (ID_DSD_BLOCK) with 0 data words (empty payload)
      // subblock header: id byte = 0x0E (function 0x0E, small block), size = 0
      final subblock = <int>[0x0E, 0x00];
      bd.setUint32(4, 24 + subblock.length, Endian.little);

      final fileBytes = <int>[...modifiedHeader, ...subblock];
      final loader = WavPackLoader();
      expect(
        () => loader.parse(
          BytesTokenizer(Uint8List.fromList(fileBytes)),
          const ParseOptions(),
        ),
        throwsA(isA<WavPackContentError>().having(
          (e) => e.message,
          'message',
          contains('Truncated WavPack DSD metadata'),
        )),
      );
    });
  });

  group('ADTS AAC Trailing ID3v1 Retention', () {
    List<int> buildId3v1Tag({
      required String title,
      required String artist,
      required String album,
      required String year,
      required int track,
    }) {
      final tag = Uint8List(128);
      final tagAscii = ascii.encode('TAG');
      tag.setRange(0, 3, tagAscii);

      void writeFixed(int offset, int length, String value) {
        final encoded = ascii.encode(value);
        final len = encoded.length > length ? length : encoded.length;
        tag.setRange(offset, offset + len, encoded.sublist(0, len));
      }

      writeFixed(3, 30, title);
      writeFixed(33, 30, artist);
      writeFixed(63, 30, album);
      writeFixed(93, 4, year);
      writeFixed(97, 28, 'Test Comment');
      tag[125] = 0;
      tag[126] = track;
      tag[127] = 12; // Other genre

      return tag;
    }

    test('retains trailing ID3v1 tag after ADTS duration scan', () async {
      // Build 4 consecutive ADTS frames of 20 bytes each
      final frame = <int>[
        0xFF,
        0xF1,
        0x50,
        0x80,
        2,
        0x9F,
        0xFC,
        ...Uint8List(13),
      ];
      final audioData = <int>[
        ...frame,
        ...frame,
        ...frame,
        ...frame,
      ];

      final id3v1 = buildId3v1Tag(
        title: 'ADTS ID3v1 Title',
        artist: 'ADTS ID3v1 Artist',
        album: 'ADTS ID3v1 Album',
        year: '2026',
        track: 5,
      );

      final fullFile = <int>[...audioData, ...id3v1];
      final mapper = CombinedTagMapper()
        ..registerMapper('ID3v1', Id3v1TagMapper())
        ..registerMapper('ID3v2.4', Id3v2TagMapper());
      final collector = MetadataCollector(mapper);
      final tokenizer = BytesTokenizer(
        Uint8List.fromList(fullFile),
        fileInfo: FileInfo(size: fullFile.length),
      );

      final parser = MpegParser(
        metadata: collector,
        tokenizer: tokenizer,
        options: const ParseOptions(duration: true),
      );
      await parser.parse();

      final meta = collector.toAudioMetadata();
      expect(meta.format.tagTypes, contains('ID3v1'));
      expect(meta.common.title, 'ADTS ID3v1 Title');
      expect(meta.common.artist, 'ADTS ID3v1 Artist');
      expect(meta.common.album, 'ADTS ID3v1 Album');
      expect(meta.common.year, 2026);
      expect(meta.common.track.no, 5);
    });
  });
}

List<int> _u16le(int value) => <int>[value & 0xFF, (value >> 8) & 0xFF];

List<int> _u16be(int value) => <int>[(value >> 8) & 0xFF, value & 0xFF];

List<int> _u32le(int value) => <int>[
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

List<int> _u32be(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _u64be(int value) {
  final bd = ByteData(8);
  bd.setInt64(0, value);
  return bd.buffer.asUint8List();
}
