library;

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:metadata_audio/src/common/metadata_collector.dart';
import 'package:metadata_audio/src/id3v2/frame_header.dart';
import 'package:metadata_audio/src/id3v2/frame_parser.dart';
import 'package:metadata_audio/src/id3v2/id3v2_token.dart';
import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/tokenizer/tokenizer.dart';

class Id3v2ChapterInfo {
  const Id3v2ChapterInfo({
    required this.startTime,
    required this.endTime,
    required this.startOffset,
    required this.endOffset,
  });
  final int startTime;
  final int endTime;
  final int? startOffset;
  final int? endOffset;
}

class Id3v2ChapterFrame {
  const Id3v2ChapterFrame({
    required this.label,
    required this.info,
    required this.frames,
  });
  final String label;
  final Id3v2ChapterInfo info;
  final Map<String, dynamic> frames;
}

class Id3v2TocFlags {
  const Id3v2TocFlags({required this.topLevel, required this.ordered});
  final bool topLevel;
  final bool ordered;
}

class Id3v2TocFrame {
  const Id3v2TocFrame({
    required this.label,
    required this.flags,
    required this.childElementIds,
  });
  final String label;
  final Id3v2TocFlags flags;
  final List<String> childElementIds;
}

class Id3v2Parser {
  Id3v2Parser({
    required this.metadata,
    required this.tokenizer,
    required this.options,
  });
  final MetadataCollector metadata;
  final Tokenizer tokenizer;
  final ParseOptions options;

  Future<void> parse() async {
    while (_hasNextId3Header()) {
      await _parseSingleTag();
    }
  }

  bool _hasNextId3Header() {
    try {
      final bytes = tokenizer.peekBytes(3);
      return bytes.length == 3 &&
          ascii.decode(bytes, allowInvalid: true) == 'ID3';
    } on TokenizerException {
      return false;
    }
  }

  Future<void> _parseSingleTag() async {
    final header = ID3v2Token.parseHeader(
      tokenizer.readBytes(ID3v2Token.id3v2HeaderLength),
    );
    if (header.fileIdentifier != 'ID3') {
      throw const Id3v2ContentError(
        'expected ID3-header file-identifier "ID3" was not found',
      );
    }

    if (header.version.major < 2 || header.version.major > 4) {
      metadata.addWarning(
        'Unsupported ID3v2 major version: ${header.version.major}',
      );
      tokenizer.skip(header.size);
      return;
    }

    final tagType = 'ID3v2.${header.version.major}';
    final dataLen = header.flags.isExtendedHeader
        ? _consumeExtendedHeaderAndGetDataLen(header)
        : header.size;

    if (dataLen < 0) {
      metadata.addWarning('Invalid ID3v2 extended header size');
      return;
    }

    var data = tokenizer.readBytes(dataLen);
    if (header.flags.unsynchronisation && header.version.major < 4) {
      data = removeUnsyncBytes(data);
    }

    final parsed = _parseFrames(data, header.version.major);
    for (final tag in parsed.tags.entries) {
      metadata.addNativeTag(tagType, tag.key, tag.value);
    }

    if (options.includeChapters) {
      final chapters = mapId3v2Chapters(parsed.chapters, parsed.tocs);
      if (chapters != null) {
        metadata.setFormat(chapters: chapters);
      }
    }
  }

  int _consumeExtendedHeaderAndGetDataLen(Id3v2Header header) {
    if (header.size < 4) {
      return -1;
    }

    final extSizeBytes = tokenizer.readBytes(4);
    final extSize = header.version.major == 4
        ? ID3v2Token.uint32Synchsafe(extSizeBytes, 0)
        : ID3v2Token.uint32Be(extSizeBytes, 0);

    if (extSize < 4 || extSize > header.size) {
      return -1;
    }

    final toSkip = extSize - 4;
    if (toSkip > 0) {
      tokenizer.skip(toSkip);
    }
    return header.size - extSize;
  }

  static List<int> removeUnsyncBytes(List<int> buffer) {
    final output = <int>[];
    var index = 0;
    while (index < buffer.length) {
      final byte = buffer[index];
      if (byte == 0xFF &&
          index + 1 < buffer.length &&
          buffer[index + 1] == 0x00) {
        output.add(0xFF);
        index += 2;
        continue;
      }
      output.add(byte);
      index++;
    }
    return output;
  }

  _ParsedFrames _parseFrames(List<int> data, Id3v2MajorVersion majorVersion) {
    final frameParser = FrameParser(
      majorVersion,
      warningCollector: metadata.addWarning,
    );
    final tags = <String, dynamic>{};
    final chapters = <Id3v2ChapterFrame>[];
    final tocs = <Id3v2TocFrame>[];

    var offset = 0;
    while (offset < data.length) {
      final frameHeaderLength = FrameHeader.getFrameHeaderLength(majorVersion);
      if (offset + frameHeaderLength > data.length) {
        metadata.addWarning('Illegal ID3v2 tag length');
        break;
      }

      final headerBytes = data.sublist(offset, offset + frameHeaderLength);
      offset += frameHeaderLength;
      final frameHeader = FrameHeader.parse(
        headerBytes,
        majorVersion,
        warningCollector: metadata.addWarning,
      );

      if (frameHeader.isPadding) {
        break;
      }

      if (frameHeader.length < 0 || offset + frameHeader.length > data.length) {
        metadata.addWarning('Illegal ID3v2 frame length for ${frameHeader.id}');
        break;
      }

      var frameData = data.sublist(offset, offset + frameHeader.length);
      offset += frameHeader.length;

      if (frameHeader.flags?.format.unsynchronisation ?? false) {
        frameData = removeUnsyncBytes(frameData);
      }
      if ((frameHeader.flags?.format.dataLengthIndicator ?? false) &&
          frameData.length >= 4) {
        frameData = frameData.sublist(4);
      }

      dynamic value;
      if (frameHeader.id == 'CHAP' && options.includeChapters) {
        value = _parseChapterFrame(frameData, majorVersion);
        if (value is Id3v2ChapterFrame) {
          chapters.add(value);
        }
      } else if (frameHeader.id == 'CTOC' && options.includeChapters) {
        value = _parseTocFrame(frameData);
        if (value is Id3v2TocFrame) {
          tocs.add(value);
        }
      } else {
        value = frameParser.readData(
          frameData,
          frameHeader.id,
          includeCovers: !options.skipCovers,
        );
      }

      if (value == null) {
        continue;
      }

      if (frameHeader.id == 'TXXX' && value is Map<String, dynamic>) {
        final description = (value['description'] as String?) ?? '';
        final text = value['text'];
        if (text is List) {
          final first = text.whereType<String>().firstOrNull;
          if (first != null) {
            tags['TXXX:$description'] = first;
          }
        }
        continue;
      }

      tags[frameHeader.id] = value;
    }

    return _ParsedFrames(tags: tags, chapters: chapters, tocs: tocs);
  }

  Id3v2ChapterFrame? _parseChapterFrame(
    List<int> bytes,
    Id3v2MajorVersion majorVersion,
  ) {
    final labelRes = _readLatin1CString(bytes, 0);
    if (labelRes == null) {
      return null;
    }

    var offset = labelRes.nextOffset;
    if (offset + 16 > bytes.length) {
      metadata.addWarning('CHAP frame too short');
      return null;
    }

    final chapterInfo = Id3v2ChapterInfo(
      startTime: ID3v2Token.uint32Be(bytes, offset),
      endTime: ID3v2Token.uint32Be(bytes, offset + 4),
      startOffset: _parseOptionalOffset(ID3v2Token.uint32Be(bytes, offset + 8)),
      endOffset: _parseOptionalOffset(ID3v2Token.uint32Be(bytes, offset + 12)),
    );
    offset += 16;

    final nested = _parseEmbeddedFrames(bytes.sublist(offset), majorVersion);
    if (!nested.containsKey('TIT2') && !nested.containsKey('TT2')) {
      final title = _extractEmbeddedTitle(bytes.sublist(offset), majorVersion);
      if (title != null) {
        nested['TIT2'] = title;
      }
    }
    return Id3v2ChapterFrame(
      label: labelRes.text,
      info: chapterInfo,
      frames: nested,
    );
  }

  Id3v2TocFrame? _parseTocFrame(List<int> bytes) {
    final labelRes = _readLatin1CString(bytes, 0);
    if (labelRes == null) {
      return null;
    }

    var offset = labelRes.nextOffset;
    if (offset + 2 > bytes.length) {
      metadata.addWarning('CTOC frame too short');
      return null;
    }

    final flagsByte = bytes[offset++];
    final entryCount = bytes[offset++];
    final childElementIds = <String>[];

    for (var i = 0; i < entryCount; i++) {
      final idRes = _readLatin1CString(bytes, offset);
      if (idRes == null) {
        break;
      }
      childElementIds.add(idRes.text);
      offset = idRes.nextOffset;
    }

    return Id3v2TocFrame(
      label: labelRes.text,
      flags: Id3v2TocFlags(
        topLevel: (flagsByte & 0x02) != 0,
        ordered: (flagsByte & 0x01) != 0,
      ),
      childElementIds: childElementIds,
    );
  }

  Map<String, dynamic> _parseEmbeddedFrames(
    List<int> data,
    Id3v2MajorVersion majorVersion,
  ) {
    final frameParser = FrameParser(
      majorVersion,
      warningCollector: metadata.addWarning,
    );
    final result = <String, dynamic>{};
    var offset = 0;

    while (offset < data.length) {
      final frameHeaderLength = FrameHeader.getFrameHeaderLength(majorVersion);
      if (offset + frameHeaderLength > data.length) {
        break;
      }

      final headerBytes = data.sublist(offset, offset + frameHeaderLength);
      offset += frameHeaderLength;

      final frameHeader = FrameHeader.parse(
        headerBytes,
        majorVersion,
        warningCollector: metadata.addWarning,
      );

      if (frameHeader.isPadding) {
        break;
      }

      if (frameHeader.length < 0 || offset + frameHeader.length > data.length) {
        break;
      }

      final frameData = data.sublist(offset, offset + frameHeader.length);
      offset += frameHeader.length;

      dynamic value;
      if (frameHeader.id == 'WXXX') {
        value = _parseUserUrlFrame(frameData);
      } else if (frameHeader.id.startsWith('W')) {
        value = latin1
            .decode(frameData, allowInvalid: true)
            .replaceAll(RegExp(r'\x00+$'), '');
      } else {
        value = frameParser.readData(
          frameData,
          frameHeader.id,
          includeCovers: !options.skipCovers,
        );
      }

      if (value == null) {
        continue;
      }

      if (value is List) {
        result[frameHeader.id] = value.isNotEmpty ? value.first : null;
      } else {
        result[frameHeader.id] = value;
      }
    }

    return result;
  }

  Url? _parseUserUrlFrame(List<int> frameData) {
    if (frameData.isEmpty) {
      return null;
    }

    final encoding = ID3v2Token.textEncodingFromByte(frameData[0]);
    final payload = frameData.sublist(1);
    final split = _splitAtNull(
      payload,
      encoding.encoding.startsWith('utf16') ? 2 : 1,
    );
    final description = _decodeByEncoding(split.first, encoding);
    final url = latin1
        .decode(split.second, allowInvalid: true)
        .replaceAll(RegExp(r'\x00+$'), '');

    if (url.isEmpty) {
      return null;
    }

    return Url(url: url, description: description);
  }

  static String _decodeByEncoding(List<int> bytes, TextEncodingInfo encoding) {
    if (bytes.isEmpty) {
      return '';
    }

    switch (encoding.encoding) {
      case 'latin1':
        return latin1.decode(bytes, allowInvalid: true);
      case 'utf8':
        return utf8.decode(bytes, allowMalformed: true);
      case 'utf16':
      case 'utf16be':
        final units = <int>[];
        for (var i = 0; i + 1 < bytes.length; i += 2) {
          units.add(
            encoding.encoding == 'utf16be'
                ? ((bytes[i] << 8) | bytes[i + 1])
                : (bytes[i] | (bytes[i + 1] << 8)),
          );
        }
        return String.fromCharCodes(units);
      default:
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  static _CStringResult? _readLatin1CString(List<int> data, int offset) {
    if (offset >= data.length) {
      return null;
    }
    final zeroIndex = data.indexOf(0, offset);
    final end = zeroIndex == -1 ? data.length : zeroIndex;
    final text = latin1.decode(data.sublist(offset, end), allowInvalid: true);
    return _CStringResult(
      text: text,
      nextOffset: end + (zeroIndex == -1 ? 0 : 1),
    );
  }

  static ({List<int> first, List<int> second}) _splitAtNull(
    List<int> data,
    int separatorLength,
  ) {
    if (separatorLength == 2) {
      for (var i = 0; i + 1 < data.length; i += 2) {
        if (data[i] == 0 && data[i + 1] == 0) {
          return (first: data.sublist(0, i), second: data.sublist(i + 2));
        }
      }
      return (first: data, second: const <int>[]);
    }

    final index = data.indexOf(0);
    if (index == -1) {
      return (first: data, second: const <int>[]);
    }

    return (first: data.sublist(0, index), second: data.sublist(index + 1));
  }

  static int? _parseOptionalOffset(int value) =>
      value == 0xFFFFFFFF ? null : value;

  String? _extractEmbeddedTitle(
    List<int> data,
    Id3v2MajorVersion majorVersion,
  ) {
    final frameId = majorVersion == 2 ? 'TT2' : 'TIT2';
    final frameIdBytes = ascii.encode(frameId);
    final frameHeaderLength = FrameHeader.getFrameHeaderLength(majorVersion);
    final frameParser = FrameParser(
      majorVersion,
      warningCollector: metadata.addWarning,
    );

    var offset = 0;
    while (offset + frameHeaderLength <= data.length) {
      final headerBytes = data.sublist(offset, offset + frameHeaderLength);
      final header = FrameHeader.parse(
        headerBytes,
        majorVersion,
        warningCollector: metadata.addWarning,
      );
      if (header.isPadding || header.length < 0) {
        return null;
      }

      final payloadOffset = offset + frameHeaderLength;
      final payloadEnd = payloadOffset + header.length;
      if (payloadEnd > data.length) {
        return null;
      }

      final idBytes = headerBytes.sublist(0, frameIdBytes.length);
      if (const ListEquality<int>().equals(idBytes, frameIdBytes)) {
        final value = frameParser.readData(
          data.sublist(payloadOffset, payloadEnd),
          frameId,
          includeCovers: false,
        );
        if (value is String && value.isNotEmpty) {
          return value;
        }
      }

      offset = payloadEnd;
    }

    return null;
  }

  static List<Chapter>? mapId3v2Chapters(
    List<Id3v2ChapterFrame> chapterFrames,
    List<Id3v2TocFrame> tocFrames,
  ) {
    if (chapterFrames.isEmpty) {
      return null;
    }

    final chapterById = <String, Id3v2ChapterFrame>{
      for (final chapter in chapterFrames) chapter.label: chapter,
    };

    final topLevelToc = tocFrames
        .where((toc) => toc.flags.topLevel)
        .firstOrNull;
    final sourceIds =
        topLevelToc != null && topLevelToc.childElementIds.isNotEmpty
        ? topLevelToc.childElementIds
        : chapterById.keys.toList();

    final chapters = <Chapter>[];
    for (final id in sourceIds) {
      final chapter = chapterById[id];
      if (chapter == null) {
        continue;
      }

      final titleValue = chapter.frames['TIT2'] ?? chapter.frames['TT2'];
      final title = titleValue is String
          ? titleValue
          : titleValue is List<String> && titleValue.isNotEmpty
          ? titleValue.first
          : null;
      final resolvedTitle = (title == null || title.isEmpty) ? id : title;

      chapters.add(
        Chapter(
          id: id,
          title: resolvedTitle,
          url: chapter.frames['WXXX'] as Url?,
          sampleOffset: chapter.info.startOffset,
          start: chapter.info.startTime,
          end: chapter.info.endTime == 0xFFFFFFFF ? null : chapter.info.endTime,
          image: chapter.frames['APIC'] as Picture?,
        ),
      );
    }

    if (topLevelToc == null) {
      chapters.sort((a, b) => a.start.compareTo(b.start));
    }

    return chapters.isEmpty ? null : chapters;
  }
}

class _CStringResult {
  const _CStringResult({required this.text, required this.nextOffset});
  final String text;
  final int nextOffset;
}

class _ParsedFrames {
  const _ParsedFrames({
    required this.tags,
    required this.chapters,
    required this.tocs,
  });
  final Map<String, dynamic> tags;
  final List<Id3v2ChapterFrame> chapters;
  final List<Id3v2TocFrame> tocs;
}
