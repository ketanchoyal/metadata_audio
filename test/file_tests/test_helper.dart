import 'dart:io';

import 'package:metadata_audio/metadata_audio.dart';
import 'package:test/test.dart';

/// Helper to check format metadata fields
void checkFormat(
  Format format, {
  String? container,
  String? codec,
  String? codecProfile,
  int? sampleRate,
  int? numberOfChannels,
  int? bitrate,
  double? duration,
  int? numberOfSamples,
  bool? lossless,
}) {
  if (container != null) {
    expect(format.container, equals(container), reason: 'format.container');
  }
  if (codec != null) {
    expect(format.codec, equals(codec), reason: 'format.codec');
  }
  if (codecProfile != null) {
    expect(
      format.codecProfile,
      equals(codecProfile),
      reason: 'format.codecProfile',
    );
  }
  if (sampleRate != null) {
    expect(format.sampleRate, equals(sampleRate), reason: 'format.sampleRate');
  }
  if (numberOfChannels != null) {
    expect(
      format.numberOfChannels,
      equals(numberOfChannels),
      reason: 'format.numberOfChannels',
    );
  }
  if (bitrate != null) {
    expect(format.bitrate, equals(bitrate), reason: 'format.bitrate');
  }
  if (duration != null) {
    expect(format.duration, closeTo(duration, 0.1), reason: 'format.duration');
  }
  if (numberOfSamples != null) {
    expect(
      format.numberOfSamples,
      equals(numberOfSamples),
      reason: 'format.numberOfSamples',
    );
  }
  if (lossless != null) {
    expect(format.lossless, equals(lossless), reason: 'format.lossless');
  }
}

/// Helper to check common metadata fields
void checkCommon(
  CommonTags common, {
  String? title,
  String? artist,
  String? album,
  String? albumartist,
  int? year,
  int? track,
  int? disk,
  List<String>? genre,
  List<String>? composer,
}) {
  if (title != null) {
    expect(common.title, equals(title), reason: 'common.title');
  }
  if (artist != null) {
    expect(common.artist, equals(artist), reason: 'common.artist');
  }
  if (album != null) {
    expect(common.album, equals(album), reason: 'common.album');
  }
  if (albumartist != null) {
    expect(
      common.albumartist,
      equals(albumartist),
      reason: 'common.albumartist',
    );
  }
  if (year != null) {
    expect(common.year, equals(year), reason: 'common.year');
  }
  if (track != null) {
    expect(common.track.no, equals(track), reason: 'common.track.no');
  }
  if (disk != null) {
    expect(common.disk.no, equals(disk), reason: 'common.disk.no');
  }
  if (genre != null) {
    expect(common.genre, equals(genre), reason: 'common.genre');
  }
  if (composer != null) {
    expect(common.composer, equals(composer), reason: 'common.composer');
  }
}

/// Get the path to the test samples directory
String get samplePath => '${Directory.current.path}/test/samples';
