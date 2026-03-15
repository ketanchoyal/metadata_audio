library;

import 'package:audio_metadata/src/asf/asf_guid.dart';
import 'package:audio_metadata/src/asf/asf_object.dart';
import 'package:audio_metadata/src/common/metadata_collector.dart';
import 'package:audio_metadata/src/model/types.dart';
import 'package:audio_metadata/src/tokenizer/tokenizer.dart';

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
  }

  Future<void> _addTags(List<AsfNativeTag> tags) async {
    for (final tag in tags) {
      metadata.addNativeTag(_headerType, tag.id, tag.value);
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
          AsfExtendedStreamPropertiesObject.parse(
            tokenizer.readBytes(payloadSize),
          );
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
