import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_audio/src/apev2/apev2_tag_map.dart';
import 'package:metadata_audio/src/asf/asf_tag_map.dart';
import 'package:metadata_audio/src/caf/caf_loader.dart';
import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/common/util.dart';
import 'package:metadata_audio/src/flac/flac_vorbis_tag_map.dart';
import 'package:metadata_audio/src/id3v1/id3v1_tag_map.dart';
import 'package:metadata_audio/src/id3v2/id3v2_tag_map.dart';
import 'package:metadata_audio/src/matroska/matroska_tag_mapper.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/mp4/mp4_loader.dart';
import 'package:metadata_audio/src/mp4/mp4_tag_mapper.dart';
import 'package:metadata_audio/src/mpeg/mpeg_parser.dart';
import 'package:metadata_audio/src/tokenizer/io_tokenizers.dart';
import 'package:metadata_audio/src/utils/audio_metadata_cache.dart';
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

    test('resolves extensible FLAC (0xF1AC) as lossless', () async {
      final wav = buildExtensibleWave(
        subFormatTag: WaveFormat.flac,
      );
      final loader = WaveLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wav)),
        const ParseOptions(duration: true),
      );

      expect(res.format.codec, 'FLAC');
      expect(res.format.lossless, isTrue);
    });

    test('resolves extensible MULAW (0x0007) as lossy', () async {
      final wav = buildExtensibleWave(
        subFormatTag: WaveFormat.mulaw,
        validBits: 8,
        containerBits: 8,
      );
      final loader = WaveLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wav)),
        const ParseOptions(duration: true),
      );

      expect(res.format.codec, 'MULAW');
      expect(res.format.lossless, isFalse);
    });

    test('truncated or missing cbSize (< 22) falls back to non-PCM (65534)', () async {
      final wavTrunc = buildExtensibleWave(
        subFormatTag: WaveFormat.pcm,
        cbSize: 10,
      );
      final loader = WaveLoader();
      final resTrunc = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wavTrunc)),
        const ParseOptions(duration: true),
      );
      expect(resTrunc.format.codec, 'non-PCM (65534)');

      final wavMissing = buildExtensibleWave(
        subFormatTag: WaveFormat.pcm,
        cbSize: -1,
      );
      final resMissing = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wavMissing)),
        const ParseOptions(duration: true),
      );
      expect(resMissing.format.codec, 'non-PCM (65534)');
    });

    test('resolves 24-bit valid audio packed inside 32-bit container', () async {
      final wav = buildExtensibleWave(
        subFormatTag: WaveFormat.pcm,
        containerBits: 32,
      );
      final loader = WaveLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(wav)),
        const ParseOptions(duration: true),
      );

      expect(res.format.bitsPerSample, 24);
      expect(res.format.lossless, isTrue);
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

    test('ASF mapper handles boolean, numeric, string, and list representations', () {
      final mapper = AsfTagMapper();
      expect(mapper.mapTags({'WM/IsCompilation': 1})['compilation'], isTrue);
      expect(mapper.mapTags({'WM/IsCompilation': '1'})['compilation'], isTrue);
      expect(mapper.mapTags({'WM/IsCompilation': ['1']})['compilation'], isTrue);
      expect(mapper.mapTags({'WM/IsCompilation': [1]})['compilation'], isTrue);
      expect(mapper.mapTags({'WM/IsCompilation': 'true'})['compilation'], isTrue);

      expect(mapper.mapTags({'WM/IsCompilation': 0})['compilation'], isFalse);
      expect(mapper.mapTags({'WM/IsCompilation': '0'})['compilation'], isFalse);
      expect(mapper.mapTags({'WM/IsCompilation': 'false'})['compilation'], isFalse);
      expect(mapper.mapTags({'WM/IsCompilation': ['0']})['compilation'], isFalse);
    });

    test('ID3v2 mapper maps TCP / TCMP to compilation boolean', () {
      final mapper = Id3v2TagMapper();
      final mapped = mapper.mapTags({'TCMP': '1'});
      expect(mapped['compilation'], isTrue);

      final mappedZero = mapper.mapTags({'TCMP': '0'});
      expect(mappedZero['compilation'], isFalse);
    });

    test('ID3v2 mapper maps TCP, TCMP, and TXXX:COMPILATION across multiple data types', () {
      final mapper = Id3v2TagMapper();
      expect(mapper.mapTags({'TCP': '1'})['compilation'], isTrue);
      expect(mapper.mapTags({'TCP': 1})['compilation'], isTrue);
      expect(mapper.mapTags({'TCP': true})['compilation'], isTrue);

      expect(mapper.mapTags({'TCMP': true})['compilation'], isTrue);
      expect(mapper.mapTags({'TCMP': 1})['compilation'], isTrue);
      expect(mapper.mapTags({'TCMP': [1]})['compilation'], isTrue);
      expect(mapper.mapTags({'TCMP': ['1']})['compilation'], isTrue);

      expect(mapper.mapTags({'TXXX:COMPILATION': '1'})['compilation'], isTrue);
      expect(mapper.mapTags({'TXXX:COMPILATION': true})['compilation'], isTrue);
      expect(mapper.mapTags({'TXXX:COMPILATION': '0'})['compilation'], isFalse);
      expect(mapper.mapTags({'TXXX:COMPILATION': false})['compilation'], isFalse);
    });

    test('APEv2 mapper maps Compilation across boolean, int, string, and list', () {
      final mapper = Apev2TagMapper();
      expect(mapper.mapTags({'Compilation': true})['compilation'], isTrue);
      expect(mapper.mapTags({'Compilation': false})['compilation'], isFalse);
      expect(mapper.mapTags({'Compilation': 1})['compilation'], isTrue);
      expect(mapper.mapTags({'Compilation': 0})['compilation'], isFalse);
      expect(mapper.mapTags({'Compilation': '1'})['compilation'], isTrue);
      expect(mapper.mapTags({'Compilation': '0'})['compilation'], isFalse);
      expect(mapper.mapTags({'Compilation': [true]})['compilation'], isTrue);
      expect(mapper.mapTags({'Compilation': ['1']})['compilation'], isTrue);
    });

    test('MP4 mapper maps cpil across boolean, int, string, and list', () {
      final mapper = Mp4TagMapper();
      expect(mapper.mapTags({'cpil': true})['compilation'], isTrue);
      expect(mapper.mapTags({'cpil': false})['compilation'], isFalse);
      expect(mapper.mapTags({'cpil': 1})['compilation'], isTrue);
      expect(mapper.mapTags({'cpil': 0})['compilation'], isFalse);
      expect(mapper.mapTags({'cpil': '1'})['compilation'], isTrue);
      expect(mapper.mapTags({'cpil': '0'})['compilation'], isFalse);
      expect(mapper.mapTags({'cpil': [1]})['compilation'], isTrue);
      expect(mapper.mapTags({'cpil': [true]})['compilation'], isTrue);
    });

    test('MetadataCollector assigns boolean to common.compilation', () {
      final mapper = CombinedTagMapper()..registerMapper('asf', AsfTagMapper());
      final collector = MetadataCollector(mapper);
      collector.addNativeTag('asf', 'WM/IsCompilation', true);
      final meta = collector.toAudioMetadata();
      expect(meta.common.compilation, isTrue);
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

    test('ID3v2.2 mapper maps ULT frame with Comment object to LyricsTag', () {
      final mapper = CombinedTagMapper()
        ..registerMapper('ID3v2.2', Id3v2TagMapper());
      final collector = MetadataCollector(mapper);
      collector.addNativeTag(
        'ID3v2.2',
        'ULT',
        const Comment(
          language: 'jpn',
          descriptor: 'Romaji',
          text: 'Kimi no na wa',
        ),
      );
      final meta = collector.toAudioMetadata();

      expect(meta.common.lyrics, isNotNull);
      final lyric = meta.common.lyrics!.first;
      expect(lyric.text, 'Kimi no na wa');
      expect(lyric.language, 'jpn');
      expect(lyric.descriptor, 'Romaji');
    });

    test('normalizes Map with text, descriptor, and language to LyricsTag', () {
      final mapper = CombinedTagMapper()
        ..registerMapper('ID3v2.4', Id3v2TagMapper());
      final collector = MetadataCollector(mapper);
      collector.addNativeTag(
        'ID3v2.4',
        'USLT',
        {
          'text': 'Map Lyrics Text',
          'language': 'fra',
          'descriptor': 'French Version',
        },
      );
      final meta = collector.toAudioMetadata();

      expect(meta.common.lyrics, isNotNull);
      final lyric = meta.common.lyrics!.first;
      expect(lyric.text, 'Map Lyrics Text');
      expect(lyric.language, 'fra');
      expect(lyric.descriptor, 'French Version');
    });

    test('preserves multiple lyrics tags (original text and translation)', () {
      final mapper = CombinedTagMapper()
        ..registerMapper('ID3v2.4', Id3v2TagMapper());
      final collector = MetadataCollector(mapper);
      collector.addNativeTag(
        'ID3v2.4',
        'USLT',
        const Comment(
          language: 'eng',
          descriptor: 'Original',
          text: 'Original English lyrics',
        ),
      );
      collector.addNativeTag(
        'ID3v2.4',
        'USLT',
        const Comment(
          language: 'spa',
          descriptor: 'Spanish',
          text: 'Letras en español',
        ),
      );
      final meta = collector.toAudioMetadata();

      expect(meta.common.lyrics, hasLength(2));
      expect(meta.common.lyrics![0].text, 'Original English lyrics');
      expect(meta.common.lyrics![0].language, 'eng');
      expect(meta.common.lyrics![0].descriptor, 'Original');
      expect(meta.common.lyrics![1].text, 'Letras en español');
      expect(meta.common.lyrics![1].language, 'spa');
      expect(meta.common.lyrics![1].descriptor, 'Spanish');
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

    test('discards unaligned leftover bytes in stream running to EOF', () async {
      // 11 payload bytes: 11 ~/ 4 = 2 complete packets (8 bytes = 4 frames), 3 leftover bytes discarded
      final cafBytes = buildCafUnknownSizeStream(payloadBytes: 11);
      final loader = CafLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(cafBytes), fileInfo: const FileInfo()),
        const ParseOptions(duration: true),
      );

      expect(res.format.numberOfSamples, 4);
      expect(res.format.duration, closeTo(4 / 44100.0, 0.0001));
    });

    test('handles zero bytesPerPacket gracefully without division by zero', () async {
      final cafBytes = buildCafUnknownSizeStream(payloadBytes: 16);
      final bd = ByteData.sublistView(Uint8List.fromList(cafBytes));
      // In desc chunk, mBytesPerPacket is at offset:
      // file header (8) + chunk header (12) + mBytesPerPacket (16) = 36
      // Let's verify desc chunk layout:
      // caff (4), version (2), flags (2) = 8 bytes
      // 'desc' (4), size (8) = 12 bytes
      // mSampleRate (8), mFormatId (4), mFormatFlags (4) = 16 bytes
      // mBytesPerPacket (4) = offset 8 + 12 + 16 = 36
      bd.setUint32(36, 0); // mBytesPerPacket = 0

      final loader = CafLoader();
      final res = await loader.parse(
        BytesTokenizer(bd.buffer.asUint8List(), fileInfo: const FileInfo()),
        const ParseOptions(duration: true),
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
      int blockIndexHigh = 0,
      int totalSamplesHigh = 0,
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
      block.setUint8(10, blockIndexHigh);
      block.setUint8(11, totalSamplesHigh);
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

    test('handles 40-bit block indexing with high bytes', () async {
      final block = buildWavPackBlock(
        blockIndex: 0,
        blockSamples: 500,
        totalSamples: 500,
        isInitial: true,
        isFinal: true,
        blockIndexHigh: 1,
        totalSamplesHigh: 1,
      );

      final loader = WavPackLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(block)),
        const ParseOptions(duration: true),
      );

      const expectedSamples = 500 + 1 * 0xFFFFFFFF;
      expect(res.format.numberOfSamples, expectedSamples);
      expect(res.format.duration, closeTo(expectedSamples / 44100.0, 0.001));
    });

    test('detects block index sequence gap, records warning, leaves total samples undefined', () async {
      final block1 = buildWavPackBlock(
        blockIndex: 0,
        blockSamples: 1000,
        totalSamples: 0xFFFFFFFF,
        isInitial: true,
        isFinal: true,
      );
      // Gap: block 2 starts at index 1500 instead of 1000
      final block2 = buildWavPackBlock(
        blockIndex: 1500,
        blockSamples: 1000,
        totalSamples: 0xFFFFFFFF,
        isInitial: true,
        isFinal: true,
      );

      final loader = WavPackLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(<int>[...block1, ...block2])),
        const ParseOptions(duration: true),
      );

      expect(res.quality.warnings, anyElement(predicate<ParserWarning>((w) => w.message.contains('incomplete or non-contiguous blocks'))));
      expect(res.format.numberOfSamples, isNull);
      expect(res.format.duration, isNull);
    });

    test('detects incomplete multichannel block group, records warning', () async {
      // Block 1 is initial but NOT final (waiting for subsequent multichannel blocks)
      final block1 = buildWavPackBlock(
        blockIndex: 0,
        blockSamples: 1000,
        totalSamples: 0xFFFFFFFF,
        isInitial: true,
        isFinal: false,
      );
      // Block 2 is a new initial block without block 1 having ended with a final block
      final block2 = buildWavPackBlock(
        blockIndex: 1000,
        blockSamples: 1000,
        totalSamples: 0xFFFFFFFF,
        isInitial: true,
        isFinal: true,
      );

      final loader = WavPackLoader();
      final res = await loader.parse(
        BytesTokenizer(Uint8List.fromList(<int>[...block1, ...block2])),
        const ParseOptions(duration: true),
      );

      expect(res.quality.warnings, anyElement(predicate<ParserWarning>((w) => w.message.contains('incomplete or non-contiguous blocks'))));
      expect(res.format.numberOfSamples, isNull);
      expect(res.format.duration, isNull);
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

    test('AAC stream with leading ID3v2.4 and trailing ID3v1 preserves both tagTypes and contents', () async {
      final id3v2 = _buildId3v24Tag({'TIT2': 'Leading AAC Title'});
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
        title: 'Trailing AAC Title',
        artist: 'Trailing AAC Artist',
        album: 'Trailing AAC Album',
        year: '2026',
        track: 1,
      );

      final fullFile = <int>[...id3v2, ...audioData, ...id3v1];
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
      expect(meta.format.tagTypes, containsAll(<String>['ID3v2.4', 'ID3v1']));
      expect(meta.native['ID3v2.4'], isNotNull);
      expect(meta.native['ID3v2.4']!.any((t) => t.id == 'TIT2' && t.value == 'Leading AAC Title'), isTrue);
      expect(meta.native['ID3v1'], isNotNull);
      expect(meta.native['ID3v1']!.any((t) => t.id == 'title' && t.value == 'Trailing AAC Title'), isTrue);
      // Common title prefers ID3v2
      expect(meta.common.title, 'Leading AAC Title');
      // Common artist merged from ID3v1
      expect(meta.common.artist, 'Trailing AAC Artist');
    });
  });

  group('MP4 AAC AudioSpecificConfig Channel Configurations', () {
    test('derives channel counts for configurations 2, 3, 4, 5, 6 (5.1), and 7 (7.1)', () async {
      final configs = <int, int>{
        2: 2, // Stereo
        3: 3, // 3 channels
        4: 4, // 4 channels
        5: 5, // 5 channels
        6: 6, // 5.1 surround
        7: 8, // 7.1 surround
      };

      for (final entry in configs.entries) {
        final mp4Bytes = _buildSyntheticMp4WithEsds(entry.key);
        final loader = Mp4Loader();
        final meta = await loader.parse(
          BytesTokenizer(Uint8List.fromList(mp4Bytes), fileInfo: FileInfo(size: mp4Bytes.length)),
          const ParseOptions(),
        );
        expect(
          meta.format.numberOfChannels,
          entry.value,
          reason: 'channelConfig ${entry.key} should resolve to ${entry.value} channels',
        );
      }
    });

    test('retains container channel count for invalid channel configurations (0 and 15)', () async {
      for (final invalidConfig in [0, 15]) {
        final mp4Bytes = _buildSyntheticMp4WithEsds(invalidConfig);
        final loader = Mp4Loader();
        final meta = await loader.parse(
          BytesTokenizer(Uint8List.fromList(mp4Bytes), fileInfo: FileInfo(size: mp4Bytes.length)),
          const ParseOptions(),
        );
        // sampleEntry specifies 2 channels, so invalid config should keep 2 channels
        expect(meta.format.numberOfChannels, 2);
      }
    });

    test('truncated esds atom gracefully falls back to container channel count', () async {
      final mp4Bytes = _buildSyntheticMp4WithEsds(6, truncated: true);
      final loader = Mp4Loader();
      final meta = await loader.parse(
        BytesTokenizer(Uint8List.fromList(mp4Bytes), fileInfo: FileInfo(size: mp4Bytes.length)),
        const ParseOptions(),
      );
      expect(meta.format.numberOfChannels, 2);
    });
  });

  group('Matroska Flat Tags and Event Stream', () {
    test('maps track:ALBUM, track:ALBUM_ARTIST, track:COMPOSER, track:DATE, track:DISC to common tags', () {
      final mapper = MatroskaTagMapper();
      final mapped = mapper.mapTags({
        'track:ALBUM': 'Flat Album',
        'track:ALBUM_ARTIST': 'Flat Album Artist',
        'track:COMPOSER': 'Flat Composer',
        'track:DATE': '2024-05-01',
        'track:DISC': '2/3',
      });

      expect(mapped['album'], 'Flat Album');
      expect(mapped['albumartist'], 'Flat Album Artist');
      expect(mapped['composer'], equals(['Flat Composer']));
      expect(mapped['date'], '2024-05-01');
      expect(mapped['disk'], equals(2));
    });

    test('emits MetadataEvent.commonTag events for Matroska track-level flat tags', () {
      final mapper = CombinedTagMapper()
        ..registerMapper('matroska', MatroskaTagMapper());
      final events = <MetadataEvent>[];
      final collector = MetadataCollector(mapper, ParseOptions(observer: events.add));

      collector.addNativeTag('matroska', 'track:ALBUM', 'Stream Album');
      collector.addNativeTag('matroska', 'track:ALBUM_ARTIST', 'Stream Artist');
      collector.addNativeTag('matroska', 'track:COMPOSER', 'Stream Composer');
      collector.addNativeTag('matroska', 'track:DATE', '2026');
      collector.addNativeTag('matroska', 'track:DISC', '1/2');

      final commonEvents = events.where((e) => e.tag?.type == MetadataEventTagType.common).toList();
      expect(commonEvents.any((e) => e.tag?.id == MetadataCommonId.album && e.tag?.value == 'Stream Album'), isTrue);
      expect(commonEvents.any((e) => e.tag?.id == MetadataCommonId.albumartist && e.tag?.value == 'Stream Artist'), isTrue);
      expect(commonEvents.any((e) => e.tag?.id == MetadataCommonId.composer), isTrue);
      expect(commonEvents.any((e) => e.tag?.id == MetadataCommonId.date && e.tag?.value == '2026'), isTrue);
      expect(commonEvents.any((e) => e.tag?.id == MetadataCommonId.disk), isTrue);
    });
  });

  group('ReplayGain Validation, Edge Cases, and Event Stream', () {
    test('parses scientific notation (+1.0e-1, -2.5e+0 dB, +1.23e+01 dB, -5.0e-2 dB)', () {
      final r1 = toRatio('+1.0e-1');
      expect(r1, isNotNull);
      expect(r1!.ratio, closeTo(0.1, 0.0001));

      final r2 = toRatio('-2.5e+0 dB');
      expect(r2, isNotNull);
      expect(r2!.dB, closeTo(-2.5, 0.0001));

      final r3 = toRatio('+1.23e+01 dB');
      expect(r3, isNotNull);
      expect(r3!.dB, closeTo(12.3, 0.0001));

      final r4 = toRatio('-5.0e-2 dB');
      expect(r4, isNotNull);
      expect(r4!.dB, closeTo(-0.05, 0.0001));
    });

    test('parses raw peak ratios without dB units', () {
      final r1 = toRatio('0.95');
      expect(r1, isNotNull);
      expect(r1!.ratio, closeTo(0.95, 0.0001));
      expect(r1.dB, isNull);

      final r2 = toRatio('1.025');
      expect(r2, isNotNull);
      expect(r2!.ratio, closeTo(1.025, 0.0001));
      expect(r2.dB, isNull);
    });

    test('rejects invalid ReplayGain strings (NaN, Infinity, trailing text, empty)', () {
      for (final invalid in [
        '',
        ' ',
        '   ',
        'NaN',
        'NaN dB',
        'Infinity',
        '+Infinity dB',
        '-Infinity dB',
        'abc dB',
        '1.23.45 dB',
        '1.23 foo',
        'dB',
      ]) {
        expect(toRatio(invalid), isNull, reason: '$invalid should return null');
      }
    });

    test('maps FLAC Vorbis, APEv2, and ID3v2 ReplayGain tags to common tags', () {
      final vorbisMapper = FlacVorbisTagMapper();
      final vorbisMapped = vorbisMapper.mapTags({
        'REPLAYGAIN_TRACK_GAIN': '-7.03 dB',
        'REPLAYGAIN_TRACK_PEAK': '0.95',
      });
      expect(vorbisMapped['replaygain_track_gain'], isNotNull);
      expect((vorbisMapped['replaygain_track_gain'] as Ratio).dB, closeTo(-7.03, 0.001));
      expect((vorbisMapped['replaygain_track_peak'] as Ratio).ratio, closeTo(0.95, 0.001));

      final apeMapper = Apev2TagMapper();
      final apeMapped = apeMapper.mapTags({
        'REPLAYGAIN_ALBUM_GAIN': '-8.12 dB',
        'REPLAYGAIN_ALBUM_PEAK': '0.98',
      });
      expect((apeMapped['replaygain_album_gain'] as Ratio).dB, closeTo(-8.12, 0.001));
      expect((apeMapped['replaygain_album_peak'] as Ratio).ratio, closeTo(0.98, 0.001));

      final id3Mapper = Id3v2TagMapper();
      final id3Mapped = id3Mapper.mapTags({
        'TXXX:REPLAYGAIN_TRACK_GAIN': '+1.50 dB',
      });
      expect((id3Mapped['replaygain_track_gain'] as Ratio).dB, closeTo(1.5, 0.001));
    });

    test('emits MetadataEvent.commonTag events for ReplayGain gain and peak', () {
      final mapper = CombinedTagMapper()
        ..registerMapper('ID3v2.4', Id3v2TagMapper());
      final events = <MetadataEvent>[];
      final collector = MetadataCollector(mapper, ParseOptions(observer: events.add));

      collector.addNativeTag('ID3v2.4', 'TXXX:REPLAYGAIN_TRACK_GAIN', '-6.50 dB');
      collector.addNativeTag('ID3v2.4', 'TXXX:REPLAYGAIN_TRACK_PEAK', '0.975');

      final gainEvents = events.where((e) => e.tag?.id == MetadataCommonId.replaygainTrackGain).toList();
      expect(gainEvents, hasLength(1));
      final gainRatio = gainEvents.first.tag!.value! as Ratio;
      expect(gainRatio.dB, closeTo(-6.5, 0.001));

      final peakEvents = events.where((e) => e.tag?.id == MetadataCommonId.replaygainTrackPeak).toList();
      expect(peakEvents, hasLength(1));
      final peakRatio = peakEvents.first.tag!.value! as Ratio;
      expect(peakRatio.ratio, closeTo(0.975, 0.001));
    });
  });

  group('AudioMetadataCache Serialization Round-Trip', () {
    late Directory testCacheDir;

    setUpAll(() async {
      testCacheDir = await Directory.systemTemp.createTemp(
        'metadata_audio_cache_v12_test_',
      );
      AudioMetadataCache.overrideDirForTesting = testCacheDir;
      AudioMetadataCache.overrideHasIoForTesting = true;
    });

    tearDownAll(() async {
      AudioMetadataCache.overrideDirForTesting = null;
      AudioMetadataCache.overrideHasIoForTesting = null;
      if (testCacheDir.existsSync()) {
        await testCacheDir.delete(recursive: true);
      }
    });

    setUp(() async {
      AudioMetadataCache.enabled = false;
      await AudioMetadataCache.clearCache();
    });

    test('round-trips compilation, copyright, lyrics list, tagTypes, and ReplayGain', () async {
      const original = AudioMetadata(
        format: Format(
          container: 'WAVE',
          codec: 'PCM',
          tagTypes: ['ID3v2.4', 'ID3v1'],
          bitsPerSample: 24,
          lossless: true,
          numberOfChannels: 2,
          sampleRate: 48000,
        ),
        common: CommonTags(
          track: TrackNo(no: 1, of: 10),
          disk: TrackNo(),
          movementIndex: TrackNo(),
          title: 'Cached Song',
          compilation: true,
          copyright: '(C) 2026 Test Studio Records',
          lyrics: [
            LyricsTag(
              text: 'Main lyric text',
              contentType: 'lyrics',
              timeStampFormat: 'none',
              language: 'eng',
              descriptor: 'Original',
              syncText: [
                LyricsText(text: 'Line 1', timestamp: 1000),
                LyricsText(text: 'Line 2', timestamp: 2500),
              ],
            ),
            LyricsTag(
              text: 'Translated lyrics text',
              contentType: 'lyrics',
              timeStampFormat: 'none',
              syncText: [],
              language: 'deu',
              descriptor: 'German Translation',
            ),
          ],
          replaygain_track_gain: Ratio(dB: -6.5, ratio: 0.22),
          replaygain_track_peak: Ratio(ratio: 0.98),
          replaygain_album_gain: Ratio(dB: -7.2, ratio: 0.19),
          replaygain_album_peak: Ratio(ratio: 0.99),
        ),
        quality: QualityInformation(warnings: [
          ParserWarning(message: 'Sample test warning'),
        ]),
        native: {
          'matroska': [
            Tag(id: 'track:ALBUM', value: 'Flat Album'),
            Tag(id: 'track:COMPOSER', value: 'Hans Zimmer'),
          ],
        },
      );

      await AudioMetadataCache.putMetadata('test-v12-cache-key', original);
      final cached = await AudioMetadataCache.getMetadata('test-v12-cache-key');

      expect(cached, isNotNull);
      expect(cached!.format.container, 'WAVE');
      expect(cached.format.codec, 'PCM');
      expect(cached.format.bitsPerSample, 24);
      expect(cached.format.lossless, isTrue);
      expect(cached.format.tagTypes, equals(['ID3v2.4', 'ID3v1']));

      expect(cached.common.title, 'Cached Song');
      expect(cached.common.compilation, isTrue);
      expect(cached.common.copyright, '(C) 2026 Test Studio Records');

      expect(cached.common.lyrics, hasLength(2));
      final lyric1 = cached.common.lyrics![0];
      expect(lyric1.text, 'Main lyric text');
      expect(lyric1.language, 'eng');
      expect(lyric1.descriptor, 'Original');
      expect(lyric1.syncText, hasLength(2));
      expect(lyric1.syncText[0].text, 'Line 1');
      expect(lyric1.syncText[0].timestamp, 1000);

      final lyric2 = cached.common.lyrics![1];
      expect(lyric2.text, 'Translated lyrics text');
      expect(lyric2.language, 'deu');
      expect(lyric2.descriptor, 'German Translation');

      expect(cached.common.replaygain_track_gain!.dB, closeTo(-6.5, 0.001));
      expect(cached.common.replaygain_track_gain!.ratio, closeTo(0.22, 0.001));
      expect(cached.common.replaygain_track_peak!.ratio, closeTo(0.98, 0.001));
      expect(cached.common.replaygain_album_gain!.dB, closeTo(-7.2, 0.001));
      expect(cached.common.replaygain_album_peak!.ratio, closeTo(0.99, 0.001));

      expect(cached.native['matroska'], hasLength(2));
      expect(cached.native['matroska']!.first.id, 'track:ALBUM');
      expect(cached.quality.warnings, hasLength(1));
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

List<int> _buildId3v24Tag(Map<String, String> textFrames) {
  final frames = <int>[];
  for (final entry in textFrames.entries) {
    final payload = <int>[0x03, ...utf8.encode(entry.value)];
    final len = payload.length;
    final size = <int>[
      (len >> 21) & 0x7F,
      (len >> 14) & 0x7F,
      (len >> 7) & 0x7F,
      len & 0x7F,
    ];
    frames.addAll(ascii.encode(entry.key));
    frames.addAll(size);
    frames.addAll([0x00, 0x00]); // flags
    frames.addAll(payload);
  }

  final totalSize = frames.length;
  final syncsafeSize = <int>[
    (totalSize >> 21) & 0x7F,
    (totalSize >> 14) & 0x7F,
    (totalSize >> 7) & 0x7F,
    totalSize & 0x7F,
  ];

  return <int>[
    0x49, 0x44, 0x33, // 'ID3'
    0x04, 0x00, // v2.4
    0x00, // flags
    ...syncsafeSize,
    ...frames,
  ];
}

List<int> _atom(String name, List<int> payload) {
  final length = payload.length + 8;
  return <int>[..._u32be(length), ...ascii.encode(name), ...payload];
}

List<int> _mvhdPayload({required int timeScale, required int duration}) {
  final data = ByteData(100);
  data.setUint8(0, 0); // version
  data.setUint32(12, timeScale);
  data.setUint32(16, duration);
  data.setUint32(20, 0x00010000); // rate
  data.setUint16(24, 0x0100); // volume
  data.setUint32(96, 2); // nextTrackId
  return data.buffer.asUint8List();
}

List<int> _tkhdPayload({required int trackId}) {
  final data = ByteData(84);
  data.setUint32(12, trackId);
  return data.buffer.asUint8List();
}

List<int> _mdhdPayload({required int timeScale, required int duration}) {
  final data = ByteData(24);
  data.setUint32(12, timeScale);
  data.setUint32(16, duration);
  return data.buffer.asUint8List();
}

List<int> _hdlrPayload(String componentSubtype) {
  final data = ByteData(24);
  final encoded = ascii.encode(componentSubtype);
  for (var i = 0; i < 4; i++) {
    data.setUint8(8 + i, encoded[i]);
  }
  return data.buffer.asUint8List();
}

List<int> _stsdPayloadMp4a(int channelConfig, {bool truncated = false}) {
  List<int> esdsAtom;
  if (truncated) {
    esdsAtom = _atom('esds', <int>[0, 0, 0, 0, 0x03, 0x02]);
  } else {
    const ascByte0 = 0x12;
    final ascByte1 = ((4 & 1) << 7) | ((channelConfig & 0x0F) << 3);
    final ascPayload = <int>[ascByte0, ascByte1];
    final desc5 = <int>[0x05, ascPayload.length, ...ascPayload];
    final decConfigPayload = <int>[
      0x40,
      0x15,
      0x00, 0x00, 0x00,
      0x00, 0x01, 0xF4, 0x00,
      0x00, 0x01, 0xF4, 0x00,
      ...desc5,
    ];
    final desc4 = <int>[0x04, decConfigPayload.length, ...decConfigPayload];
    final esDescPayload = <int>[
      0x00, 0x01,
      0x00,
      ...desc4,
    ];
    final desc3 = <int>[0x03, esDescPayload.length, ...esDescPayload];
    esdsAtom = _atom('esds', <int>[0, 0, 0, 0, ...desc3]);
  }

  final sampleEntry = <int>[
    ..._u32be(28 + 8 + esdsAtom.length),
    ...ascii.encode('mp4a'),
    ...List<int>.filled(6, 0),
    0, 1,
    ...List<int>.filled(8, 0),
    0, 2, // 2 channels default
    0, 16,
    0, 0, 0, 0,
    ..._u32be(44100 << 16),
    ...esdsAtom,
  ];

  return <int>[0, 0, 0, 0, ..._u32be(1), ...sampleEntry];
}

List<int> _buildSyntheticMp4WithEsds(int channelConfig, {bool truncated = false}) {
  final ftyp = _atom('ftyp', <int>[
    ...ascii.encode('M4A '),
    ...ascii.encode('isom'),
    ...ascii.encode('mp42'),
  ]);

  final mvhd = _atom('mvhd', _mvhdPayload(timeScale: 1000, duration: 2000));
  final tkhd = _atom('tkhd', _tkhdPayload(trackId: 1));
  final mdhd = _atom('mdhd', _mdhdPayload(timeScale: 44100, duration: 88200));
  final hdlr = _atom('hdlr', _hdlrPayload('soun'));
  final stsd = _atom('stsd', _stsdPayloadMp4a(channelConfig, truncated: truncated));
  final stbl = _atom('stbl', stsd);
  final minf = _atom('minf', stbl);
  final mdia = _atom('mdia', <int>[...mdhd, ...hdlr, ...minf]);
  final trak = _atom('trak', <int>[...tkhd, ...mdia]);
  final moov = _atom('moov', <int>[...mvhd, ...trak]);

  return <int>[...ftyp, ...moov];
}
