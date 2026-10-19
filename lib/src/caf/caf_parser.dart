/// CAF (Core Audio File) metadata parser, ported 1:1 from upstream
/// `lib/caf/CafParser.ts` (Borewit/music-metadata).
///
/// Ref: https://developer.apple.com/library/archive/documentation/MusicAudio/Reference/CAFSpec/CAF_spec/CAF_spec.html
library;

import 'package:metadata_audio/src/caf/caf_token.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

const int _editCountLength = 4;
const int _numEntriesLength = 4;

class _CodecInfo {
  const _CodecInfo(this.codec, this.lossless);

  final String codec;
  final bool lossless;
}

// Unrecognised mFormatID values are reported as-is, without claiming losslessness.
const Map<String, _CodecInfo> _codecByFormatId = <String, _CodecInfo>{
  'lpcm': _CodecInfo('PCM', true),
  'ima4': _CodecInfo('IMA4 ADPCM', false),
  'alac': _CodecInfo('ALAC', true),
  'flac': _CodecInfo('FLAC', true),
  'ulaw': _CodecInfo('ITU-T G.711 mu-law', false),
  'alaw': _CodecInfo('ITU-T G.711 A-law', false),
  '.mp1': _CodecInfo('MPEG-1 Layer I', false),
  '.mp2': _CodecInfo('MPEG-1 Layer II', false),
  '.mp3': _CodecInfo('MPEG-1 Layer III', false),
  'aac ': _CodecInfo('AAC', false),
  'aace': _CodecInfo('AAC', false),
  'aacf': _CodecInfo('AAC', false),
  'aacg': _CodecInfo('AAC', false),
  'aach': _CodecInfo('AAC', false),
  'aacl': _CodecInfo('AAC', false),
  'aacp': _CodecInfo('AAC', false),
};

class CafParser {
  CafParser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  AudioDescription? _desc;
  PacketTableHeader? _packetTable;
  int? _dataBytes;
  bool _expectedFirstChunk = true;
  bool _reachedEndOfFile = false;

  Future<void> parse() async {
    final header = CafFileHeader.parse(tokenizer.readBytes(CafFileHeader.length));
    if (header.fileType != 'caff') {
      throw CafContentError(
        "Invalid file-type, expected 'caff', found '${header.fileType}'",
      );
    }

    metadata.setFormat(container: 'CAF', hasAudio: true, hasVideo: false);

    while (!_reachedEndOfFile && !_endOfFileReached()) {
      CafChunkHeader chunkHeader;
      try {
        chunkHeader = CafChunkHeader.parse(
          tokenizer.readBytes(CafChunkHeader.length),
        );
      } on TokenizerException {
        // End-of-stream.
        break;
      }

      if (_expectedFirstChunk) {
        _expectedFirstChunk = false;
        if (chunkHeader.chunkType != 'desc') {
          throw CafContentError(
            "Expected an Audio Description chunk, found "
            "'${chunkHeader.chunkType}'",
          );
        }
      }
      await _readChunk(chunkHeader);
    }

    final desc = _desc;
    if (desc == null) {
      throw CafContentError('Missing Audio Description chunk');
    }
    _applyDerivedFormat();
  }

  bool _endOfFileReached() {
    final size = tokenizer.fileInfo?.size;
    return size != null && size - tokenizer.position < CafChunkHeader.length;
  }

  Future<void> _readChunk(CafChunkHeader header) async {
    switch (header.chunkType) {
      case 'desc':
        return _readAudioDescription(header.chunkSize);
      case 'pakt':
        return _readPacketTable(header.chunkSize);
      case 'data':
        return _readAudioData(header.chunkSize);
      case 'info':
        return _readInfo(header.chunkSize);
      case 'chan':
        return _readChannelLayout(header.chunkSize);
      default:
        return _skipUnknownChunk(header.chunkSize);
    }
  }

  Future<void> _readAudioDescription(int chunkSize) async {
    if (chunkSize < AudioDescription.length) {
      throw CafContentError(
        'Audio Description chunk size $chunkSize is smaller than '
        '${AudioDescription.length}',
      );
    }
    _desc = AudioDescription.parse(
      tokenizer.readBytes(AudioDescription.length),
    );
    final remaining = chunkSize - AudioDescription.length;
    if (remaining > 0) {
      tokenizer.skip(remaining);
    }
    _applyAudioDescription(_desc!);
  }

  void _applyAudioDescription(AudioDescription desc) {
    metadata.setFormat(
      sampleRate: desc.sampleRate.round(),
      numberOfChannels: desc.channelsPerFrame,
    );
    if (desc.bitsPerChannel > 0) {
      metadata.setFormat(bitsPerSample: desc.bitsPerChannel);
    }

    final codec = _codecByFormatId[desc.formatId];
    metadata.setFormat(codec: codec?.codec ?? desc.formatId);
    if (codec != null) {
      metadata.setFormat(lossless: codec.lossless);
    }
  }

  Future<void> _readPacketTable(int chunkSize) async {
    final desc = _desc;
    if (desc == null) {
      throw CafContentError(
        'Packet Table chunk found before the Audio Description chunk',
      );
    }
    if (chunkSize < PacketTableHeader.length) {
      throw CafContentError(
        'Packet Table chunk size $chunkSize is smaller than '
        '${PacketTableHeader.length}',
      );
    }
    final packetTable = PacketTableHeader.parse(
      tokenizer.readBytes(PacketTableHeader.length),
    );
    final body = await _readChunkBody(
      chunkSize - PacketTableHeader.length,
      'Packet Table',
    );
    decodePacketTableEntries(body, desc, packetTable.numberPackets);
    _packetTable = packetTable;
  }

  Future<void> _readAudioData(int chunkSize) async {
    if (chunkSize >= 0 && chunkSize < _editCountLength) {
      throw CafContentError(
        'Audio Data chunk size $chunkSize is too small to hold mEditCount',
      );
    }

    // Skip the 4-byte mEditCount field the body always starts with.
    tokenizer.skip(_editCountLength);

    if (chunkSize == -1) {
      // Audio Data runs to the end of the file, nothing can follow.
      _reachedEndOfFile = true;
      final size = tokenizer.fileInfo?.size;
      if (size == null) {
        // Cannot derive the number of audio bytes without the file size.
        return;
      }
      final dataBytes = size - tokenizer.position;
      tokenizer.skip(dataBytes);
      _dataBytes = dataBytes;
      return;
    }

    final dataBytes = chunkSize - _editCountLength;
    if (dataBytes < 0) {
      throw CafContentError(
        'Audio Data chunk size $chunkSize is too small to hold mEditCount',
      );
    }
    tokenizer.skip(dataBytes);
    _dataBytes = dataBytes;
  }

  Future<void> _readInfo(int chunkSize) async {
    if (chunkSize < _numEntriesLength) {
      throw CafContentError(
        'Information chunk size $chunkSize is too small to hold mNumEntries',
      );
    }
    final body = await _readChunkBody(chunkSize, 'Information');
    for (final (:key, :value)
        in parseInfoEntries(body).map((e) => (key: e.key, value: e.value))) {
      metadata.addNativeTag('CAF', key, value);
    }
  }

  Future<void> _readChannelLayout(int chunkSize) async {
    if (chunkSize < ChannelLayoutHeader.length) {
      throw CafContentError(
        'Channel Layout chunk size $chunkSize is smaller than '
        '${ChannelLayoutHeader.length}',
      );
    }
    final header = ChannelLayoutHeader.parse(
      tokenizer.readBytes(ChannelLayoutHeader.length),
    );

    final descriptionLength =
        header.numberChannelDescriptions * channelDescriptionLength;
    final bodyLength = ChannelLayoutHeader.length + descriptionLength;
    if (bodyLength > chunkSize) {
      throw CafContentError(
        'Channel Layout chunk declares ${header.numberChannelDescriptions} '
        'description(s) which exceed its size of $chunkSize',
      );
    }

    final descriptions = <ChannelDescription>[];
    if (descriptionLength > 0) {
      final body = await _readChunkBody(descriptionLength, 'Channel Layout');
      descriptions.addAll(
        parseChannelDescriptions(body, header.numberChannelDescriptions),
      );
    }

    metadata.addNativeTag('CAF', 'channelLayoutTag', header.channelLayoutTag);
    metadata.addNativeTag('CAF', 'channelLayoutBitmap', header.channelBitmap);
    if (descriptions.isNotEmpty) {
      // No common tag describes channel order so keep the complete
      // descriptions as a native tag.
      metadata.addNativeTag('CAF', 'channelLayoutDescriptions', descriptions);
    }

    final remaining = chunkSize - bodyLength;
    if (remaining > 0) {
      tokenizer.skip(remaining);
    }
  }

  /// Rejects a chunk whose declared size exceeds the remaining input. Only
  /// applicable when the total input size is known.
  void _validateChunkAvailability(int chunkSize, String chunkType) {
    final size = tokenizer.fileInfo?.size;
    if (size != null) {
      final available = size - tokenizer.position;
      if (chunkSize > available) {
        throw CafContentError(
          '$chunkType chunk size $chunkSize exceeds available input size '
          '$available',
        );
      }
    }
  }

  /// Reads a chunk body without trusting its declared size.
  Future<List<int>> _readChunkBody(int chunkSize, String chunkType) async {
    _validateChunkAvailability(chunkSize, chunkType);
    return tokenizer.readBytes(chunkSize);
  }

  Future<void> _skipUnknownChunk(int chunkSize) async {
    if (chunkSize < 0) {
      throw CafContentError(
        'Chunk size $chunkSize may only be -1 for an Audio Data chunk',
      );
    }
    tokenizer.skip(chunkSize);
  }

  /// Duration / sample count / bitrate are deferred until the whole file has
  /// been scanned, because the packet table and audio payload may arrive
  /// after the description.
  void _applyDerivedFormat() {
    final desc = _desc;
    if (desc == null || desc.sampleRate <= 0) {
      return;
    }

    final frames = _deriveFrameCount(desc);
    if (frames == null) {
      return;
    }

    final duration = frames / desc.sampleRate;
    metadata.setFormat(numberOfSamples: frames, duration: duration);

    final dataBytes = _dataBytes;
    if (dataBytes != null) {
      metadata.setFormat(bitrate: (8 * dataBytes) / duration);
    }
  }

  int? _deriveFrameCount(AudioDescription desc) {
    final packetTable = _packetTable;
    if (packetTable != null) {
      // Signed field, writers emit negative values. Already excludes priming
      // and remainder frames.
      if (packetTable.numberValidFrames > 0) {
        return packetTable.numberValidFrames;
      }
    }
    if (desc.bytesPerPacket > 0 &&
        desc.framesPerPacket > 0 &&
        _dataBytes != null) {
      final frames = (_dataBytes! * desc.framesPerPacket) / desc.bytesPerPacket;
      if (frames > 0) {
        return frames.floor();
      }
    }
    return null;
  }
}
