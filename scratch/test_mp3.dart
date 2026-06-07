import 'dart:io';
import 'dart:typed_data';
import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/mpeg/mpeg_parser.dart';
import 'package:metadata_audio/src/mpeg/xing_tag.dart';
import 'package:metadata_audio/src/utils/chapter_downloader.dart';

// Copying internal private helpers from ChapterDownloader to diagnose
Future<int> _findMpegAudioOffset(Tokenizer tokenizer) async {
  var offset = 0;
  while (true) {
    try {
      final bytes = tokenizer.peekBytes(10);
      if (bytes.length < 10) break;
      final tag = String.fromCharCodes(bytes.sublist(0, 3));
      if (tag == 'ID3') {
        final sizeBytes = bytes.sublist(6, 10);
        final size = (sizeBytes[0] << 21) |
            (sizeBytes[1] << 14) |
            (sizeBytes[2] << 7) |
            sizeBytes[3];
        final hasFooter = (bytes[5] & 0x10) != 0;
        final totalTagSize = 10 + size + (hasFooter ? 10 : 0);
        tokenizer.skip(totalTagSize);
        offset += totalTagSize;
      } else {
        break;
      }
    } catch (_) {
      break;
    }
  }
  return offset;
}

Future<MpegFrameHeader?> _findFirstMpegFrame(
    Tokenizer tokenizer, int mpegOffset) async {
  tokenizer.seek(mpegOffset);
  while (true) {
    try {
      final sync = tokenizer.peekBytes(4);
      if (sync.length < 4) return null;
      if (sync[0] == 0xFF && (sync[1] & 0xE0) == 0xE0) {
        if (!MpegFrameHeader.isAdtsHeader(sync)) {
          final header = MpegFrameHeader.parse(sync);
          if (header != null) return header;
        }
      }
      tokenizer.skip(1);
    } catch (_) {
      return null;
    }
  }
}

Future<XingInfoTag?> _findXingHeader(
  Tokenizer tokenizer,
  MpegFrameHeader header,
  int mpegOffset,
) async {
  try {
    tokenizer.seek(mpegOffset);
    final frameData = tokenizer.peekBytes(header.frameLength);
    if (frameData.length < header.frameLength) return null;

    var offset = 4;
    if (header.isProtectedByCrc) {
      offset += 2;
    }

    final sideInfoLength = header.sideInformationLength;
    if (sideInfoLength == null) return null;
    offset += sideInfoLength;

    if (offset + 4 > frameData.length) return null;
    final tag = String.fromCharCodes(frameData.sublist(offset, offset + 4));
    if (tag == 'Xing' || tag == 'Info') {
      return parseXingHeader(frameData, offset + 4);
    }
  } catch (_) {}
  return null;
}

double _interpolateToc(List<int> toc, double percent) {
  if (percent <= 0) return 0;
  if (percent >= 100) return 255;

  final index = percent.floor().clamp(0, 98);
  final fraction = percent - index;

  final val1 = toc[index] & 0xFF;
  final val2 = toc[index + 1] & 0xFF;

  return val1 + (val2 - val1) * fraction;
}

void diagnoseFile(String name, String path, int startMs, int endMs) async {
  print('=== DIAGNOSING: $name ===');
  final file = File(path);
  if (!file.existsSync()) {
    print('File does not exist at $path');
    return;
  }
  final tokenizer = FileTokenizer.fromFile(file);
  try {
    final mpegOffset = await _findMpegAudioOffset(tokenizer);
    final header = await _findFirstMpegFrame(tokenizer, mpegOffset);
    if (header == null) {
      print('Failed to find first MPEG frame header.');
      return;
    }
    final xingInfo = await _findXingHeader(tokenizer, header, mpegOffset);

    final frameDurationMs = (header.samplesPerFrame * 1000) / header.sampleRate;
    int startByte;
    int endByte;

    if (xingInfo != null &&
        xingInfo.toc != null &&
        xingInfo.streamSize != null &&
        xingInfo.numFrames != null) {
      final totalDurationMs = (xingInfo.numFrames! * header.samplesPerFrame * 1000) /
              header.sampleRate;

      final startPercent = (startMs / totalDurationMs) * 100;
      final endPercent = (endMs / totalDurationMs) * 100;

      final startOffsetNormalized = _interpolateToc(xingInfo.toc!, startPercent);
      final endOffsetNormalized = _interpolateToc(xingInfo.toc!, endPercent);

      startByte = mpegOffset +
          ((startOffsetNormalized / 256.0) * xingInfo.streamSize!).round();
      endByte = mpegOffset +
          ((endOffsetNormalized / 256.0) * xingInfo.streamSize!).round();
    } else {
      final startFrame = startMs ~/ frameDurationMs;
      final endFrame = (endMs / frameDurationMs).ceil();
      startByte = mpegOffset + startFrame * header.frameLength;
      endByte = mpegOffset + endFrame * header.frameLength;
    }

    final fileSize = tokenizer.fileInfo?.size;
    if (fileSize != null) {
      startByte = startByte.clamp(mpegOffset, fileSize);
      endByte = endByte.clamp(mpegOffset, fileSize);
    }

    final downloadSize = endByte - startByte;
    print('  Range: $startByte to $endByte (size: $downloadSize)');

    // Read the payload bytes
    final payloadBytes = await file.openRead(startByte, endByte).fold<BytesBuilder>(
      BytesBuilder(),
      (bb, chunk) => bb..add(chunk),
    ).then((bb) => bb.takeBytes());

    // Align start
    var alignedStart = 0;
    while (alignedStart < payloadBytes.length - 4) {
      if (payloadBytes[alignedStart] == 0xFF &&
          (payloadBytes[alignedStart + 1] & 0xE0) == 0xE0) {
        final sync = payloadBytes.sublist(alignedStart, alignedStart + 4);
        if (!MpegFrameHeader.isAdtsHeader(sync)) {
          final header = MpegFrameHeader.parse(sync);
          if (header != null) {
            break;
          }
        }
      }
      alignedStart++;
    }

    print('  Original first 5 bytes: ${payloadBytes.sublist(0, 5.clamp(0, payloadBytes.length))}');
    print('  Aligned start index: $alignedStart');
    final sliced = payloadBytes.sublist(alignedStart);
    print('  Aligned first 5 bytes: ${sliced.sublist(0, 5.clamp(0, sliced.length))}');
  } finally {
    tokenizer.close();
  }
  print('\n');
}

void main() {
  diagnoseFile('no-tags.mp3', '${Directory.current.path}/test/samples/mp3/no-tags.mp3', 0, 1000);
  diagnoseFile('id3v2.3.mp3', '${Directory.current.path}/test/samples/mp3/id3v2.3.mp3', 100, 600);
}
