library;

// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:metadata_audio/src/apev2/apev2_parser.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/musepack/musepack_content_error.dart';
import 'package:metadata_audio/src/musepack/sv8/stream_version8.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class MpcSv8Parser {
  MpcSv8Parser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  var _audioLength = 0;

  Future<void> parse() async {
    final signature = latin1.decode(tokenizer.readBytes(4), allowInvalid: true);
    if (signature != 'MPCK') {
      throw MusepackContentError('Invalid Magic number');
    }

    metadata.setFormat(container: 'Musepack, SV8');
    await _parsePackets();
  }

  Future<void> _parsePackets() async {
    final reader = StreamVersion8Reader(tokenizer);

    while (true) {
      final header = await reader.readPacketHeader();
      switch (header.key) {
        case 'SH':
          final streamHeader = await reader.readStreamHeader(
            header.payloadLength,
          );
          metadata.setFormat(
            numberOfSamples: streamHeader.sampleCount,
            sampleRate: streamHeader.sampleFrequency,
            duration: streamHeader.sampleCount / streamHeader.sampleFrequency,
            numberOfChannels: streamHeader.channelCount,
          );
          break;
        case 'AP':
          _audioLength += header.payloadLength;
          tokenizer.skip(header.payloadLength);
          break;
        case 'RG':
        case 'EI':
        case 'SO':
        case 'ST':
        case 'CT':
          tokenizer.skip(header.payloadLength);
          break;
        case 'SE':
          final duration = metadata.format.duration;
          if (duration != null && duration > 0) {
            metadata.setFormat(bitrate: (_audioLength * 8 / duration).round());
          }

          await Apev2Parser(
            metadata: metadata,
            tokenizer: tokenizer,
            options: options,
          ).tryParseApeHeader();
          return;
        default:
          throw MusepackContentError('Unexpected header: ${header.key}');
      }
    }
  }
}
