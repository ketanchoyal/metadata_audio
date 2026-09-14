import 'dart:typed_data';

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
  static Uint8List buildM4a({
    required List<int> rawStsdBox,
    required List<int> sampleSizes,
    required int timeScale,
    required int sampleDuration,
    required Uint8List rawAudioData,
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

    // 5. Build moov with stco placeholder (offset = 0) to measure header size
    var moovBox = _buildMoov(
      rawStsdBox: rawStsdBox,
      sttsBox: sttsBox,
      stscBox: stscBox,
      stszBox: stszBox,
      chunkOffset: 0,
      timeScale: timeScale,
      totalDuration: totalDuration,
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
      ..add(const [0x53, 0x6F, 0x75, 0x6E, 0x64, 0x48, 0x61, 0x6E, 0x64, 0x6C, 0x65, 0x72, 0x00]); // 'SoundHandler\0'
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
      0x00, 0x01, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0x00, 0x01, 0x00, 0x00, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0, 0x40, 0x00, 0x00, 0x00,
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
    return _makeBox('moov', moovBuilder.takeBytes());
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
