library;

// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:typed_data';

import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/ebml/ebml_iterator.dart';
import 'package:metadata_audio/src/ebml/types.dart';
import 'package:metadata_audio/src/id3v2/id3v2_parser.dart';
import 'package:metadata_audio/src/matroska/matroska_dtd.dart';
import 'package:metadata_audio/src/matroska/types.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/musepack/musepack_content_error.dart';
import 'package:metadata_audio/src/musepack/sv7/mpc_sv7_parser.dart';
import 'package:metadata_audio/src/musepack/sv8/mpc_sv8_parser.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class MusepackParser {
  MusepackParser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  EbmlTree? _seekHead;
  int _seekHeadOffset = 0;

  Future<void> parse() async {
    await Id3v2Parser(
      metadata: metadata,
      tokenizer: tokenizer,
      options: options,
    ).parse();

    final signature = ascii.decode(tokenizer.peekBytes(3), allowInvalid: true);

    if (signature == 'MP+') {
      metadata.setFormat(hasAudio: true, hasVideo: false);
      await MpcSv7Parser(
        metadata: metadata,
        tokenizer: tokenizer,
        options: options,
      ).parse();
      return;
    }

    if (signature == 'MPC') {
      metadata.setFormat(hasAudio: true, hasVideo: false);
      await MpcSv8Parser(
        metadata: metadata,
        tokenizer: tokenizer,
        options: options,
      ).parse();
      return;
    }

    final maybeEbml = tokenizer.peekBytes(4);
    if (_isEbmlHeader(maybeEbml)) {
      await _parseMatroskaContainer();
      return;
    }

    throw MusepackContentError('Invalid signature prefix');
  }

  Future<void> _parseMatroskaContainer() async {
    final containerSize = tokenizer.fileInfo?.size ?? 0x7FFFFFFFFFFFFFFF;
    final iterator = EbmlIterator(tokenizer);

    await iterator.iterate(
      matroskaDtd,
      containerSize,
      EbmlElementListener(
        startNext: (element) {
          switch (element.id) {
            case 0x1C53BB6B:
              return ParseAction.ignoreElement;
            case 0x1F43B675:
              if (_seekHead != null) {
                final seekEntries = _asTreeList(_seekHead!['seek']);
                final nextSeek = seekEntries
                    .map((entry) => _asInt(entry['position']))
                    .whereType<int>()
                    .map((position) => position + _seekHeadOffset)
                    .where((position) => position > tokenizer.position)
                    .fold<int?>(null, (acc, value) {
                      if (acc == null || value < acc) {
                        return value;
                      }
                      return acc;
                    });

                if (nextSeek != null) {
                  final ignoreSize = nextSeek - tokenizer.position;
                  if (ignoreSize > 0) {
                    tokenizer.skip(ignoreSize);
                    return ParseAction.skipElement;
                  }
                }
              }
              return ParseAction.ignoreElement;
            default:
              return ParseAction.readNext;
          }
        },
        elementValue: (element, value, offset) async {
          switch (element.id) {
            case 0x4282:
              _parseDocType(value);
              break;
            case 0x114D9B74:
              if (value is EbmlTree) {
                _seekHead = value;
                _seekHeadOffset = offset;
              }
              break;
            case 0x1549A966:
              if (value is EbmlTree) {
                _parseInfo(value);
              }
              break;
            case 0x1654AE6B:
              if (value is EbmlTree) {
                _parseTracks(value);
              }
              break;
            case 0x1254C367:
              if (value is EbmlTree) {
                _parseTags(value);
              }
              break;
            case 0x1941A469:
              if (value is EbmlTree) {
                _parseAttachments(value);
              }
              break;
            case 0x1043A770:
              if (value is EbmlTree) {
                _parseChapters(value);
              }
              break;
          }
        },
      ),
    );
  }

  void _parseDocType(Object? value) {
    final docType = value is String ? value : null;
    if (docType == null) {
      return;
    }

    if (docType != 'matroska' && docType != 'webm') {
      throw MusepackContentError('Unsupported Matroska docType: $docType');
    }

    metadata.setFormat(container: 'EBML/$docType');
  }

  void _parseInfo(EbmlTree info) {
    final timecodeScale = _asInt(info['timecodeScale']) ?? 1000000;
    final duration = _asDouble(info['duration']);
    if (duration != null) {
      final seconds = duration * timecodeScale / 1000000000.0;
      metadata.setFormat(duration: seconds);
    }

    final title = _asString(info['title']);
    if (title != null && title.isNotEmpty) {
      metadata.addNativeTag('matroska', 'segment:title', title);
    }

    final writingApp = _asString(info['writingApp']);
    if (writingApp != null && writingApp.isNotEmpty) {
      metadata.setFormat(tool: writingApp);
    }
  }

  void _parseTracks(EbmlTree tracks) {
    final entries = _asTreeList(tracks['entries']);
    if (entries.isEmpty) {
      return;
    }

    final trackInfos = <TrackInfo>[];
    var hasAudio = false;
    var hasVideo = false;

    for (final entry in entries) {
      final trackTypeValue = _asInt(entry['trackType']);
      final trackTypeName = MatroskaTrackType.nameOf(trackTypeValue);

      final codecId = _asString(entry['codecID']) ?? '';
      final codecName = codecId.replaceFirst('A_', '').replaceFirst('V_', '');

      final audio = _readAudioTrack(entry['audio']);
      final video = _readVideoTrack(entry['video']);

      if (trackTypeName == 'audio') {
        hasAudio = true;
      } else if (trackTypeName == 'video') {
        hasVideo = true;
      }

      trackInfos.add(
        TrackInfo(
          type: trackTypeName,
          codecName: codecName.isEmpty ? null : codecName,
          codecSettings: _asString(entry['codecSettings']),
          flagDefault: _asBool(entry['flagDefault']),
          flagLacing: _asBool(entry['flagLacing']),
          flagEnabled: _asBool(entry['flagEnabled']),
          language: _asString(entry['language']),
          name: _asString(entry['name']),
          audio: audio,
          video: video,
        ),
      );
    }

    metadata.setFormat(
      trackInfo: trackInfos,
      hasAudio: hasAudio,
      hasVideo: hasVideo,
    );

    final audioTrack = entries
        .where((entry) => _asInt(entry['trackType']) == MatroskaTrackType.audio)
        .fold<EbmlTree?>(null, (acc, current) {
          if (acc == null) {
            return current;
          }

          final currentDefault = _asBool(current['flagDefault']) ?? false;
          final accDefault = _asBool(acc['flagDefault']) ?? false;
          if (currentDefault && !accDefault) {
            return current;
          }

          final currentNumber = _asInt(current['trackNumber']) ?? 0;
          final accNumber = _asInt(acc['trackNumber']) ?? 0;
          if (currentNumber < accNumber) {
            return current;
          }

          return acc;
        });

    if (audioTrack != null) {
      final codecId = _asString(audioTrack['codecID']);
      final audio = audioTrack['audio'] as EbmlTree?;
      metadata.setFormat(
        codec: codecId?.replaceFirst('A_', ''),
        sampleRate: _asDouble(audio?['samplingFrequency'])?.round(),
        numberOfChannels: _asInt(audio?['channels']),
      );
    }
  }

  void _parseTags(EbmlTree tags) {
    final tagEntries = _asTreeList(tags['tag']);
    for (final tag in tagEntries) {
      final target = tag['target'] as EbmlTree?;
      final targetTypeValue = _asInt(target?['targetTypeValue']);
      final targetType =
          targetTypeByValue[targetTypeValue] ??
          _asString(target?['targetType'])?.toLowerCase() ??
          'track';

      final simpleTags = _asTreeList(tag['simpleTags']);
      for (final simpleTag in simpleTags) {
        final name = _asString(simpleTag['name']);
        if (name == null || name.isEmpty) {
          continue;
        }

        final value = simpleTag['string'] ?? simpleTag['binary'];
        if (value == null) {
          continue;
        }

        metadata.addNativeTag('matroska', '$targetType:$name', value);
      }
    }
  }

  void _parseAttachments(EbmlTree attachments) {
    if (options.skipCovers) {
      return;
    }

    final files = _asTreeList(attachments['attachedFiles']);
    for (final file in files) {
      final mimeType = _asString(file['mimeType']);
      if (mimeType == null || !mimeType.startsWith('image/')) {
        continue;
      }

      final data = _asBytes(file['data']);
      if (data == null) {
        continue;
      }

      metadata.addNativeTag(
        'matroska',
        'picture',
        Picture(
          data: data,
          format: mimeType,
          description: _asString(file['description']),
          name: _asString(file['name']),
        ),
      );
    }
  }

  void _parseChapters(EbmlTree chapters) {
    if (!options.includeChapters) {
      return;
    }

    final chapterList = <Chapter>[];
    final editions = _asTreeList(chapters['editionEntry']);
    for (final edition in editions) {
      final atoms = _asTreeList(edition['chapterAtom']);
      for (final atom in atoms) {
        final startNs = _asInt(atom['timeStart']) ?? 0;
        final endRaw = atom['timeEnd'];
        final endNs = endRaw is Uint8List
            ? _uintFromBytes(endRaw)
            : _asInt(endRaw);

        final display = (atom['track'] as EbmlTree?)?['display'] as EbmlTree?;
        final title = _asString(display?['string']) ?? 'Chapter';

        chapterList.add(
          Chapter(
            id: _idFromUid(atom['uid']),
            title: title,
            start: (startNs / 1000000).round(),
            end: endNs == null ? null : (endNs / 1000000).round(),
            timeScale: 1000,
          ),
        );
      }
    }

    if (chapterList.isNotEmpty) {
      metadata.setFormat(chapters: chapterList);
    }
  }

  AudioTrack? _readAudioTrack(Object? value) {
    final audio = value as EbmlTree?;
    if (audio == null) {
      return null;
    }

    return AudioTrack(
      samplingFrequency: _asDouble(audio['samplingFrequency'])?.round(),
      outputSamplingFrequency: _asDouble(
        audio['outputSamplingFrequency'],
      )?.round(),
      channels: _asInt(audio['channels']),
      channelPositions: _asBytes(audio['channelPositions']),
      bitDepth: _asInt(audio['bitDepth']),
    );
  }

  VideoTrack? _readVideoTrack(Object? value) {
    final video = value as EbmlTree?;
    if (video == null) {
      return null;
    }

    return VideoTrack(
      flagInterlaced: _asBool(video['flagInterlaced']),
      stereoMode: _asInt(video['stereoMode']),
      pixelWidth: _asInt(video['pixelWidth']),
      pixelHeight: _asInt(video['pixelHeight']),
      displayWidth: _asInt(video['displayWidth']),
      displayHeight: _asInt(video['displayHeight']),
      displayUnit: _asInt(video['displayUnit']),
      aspectRatioType: _asInt(video['aspectRatioType']),
      colourSpace: _asBytes(video['colourSpace']),
      gammaValue: _asDouble(video['gammaValue']),
    );
  }

  static bool _isEbmlHeader(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x1A &&
      bytes[1] == 0x45 &&
      bytes[2] == 0xDF &&
      bytes[3] == 0xA3;

  static List<EbmlTree> _asTreeList(Object? value) {
    if (value is List<EbmlTree>) {
      return value;
    }
    if (value is EbmlTree) {
      return <EbmlTree>[value];
    }
    return const <EbmlTree>[];
  }

  static String? _asString(Object? value) => value is String ? value : null;

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is Uint8List) {
      return _uintFromBytes(value);
    }
    return null;
  }

  static double? _asDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    return null;
  }

  static bool? _asBool(Object? value) => value is bool ? value : null;

  static List<int>? _asBytes(Object? value) {
    if (value is Uint8List) {
      return value;
    }
    if (value is List<int>) {
      return value;
    }
    return null;
  }

  static int? _uintFromBytes(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    var value = 0;
    for (final byte in bytes) {
      value = (value << 8) | byte;
    }
    return value;
  }

  static String? _idFromUid(Object? uid) {
    final bytes = uid is Uint8List ? uid : null;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
