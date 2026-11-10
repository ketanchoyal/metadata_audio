import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/model/types.dart';

/// Pure-Dart ISO Base Media File Format (ISOBMFF / MP4 / M4A) muxer.
///
/// Wraps raw AAC audio frames (as stored in MP4/M4B audio tracks)
/// into a standalone, seekable, Chromecast- and player-compatible `.m4a` file.
class M4aMuxer {
  M4aMuxer._();

  /// Builds a complete `.m4a` container file from extracted AAC samples.
  ///
  /// - [rawStsdBox]: The complete original `stsd` atom bytes
  ///   (including 4-byte size + 'stsd' header).
  /// - [sampleSizes]: The byte length of each AAC sample in the chapter.
  /// - [timeScale]: The timescale of the audio track (e.g., 44100).
  /// - [sampleDuration]: Duration of each sample in timescale units
  ///   (standard AAC is 1024).
  /// - [rawAudioData]: The concatenated raw AAC audio sample bytes.
  /// - [rawUdtaBox]: Optional complete `udta` box bytes copied from the
  ///   original container to preserve iTunes/MP4 metadata and cover art.
  /// - [rawMetaBox]: Optional complete `moov.meta` box bytes copied from the
  ///   original container when metadata sits directly under `moov`.
  static Uint8List buildM4a({
    required List<int> rawStsdBox,
    required List<int> sampleSizes,
    required int timeScale,
    required int sampleDuration,
    required Uint8List rawAudioData,
    List<int>? rawUdtaBox,
    List<int>? rawMetaBox,
  }) {
    final sampleCount = sampleSizes.length;
    final totalDuration = sampleCount * sampleDuration;

    // 1. ftyp box
    // Major brand: M4A , minor version: 0x00000200,
    // compatible brands: M4A , mp42, isom
    final ftypPayload = BytesBuilder(copy: false)
      ..add(const [0x4D, 0x34, 0x41, 0x20]) // 'M4A '
      ..add(const [0x00, 0x00, 0x02, 0x00]) // minor version
      ..add(const [0x4D, 0x34, 0x41, 0x20]) // 'M4A '
      ..add(const [0x6D, 0x70, 0x34, 0x32]) // 'mp42'
      ..add(const [0x69, 0x73, 0x6F, 0x6D]); // 'isom'
    final ftypBox = _makeBox('ftyp', ftypPayload.takeBytes());

    // 2. stts box (Time-to-sample table)
    // 1 entry: count = sampleCount, duration = sampleDuration
    final sttsBuilder = BytesBuilder(copy: false)
      ..add(const [0, 0, 0, 0]) // version + flags
      ..add(_uint32Be(1)) // entry count = 1
      ..add(_uint32Be(sampleCount))
      ..add(_uint32Be(sampleDuration));
    final sttsBox = _makeBox('stts', sttsBuilder.takeBytes());

    // 3. stsc box (Sample-to-chunk table)
    // 1 entry: first_chunk=1, samples_per_chunk=sampleCount,
    // sample_description_index=1
    final stscBuilder = BytesBuilder(copy: false)
      ..add(const [0, 0, 0, 0]) // version + flags
      ..add(_uint32Be(1)) // entry count = 1
      ..add(_uint32Be(1)) // first_chunk = 1
      ..add(_uint32Be(sampleCount)) // samples_per_chunk
      ..add(_uint32Be(1)); // sample_description_index
    final stscBox = _makeBox('stsc', stscBuilder.takeBytes());

    // 4. stsz box (Sample size table)
    final stszBuilder = BytesBuilder(copy: false)
      ..add(const [0, 0, 0, 0]) // version + flags
      ..add(const [0, 0, 0, 0]) // uniform sample_size = 0 (variable)
      ..add(_uint32Be(sampleCount));
    for (final size in sampleSizes) {
      stszBuilder.add(_uint32Be(size));
    }
    final stszBox = _makeBox('stsz', stszBuilder.takeBytes());

    final safeUdta = rawUdtaBox == null
        ? null
        : sanitizeUdtaForSlice(rawUdtaBox);
    final safeMeta = rawMetaBox == null
        ? null
        : sanitizeMetaForSlice(rawMetaBox);

    // 5. Build moov with stco placeholder (offset = 0) to measure header size
    var moovBox = _buildMoov(
      rawStsdBox: rawStsdBox,
      sttsBox: sttsBox,
      stscBox: stscBox,
      stszBox: stszBox,
      chunkOffset: 0,
      timeScale: timeScale,
      totalDuration: totalDuration,
      rawUdtaBox: safeUdta,
      rawMetaBox: safeMeta,
    );

    // 6. Calculate exact mdat payload offset
    // Total header = ftypBox + moovBox + mdat header (8 bytes)
    final headerSize = ftypBox.length + moovBox.length;
    final mdatPayloadOffset = headerSize + 8;

    // 7. Rebuild moov with the exact chunk offset
    moovBox = _buildMoov(
      rawStsdBox: rawStsdBox,
      sttsBox: sttsBox,
      stscBox: stscBox,
      stszBox: stszBox,
      chunkOffset: mdatPayloadOffset,
      timeScale: timeScale,
      totalDuration: totalDuration,
      rawUdtaBox: safeUdta,
      rawMetaBox: safeMeta,
    );

    // 8. mdat box
    final mdatBox = _makeBox('mdat', rawAudioData);

    // 9. Combine all boxes
    final result = BytesBuilder(copy: false)
      ..add(ftypBox)
      ..add(moovBox)
      ..add(mdatBox);

    return result.takeBytes();
  }

  static Uint8List _buildMoov({
    required List<int> rawStsdBox,
    required Uint8List sttsBox,
    required Uint8List stscBox,
    required Uint8List stszBox,
    required int chunkOffset,
    required int timeScale,
    required int totalDuration,
    List<int>? rawUdtaBox,
    List<int>? rawMetaBox,
  }) {
    // stco box
    final stcoBuilder = BytesBuilder(copy: false)
      ..add(const [0, 0, 0, 0]) // version + flags
      ..add(_uint32Be(1)) // entry count = 1 chunk
      ..add(_uint32Be(chunkOffset));
    final stcoBox = _makeBox('stco', stcoBuilder.takeBytes());

    // stbl box
    final stblBuilder = BytesBuilder(copy: false)
      ..add(rawStsdBox)
      ..add(sttsBox)
      ..add(stscBox)
      ..add(stszBox)
      ..add(stcoBox);
    final stblBox = _makeBox('stbl', stblBuilder.takeBytes());

    // dinf / dref box
    // self-contained flag = 1
    final urlBox = _makeBox('url ', const [0, 0, 0, 1]);
    final drefBuilder = BytesBuilder(copy: false)
      ..add(const [0, 0, 0, 0]) // version + flags
      ..add(_uint32Be(1)) // entry count = 1
      ..add(urlBox);
    final drefBox = _makeBox('dref', drefBuilder.takeBytes());
    final dinfBox = _makeBox('dinf', drefBox);

    // smhd box (Sound Media Header)
    final smhdBox = _makeBox('smhd', const [0, 0, 0, 0, 0, 0, 0, 0]);

    // minf box
    final minfBuilder = BytesBuilder(copy: false)
      ..add(smhdBox)
      ..add(dinfBox)
      ..add(stblBox);
    final minfBox = _makeBox('minf', minfBuilder.takeBytes());

    // hdlr box (Sound Handler)
    final hdlrBuilder = BytesBuilder(copy: false)
      ..add(const [0, 0, 0, 0]) // version + flags
      ..add(const [0, 0, 0, 0]) // component type
      ..add(const [0x73, 0x6F, 0x75, 0x6E]) // 'soun'
      ..add(List<int>.filled(12, 0)) // manufacturer + flags
      ..add(const [
        0x53,
        0x6F,
        0x75,
        0x6E,
        0x64,
        0x48,
        0x61,
        0x6E,
        0x64,
        0x6C,
        0x65,
        0x72,
        0x00,
      ]); // 'SoundHandler\0'
    final hdlrBox = _makeBox('hdlr', hdlrBuilder.takeBytes());

    // mdhd box
    final mdhdBuilder = BytesBuilder(copy: false)
      ..add(const [0, 0, 0, 0]) // version + flags
      ..add(const [0, 0, 0, 0]) // creation time
      ..add(const [0, 0, 0, 0]) // modification time
      ..add(_uint32Be(timeScale))
      ..add(_uint32Be(totalDuration))
      ..add(const [0x55, 0xC4]) // language: 'und' (0x55C4)
      ..add(const [0, 0]); // quality
    final mdhdBox = _makeBox('mdhd', mdhdBuilder.takeBytes());

    // mdia box
    final mdiaBuilder = BytesBuilder(copy: false)
      ..add(mdhdBox)
      ..add(hdlrBox)
      ..add(minfBox);
    final mdiaBox = _makeBox('mdia', mdiaBuilder.takeBytes());

    // tkhd box (Track Header)
    // Flags: track_enabled (1) | track_in_movie (2) | track_in_preview (4) = 7
    final unityMatrix = <int>[
      0x00,
      0x01,
      0x00,
      0x00,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0x00,
      0x01,
      0x00,
      0x00,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0x40,
      0x00,
      0x00,
      0x00,
    ];
    final tkhdBuilder = BytesBuilder(copy: false)
      ..add(const [0, 0, 0, 7]) // version + flags (enabled, in movie)
      ..add(const [0, 0, 0, 0]) // creation time
      ..add(const [0, 0, 0, 0]) // modification time
      ..add(_uint32Be(1)) // track ID = 1
      ..add(const [0, 0, 0, 0]) // reserved
      ..add(_uint32Be(totalDuration))
      ..add(const [0, 0, 0, 0, 0, 0, 0, 0]) // reserved
      ..add(const [0, 0]) // layer
      ..add(const [0, 0]) // alternate group
      ..add(const [0x01, 0x00]) // volume (1.0 = 0x0100)
      ..add(const [0, 0]) // reserved
      ..add(unityMatrix)
      ..add(const [0, 0, 0, 0, 0, 0, 0, 0]); // width, height (0 for audio)
    final tkhdBox = _makeBox('tkhd', tkhdBuilder.takeBytes());

    // trak box
    final trakBuilder = BytesBuilder(copy: false)
      ..add(tkhdBox)
      ..add(mdiaBox);
    final trakBox = _makeBox('trak', trakBuilder.takeBytes());

    // mvhd box (Movie Header)
    final mvhdBuilder = BytesBuilder(copy: false)
      ..add(const [0, 0, 0, 0]) // version + flags
      ..add(const [0, 0, 0, 0]) // creation time
      ..add(const [0, 0, 0, 0]) // modification time
      ..add(_uint32Be(timeScale))
      ..add(_uint32Be(totalDuration))
      ..add(const [0x00, 0x01, 0x00, 0x00]) // rate 1.0
      ..add(const [0x01, 0x00]) // volume 1.0
      ..add(const [0, 0]) // reserved
      ..add(List<int>.filled(8, 0)) // reserved
      ..add(unityMatrix)
      ..add(List<int>.filled(24, 0)) // pre-defined
      ..add(_uint32Be(2)); // next track ID = 2
    final mvhdBox = _makeBox('mvhd', mvhdBuilder.takeBytes());

    // moov box
    final moovBuilder = BytesBuilder(copy: false)
      ..add(mvhdBox)
      ..add(trakBox);
    if (rawUdtaBox != null && rawUdtaBox.isNotEmpty) {
      moovBuilder.add(rawUdtaBox);
    }
    if (rawMetaBox != null && rawMetaBox.isNotEmpty) {
      moovBuilder.add(rawMetaBox);
    }
    return _makeBox('moov', moovBuilder.takeBytes());
  }

  static const Set<String> _unsafeUdtaChildren = <String>{
    'chpl', // Nero chapter list
    'chap', // QuickTime chapter reference
    'tref', // Track references
    'tmcd', // Timecode
    'elst', // Edit list
    'edts', // Edit container
    'hnti', // Hint info
    'rtp ', // RTP hint
    'AllF', // QuickTime play all frames
    'SelO', // QuickTime play selection only
    'WLOC', // QuickTime window location
    'ptv ', // QuickTime print to video
  };

  static const Set<String> _unsafeIlstAtoms = <String>{
    'pgap', // Gapless playback flag tied to original stream
  };

  static const Set<String> _unsafeCustomAtomNames = <String>{
    'itunsmpb', // Original file AAC sample count & encoder delay/padding
    'itunpgap',
    'overdrive mediamarkers',
    'chapters',
  };

  /// Sanitizes a `udta` box for a standalone sliced chapter `.m4a`:
  /// removes chapter lists (`chpl`), edit/hint/playback-state boxes, and
  /// unsafe `meta/ilst` atoms (`pgap`, `iTunSMPB`, chapter XML, etc.), while
  /// preserving cover art (`covr`) and safe descriptive metadata.
  ///
  /// Returns `null` if no valid metadata remains.
  static Uint8List? sanitizeUdtaForSlice(List<int> udtaBytes) =>
      _sanitizeContainer(udtaBytes, expectedType: 'udta');

  /// Sanitizes a `meta` box for a standalone sliced chapter `.m4a`.
  ///
  /// Returns `null` if no valid metadata remains.
  static Uint8List? sanitizeMetaForSlice(List<int> metaBytes) =>
      _sanitizeMetaBox(metaBytes);

  static Uint8List? _sanitizeContainer(
    List<int> boxBytes, {
    required String expectedType,
  }) {
    final parsed = _readBoxBounds(boxBytes);
    if (parsed == null) return null;
    final (headerLen, totalLen, boxType) = parsed;
    if (boxType != expectedType) return Uint8List.fromList(boxBytes);

    final keptChildren = BytesBuilder(copy: false);
    var offset = headerLen;
    while (offset + 8 <= totalLen) {
      final childBounds = _readBoxBounds(boxBytes, offset: offset, limit: totalLen);
      if (childBounds == null) break;
      final (childHeader, childLen, childType) = childBounds;
      if (childLen < childHeader || offset + childLen > totalLen) break;

      final childBytes = boxBytes.sublist(offset, offset + childLen);
      if (!_unsafeUdtaChildren.contains(childType)) {
        if (childType == 'meta') {
          final cleanMeta = _sanitizeMetaBox(childBytes);
          if (cleanMeta != null) keptChildren.add(cleanMeta);
        } else {
          keptChildren.add(childBytes);
        }
      }
      offset += childLen;
    }

    final payload = keptChildren.takeBytes();
    if (payload.isEmpty) return null;
    return _makeBox(boxType, payload);
  }

  static Uint8List? _sanitizeMetaBox(List<int> metaBytes) {
    final parsed = _readBoxBounds(metaBytes);
    if (parsed == null) return null;
    final (headerLen, totalLen, boxType) = parsed;
    if (boxType != 'meta') return Uint8List.fromList(metaBytes);

    var cursor = headerLen;
    var hasFullBoxPrefix = false;
    if (cursor + 8 <= totalLen) {
      final probeName = String.fromCharCodes(
        metaBytes.sublist(cursor + 4, cursor + 8),
      );
      if (probeName != 'hdlr') {
        hasFullBoxPrefix = true;
        cursor += 4;
      }
    }

    final keptChildren = BytesBuilder(copy: false);
    if (hasFullBoxPrefix) {
      keptChildren.add(metaBytes.sublist(headerLen, headerLen + 4));
    }

    var hasIlstOrTags = false;
    while (cursor + 8 <= totalLen) {
      final childBounds = _readBoxBounds(metaBytes, offset: cursor, limit: totalLen);
      if (childBounds == null) break;
      final (childHeader, childLen, childType) = childBounds;
      if (childLen < childHeader || cursor + childLen > totalLen) break;

      final childBytes = metaBytes.sublist(cursor, cursor + childLen);
      if (_unsafeUdtaChildren.contains(childType)) {
        cursor += childLen;
        continue;
      }
      if (childType == 'ilst') {
        final cleanIlst = _sanitizeIlstBox(childBytes);
        if (cleanIlst != null) {
          keptChildren.add(cleanIlst);
          hasIlstOrTags = true;
        }
      } else {
        keptChildren.add(childBytes);
        if (childType != 'hdlr') hasIlstOrTags = true;
      }
      cursor += childLen;
    }

    if (!hasIlstOrTags) return null;
    return _makeBox('meta', keptChildren.takeBytes());
  }

  static Uint8List? _sanitizeIlstBox(List<int> ilstBytes) {
    final parsed = _readBoxBounds(ilstBytes);
    if (parsed == null) return null;
    final (headerLen, totalLen, boxType) = parsed;
    if (boxType != 'ilst') return Uint8List.fromList(ilstBytes);

    final kept = BytesBuilder(copy: false);
    var offset = headerLen;
    while (offset + 8 <= totalLen) {
      final childBounds = _readBoxBounds(ilstBytes, offset: offset, limit: totalLen);
      if (childBounds == null) break;
      final (childHeader, childLen, childType) = childBounds;
      if (childLen < childHeader || offset + childLen > totalLen) break;

      final itemBytes = ilstBytes.sublist(offset, offset + childLen);
      if (!_isUnsafeIlstItem(childType, itemBytes, childHeader)) {
        kept.add(itemBytes);
      }
      offset += childLen;
    }

    final payload = kept.takeBytes();
    if (payload.isEmpty) return null;
    return _makeBox('ilst', payload);
  }

  static bool _isUnsafeIlstItem(
    String itemType,
    List<int> itemBytes,
    int itemHeaderLen,
  ) {
    if (_unsafeIlstAtoms.contains(itemType)) return true;
    if (itemType != '----') return false;

    // Parse 'name' sub-atom inside '----' freeform atom.
    var offset = itemHeaderLen;
    while (offset + 8 <= itemBytes.length) {
      final sub = _readBoxBounds(itemBytes, offset: offset, limit: itemBytes.length);
      if (sub == null) break;
      final (subHeader, subLen, subType) = sub;
      if (subLen < subHeader || offset + subLen > itemBytes.length) break;
      if (subType == 'name' && subLen > subHeader + 4) {
        final name = utf8
            .decode(
              itemBytes.sublist(offset + subHeader + 4, offset + subLen),
              allowMalformed: true,
            )
            .trim()
            .toLowerCase();
        if (_unsafeCustomAtomNames.contains(name) ||
            name.contains('chapter') ||
            name.contains('mediamarkers')) {
          return true;
        }
      }
      offset += subLen;
    }
    return false;
  }

  static (int headerLen, int totalLen, String type)? _readBoxBounds(
    List<int> bytes, {
    int offset = 0,
    int? limit,
  }) {
    final end = limit ?? bytes.length;
    if (offset + 8 > end) return null;
    final boxSize = _readUint32Be(bytes, offset);
    var headerLen = 8;
    var totalLen = boxSize;
    if (boxSize == 1) {
      if (offset + 16 > end) return null;
      headerLen = 16;
      totalLen = _readUint64Be(bytes, offset + 8);
    } else if (boxSize == 0) {
      totalLen = end - offset;
    }
    if (totalLen < headerLen || offset + totalLen > end) return null;
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    return (headerLen, totalLen, type);
  }

  /// Builds an iTunes-compatible `udta -> meta -> hdlr + ilst` box from
  /// [AudioMetadata.common] as a fallback when raw `udta` bytes are absent.
  static Uint8List? buildUdtaFromMetadata(AudioMetadata metadata) {
    final c = metadata.common;
    final items = BytesBuilder(copy: false);

    void addTextItem(String atomName, String? value) {
      if (value == null || value.isEmpty) return;
      items.add(_makeIlstItem(atomName, 1, utf8.encode(value)));
    }

    addTextItem('©nam', c.title);
    addTextItem('©ART', c.artist);
    addTextItem('©alb', c.album);
    addTextItem('aART', c.albumartist);
    addTextItem('©day', c.date ?? c.year?.toString());
    if (c.genre != null && c.genre!.isNotEmpty) {
      addTextItem('©gen', c.genre!.join(', '));
    }
    if (c.comment != null && c.comment!.isNotEmpty) {
      final text = c.comment!.first.text;
      addTextItem('©cmt', text);
    }
    if (c.composer != null && c.composer!.isNotEmpty) {
      addTextItem('©wrt', c.composer!.join(', '));
    }
    addTextItem('©grp', c.grouping);
    if (c.description != null && c.description!.isNotEmpty) {
      addTextItem('desc', c.description!.join(', '));
    }
    addTextItem('ldes', c.longDescription);
    addTextItem('cprt', c.copyright);
    addTextItem('©too', c.encodedby ?? metadata.format.tool);

    if (c.track.no != null || c.track.of != null) {
      items.add(
        _makeIlstItem('trkn', 0, [
          0,
          0,
          ((c.track.no ?? 0) >> 8) & 0xFF,
          (c.track.no ?? 0) & 0xFF,
          ((c.track.of ?? 0) >> 8) & 0xFF,
          (c.track.of ?? 0) & 0xFF,
          0,
          0,
        ]),
      );
    }
    if (c.disk.no != null || c.disk.of != null) {
      items.add(
        _makeIlstItem('disk', 0, [
          0,
          0,
          ((c.disk.no ?? 0) >> 8) & 0xFF,
          (c.disk.no ?? 0) & 0xFF,
          ((c.disk.of ?? 0) >> 8) & 0xFF,
          (c.disk.of ?? 0) & 0xFF,
        ]),
      );
    }
    if (c.compilation ?? false) {
      items.add(_makeIlstItem('cpil', 21, [1]));
    }
    if (c.bpm != null) {
      items.add(
        _makeIlstItem('tmpo', 21, [(c.bpm! >> 8) & 0xFF, c.bpm! & 0xFF]),
      );
    }
    if (c.picture != null) {
      for (final pic in c.picture!) {
        if (pic.data.isEmpty) continue;
        final isPng = pic.format.toLowerCase().contains('png');
        items.add(_makeIlstItem('covr', isPng ? 14 : 13, pic.data));
      }
    }

    final ilstPayload = items.takeBytes();
    if (ilstPayload.isEmpty) return null;

    final ilstBox = _makeBox('ilst', ilstPayload);
    final hdlrPayload = BytesBuilder(copy: false)
      ..add(const [0, 0, 0, 0]) // version + flags
      ..add(const [0, 0, 0, 0]) // component type
      ..add(const [0x6D, 0x64, 0x69, 0x72]) // 'mdir'
      ..add(const [0x61, 0x70, 0x70, 0x6C]) // 'appl'
      ..add(List<int>.filled(9, 0));
    final hdlrBox = _makeBox('hdlr', hdlrPayload.takeBytes());

    final metaPayload = BytesBuilder(copy: false)
      ..add(const [0, 0, 0, 0]) // FullBox version + flags
      ..add(hdlrBox)
      ..add(ilstBox);
    final metaBox = _makeBox('meta', metaPayload.takeBytes());
    return _makeBox('udta', metaBox);
  }

  static Uint8List _makeIlstItem(
    String name,
    int dataType,
    List<int> valueBytes,
  ) {
    final dataPayload = BytesBuilder(copy: false)
      ..add([
        0,
        (dataType >> 16) & 0xFF,
        (dataType >> 8) & 0xFF,
        dataType & 0xFF,
      ])
      ..add(const [0, 0, 0, 0]) // locale
      ..add(valueBytes);
    final dataBox = _makeBox('data', dataPayload.takeBytes());
    return _makeBoxLatin1(name, dataBox);
  }

  static Uint8List _makeBoxLatin1(String type, List<int> payload) {
    final length = payload.length + 8;
    final typeBytes = latin1.encode(type);
    final builder = BytesBuilder(copy: false)
      ..add(_uint32Be(length))
      ..add(typeBytes)
      ..add(payload);
    return builder.takeBytes();
  }

  static int _readUint32Be(List<int> b, int o) =>
      ((b[o] & 0xFF) << 24) |
      ((b[o + 1] & 0xFF) << 16) |
      ((b[o + 2] & 0xFF) << 8) |
      (b[o + 3] & 0xFF);

  static int _readUint64Be(List<int> b, int o) {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v = (v << 8) | (b[o + i] & 0xFF);
    }
    return v;
  }

  static Uint8List _makeBox(String type, List<int> payload) {
    final length = payload.length + 8;
    final typeBytes = [
      type.codeUnitAt(0),
      type.codeUnitAt(1),
      type.codeUnitAt(2),
      type.codeUnitAt(3),
    ];
    final builder = BytesBuilder(copy: false)
      ..add(_uint32Be(length))
      ..add(typeBytes)
      ..add(payload);
    return builder.takeBytes();
  }

  static List<int> _uint32Be(int value) => [
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];
}
