library;

import 'package:metadata_audio/src/model/types.dart';
import 'package:metadata_audio/src/native/api.dart';

AudioMetadata convertFfiAudioMetadata(FfiAudioMetadata ffi) {
  final pictures = _mergePictures(
    convertFfiPictures(ffi.common.picture),
    convertFfiPictures(ffi.pictures),
  );

  return AudioMetadata(
    format: convertFfiFormat(ffi.format),
    native: convertFfiNativeTags(ffi.native),
    common: _convertFfiCommonTags(ffi.common, picturesOverride: pictures),
    quality: convertWarnings(ffi.warnings),
  );
}

Format convertFfiFormat(FfiFormat ffi) => Format(
  container: _nullIfEmpty(ffi.container),
  tagTypes: List<String>.unmodifiable(ffi.tagTypes),
  duration: ffi.duration,
  bitrate: ffi.bitrate,
  sampleRate: ffi.sampleRate,
  bitsPerSample: ffi.bitsPerSample,
  tool: ffi.tool,
  codec: ffi.codec,
  codecProfile: ffi.codecProfile,
  lossless: ffi.lossless,
  numberOfChannels: ffi.numberOfChannels,
  numberOfSamples: ffi.numberOfSamples?.toInt(),
  trackGain: ffi.trackGain,
  trackPeakLevel: ffi.trackPeakLevel,
  albumGain: ffi.albumGain,
  hasAudio: ffi.hasAudio,
  hasVideo: ffi.hasVideo,
);

CommonTags convertFfiCommonTags(FfiCommonTags ffi) =>
    _convertFfiCommonTags(ffi);

NativeTags convertFfiNativeTags(List<FfiNativeTag> ffi) {
  final nativeTags = <String, List<Tag>>{};

  for (final tag in ffi) {
    final groupKey = _nativeTagKey(tag);
    nativeTags.putIfAbsent(groupKey, () => <Tag>[]).add(
      Tag(id: groupKey, value: tag.value),
    );
  }

  return nativeTags;
}

List<Picture> convertFfiPictures(List<FfiPicture> ffi) => [
  for (final picture in ffi)
    Picture(
      format: picture.format ?? 'application/octet-stream',
      data: picture.data,
      description: picture.description,
      type: picture.type,
      name: picture.name,
    ),
];

QualityInformation convertWarnings(List<String> warnings) => QualityInformation(
  warnings: [
    for (final warning in warnings) ParserWarning(message: warning),
  ],
);

CommonTags _convertFfiCommonTags(
  FfiCommonTags ffi, {
  List<Picture>? picturesOverride,
}) => CommonTags(
  track: _convertTrackNo(ffi.track),
  disk: _convertTrackNo(ffi.disk),
  movementIndex: ffi.movementIndex != null
      ? TrackNo(no: ffi.movementIndex)
      : const TrackNo(),
  year: ffi.year,
  title: ffi.title,
  artist: ffi.artist,
  artists: _nullableStringList(ffi.artists),
  albumartist: ffi.albumartist,
  albumartists: _nullableStringList(ffi.albumartists),
  album: ffi.album,
  date: ffi.date,
  originaldate: ffi.originaldate,
  originalyear: ffi.originalyear,
  releasedate: ffi.releasedate,
  comment: _nullableMappedList(ffi.comment, _convertComment),
  genre: _nullableStringList(ffi.genre),
  picture: picturesOverride ?? _nullablePictures(ffi.picture),
  composer: _nullableStringList(ffi.composer),
  lyrics: _nullableMappedList(ffi.lyrics, _convertLyricsTag),
  albumsort: ffi.albumsort,
  titlesort: ffi.titlesort,
  work: ffi.work,
  artistsort: ffi.artistsort,
  albumartistsort: ffi.albumartistsort,
  composersort: ffi.composersort,
  lyricist: _nullableStringList(ffi.lyricist),
  writer: _nullableStringList(ffi.writer),
  conductor: _nullableStringList(ffi.conductor),
  remixer: _nullableStringList(ffi.remixer),
  arranger: _nullableStringList(ffi.arranger),
  engineer: _nullableStringList(ffi.engineer),
  publisher: _nullableStringList(ffi.publisher),
  producer: _nullableStringList(ffi.producer),
  djmixer: _nullableStringList(ffi.djmixer),
  mixer: _nullableStringList(ffi.mixer),
  technician: _nullableStringList(ffi.technician),
  label: _nullableStringList(ffi.label),
  grouping: ffi.grouping,
  subtitle: _nullableStringList(ffi.subtitle),
  description: _nullableStringList(ffi.description),
  longDescription: ffi.longDescription,
  discsubtitle: _nullableStringList(ffi.discsubtitle),
  totaltracks: ffi.totaltracks,
  totaldiscs: ffi.totaldiscs,
  movementTotal: ffi.movementTotal,
  compilation: ffi.compilation,
  rating: _nullableMappedList(ffi.rating, _convertRating),
  bpm: ffi.bpm,
  mood: ffi.mood,
  media: ffi.media,
  catalognumber: _nullableStringList(ffi.catalognumber),
  tvShow: ffi.tvShow,
  tvShowSort: ffi.tvShowSort,
  tvSeason: ffi.tvSeason,
  tvEpisode: ffi.tvEpisode,
  tvEpisodeId: ffi.tvEpisodeId,
  tvNetwork: ffi.tvNetwork,
  podcast: ffi.podcast,
  podcasturl: ffi.podcasturl,
  releasestatus: ffi.releasestatus,
  releasetype: _nullableStringList(ffi.releasetype),
  releasecountry: ffi.releasecountry,
  script: ffi.script,
  language: ffi.language,
  copyright: ffi.copyright,
  license: ffi.license,
  encodedby: ffi.encodedby,
  encodersettings: ffi.encodersettings,
  gapless: _parseBool(ffi.gapless),
  barcode: ffi.barcode,
  isrc: _wrapString(ffi.isrc),
  asin: ffi.asin,
  musicbrainz_recordingid: ffi.musicbrainzRecordingid,
  musicbrainz_trackid: ffi.musicbrainzTrackid,
  musicbrainz_albumid: ffi.musicbrainzAlbumid,
  musicbrainz_artistid: _wrapString(ffi.musicbrainzArtistid),
  musicbrainz_albumartistid: _wrapString(ffi.musicbrainzAlbumartistid),
  musicbrainz_releasegroupid: ffi.musicbrainzReleasegroupid,
  musicbrainz_workid: ffi.musicbrainzWorkid,
  musicbrainz_trmid: ffi.musicbrainzTrmid,
  musicbrainz_discid: ffi.musicbrainzDiscid,
  acoustid_id: ffi.acoustidId,
  acoustid_fingerprint: ffi.acoustidFingerprint,
  musicip_puid: ffi.musicipPuid,
  musicip_fingerprint: ffi.musicipFingerprint,
  website: ffi.website,
  performerInstrument: _wrapString(ffi.performerInstrument),
  notes: _wrapString(ffi.notes),
  originalalbum: ffi.originalalbum,
  originalartist: ffi.originalartist,
  discogs_artist_id: _parseIntList(ffi.discogsArtistId),
  discogs_release_id: _parseInt(ffi.discogsReleaseId),
  discogs_label_id: _parseInt(ffi.discogsLabelId),
  discogs_master_release_id: _parseInt(ffi.discogsMasterReleaseId),
  discogs_votes: ffi.discogsVotes?.toInt(),
  discogs_rating: ffi.discogsRating,
  replaygain_track_gain_ratio: ffi.replaygainTrackGainRatio,
  replaygain_track_peak_ratio: ffi.replaygainTrackPeakRatio,
  replaygain_track_gain: _ratioFromDouble(ffi.replaygainTrackGain),
  replaygain_track_peak: _ratioFromDouble(ffi.replaygainTrackPeak),
  replaygain_album_gain: _ratioFromDouble(ffi.replaygainAlbumGain),
  replaygain_album_peak: _ratioFromDouble(ffi.replaygainAlbumPeak),
  replaygain_undo: ffi.replaygainUndo != null
      ? <String, double>{'value': ffi.replaygainUndo!}
      : null,
  replaygain_track_minmax: ffi.replaygainTrackMinmax != null
      ? <double>[ffi.replaygainTrackMinmax!]
      : null,
  replaygain_album_minmax: ffi.replaygainAlbumMinmax != null
      ? <double>[ffi.replaygainAlbumMinmax!]
      : null,
  key: ffi.key,
  category: _nullableStringList(ffi.category),
  hdVideo: _parseInt(ffi.hdVideo),
  keywords: _nullableStringList(ffi.keywords),
  movement: ffi.movement,
  podcastId: ffi.podcastId,
  showMovement: _parseBool(ffi.showMovement),
  stik: _parseInt(ffi.stik),
  playCounter: _parseInt(ffi.playCounter),
);

TrackNo _convertTrackNo(FfiTrackNo ffi) => TrackNo(no: ffi.no, of: ffi.of);

Comment _convertComment(FfiComment ffi) => Comment(
  descriptor: ffi.descriptor,
  language: ffi.language,
  text: ffi.text,
);

Rating _convertRating(FfiRating ffi) =>
    Rating(source: ffi.source, rating: ffi.rating);

LyricsTag _convertLyricsTag(FfiLyricsTag ffi) => LyricsTag(
  descriptor: ffi.descriptor,
  language: ffi.language,
  text: ffi.text,
  contentType: 'lyrics',
  timeStampFormat: 'unsynchronized',
  syncText: const <LyricsText>[],
);

List<T>? _nullableMappedList<S, T>(
  List<S> values,
  T Function(S) convert,
) {
  if (values.isEmpty) {
    return null;
  }

  return <T>[for (final value in values) convert(value)];
}

List<String>? _nullableStringList(List<String> values) =>
    values.isEmpty ? null : List<String>.unmodifiable(values);

List<Picture>? _nullablePictures(List<FfiPicture> values) {
  final pictures = convertFfiPictures(values);
  return pictures.isEmpty ? null : pictures;
}

List<String>? _wrapString(String? value) =>
    _nullIfEmpty(value) == null ? null : <String>[value!];

String? _nullIfEmpty(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }

  return value;
}

Ratio? _ratioFromDouble(double? value) =>
    value == null ? null : Ratio(ratio: value, dB: value);

int? _parseInt(String? value) {
  final normalized = _nullIfEmpty(value)?.trim();
  if (normalized == null) {
    return null;
  }

  return int.tryParse(normalized);
}

bool? _parseBool(String? value) {
  final normalized = _nullIfEmpty(value)?.trim().toLowerCase();
  switch (normalized) {
    case '1':
    case 'true':
    case 'yes':
      return true;
    case '0':
    case 'false':
    case 'no':
      return false;
    case null:
      return null;
  }

  return null;
}

List<int>? _parseIntList(String? value) {
  final normalized = _nullIfEmpty(value);
  if (normalized == null) {
    return null;
  }

  final matches = RegExp(r'-?\d+').allMatches(normalized);
  final parsed = <int>[
    for (final match in matches)
      if (match.group(0) != null) int.parse(match.group(0)!),
  ];

  return parsed.isEmpty ? null : parsed;
}

List<Picture>? _mergePictures(List<Picture> first, List<Picture> second) {
  final merged = <Picture>[];

  void addUnique(List<Picture> pictures) {
    for (final picture in pictures) {
      final exists = merged.any(
        (existing) =>
            existing.format == picture.format &&
            existing.description == picture.description &&
            existing.type == picture.type &&
            existing.name == picture.name &&
            _listEquals(existing.data, picture.data),
      );
      if (!exists) {
        merged.add(picture);
      }
    }
  }

  addUnique(first);
  addUnique(second);

  return merged.isEmpty ? null : merged;
}

bool _listEquals(List<int> left, List<int> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }

  return true;
}

String _nativeTagKey(FfiNativeTag tag) {
  final key = tag.key.trim();
  if (key.isNotEmpty) {
    return key;
  }

  final stdKey = tag.stdKey?.trim();
  if (stdKey != null && stdKey.isNotEmpty) {
    return stdKey;
  }

  return 'unknown';
}
