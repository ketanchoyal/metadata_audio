library;

import 'dart:convert';

class XingInfoTag {
  final int? numFrames;
  final int? streamSize;
  final List<int>? toc;
  final int? vbrScale;
  final String? lameVersion;
  final int? lameMusicLengthMs;

  const XingInfoTag({
    required this.numFrames,
    required this.streamSize,
    required this.toc,
    required this.vbrScale,
    required this.lameVersion,
    required this.lameMusicLengthMs,
  });
}

int _readUint32Be(List<int> data, int offset) {
  return (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];
}

String _asciiTrimNull(List<int> bytes) {
  final text = ascii.decode(bytes, allowInvalid: true);
  return text.replaceAll(RegExp(r'\x00+$'), '').trim();
}

XingInfoTag parseXingHeader(List<int> data, int offset) {
  if (offset + 4 > data.length) {
    return const XingInfoTag(
      numFrames: null,
      streamSize: null,
      toc: null,
      vbrScale: null,
      lameVersion: null,
      lameMusicLengthMs: null,
    );
  }

  var cursor = offset;
  final flags = _readUint32Be(data, cursor);
  cursor += 4;

  int? numFrames;
  int? streamSize;
  List<int>? toc;
  int? vbrScale;

  if ((flags & 0x00000001) != 0 && cursor + 4 <= data.length) {
    numFrames = _readUint32Be(data, cursor);
    cursor += 4;
  }

  if ((flags & 0x00000002) != 0 && cursor + 4 <= data.length) {
    streamSize = _readUint32Be(data, cursor);
    cursor += 4;
  }

  if ((flags & 0x00000004) != 0 && cursor + 100 <= data.length) {
    toc = data.sublist(cursor, cursor + 100);
    cursor += 100;
  }

  if ((flags & 0x00000008) != 0 && cursor + 4 <= data.length) {
    vbrScale = _readUint32Be(data, cursor);
    cursor += 4;
  }

  String? lameVersion;
  int? lameMusicLengthMs;
  if (cursor + 9 <= data.length) {
    final lameTag = ascii.decode(
      data.sublist(cursor, cursor + 4),
      allowInvalid: true,
    );
    if (lameTag == 'LAME') {
      final versionField = data.sublist(cursor + 4, cursor + 9);
      lameVersion = _asciiTrimNull(versionField);

      final extOffset = cursor + 9;
      if (extOffset + 27 <= data.length) {
        lameMusicLengthMs = _readUint32Be(data, extOffset + 20);
      }
    }
  }

  return XingInfoTag(
    numFrames: numFrames,
    streamSize: streamSize,
    toc: toc,
    vbrScale: vbrScale,
    lameVersion: lameVersion,
    lameMusicLengthMs: lameMusicLengthMs,
  );
}
