library;

import 'dart:convert';

import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/mp4/atom.dart';
import 'package:audio_metadata/src/mp4/atom_token.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

class Mp4Parser {
  Mp4Parser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  final Map<int, _TrackDescription> _tracks = <int, _TrackDescription>{};

  _TrackDescription? _currentTrack;
  bool _hasAudioTrack = false;
  bool _hasVideoTrack = false;
  int? _audioLengthInBytes;

  Future<void> parse() async {
    var remaining = tokenizer.fileInfo?.size;

    while (remaining == null || remaining > 0) {
      try {
        final probe = tokenizer.peekBytes(8);
        final probeName = ascii.decode(probe.sublist(4, 8), allowInvalid: true);
        if (probeName == '\x00\x00\x00\x00') {
          metadata.addWarning(
            'Error at offset=${tokenizer.position}: box.id=0',
          );
          break;
        }

        final atom = await Mp4Atom.readAtom(
          tokenizer,
          _handleAtom,
          null,
          remaining ?? 0x7FFFFFFF,
        );

        if (remaining != null) {
          if (atom.header.length == 0) {
            break;
          }
          remaining -= atom.header.length;
          if (remaining < 0) {
            break;
          }
        }
      } on TokenizerException {
        break;
      }
    }

    _postProcessTracks();
  }

  Future<void> _handleAtom(Mp4Atom atom, int payloadLength) async {
    switch (atom.header.name) {
      case 'ftyp':
        _parseFtyp(tokenizer.readBytes(payloadLength));
        return;
      case 'mvhd':
        _parseMvhd(tokenizer.readBytes(payloadLength));
        return;
      case 'tkhd':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseTkhd(tokenizer.readBytes(payloadLength));
        return;
      case 'mdhd':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseMdhd(tokenizer.readBytes(payloadLength));
        return;
      case 'hdlr':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseHdlr(tokenizer.readBytes(payloadLength));
        return;
      case 'stsd':
        if (!_isTrackScopedAtom(atom)) {
          tokenizer.skip(payloadLength);
          return;
        }
        _parseStsd(tokenizer.readBytes(payloadLength));
        return;
      case 'mdat':
        _audioLengthInBytes = payloadLength;
        tokenizer.skip(payloadLength);
        return;
      default:
        if (atom.parent?.header.name == 'ilst') {
          await _parseMetadataItem(atom, payloadLength);
        } else {
          tokenizer.skip(payloadLength);
        }
        return;
    }
  }

  bool _isTrackScopedAtom(Mp4Atom atom) {
    return atom.atomPath.startsWith('moov.trak.') ||
        atom.atomPath.contains('.trak.');
  }

  void _parseFtyp(List<int> payload) {
    final brands = AtomToken.parseFtypBrands(payload);
    if (brands.isEmpty) {
      return;
    }

    final orderedDistinct = <String>[];
    for (final brand in brands) {
      if (!orderedDistinct.contains(brand)) {
        orderedDistinct.add(brand);
      }
    }

    metadata.setFormat(container: orderedDistinct.join('/'));
  }

  void _parseMvhd(List<int> payload) {
    final mvhd = AtomToken.parseMvhd(payload);
    metadata.setFormat(
      creationTime: mvhd.creationTime,
      modificationTime: mvhd.modificationTime,
    );

    if (mvhd.timeScale > 0 && mvhd.duration > 0) {
      metadata.setFormat(duration: mvhd.duration / mvhd.timeScale);
    }
  }

  void _parseTkhd(List<int> payload) {
    if (payload.length < 24) {
      metadata.addWarning('Ignoring truncated tkhd atom');
      return;
    }

    final trackId = AtomToken.readUint32Be(payload, 12);
    final track = _tracks.putIfAbsent(
      trackId,
      () => _TrackDescription(trackId),
    );
    _currentTrack = track;
  }

  void _parseMdhd(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }

    final mdhd = AtomToken.parseMdhd(payload);
    track.timeScale = mdhd.timeScale;
    track.durationUnits = mdhd.duration;
  }

  void _parseHdlr(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }

    final handler = AtomToken.parseHandlerType(payload);
    track.handlerType = handler;

    if (handler == 'soun' || handler == 'audi') {
      _hasAudioTrack = true;
    }
    if (handler == 'vide') {
      _hasVideoTrack = true;
    }
  }

  void _parseStsd(List<int> payload) {
    final track = _currentTrack;
    if (track == null) {
      return;
    }

    final descriptions = AtomToken.parseStsd(payload);
    track.sampleDescriptions.addAll(descriptions);
  }

  Future<void> _parseMetadataItem(Mp4Atom itemAtom, int payloadLength) async {
    final itemPayloadEnd = tokenizer.position + payloadLength;

    final dataValues = <dynamic>[];
    String? mean;
    String? name;

    while (tokenizer.position < itemPayloadEnd) {
      final remaining = itemPayloadEnd - tokenizer.position;
      if (remaining < 8) {
        tokenizer.skip(remaining);
        break;
      }

      final child = await Mp4Atom.readAtom(
        tokenizer,
        (atom, atomPayloadLength) async {
          if (atom.header.name == 'data') {
            final data = AtomToken.parseDataAtom(
              tokenizer.readBytes(atomPayloadLength),
            );
            final value = _decodeDataValue(itemAtom.header.name, data);
            if (value != null) {
              dataValues.add(value);
            }
            return;
          }

          if (atom.header.name == 'mean') {
            mean = AtomToken.parseNameAtom(
              tokenizer.readBytes(atomPayloadLength),
            );
            return;
          }

          if (atom.header.name == 'name') {
            name = AtomToken.parseNameAtom(
              tokenizer.readBytes(atomPayloadLength),
            );
            return;
          }

          tokenizer.skip(atomPayloadLength);
        },
        itemAtom,
        remaining,
      );

      if (child.header.length == 0) {
        break;
      }
    }

    final tagKey = itemAtom.header.name == '----'
        ? _buildCustomTagKey(mean, name)
        : itemAtom.header.name;

    if (tagKey == null) {
      return;
    }

    for (final value in dataValues) {
      metadata.addNativeTag('iTunes', tagKey, value);
    }
  }

  dynamic _decodeDataValue(String tagKey, DataAtom dataAtom) {
    if (dataAtom.type.set != 0) {
      metadata.addWarning('Unsupported MP4 data atom set=${dataAtom.type.set}');
      return null;
    }

    final value = dataAtom.value;
    switch (dataAtom.type.type) {
      case 0:
        return _decodeTypeReserved(tagKey, value);
      case 1:
      case 18:
        return utf8.decode(value, allowMalformed: true);
      case 13:
        if (options.skipCovers) {
          return null;
        }
        return Picture(format: 'image/jpeg', data: List<int>.from(value));
      case 14:
        if (options.skipCovers) {
          return null;
        }
        return Picture(format: 'image/png', data: List<int>.from(value));
      case 21:
        return _readSignedBeInteger(value);
      case 22:
        return _readUnsignedBeInteger(value);
      case 65:
        return value.isEmpty ? null : value[0];
      case 66:
        return value.length < 2 ? null : AtomToken.readUint16Be(value, 0);
      case 67:
        return value.length < 4 ? null : AtomToken.readUint32Be(value, 0);
      default:
        metadata.addWarning(
          'Unknown MP4 data type ${dataAtom.type.type} for tag=$tagKey',
        );
        return null;
    }
  }

  dynamic _decodeTypeReserved(String tagKey, List<int> value) {
    switch (tagKey) {
      case 'trkn':
      case 'disk':
        if (value.length < 6) {
          return null;
        }
        final number = value[3];
        final total = value[5];
        return '$number/$total';
      case 'rate':
        return ascii.decode(value, allowInvalid: true).trim();
      default:
        return null;
    }
  }

  int? _readSignedBeInteger(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > 8) {
      return null;
    }
    var value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte & 0xFF);
    }
    final bits = bytes.length * 8;
    final signBit = BigInt.one << (bits - 1);
    if ((value & signBit) != BigInt.zero) {
      value -= BigInt.one << bits;
    }
    if (value > BigInt.from(0x7FFFFFFF) || value < BigInt.from(-0x80000000)) {
      return null;
    }
    return value.toInt();
  }

  int? _readUnsignedBeInteger(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > 8) {
      return null;
    }
    var value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte & 0xFF);
    }
    if (value > BigInt.from(0x7FFFFFFF)) {
      return null;
    }
    return value.toInt();
  }

  String? _buildCustomTagKey(String? mean, String? name) {
    final normalizedMean = mean?.trim();
    final normalizedName = name?.trim();
    if (normalizedMean == null || normalizedMean.isEmpty) {
      return null;
    }
    if (normalizedName == null || normalizedName.isEmpty) {
      return null;
    }
    return '----:$normalizedMean:$normalizedName';
  }

  void _postProcessTracks() {
    final audioTracks = _tracks.values.where((t) => t.isAudio).toList();
    final videoTracks = _tracks.values.where((t) => t.isVideo).toList();

    _hasAudioTrack = _hasAudioTrack || audioTracks.isNotEmpty;
    _hasVideoTrack = _hasVideoTrack || videoTracks.isNotEmpty;

    final primaryAudio = audioTracks.isNotEmpty ? audioTracks.first : null;
    if (primaryAudio != null) {
      final firstSample = primaryAudio.sampleDescriptions.isNotEmpty
          ? primaryAudio.sampleDescriptions.first
          : null;

      if (firstSample != null) {
        metadata.setFormat(
          codec: _formatCodec(firstSample.dataFormat),
          sampleRate: firstSample.sampleRate,
          bitsPerSample: firstSample.bitsPerSample,
          numberOfChannels: firstSample.numberOfChannels,
          lossless: _isLossless(firstSample.dataFormat),
        );
      }

      if (primaryAudio.timeScale != null &&
          primaryAudio.durationUnits != null &&
          primaryAudio.timeScale! > 0 &&
          primaryAudio.durationUnits! > 0) {
        metadata.setFormat(
          duration: primaryAudio.durationUnits! / primaryAudio.timeScale!,
        );
      }
    }

    final currentDuration = metadata.format.duration;
    final audioLength = _audioLengthInBytes;
    if (audioLength != null && currentDuration != null && currentDuration > 0) {
      metadata.setFormat(bitrate: 8 * audioLength / currentDuration);
    } else {
      final fileSize = tokenizer.fileInfo?.size;
      if (fileSize != null && currentDuration != null && currentDuration > 0) {
        metadata.setFormat(bitrate: 8 * fileSize / currentDuration);
      }
    }

    metadata.setFormat(hasAudio: _hasAudioTrack, hasVideo: _hasVideoTrack);
  }

  String _formatCodec(String dataFormat) {
    switch (dataFormat) {
      case 'mp4a':
        return 'MPEG-4/AAC';
      case 'alac':
        return 'ALAC';
      case 'ac-3':
        return 'AC-3';
      default:
        return dataFormat;
    }
  }

  bool _isLossless(String dataFormat) {
    switch (dataFormat) {
      case 'alac':
      case 'raw':
        return true;
      default:
        return false;
    }
  }
}

class _TrackDescription {
  _TrackDescription(this.trackId);

  final int trackId;
  String? handlerType;
  int? timeScale;
  int? durationUnits;
  final List<SampleDescription> sampleDescriptions = <SampleDescription>[];

  bool get isAudio => handlerType == 'soun' || handlerType == 'audi';
  bool get isVideo => handlerType == 'vide';
}
