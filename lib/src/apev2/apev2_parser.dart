library;

import 'dart:convert';

import 'package:metadata_audio/src/apev2/apev2_token.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/parse_error.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class ApeContentError extends UnexpectedFileContentError {
  ApeContentError(String message) : super('APEv2', message);
}

class Apev2Parser {
  Apev2Parser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });

  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  static double calculateDuration(ApeHeader header) {
    var sampleCount = header.totalFrames > 1
        ? header.blocksPerFrame * (header.totalFrames - 1)
        : 0;
    sampleCount += header.finalFrameBlocks;

    if (header.sampleRate <= 0) {
      return 0;
    }

    return sampleCount / header.sampleRate;
  }

  Future<void> parse() async {
    if (await tryParseApeHeader(searchFromTail: false)) {
      return;
    }

    final descriptor = Apev2Token.parseDescriptor(
      tokenizer.readBytes(Apev2Token.descriptorLength),
    );
    if (descriptor.id != 'MAC ') {
      throw ApeContentError('Unexpected descriptor ID');
    }

    final descriptorExpansion =
        descriptor.descriptorBytes - Apev2Token.descriptorLength;
    if (descriptorExpansion > 0) {
      tokenizer.skip(descriptorExpansion);
    }

    final header = Apev2Token.parseHeader(
      tokenizer.readBytes(Apev2Token.headerLength),
    );

    metadata.setFormat(
      container: "Monkey's Audio",
      lossless: true,
      bitsPerSample: header.bitsPerSample,
      sampleRate: header.sampleRate,
      numberOfChannels: header.channel,
      duration: calculateDuration(header),
      hasAudio: true,
      hasVideo: false,
    );

    final forwardBytes =
        descriptor.seekTableBytes +
        descriptor.headerDataBytes +
        descriptor.apeFrameDataBytes +
        descriptor.terminatingDataBytes;
    if (forwardBytes > 0) {
      tokenizer.skip(forwardBytes);
    }

    await tryParseApeHeader();
  }

  Future<bool> tryParseApeHeader({bool searchFromTail = true}) async {
    if (_remainingBytes != null &&
        _remainingBytes! < Apev2Token.tagFooterLength) {
      return false;
    }

    try {
      final current = Apev2Token.parseTagFooter(
        tokenizer.peekBytes(Apev2Token.tagFooterLength),
      );
      if (current.id == Apev2Token.preamble) {
        tokenizer.skip(Apev2Token.tagFooterLength);
        await _parseTags(current);
        return true;
      }
    } on TokenizerException {
      return false;
    } on FormatException {
      return false;
    }

    if (!searchFromTail) {
      return false;
    }

    return _parseFromTail();
  }

  Future<bool> _parseFromTail() async {
    final fileSize = tokenizer.fileInfo?.size;
    if (!tokenizer.canSeek ||
        fileSize == null ||
        fileSize < Apev2Token.tagFooterLength) {
      return false;
    }

    final origin = tokenizer.position;
    var success = false;

    try {
      tokenizer.seek(fileSize - Apev2Token.tagFooterLength);
      final footer = Apev2Token.parseTagFooter(
        tokenizer.readBytes(Apev2Token.tagFooterLength),
      );
      if (footer.id != Apev2Token.preamble) {
        return false;
      }

      final tagStart = footer.flags.isHeader
          ? fileSize - Apev2Token.tagFooterLength
          : fileSize - footer.size;
      if (tagStart < 0 || tagStart > fileSize) {
        metadata.addWarning('Invalid APEv2 tag size: ${footer.size}');
        return false;
      }

      tokenizer.seek(tagStart);
      if (footer.flags.containsHeader || footer.flags.isHeader) {
        final header = Apev2Token.parseTagFooter(
          tokenizer.readBytes(Apev2Token.tagFooterLength),
        );
        if (header.id != Apev2Token.preamble) {
          metadata.addWarning('Invalid APEv2 header preamble at tag start');
          return false;
        }
      }

      await _parseTags(footer);
      success = true;
      return true;
    } on TokenizerException {
      return false;
    } on FormatException {
      return false;
    } finally {
      if (!success) {
        tokenizer.seek(origin);
      }
    }
  }

  Future<void> _parseTags(ApeTagFooter footer) async {
    const tagFormat = 'APEv2';
    var bytesRemaining = footer.size - Apev2Token.tagFooterLength;

    for (var i = 0; i < footer.fields; i++) {
      if (bytesRemaining < Apev2Token.tagItemHeaderLength) {
        metadata.addWarning(
          'APEv2 Tag-header: ${footer.fields - i} items remaining, but no more tag data to read.',
        );
        break;
      }

      final itemHeader = Apev2Token.parseTagItemHeader(
        tokenizer.readBytes(Apev2Token.tagItemHeaderLength),
      );
      bytesRemaining -= Apev2Token.tagItemHeaderLength;

      final keyInfo = _readKey(bytesRemaining);
      bytesRemaining -= keyInfo.consumed;
      if (!keyInfo.terminated) {
        metadata.addWarning('APEv2 item key is not null terminated');
        break;
      }

      if (itemHeader.size > bytesRemaining) {
        metadata.addWarning(
          'APEv2 item size exceeds remaining tag data for key "${keyInfo.key}"',
        );
        tokenizer.skip(bytesRemaining);
        bytesRemaining = 0;
        break;
      }

      switch (itemHeader.flags.dataType) {
        case Apev2DataType.textUtf8:
          final textBytes = tokenizer.readBytes(itemHeader.size);
          bytesRemaining -= itemHeader.size;
          final decoded = utf8.decode(textBytes, allowMalformed: true);
          final values = decoded
              .split('\x00')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList();

          if (values.isEmpty) {
            metadata.addNativeTag(tagFormat, keyInfo.key, '');
          } else if (values.length == 1) {
            metadata.addNativeTag(tagFormat, keyInfo.key, values.first);
          } else {
            metadata.addNativeTag(tagFormat, keyInfo.key, values);
          }
          break;

        case Apev2DataType.binary:
          if (options.skipCovers) {
            tokenizer.skip(itemHeader.size);
            bytesRemaining -= itemHeader.size;
            break;
          }

          final data = tokenizer.readBytes(itemHeader.size);
          bytesRemaining -= itemHeader.size;
          final zero = data.indexOf(0);
          final description = zero == -1
              ? ''
              : utf8.decode(data.sublist(0, zero), allowMalformed: true);
          final imageData = zero == -1 ? data : data.sublist(zero + 1);

          metadata.addNativeTag(
            tagFormat,
            keyInfo.key,
            ApePicture(description: description, data: imageData),
          );
          break;

        case Apev2DataType.externalInfo:
          tokenizer.skip(itemHeader.size);
          bytesRemaining -= itemHeader.size;
          break;

        case Apev2DataType.reserved:
          metadata.addWarning(
            'APEv2 header declares a reserved datatype for "${keyInfo.key}"',
          );
          tokenizer.skip(itemHeader.size);
          bytesRemaining -= itemHeader.size;
          break;

        default:
          metadata.addWarning(
            'APEv2 header declares an unknown datatype for "${keyInfo.key}"',
          );
          tokenizer.skip(itemHeader.size);
          bytesRemaining -= itemHeader.size;
      }
    }
  }

  ({String key, int consumed, bool terminated}) _readKey(int bytesRemaining) {
    final keyBytes = <int>[];
    var consumed = 0;
    var terminated = false;

    while (consumed < bytesRemaining) {
      final byte = tokenizer.readUint8();
      consumed++;

      if (byte == 0) {
        terminated = true;
        break;
      }

      keyBytes.add(byte);
    }

    return (
      key: ascii.decode(keyBytes, allowInvalid: true),
      consumed: consumed,
      terminated: terminated,
    );
  }

  int? get _remainingBytes {
    final size = tokenizer.fileInfo?.size;
    if (size == null) {
      return null;
    }
    return size - tokenizer.position;
  }
}
