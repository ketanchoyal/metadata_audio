library;

import 'dart:convert';

import 'package:metadata_audio/src/asf/asf_guid.dart';
import 'package:metadata_audio/src/asf/asf_object.dart';
import 'package:metadata_audio/src/asf/asf_util.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class AsfParser {
  AsfParser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  static const String _headerType = 'asf';

  final Map<int, AsfStreamPropertiesObject> _streams = {};
  final List<AsfCodecEntry> _codecs = [];
  final Map<int, AsfExtendedStreamPropertiesObject> _extendedStreams = {};
  final Map<int, int> _streamBitrates = {};

  Future<void> parse() async {
    final topLevelHeader = AsfTopLevelHeader.parse(
      tokenizer.readBytes(AsfTopLevelHeader.length),
    );

    if (!topLevelHeader.objectId.equals(AsfGuid.headerObject)) {
      throw AsfContentParseError(
        'expected ASF header but found ${topLevelHeader.objectId.str}',
      );
    }

    metadata.setFormat(container: 'ASF');
    await _parseObjectHeaders(topLevelHeader.numberOfHeaderObjects);
  }

  Future<void> _parseObjectHeaders(int numberOfObjectHeaders) async {
    var remainingHeaders = numberOfObjectHeaders;
    var hasAudio = false;
    var hasVideo = false;

    while (remainingHeaders > 0) {
      final header = AsfObjectHeader.parse(
        tokenizer.readBytes(AsfObjectHeader.length),
      );

      if (header.payloadSize < 0) {
        throw AsfContentParseError(
          'Invalid ASF header object size: ${header.objectSize}',
        );
      }

      switch (header.objectId.str) {
        case '8CABDCA1-A947-11CF-8EE4-00C00C205365':
          final fpo = AsfFilePropertiesObject.parse(
            tokenizer.readBytes(header.payloadSize),
          );

          final duration =
              fpo.playDuration.toDouble() / 10000000.0 -
              fpo.preroll.toDouble() / 1000.0;

          metadata.setFormat(
            duration: duration < 0 ? 0 : duration,
            bitrate: fpo.maximumBitrate,
          );
          break;

        case 'B7DC0791-A9B7-11CF-8EE6-00C00C205365':
          final stream = AsfStreamPropertiesObject.parse(
            tokenizer.readBytes(header.payloadSize),
          );

          _streams[stream.streamNumber ?? 0] = stream;

          if (stream.streamType != null) {
            metadata.setFormat(container: 'ASF/${stream.streamType}');
            if (stream.streamType == 'audio') {
              hasAudio = true;
            }
            if (stream.streamType == 'video') {
              hasVideo = true;
            }
            metadata.setFormat(hasAudio: hasAudio, hasVideo: hasVideo);
          }
          break;

        case '5FBF03B5-A92E-11CF-8EE3-00C00C205365':
          if (header.payloadSize < AsfHeaderExtensionObject.length) {
            throw AsfContentParseError('Header Extension payload too short');
          }

          final extHeader = AsfHeaderExtensionObject.parse(
            tokenizer.readBytes(AsfHeaderExtensionObject.length),
          );

          const alreadyConsumed = AsfHeaderExtensionObject.length;
          final toParse = extHeader.extensionDataSize;
          final extra = header.payloadSize - alreadyConsumed - toParse;
          if (extra < 0) {
            throw AsfContentParseError(
              'Header Extension object declares invalid extension data size',
            );
          }

          await _parseExtensionObject(toParse);
          if (extra > 0) {
            tokenizer.skip(extra);
          }
          break;

        case '75B22633-668E-11CF-A6D9-00AA0062CE6C':
          await _addTags(
            parseContentDescriptionObject(
              tokenizer.readBytes(header.payloadSize),
            ),
          );
          break;

        case 'D2D0A440-E307-11D2-97F0-00A0C95EA850':
          await _addTags(
            parseExtendedContentDescriptionObject(
              tokenizer.readBytes(header.payloadSize),
            ),
          );
          break;

        case '86D15240-311D-11D0-A3A4-00A0C90348F6':
          final codecs = await readCodecEntries(tokenizer, header.payloadSize);
          _codecs.addAll(codecs);
          final audioCodecs = codecs
              .where((codec) => codec.isAudioCodec)
              .map((codec) => codec.codecName)
              .where((name) => name.isNotEmpty)
              .join('/');
          if (audioCodecs.isNotEmpty) {
            metadata.setFormat(codec: audioCodecs);
          }
          break;

        case '7BF875CE-468D-11D1-8D82-006097C9A2B2':
          final bitrates = _parseStreamBitrates(header.payloadSize);
          _streamBitrates.addAll(bitrates);
          break;

        case '1806D474-CADF-4509-A4BA-9AABCB96AAE8':
          tokenizer.skip(header.payloadSize);
          break;

        default:
          metadata.addWarning('Ignore ASF-Object-GUID: ${header.objectId.str}');
          tokenizer.skip(header.payloadSize);
          break;
      }

      remainingHeaders--;
    }

    await _buildTrackInfos();
  }

  Map<int, int> _parseStreamBitrates(int payloadSize) {
    final bytes = tokenizer.readBytes(payloadSize);
    if (payloadSize < 2) {
      throw AsfContentParseError('Truncated Stream Bitrate Properties Object');
    }
    final count = readUint16Le(bytes, 0);
    if (count * 6 > payloadSize - 2) {
      throw AsfContentParseError(
        'ASF stream bitrate records exceed object payload',
      );
    }
    final bitrates = <int, int>{};
    for (var i = 0; i < count; i++) {
      final streamNumber = readUint16Le(bytes, 2 + i * 6) & 0x7f;
      bitrates[streamNumber] = readUint32Le(bytes, 4 + i * 6);
    }
    return bitrates;
  }

  /// Builds [TrackInfo]s from the discovered streams (upstream parity).
  ///
  /// Matches each stream's codec id against the Codec List entries, applies
  /// Extended Stream Properties (duration, name, frame rate) and Stream
  /// Bitrate Properties substitutions, and surfaces the first audio stream's
  /// characteristics at the format level.
  Future<void> _buildTrackInfos() async {
    final trackInfos = <TrackInfo>[];
    AsfStreamPropertiesObject? firstAudioStream;

    for (final entry in _streams.entries) {
      final stream = entry.value;
      final streamNumber = stream.streamNumber ?? 0;

      final typeName = switch (stream.streamType) {
        'audio' => 'audio',
        'video' => 'video',
        'command' => 'control',
        'binary' => 'metadata',
        _ => null,
      };

      final codec = _findCodec(stream, typeName);
      final extended = _extendedStreams[streamNumber];

      var duration = 0.0;
      if (extended != null && extended.endTime > extended.startTime) {
        duration = (extended.endTime - extended.startTime) / 1000;
      }

      var bitrate = _streamBitrates[streamNumber];
      if (bitrate == null && extended != null && extended.dataBitrate > 0) {
        bitrate = extended.dataBitrate;
      }
      if (bitrate == null) {
        bitrate = stream.bitrate;
      }

      final audio = stream.streamType == 'audio'
          ? AudioTrack(
              samplingFrequency: stream.audioSampleRate,
              channels: stream.audioChannels,
              bitDepth:
                  stream.audioBitDepth != null && stream.audioBitDepth! > 0
                  ? stream.audioBitDepth
                  : null,
            )
          : null;
      final video = stream.streamType == 'video'
          ? VideoTrack(
              pixelWidth: stream.videoPixelWidth,
              pixelHeight: stream.videoPixelHeight,
              frameRate: extended != null && extended.averageTimePerFrame > 0
                  ? 10000000 / extended.averageTimePerFrame
                  : null,
            )
          : null;

      trackInfos.add(
        TrackInfo(
          type: typeName,
          id: streamNumber,
          codecId: stream.codecId,
          codecName: codec != null && codec.codecName.isNotEmpty
              ? codec.codecName
              : null,
          name: extended?.streamName,
          duration: duration > 0 ? duration : null,
          bitrate: bitrate != null && bitrate > 0 ? bitrate.toDouble() : null,
          audio: audio,
          video: video,
        ),
      );

      if (typeName == 'audio' &&
          firstAudioStream == null &&
          stream.audioChannels != null) {
        firstAudioStream = stream;
      }
    }

    for (final track in trackInfos) {
      metadata.addStreamInfo(track);
    }

    final audio = firstAudioStream;
    if (audio != null) {
      metadata.setFormat(
        sampleRate: audio.audioSampleRate,
        numberOfChannels: audio.audioChannels,
        bitsPerSample: audio.audioBitDepth != null && audio.audioBitDepth! > 0
            ? audio.audioBitDepth
            : null,
      );
    }
  }

  AsfCodecEntry? _findCodec(
    AsfStreamPropertiesObject stream,
    String? typeName,
  ) {
    if (typeName == 'audio') {
      for (final codec in _codecs) {
        if (!codec.isAudioCodec || codec.information.length < 2) {
          continue;
        }
        final formatTag =
            '0x${readUint16Le(codec.information, 0).toRadixString(16).padLeft(4, '0')}';
        if (stream.codecId == formatTag) {
          return codec;
        }
      }
      return null;
    }

    if (typeName == 'video') {
      for (final codec in _codecs) {
        if (!codec.isVideoCodec || codec.information.length < 4) {
          continue;
        }
        final fourcc = ascii.decode(
          codec.information.sublist(0, 4),
          allowInvalid: true,
        );
        if (stream.codecId == fourcc) {
          return codec;
        }
      }
      return null;
    }

    return null;
  }

  Future<void> _addTags(List<AsfNativeTag> tags) async {
    for (final tag in tags) {
      _validateReplayGainValue(tag.id, tag.value);
      metadata.addNativeTag(_headerType, tag.id, tag.value);
    }
  }

  /// Emits the upstream warning for ASF ReplayGain attributes whose value
  /// does not match `<number>[ <dB>]` (mirrors `AsfTagMapper.postMap`).
  ///
  /// Invalid values stay native without being mapped to common metadata.
  static final RegExp _replayGainPattern = RegExp(
    r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?)\s*(dB)?$',
    caseSensitive: false,
  );

  void _validateReplayGainValue(String id, dynamic value) {
    if (!id.toLowerCase().startsWith('replaygain_')) {
      return;
    }
    if (value is! String) {
      return;
    }
    final match = _replayGainPattern.firstMatch(value.trim());
    if (match == null) {
      metadata.addWarning('Invalid ASF ReplayGain value for $id');
    }
  }

  Future<void> _parseExtensionObject(int extensionSize) async {
    var remaining = extensionSize;
    while (remaining > 0) {
      final header = AsfObjectHeader.parse(
        tokenizer.readBytes(AsfObjectHeader.length),
      );

      final objectSize = header.objectSize;
      if (objectSize <= 0) {
        throw AsfContentParseError(
          'Invalid ASF extension object size: $objectSize',
        );
      }

      final payloadSize = header.payloadSize;
      if (payloadSize < 0) {
        throw AsfContentParseError(
          'Invalid ASF extension payload size: $payloadSize',
        );
      }

      switch (header.objectId.str) {
        case '14E6A5CB-C672-4332-8399-A96952065B5A':
          final extended = AsfExtendedStreamPropertiesObject.parse(
            tokenizer.readBytes(payloadSize),
          );
          _extendedStreams[extended.streamNumber ?? 0] = extended;
          // An Extended Stream Properties object may embed its own stream
          // properties; use it when the main Stream Properties Object
          // headers were not encountered (or to store the same stream).
          final embedded = extended.streamProperties;
          if (embedded != null) {
            _streams.putIfAbsent(
              embedded.streamNumber ?? extended.streamNumber ?? 0,
              () => embedded,
            );
            if (embedded.streamType != null) {
              metadata.setFormat(container: 'ASF/${embedded.streamType}');
            }
          }
          break;

        case 'C5F8CBEA-5BAF-4877-8467-AA8C44FA4CCA':
          await _addTags(parseMetadataObject(tokenizer.readBytes(payloadSize)));
          break;

        case '44231C94-9498-49D1-A141-1D134E457054':
          await _addTags(
            parseMetadataLibraryObject(tokenizer.readBytes(payloadSize)),
          );
          break;

        case '1806D474-CADF-4509-A4BA-9AABCB96AAE8':
        case '26F18B5D-4584-47EC-9F5F-0E651F0452C9':
        case 'D9AADE20-7C17-4F9C-BC28-8555DD98E2A2':
          tokenizer.skip(payloadSize);
          break;

        default:
          metadata.addWarning('Ignore ASF-Object-GUID: ${header.objectId.str}');
          tokenizer.skip(payloadSize);
          break;
      }

      remaining -= objectSize;
    }
  }
}
