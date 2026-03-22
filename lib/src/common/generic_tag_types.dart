/// Generic tag type catalog with singleton/list semantics.
///
/// Defines common tag types used across different audio metadata formats,
/// and specifies whether each tag should be treated as a singleton value
/// or as a list of values, and whether duplicate values should be unique.
///
/// Based on upstream: https://github.com/Borewit/music-metadata/blob/master/lib/common/GenericTagTypes.ts
library;

/// Enumeration of common generic tag types.
enum GenericTagType {
  // Core metadata
  title,
  artist,
  artists,
  album,
  albumArtist,
  albumArtists,
  year,
  date,
  originalDate,
  originalYear,
  releaseDate,
  track,
  disk,
  totalTracks,
  totalDiscs,

  // Descriptive tags
  genre,
  comment,
  picture,
  lyrics,

  // Sorting keys
  titleSort,
  artistSort,
  albumSort,
  albumArtistSort,
  composerSort,

  // Creator roles
  composer,
  lyricist,
  writer,
  conductor,
  remixer,
  arranger,
  engineer,
  technician,
  producer,
  djMixer,
  mixer,
  publisher,
  label,

  // Album/release info
  grouping,
  subtitle,
  discSubtitle,
  compilation,
  work,
  media,
  catalognNumber,

  // Recording info
  bpm,
  key,
  mood,
  rating,
  averageLevel,
  peakLevel,

  // Metadata tags
  copyright,
  license,
  encodedBy,
  encoderSettings,
  gapless,

  // Content identifiers
  barcode,
  isrc,
  asin,

  // MusicBrainz identifiers
  musicBrainzRecordingId,
  musicBrainzTrackId,
  musicBrainzAlbumId,
  musicBrainzArtistId,
  musicBrainzAlbumArtistId,
  musicBrainzReleaseGroupId,
  musicBrainzWorkId,
  musicBrainzTrmId,
  musicBrainzDiscId,

  // Acoustic ID
  acoustIdId,
  acoustIdFingerprint,

  // MusicIP identifiers
  musicIpPuid,
  musicIpFingerprint,

  // Discogs identifiers
  discogsArtistId,
  discogsReleaseId,
  discogsLabelId,
  discogsMasterReleaseId,
  discogsVotes,
  discogsRating,

  // ReplayGain tags
  replaygainTrackGain,
  replaygainTrackPeak,
  replaygainAlbumGain,
  replaygainAlbumPeak,
  replaygainTrackMinMax,
  replaygainAlbumMinMax,
  replaygainUndo,

  // Video/TV tags
  tvShow,
  tvShowSort,
  tvSeason,
  tvEpisode,
  tvEpisodeId,
  tvNetwork,
  hdVideo,

  // Podcast tags
  podcast,
  podcastUrl,
  podcastId,

  // Release info
  releaseStatus,
  releaseType,
  releaseCountry,
  originalAlbum,
  originalArtist,

  // Misc metadata
  script,
  language,
  description,
  longDescription,
  notes,
  website,
  category,
  keywords,
  movement,
  movementIndex,
  movementTotal,
  showMovement,
  stik,
  playCounter,

  // Additional identifiers
  performerInstrument,
}

/// Defines the semantics of a tag (singleton vs list, unique vs duplicate).
class TagTypeSemantics {
  const TagTypeSemantics({required this.isSingleton, this.isUnique = false});

  /// Whether this tag should have at most one value (singleton).
  /// If false, the tag can have multiple values (list).
  final bool isSingleton;

  /// Whether duplicate values should be filtered to keep only unique values.
  /// Only relevant when [isSingleton] is false.
  final bool isUnique;
}

/// Catalog of generic tag types and their semantics.
class GenericTagTypes {
  GenericTagTypes._();
  static const Map<String, TagTypeSemantics> _semanticsMap = {
    // Core metadata - most are singletons
    'title': TagTypeSemantics(isSingleton: true),
    'artist': TagTypeSemantics(isSingleton: true),
    'artists': TagTypeSemantics(isSingleton: false, isUnique: true),
    'album': TagTypeSemantics(isSingleton: true),
    'albumartist': TagTypeSemantics(isSingleton: true),
    'albumartists': TagTypeSemantics(isSingleton: false, isUnique: true),
    'year': TagTypeSemantics(isSingleton: true),
    'date': TagTypeSemantics(isSingleton: true),
    'originaldate': TagTypeSemantics(isSingleton: true),
    'originalyear': TagTypeSemantics(isSingleton: true),
    'releasedate': TagTypeSemantics(isSingleton: true),
    'track': TagTypeSemantics(isSingleton: true),
    'disk': TagTypeSemantics(isSingleton: true),
    'totaltracks': TagTypeSemantics(isSingleton: true),
    'totaldiscs': TagTypeSemantics(isSingleton: true),

    // Descriptive tags - often lists
    'genre': TagTypeSemantics(isSingleton: false, isUnique: true),
    'comment': TagTypeSemantics(isSingleton: false),
    'picture': TagTypeSemantics(isSingleton: false, isUnique: true),
    'lyrics': TagTypeSemantics(isSingleton: false),

    // Sorting keys - singletons
    'titlesort': TagTypeSemantics(isSingleton: true),
    'artistsort': TagTypeSemantics(isSingleton: true),
    'albumsort': TagTypeSemantics(isSingleton: true),
    'albumartistsort': TagTypeSemantics(isSingleton: true),
    'composersort': TagTypeSemantics(isSingleton: true),

    // Creator roles - typically lists with unique values
    'composer': TagTypeSemantics(isSingleton: false, isUnique: true),
    'lyricist': TagTypeSemantics(isSingleton: false, isUnique: true),
    'writer': TagTypeSemantics(isSingleton: false, isUnique: true),
    'conductor': TagTypeSemantics(isSingleton: false, isUnique: true),
    'remixer': TagTypeSemantics(isSingleton: false, isUnique: true),
    'arranger': TagTypeSemantics(isSingleton: false, isUnique: true),
    'engineer': TagTypeSemantics(isSingleton: false, isUnique: true),
    'technician': TagTypeSemantics(isSingleton: false, isUnique: true),
    'producer': TagTypeSemantics(isSingleton: false, isUnique: true),
    'djmixer': TagTypeSemantics(isSingleton: false, isUnique: true),
    'mixer': TagTypeSemantics(isSingleton: false, isUnique: true),
    'publisher': TagTypeSemantics(isSingleton: false, isUnique: true),
    'label': TagTypeSemantics(isSingleton: false, isUnique: true),

    // Album/release info
    'grouping': TagTypeSemantics(isSingleton: true),
    'subtitle': TagTypeSemantics(isSingleton: false),
    'discsubtitle': TagTypeSemantics(isSingleton: true),
    'compilation': TagTypeSemantics(isSingleton: true),
    'work': TagTypeSemantics(isSingleton: true),
    'media': TagTypeSemantics(isSingleton: true),
    'catalognumber': TagTypeSemantics(isSingleton: false, isUnique: true),

    // Recording info
    'bpm': TagTypeSemantics(isSingleton: true),
    'key': TagTypeSemantics(isSingleton: true),
    'mood': TagTypeSemantics(isSingleton: true),
    'rating': TagTypeSemantics(isSingleton: false),
    'averagelevel': TagTypeSemantics(isSingleton: true),
    'peaklevel': TagTypeSemantics(isSingleton: true),

    // Metadata tags
    'copyright': TagTypeSemantics(isSingleton: true),
    'license': TagTypeSemantics(isSingleton: true),
    'encodedby': TagTypeSemantics(isSingleton: true),
    'encodersettings': TagTypeSemantics(isSingleton: true),
    'gapless': TagTypeSemantics(isSingleton: true),

    // Content identifiers - mostly singletons
    'barcode': TagTypeSemantics(isSingleton: true),
    'isrc': TagTypeSemantics(isSingleton: false),
    'asin': TagTypeSemantics(isSingleton: true),

    // MusicBrainz identifiers - mostly singletons except artist IDs
    'musicbrainz_recordingid': TagTypeSemantics(isSingleton: true),
    'musicbrainz_trackid': TagTypeSemantics(isSingleton: true),
    'musicbrainz_albumid': TagTypeSemantics(isSingleton: true),
    'musicbrainz_artistid': TagTypeSemantics(isSingleton: false),
    'musicbrainz_albumartistid': TagTypeSemantics(isSingleton: false),
    'musicbrainz_releasegroupid': TagTypeSemantics(isSingleton: true),
    'musicbrainz_workid': TagTypeSemantics(isSingleton: true),
    'musicbrainz_trmid': TagTypeSemantics(isSingleton: true),
    'musicbrainz_discid': TagTypeSemantics(isSingleton: true),

    // Acoustic ID
    'acoustid_id': TagTypeSemantics(isSingleton: true),
    'acoustid_fingerprint': TagTypeSemantics(isSingleton: true),

    // MusicIP identifiers
    'musicip_puid': TagTypeSemantics(isSingleton: true),
    'musicip_fingerprint': TagTypeSemantics(isSingleton: true),

    // Discogs identifiers
    'discogs_artist_id': TagTypeSemantics(isSingleton: false, isUnique: true),
    'discogs_release_id': TagTypeSemantics(isSingleton: true),
    'discogs_label_id': TagTypeSemantics(isSingleton: true),
    'discogs_master_release_id': TagTypeSemantics(isSingleton: true),
    'discogs_votes': TagTypeSemantics(isSingleton: true),
    'discogs_rating': TagTypeSemantics(isSingleton: true),

    // ReplayGain tags - all singletons
    'replaygain_track_gain': TagTypeSemantics(isSingleton: true),
    'replaygain_track_peak': TagTypeSemantics(isSingleton: true),
    'replaygain_album_gain': TagTypeSemantics(isSingleton: true),
    'replaygain_album_peak': TagTypeSemantics(isSingleton: true),
    'replaygain_track_minmax': TagTypeSemantics(isSingleton: true),
    'replaygain_album_minmax': TagTypeSemantics(isSingleton: true),
    'replaygain_undo': TagTypeSemantics(isSingleton: true),

    // Video/TV tags
    'tvshow': TagTypeSemantics(isSingleton: true),
    'tvshowsort': TagTypeSemantics(isSingleton: true),
    'tvseason': TagTypeSemantics(isSingleton: true),
    'tvepisode': TagTypeSemantics(isSingleton: true),
    'tvepisodeid': TagTypeSemantics(isSingleton: true),
    'tvnetwork': TagTypeSemantics(isSingleton: true),
    'hdvideo': TagTypeSemantics(isSingleton: true),

    // Podcast tags
    'podcast': TagTypeSemantics(isSingleton: true),
    'podcasturl': TagTypeSemantics(isSingleton: true),
    'podcastid': TagTypeSemantics(isSingleton: true),

    // Release info
    'releasestatus': TagTypeSemantics(isSingleton: true),
    'releasetype': TagTypeSemantics(isSingleton: false),
    'releasecountry': TagTypeSemantics(isSingleton: true),
    'originalalbum': TagTypeSemantics(isSingleton: true),
    'originalartist': TagTypeSemantics(isSingleton: true),

    // Misc metadata
    'script': TagTypeSemantics(isSingleton: true),
    'language': TagTypeSemantics(isSingleton: true),
    'description': TagTypeSemantics(isSingleton: false),
    'longdescription': TagTypeSemantics(isSingleton: true),
    'notes': TagTypeSemantics(isSingleton: false),
    'website': TagTypeSemantics(isSingleton: true),
    'category': TagTypeSemantics(isSingleton: false),
    'keywords': TagTypeSemantics(isSingleton: false),
    'movement': TagTypeSemantics(isSingleton: true),
    'movementindex': TagTypeSemantics(isSingleton: true),
    'movementtotal': TagTypeSemantics(isSingleton: true),
    'showmovement': TagTypeSemantics(isSingleton: true),
    'stik': TagTypeSemantics(isSingleton: true),
    'playcounter': TagTypeSemantics(isSingleton: true),

    // Additional identifiers
    'performer:instrument': TagTypeSemantics(
      isSingleton: false,
      isUnique: true,
    ),
  };

  static TagTypeSemantics getSemantics(String tagName) =>
      _semanticsMap[tagName.toLowerCase()] ??
      const TagTypeSemantics(isSingleton: true);

  static bool isSingleton(String tagName) => getSemantics(tagName).isSingleton;

  static bool isList(String tagName) => !isSingleton(tagName);

  static bool isUnique(String tagName) =>
      getSemantics(tagName).isUnique || isSingleton(tagName);

  static Set<String> get allTagNames => _semanticsMap.keys.toSet();

  static Set<String> get singletonTags => _semanticsMap.entries
      .where((e) => e.value.isSingleton)
      .map((e) => e.key)
      .toSet();

  static Set<String> get listTags => _semanticsMap.entries
      .where((e) => !e.value.isSingleton)
      .map((e) => e.key)
      .toSet();

  static Set<String> get uniqueTags => _semanticsMap.entries
      .where((e) => e.value.isSingleton || e.value.isUnique)
      .map((e) => e.key)
      .toSet();
}
