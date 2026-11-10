import 'package:metadata_audio/src/common/allocation.dart';
import 'package:metadata_audio/src/model/types.dart';

const Set<String> _coverNativeTagIds = <String>{
  'covr',
  'APIC',
  'PIC',
  'METADATA_BLOCK_PICTURE',
  'Cover Art (Front)',
  'Cover Art (Back)',
  'WM/Picture',
};

/// Returns a view of [metadata] shaped to match the caller's [options]
/// without mutating or discarding richer cached data.
AudioMetadata applyParseOptionsView(
  AudioMetadata metadata,
  ParseOptions options,
) {
  var format = metadata.format;
  var common = metadata.common;
  var native = metadata.native;
  var changed = false;

  if (!options.includeChapters && format.chapters != null) {
    format = _formatWithChapters(format, null);
    changed = true;
  } else if (options.includeChapters && format.chapters != null) {
    final maxChapters = getMaxChapterCount(options);
    if (format.chapters!.length > maxChapters) {
      format = _formatWithChapters(
        format,
        format.chapters!.sublist(0, maxChapters),
      );
      changed = true;
    }
  }

  if (options.skipCovers) {
    if (common.picture != null) {
      common = _commonTagsWithPicture(common, null);
      changed = true;
    }
    final filteredNative = _stripCoverNativeTags(native);
    if (filteredNative != null) {
      native = filteredNative;
      changed = true;
    }
  }

  if (!changed) {
    return metadata;
  }

  return AudioMetadata(
    format: format,
    native: native,
    common: common,
    quality: metadata.quality,
  );
}

/// Merges [delta] metadata (fetched for newly enabled [ParseOptions]) into
/// [existing] cached metadata so all previously cached information is retained.
AudioMetadata mergeAudioMetadata({
  required AudioMetadata existing,
  required AudioMetadata delta,
  bool preferExistingCommon = false,
  bool replaceChapters = false,
  bool replaceCovers = false,
  bool replaceDuration = false,
}) {
  final mergedTagTypes = <String>{
    ...existing.format.tagTypes,
    ...delta.format.tagTypes,
  }.toList();

  final mergedChapters = replaceChapters
      ? (delta.format.chapters ?? existing.format.chapters)
      : (existing.format.chapters ?? delta.format.chapters);

  final mergedDuration = replaceDuration
      ? (delta.format.duration ?? existing.format.duration)
      : (existing.format.duration ?? delta.format.duration);
  final mergedSamples = replaceDuration
      ? (delta.format.numberOfSamples ?? existing.format.numberOfSamples)
      : (existing.format.numberOfSamples ?? delta.format.numberOfSamples);
  final mergedBitrate = replaceDuration
      ? (delta.format.bitrate ?? existing.format.bitrate)
      : (existing.format.bitrate ?? delta.format.bitrate);
  final mergedContainerDuration = replaceDuration
      ? (delta.format.containerDuration ?? existing.format.containerDuration)
      : (existing.format.containerDuration ?? delta.format.containerDuration);
  final mergedOverallBitrate = replaceDuration
      ? (delta.format.overallBitrate ?? existing.format.overallBitrate)
      : (existing.format.overallBitrate ?? delta.format.overallBitrate);

  final mergedFormat = Format(
    container: existing.format.container ?? delta.format.container,
    tagTypes: mergedTagTypes,
    duration: mergedDuration,
    bitrate: mergedBitrate,
    sampleRate: existing.format.sampleRate ?? delta.format.sampleRate,
    bitsPerSample: existing.format.bitsPerSample ?? delta.format.bitsPerSample,
    tool: existing.format.tool ?? delta.format.tool,
    codec: existing.format.codec ?? delta.format.codec,
    codecProfile: existing.format.codecProfile ?? delta.format.codecProfile,
    lossless: existing.format.lossless ?? delta.format.lossless,
    numberOfChannels:
        existing.format.numberOfChannels ?? delta.format.numberOfChannels,
    numberOfSamples: mergedSamples,
    audioMD5: existing.format.audioMD5 ?? delta.format.audioMD5,
    chapters: mergedChapters,
    creationTime: existing.format.creationTime ?? delta.format.creationTime,
    modificationTime:
        existing.format.modificationTime ?? delta.format.modificationTime,
    trackGain: existing.format.trackGain ?? delta.format.trackGain,
    trackPeakLevel:
        existing.format.trackPeakLevel ?? delta.format.trackPeakLevel,
    albumGain: existing.format.albumGain ?? delta.format.albumGain,
    hasAudio: existing.format.hasAudio ?? delta.format.hasAudio,
    hasVideo: existing.format.hasVideo ?? delta.format.hasVideo,
    trackInfo: existing.format.trackInfo.isNotEmpty
        ? existing.format.trackInfo
        : delta.format.trackInfo,
    containerDuration: mergedContainerDuration,
    overallBitrate: mergedOverallBitrate,
  );

  // Merge native tags: delta re-parsed formats with more options enabled, so
  // delta's tag list for a given formatId supersedes existing's unless empty.
  final mergedNative = <String, List<Tag>>{};
  for (final entry in existing.native.entries) {
    mergedNative[entry.key] = List<Tag>.from(entry.value);
  }
  for (final entry in delta.native.entries) {
    if (entry.value.isNotEmpty || !mergedNative.containsKey(entry.key)) {
      mergedNative[entry.key] = List<Tag>.from(entry.value);
    }
  }

  final primaryCommon = preferExistingCommon ? existing.common : delta.common;
  final fallbackCommon = preferExistingCommon ? delta.common : existing.common;
  var mergedCommon = _mergeCommonTags(primaryCommon, fallbackCommon);
  if (replaceCovers) {
    mergedCommon = _commonTagsWithPicture(
      mergedCommon,
      delta.common.picture ?? existing.common.picture,
    );
  } else {
    mergedCommon = _commonTagsWithPicture(
      mergedCommon,
      existing.common.picture ?? delta.common.picture,
    );
  }

  final seenWarnings = <String>{};
  final mergedWarnings = <ParserWarning>[];
  for (final w in [...existing.quality.warnings, ...delta.quality.warnings]) {
    if (seenWarnings.add(w.message)) {
      mergedWarnings.add(w);
    }
  }

  return AudioMetadata(
    format: mergedFormat,
    native: mergedNative,
    common: mergedCommon,
    quality: QualityInformation(warnings: mergedWarnings),
  );
}

/// Emits summary metadata events to [observer] when returning cached metadata.
void emitCachedMetadataEvents(
  AudioMetadata metadata,
  MetadataObserver observer,
) {
  if (metadata.format.container != null) {
    observer(
      MetadataEvent(
        tag: FormatMetadataEventTag<String?>(
          id: MetadataFormatId.container,
          value: metadata.format.container,
        ),
        metadata: metadata,
      ),
    );
  }
  if (metadata.format.duration != null) {
    observer(
      MetadataEvent(
        tag: FormatMetadataEventTag<double?>(
          id: MetadataFormatId.duration,
          value: metadata.format.duration,
        ),
        metadata: metadata,
      ),
    );
  }
  if (metadata.format.chapters != null) {
    observer(
      MetadataEvent(
        tag: FormatMetadataEventTag<List<Chapter>?>(
          id: MetadataFormatId.chapters,
          value: metadata.format.chapters,
        ),
        metadata: metadata,
      ),
    );
  }
  if (metadata.common.title != null) {
    observer(
      MetadataEvent(
        tag: CommonMetadataEventTag<String?>(
          id: MetadataCommonId.title,
          value: metadata.common.title,
        ),
        metadata: metadata,
      ),
    );
  }
  if (metadata.common.artist != null) {
    observer(
      MetadataEvent(
        tag: CommonMetadataEventTag<String?>(
          id: MetadataCommonId.artist,
          value: metadata.common.artist,
        ),
        metadata: metadata,
      ),
    );
  }
}

Format _formatWithChapters(Format f, List<Chapter>? chapters) => Format(
  container: f.container,
  tagTypes: f.tagTypes,
  duration: f.duration,
  bitrate: f.bitrate,
  sampleRate: f.sampleRate,
  bitsPerSample: f.bitsPerSample,
  tool: f.tool,
  codec: f.codec,
  codecProfile: f.codecProfile,
  lossless: f.lossless,
  numberOfChannels: f.numberOfChannels,
  numberOfSamples: f.numberOfSamples,
  audioMD5: f.audioMD5,
  chapters: chapters,
  creationTime: f.creationTime,
  modificationTime: f.modificationTime,
  trackGain: f.trackGain,
  trackPeakLevel: f.trackPeakLevel,
  albumGain: f.albumGain,
  hasAudio: f.hasAudio,
  hasVideo: f.hasVideo,
  trackInfo: f.trackInfo,
  containerDuration: f.containerDuration,
  overallBitrate: f.overallBitrate,
);

NativeTags? _stripCoverNativeTags(NativeTags native) {
  var modified = false;
  final result = <String, List<Tag>>{};
  for (final entry in native.entries) {
    final filtered = entry.value
        .where((tag) => !_coverNativeTagIds.contains(tag.id))
        .toList();
    if (filtered.length != entry.value.length) {
      modified = true;
    }
    result[entry.key] = filtered;
  }
  return modified ? result : null;
}

TrackNo _mergeTrackNo(TrackNo primary, TrackNo fallback) =>
    (primary.no != null || primary.of != null) ? primary : fallback;

CommonTags _mergeCommonTags(CommonTags primary, CommonTags fallback) =>
    CommonTags(
      track: _mergeTrackNo(primary.track, fallback.track),
      disk: _mergeTrackNo(primary.disk, fallback.disk),
      movementIndex: _mergeTrackNo(
        primary.movementIndex,
        fallback.movementIndex,
      ),
      year: primary.year ?? fallback.year,
      title: primary.title ?? fallback.title,
      artist: primary.artist ?? fallback.artist,
      artists: primary.artists ?? fallback.artists,
      albumartist: primary.albumartist ?? fallback.albumartist,
      albumartists: primary.albumartists ?? fallback.albumartists,
      album: primary.album ?? fallback.album,
      date: primary.date ?? fallback.date,
      originaldate: primary.originaldate ?? fallback.originaldate,
      originalyear: primary.originalyear ?? fallback.originalyear,
      releasedate: primary.releasedate ?? fallback.releasedate,
      comment: primary.comment ?? fallback.comment,
      genre: primary.genre ?? fallback.genre,
      picture: primary.picture ?? fallback.picture,
      composer: primary.composer ?? fallback.composer,
      lyrics: primary.lyrics ?? fallback.lyrics,
      albumsort: primary.albumsort ?? fallback.albumsort,
      titlesort: primary.titlesort ?? fallback.titlesort,
      work: primary.work ?? fallback.work,
      artistsort: primary.artistsort ?? fallback.artistsort,
      albumartistsort: primary.albumartistsort ?? fallback.albumartistsort,
      composersort: primary.composersort ?? fallback.composersort,
      lyricist: primary.lyricist ?? fallback.lyricist,
      writer: primary.writer ?? fallback.writer,
      conductor: primary.conductor ?? fallback.conductor,
      remixer: primary.remixer ?? fallback.remixer,
      arranger: primary.arranger ?? fallback.arranger,
      engineer: primary.engineer ?? fallback.engineer,
      publisher: primary.publisher ?? fallback.publisher,
      producer: primary.producer ?? fallback.producer,
      djmixer: primary.djmixer ?? fallback.djmixer,
      mixer: primary.mixer ?? fallback.mixer,
      technician: primary.technician ?? fallback.technician,
      label: primary.label ?? fallback.label,
      grouping: primary.grouping ?? fallback.grouping,
      subtitle: primary.subtitle ?? fallback.subtitle,
      description: primary.description ?? fallback.description,
      longDescription: primary.longDescription ?? fallback.longDescription,
      discsubtitle: primary.discsubtitle ?? fallback.discsubtitle,
      totaltracks: primary.totaltracks ?? fallback.totaltracks,
      totaldiscs: primary.totaldiscs ?? fallback.totaldiscs,
      movementTotal: primary.movementTotal ?? fallback.movementTotal,
      compilation: primary.compilation ?? fallback.compilation,
      rating: primary.rating ?? fallback.rating,
      bpm: primary.bpm ?? fallback.bpm,
      mood: primary.mood ?? fallback.mood,
      media: primary.media ?? fallback.media,
      catalognumber: primary.catalognumber ?? fallback.catalognumber,
      tvShow: primary.tvShow ?? fallback.tvShow,
      tvShowSort: primary.tvShowSort ?? fallback.tvShowSort,
      tvSeason: primary.tvSeason ?? fallback.tvSeason,
      tvEpisode: primary.tvEpisode ?? fallback.tvEpisode,
      tvEpisodeId: primary.tvEpisodeId ?? fallback.tvEpisodeId,
      tvNetwork: primary.tvNetwork ?? fallback.tvNetwork,
      podcast: primary.podcast ?? fallback.podcast,
      podcasturl: primary.podcasturl ?? fallback.podcasturl,
      releasestatus: primary.releasestatus ?? fallback.releasestatus,
      releasetype: primary.releasetype ?? fallback.releasetype,
      releasecountry: primary.releasecountry ?? fallback.releasecountry,
      script: primary.script ?? fallback.script,
      language: primary.language ?? fallback.language,
      copyright: primary.copyright ?? fallback.copyright,
      license: primary.license ?? fallback.license,
      encodedby: primary.encodedby ?? fallback.encodedby,
      encodersettings: primary.encodersettings ?? fallback.encodersettings,
      gapless: primary.gapless ?? fallback.gapless,
      barcode: primary.barcode ?? fallback.barcode,
      isrc: primary.isrc ?? fallback.isrc,
      asin: primary.asin ?? fallback.asin,
      musicbrainz_recordingid:
          primary.musicbrainz_recordingid ?? fallback.musicbrainz_recordingid,
      musicbrainz_trackid:
          primary.musicbrainz_trackid ?? fallback.musicbrainz_trackid,
      musicbrainz_albumid:
          primary.musicbrainz_albumid ?? fallback.musicbrainz_albumid,
      musicbrainz_artistid:
          primary.musicbrainz_artistid ?? fallback.musicbrainz_artistid,
      musicbrainz_albumartistid:
          primary.musicbrainz_albumartistid ??
          fallback.musicbrainz_albumartistid,
      musicbrainz_releasegroupid:
          primary.musicbrainz_releasegroupid ??
          fallback.musicbrainz_releasegroupid,
      musicbrainz_workid:
          primary.musicbrainz_workid ?? fallback.musicbrainz_workid,
      musicbrainz_trmid:
          primary.musicbrainz_trmid ?? fallback.musicbrainz_trmid,
      musicbrainz_discid:
          primary.musicbrainz_discid ?? fallback.musicbrainz_discid,
      acoustid_id: primary.acoustid_id ?? fallback.acoustid_id,
      acoustid_fingerprint:
          primary.acoustid_fingerprint ?? fallback.acoustid_fingerprint,
      musicip_puid: primary.musicip_puid ?? fallback.musicip_puid,
      musicip_fingerprint:
          primary.musicip_fingerprint ?? fallback.musicip_fingerprint,
      website: primary.website ?? fallback.website,
      performerInstrument:
          primary.performerInstrument ?? fallback.performerInstrument,
      averageLevel: primary.averageLevel ?? fallback.averageLevel,
      peakLevel: primary.peakLevel ?? fallback.peakLevel,
      notes: primary.notes ?? fallback.notes,
      originalalbum: primary.originalalbum ?? fallback.originalalbum,
      originalartist: primary.originalartist ?? fallback.originalartist,
      discogs_artist_id:
          primary.discogs_artist_id ?? fallback.discogs_artist_id,
      discogs_release_id:
          primary.discogs_release_id ?? fallback.discogs_release_id,
      discogs_label_id: primary.discogs_label_id ?? fallback.discogs_label_id,
      discogs_master_release_id:
          primary.discogs_master_release_id ??
          fallback.discogs_master_release_id,
      discogs_votes: primary.discogs_votes ?? fallback.discogs_votes,
      discogs_rating: primary.discogs_rating ?? fallback.discogs_rating,
      replaygain_track_gain_ratio:
          primary.replaygain_track_gain_ratio ??
          fallback.replaygain_track_gain_ratio,
      replaygain_track_peak_ratio:
          primary.replaygain_track_peak_ratio ??
          fallback.replaygain_track_peak_ratio,
      replaygain_track_gain:
          primary.replaygain_track_gain ?? fallback.replaygain_track_gain,
      replaygain_track_peak:
          primary.replaygain_track_peak ?? fallback.replaygain_track_peak,
      replaygain_album_gain:
          primary.replaygain_album_gain ?? fallback.replaygain_album_gain,
      replaygain_album_peak:
          primary.replaygain_album_peak ?? fallback.replaygain_album_peak,
      replaygain_undo: primary.replaygain_undo ?? fallback.replaygain_undo,
      replaygain_track_minmax:
          primary.replaygain_track_minmax ?? fallback.replaygain_track_minmax,
      replaygain_album_minmax:
          primary.replaygain_album_minmax ?? fallback.replaygain_album_minmax,
      key: primary.key ?? fallback.key,
      category: primary.category ?? fallback.category,
      hdVideo: primary.hdVideo ?? fallback.hdVideo,
      keywords: primary.keywords ?? fallback.keywords,
      movement: primary.movement ?? fallback.movement,
      podcastId: primary.podcastId ?? fallback.podcastId,
      showMovement: primary.showMovement ?? fallback.showMovement,
      stik: primary.stik ?? fallback.stik,
      playCounter: primary.playCounter ?? fallback.playCounter,
    );

CommonTags _commonTagsWithPicture(CommonTags c, List<Picture>? picture) =>
    CommonTags(
      track: c.track,
      disk: c.disk,
      movementIndex: c.movementIndex,
      year: c.year,
      title: c.title,
      artist: c.artist,
      artists: c.artists,
      albumartist: c.albumartist,
      albumartists: c.albumartists,
      album: c.album,
      date: c.date,
      originaldate: c.originaldate,
      originalyear: c.originalyear,
      releasedate: c.releasedate,
      comment: c.comment,
      genre: c.genre,
      picture: picture,
      composer: c.composer,
      lyrics: c.lyrics,
      albumsort: c.albumsort,
      titlesort: c.titlesort,
      work: c.work,
      artistsort: c.artistsort,
      albumartistsort: c.albumartistsort,
      composersort: c.composersort,
      lyricist: c.lyricist,
      writer: c.writer,
      conductor: c.conductor,
      remixer: c.remixer,
      arranger: c.arranger,
      engineer: c.engineer,
      publisher: c.publisher,
      producer: c.producer,
      djmixer: c.djmixer,
      mixer: c.mixer,
      technician: c.technician,
      label: c.label,
      grouping: c.grouping,
      subtitle: c.subtitle,
      description: c.description,
      longDescription: c.longDescription,
      discsubtitle: c.discsubtitle,
      totaltracks: c.totaltracks,
      totaldiscs: c.totaldiscs,
      movementTotal: c.movementTotal,
      compilation: c.compilation,
      rating: c.rating,
      bpm: c.bpm,
      mood: c.mood,
      media: c.media,
      catalognumber: c.catalognumber,
      tvShow: c.tvShow,
      tvShowSort: c.tvShowSort,
      tvSeason: c.tvSeason,
      tvEpisode: c.tvEpisode,
      tvEpisodeId: c.tvEpisodeId,
      tvNetwork: c.tvNetwork,
      podcast: c.podcast,
      podcasturl: c.podcasturl,
      releasestatus: c.releasestatus,
      releasetype: c.releasetype,
      releasecountry: c.releasecountry,
      script: c.script,
      language: c.language,
      copyright: c.copyright,
      license: c.license,
      encodedby: c.encodedby,
      encodersettings: c.encodersettings,
      gapless: c.gapless,
      barcode: c.barcode,
      isrc: c.isrc,
      asin: c.asin,
      musicbrainz_recordingid: c.musicbrainz_recordingid,
      musicbrainz_trackid: c.musicbrainz_trackid,
      musicbrainz_albumid: c.musicbrainz_albumid,
      musicbrainz_artistid: c.musicbrainz_artistid,
      musicbrainz_albumartistid: c.musicbrainz_albumartistid,
      musicbrainz_releasegroupid: c.musicbrainz_releasegroupid,
      musicbrainz_workid: c.musicbrainz_workid,
      musicbrainz_trmid: c.musicbrainz_trmid,
      musicbrainz_discid: c.musicbrainz_discid,
      acoustid_id: c.acoustid_id,
      acoustid_fingerprint: c.acoustid_fingerprint,
      musicip_puid: c.musicip_puid,
      musicip_fingerprint: c.musicip_fingerprint,
      website: c.website,
      performerInstrument: c.performerInstrument,
      averageLevel: c.averageLevel,
      peakLevel: c.peakLevel,
      notes: c.notes,
      originalalbum: c.originalalbum,
      originalartist: c.originalartist,
      discogs_artist_id: c.discogs_artist_id,
      discogs_release_id: c.discogs_release_id,
      discogs_label_id: c.discogs_label_id,
      discogs_master_release_id: c.discogs_master_release_id,
      discogs_votes: c.discogs_votes,
      discogs_rating: c.discogs_rating,
      replaygain_track_gain_ratio: c.replaygain_track_gain_ratio,
      replaygain_track_peak_ratio: c.replaygain_track_peak_ratio,
      replaygain_track_gain: c.replaygain_track_gain,
      replaygain_track_peak: c.replaygain_track_peak,
      replaygain_album_gain: c.replaygain_album_gain,
      replaygain_album_peak: c.replaygain_album_peak,
      replaygain_undo: c.replaygain_undo,
      replaygain_track_minmax: c.replaygain_track_minmax,
      replaygain_album_minmax: c.replaygain_album_minmax,
      key: c.key,
      category: c.category,
      hdVideo: c.hdVideo,
      keywords: c.keywords,
      movement: c.movement,
      podcastId: c.podcastId,
      showMovement: c.showMovement,
      stik: c.stik,
      playCounter: c.playCounter,
    );
