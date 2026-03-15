#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:metadata_audio/src/aiff/aiff_loader.dart';
import 'package:metadata_audio/src/flac/flac_loader.dart';
import 'package:metadata_audio/src/mp4/mp4_loader.dart';
import 'package:metadata_audio/src/mpeg/mpeg_loader.dart';
import 'package:metadata_audio/src/ogg/ogg_loader.dart';
import 'package:metadata_audio/src/wav/wave_loader.dart';
import 'package:path/path.dart' as p;

final testFiles = [
  'mp3/id3v2.3.mp3',
  'mp3/id3v1.mp3',
  'mp3/no-tags.mp3',
  'mp3/issue-347.mp3',
  'mp3/adts-0-frame.mp3',
  'flac/sample.flac',
  'flac/flac-multiple-album-artists-tags.flac',
  'flac/testcase.flac',
  'ogg/vorbis.ogg',
  'ogg/opus.ogg',
  'mp4/sample.m4a',
  'mp4/The Dark Forest.m4a',
  'wav/issue-819.wav',
  'wav/odd-list-type.wav',
  'aiff/sample.aiff',
];

void main() async {
  // Initialize parsers
  final registry = ParserRegistry()
    ..register(MpegLoader())
    ..register(FlacLoader())
    ..register(OggLoader())
    ..register(Mp4Loader())
    ..register(WaveLoader())
    ..register(AiffLoader());
  initializeParserFactory(ParserFactory(registry));

  final samplesDir = p.join(Directory.current.path, 'test', 'samples');
  final results = <Map<String, dynamic>>[];

  for (final file in testFiles) {
    final filePath = p.join(samplesDir, file);
    final result = await parseAndExtract(file, filePath);
    results.add(result);
  }

  print(const JsonEncoder.withIndent('  ').convert(results));
}

Future<Map<String, dynamic>> parseAndExtract(
  String relativePath,
  String filePath,
) async {
  final file = File(filePath);

  if (!file.existsSync()) {
    return {'file': relativePath, 'error': 'File not found'};
  }

  try {
    final metadata = await parseFile(
      filePath,
      options: const ParseOptions(includeChapters: true),
    );
    final chapters = metadata.format.chapters
        ?.map(
          (chapter) => <String, dynamic>{
            'id': chapter.id,
            'title': chapter.title,
            'start': chapter.start,
            'end': chapter.end,
            'sampleOffset': chapter.sampleOffset,
            'timeScale': chapter.timeScale,
          }..removeWhere((_, value) => value == null),
        )
        .toList();
    final format = <String, dynamic>{
      'container': metadata.format.container,
      'codec': metadata.format.codec,
      'duration': metadata.format.duration,
      'sampleRate': metadata.format.sampleRate,
      'numberOfChannels': metadata.format.numberOfChannels,
      'bitrate': metadata.format.bitrate,
      'lossless': metadata.format.lossless,
      'chapters': chapters,
    }..removeWhere((_, value) => value == null);

    final common =
        <String, dynamic>{
          'title': metadata.common.title,
          'artist': metadata.common.artist,
          'album': metadata.common.album,
          'albumartist': metadata.common.albumartist,
          'year': metadata.common.year,
          'track': {
            'no': metadata.common.track.no,
            'of': metadata.common.track.of,
          },
          'disk': {
            'no': metadata.common.disk.no,
            'of': metadata.common.disk.of,
          },
          'genre': metadata.common.genre,
        }..removeWhere(
          (key, value) => key != 'track' && key != 'disk' && value == null,
        );

    return {
      'file': relativePath,
      'format': format,
      'common': common,
      'native': metadata.native.keys.toList(),
    };
  } catch (e) {
    return {'file': relativePath, 'error': e.toString()};
  }
}
