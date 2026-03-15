library;

/// Metadata event observer callback type
///
/// Called with incremental metadata updates during parsing
typedef MetadataObserver = void Function(MetadataEvent event);

/// Tag representation with id and value
class Tag {

  /// Create a Tag
  const Tag({required this.id, required this.value});
  /// Tag identifier
  final String id;

  /// Tag value
  final dynamic value;

  @override
  String toString() => 'Tag(id: $id, value: $value)';
}

/// Parser warning information
class ParserWarning {

  /// Create a ParserWarning
  const ParserWarning({required this.message});
  /// Warning message
  final String message;

  @override
  String toString() => 'ParserWarning(message: $message)';
}

/// Picture/cover art information
class Picture {

  /// Create a Picture
  const Picture({
    required this.format,
    required this.data,
    this.description,
    this.type,
    this.name,
  });
  /// Image MIME type (e.g., 'image/jpeg')
  final String format;

  /// Image data as bytes
  final List<int> data;

  /// Optional description
  final String? description;

  /// Picture type
  final String? type;

  /// File name
  final String? name;

  @override
  String toString() =>
      'Picture(format: $format, size: ${data.length}, description: $description)';
}

/// Rating information
class Rating {

  /// Create a Rating
  const Rating({this.source, this.rating});
  /// Rating source (typically an email address)
  final String? source;

  /// Rating value [0..1]
  final double? rating;

  @override
  String toString() => 'Rating(source: $source, rating: $rating)';
}

/// Comment information
class Comment {

  /// Create a Comment
  const Comment({this.descriptor, this.language, this.text});
  /// Optional descriptor/type
  final String? descriptor;

  /// Language code
  final String? language;

  /// Comment text
  final String? text;

  @override
  String toString() =>
      'Comment(descriptor: $descriptor, language: $language, text: $text)';
}

/// Lyrics text with optional timestamp
class LyricsText {

  /// Create LyricsText
  const LyricsText({required this.text, this.timestamp});
  /// Lyrics text content
  final String text;

  /// Optional timestamp in milliseconds
  final int? timestamp;

  @override
  String toString() {
    final preview = text.length > 20 ? text.substring(0, 20) : text;
    return 'LyricsText(text: $preview${text.length > 20 ? '...' : ''}, timestamp: $timestamp)';
  }
}

/// Synchronized lyrics tag
class LyricsTag extends Comment {

  /// Create LyricsTag
  const LyricsTag({
    required this.contentType, required this.timeStampFormat, required this.syncText, super.descriptor,
    super.language,
    super.text,
  });
  /// Content type
  final String contentType;

  /// Timestamp format
  final String timeStampFormat;

  /// Synchronized lyrics
  final List<LyricsText> syncText;

  @override
  String toString() =>
      'LyricsTag(contentType: $contentType, syncLines: ${syncText.length})';
}

/// Audio track information
class AudioTrack {

  /// Create AudioTrack
  const AudioTrack({
    this.samplingFrequency,
    this.outputSamplingFrequency,
    this.channels,
    this.channelPositions,
    this.bitDepth,
  });
  /// Sampling frequency in Hz
  final int? samplingFrequency;

  /// Output sampling frequency in Hz
  final int? outputSamplingFrequency;

  /// Number of channels
  final int? channels;

  /// Channel positions
  final List<int>? channelPositions;

  /// Bit depth
  final int? bitDepth;

  @override
  String toString() =>
      'AudioTrack(freq: $samplingFrequency, channels: $channels, bitDepth: $bitDepth)';
}

/// Video track information
class VideoTrack {

  /// Create VideoTrack
  const VideoTrack({
    this.flagInterlaced,
    this.stereoMode,
    this.pixelWidth,
    this.pixelHeight,
    this.displayWidth,
    this.displayHeight,
    this.displayUnit,
    this.aspectRatioType,
    this.colourSpace,
    this.gammaValue,
  });
  /// Interlaced flag
  final bool? flagInterlaced;

  /// Stereo mode
  final int? stereoMode;

  /// Pixel width
  final int? pixelWidth;

  /// Pixel height
  final int? pixelHeight;

  /// Display width
  final int? displayWidth;

  /// Display height
  final int? displayHeight;

  /// Display unit
  final int? displayUnit;

  /// Aspect ratio type
  final int? aspectRatioType;

  /// Colour space
  final List<int>? colourSpace;

  /// Gamma value
  final double? gammaValue;

  @override
  String toString() =>
      'VideoTrack(${pixelWidth}x$pixelHeight, interlaced: $flagInterlaced)';
}

/// Track information
class TrackInfo {

  /// Create TrackInfo
  const TrackInfo({
    this.type,
    this.codecName,
    this.codecSettings,
    this.flagEnabled,
    this.flagDefault,
    this.flagLacing,
    this.name,
    this.language,
    this.audio,
    this.video,
  });
  /// Track type
  final String? type;

  /// Codec name
  final String? codecName;

  /// Codec settings
  final String? codecSettings;

  /// Enabled flag
  final bool? flagEnabled;

  /// Default flag
  final bool? flagDefault;

  /// Lacing flag
  final bool? flagLacing;

  /// Track name
  final String? name;

  /// Language
  final String? language;

  /// Audio track info
  final AudioTrack? audio;

  /// Video track info
  final VideoTrack? video;

  @override
  String toString() =>
      'TrackInfo(type: $type, codec: $codecName, lang: $language)';
}

/// URL reference
class Url {

  /// Create Url
  const Url({required this.url, required this.description});
  /// URL string
  final String url;

  /// URL description
  final String description;

  @override
  String toString() => 'Url($url)';
}

/// Chapter information
class Chapter {

  /// Create Chapter
  const Chapter({
    required this.title, required this.start, this.id,
    this.url,
    this.sampleOffset,
    this.end,
    this.timeScale,
    this.image,
  });
  /// Internal chapter reference
  final String? id;

  /// Chapter title
  final String title;

  /// URL reference
  final Url? url;

  /// Audio offset in samples
  final int? sampleOffset;

  /// Chapter start timestamp
  final int start;

  /// Chapter end timestamp
  final int? end;

  /// Timescale (units per second)
  final int? timeScale;

  /// Chapter cover image
  final Picture? image;

  @override
  String toString() => 'Chapter(title: $title, start: $start, end: $end)';
}

/// Ratio with dB value
class Ratio {

  /// Create Ratio
  const Ratio({required this.ratio, required this.dB});
  /// Ratio value [0..1]
  final double ratio;

  /// Decibel value
  final double dB;

  @override
  String toString() => 'Ratio(ratio: $ratio, dB: $dB)';
}

/// TrackNo with number and total
class TrackNo {

  /// Create TrackNo
  const TrackNo({this.no, this.of});
  /// Track number
  final int? no;

  /// Total number of tracks
  final int? of;

  @override
  String toString() => 'TrackNo($no${of != null ? '/$of' : ''})';
}

/// Format information about the audio
class Format {

  /// Create Format
  const Format({
    this.container,
    this.tagTypes = const [],
    this.duration,
    this.bitrate,
    this.sampleRate,
    this.bitsPerSample,
    this.tool,
    this.codec,
    this.codecProfile,
    this.lossless,
    this.numberOfChannels,
    this.numberOfSamples,
    this.audioMD5,
    this.chapters,
    this.creationTime,
    this.modificationTime,
    this.trackGain,
    this.trackPeakLevel,
    this.albumGain,
    this.hasAudio,
    this.hasVideo,
    this.trackInfo = const [],
  });
  /// Container format (e.g., 'flac', 'mp3')
  final String? container;

  /// List of tag types found
  final List<String> tagTypes;

  /// Duration in seconds
  final double? duration;

  /// Bitrate in bits per second
  final num? bitrate;

  /// Sample rate in samples per second
  final int? sampleRate;

  /// Bits per sample
  final int? bitsPerSample;

  /// Tool/encoder name
  final String? tool;

  /// Codec name
  final String? codec;

  /// Codec profile
  final String? codecProfile;

  /// Whether the audio is lossless
  final bool? lossless;

  /// Number of audio channels
  final int? numberOfChannels;

  /// Number of sample frames
  final int? numberOfSamples;

  /// MD5 hash of raw audio
  final List<int>? audioMD5;

  /// Chapters in the audio
  final List<Chapter>? chapters;

  /// File creation time
  final DateTime? creationTime;

  /// File modification time
  final DateTime? modificationTime;

  /// Track gain
  final double? trackGain;

  /// Track peak level
  final double? trackPeakLevel;

  /// Album gain
  final double? albumGain;

  /// Whether file contains audio
  final bool? hasAudio;

  /// Whether file contains video
  final bool? hasVideo;

  /// Track information
  final List<TrackInfo> trackInfo;

  @override
  String toString() =>
      'Format(container: $container, codec: $codec, duration: $duration, bitrate: $bitrate)';
}

/// Common tags (standardized metadata)
class CommonTags {

  /// Create CommonTags
  const CommonTags({
    required this.track,
    required this.disk,
    required this.movementIndex,
    this.year,
    this.title,
    this.artist,
    this.artists,
    this.albumartist,
    this.albumartists,
    this.album,
    this.date,
    this.originaldate,
    this.originalyear,
    this.releasedate,
    this.comment,
    this.genre,
    this.picture,
    this.composer,
    this.lyrics,
    this.albumsort,
    this.titlesort,
    this.work,
    this.artistsort,
    this.albumartistsort,
    this.composersort,
    this.lyricist,
    this.writer,
    this.conductor,
    this.remixer,
    this.arranger,
    this.engineer,
    this.publisher,
    this.producer,
    this.djmixer,
    this.mixer,
    this.technician,
    this.label,
    this.grouping,
    this.subtitle,
    this.description,
    this.longDescription,
    this.discsubtitle,
    this.totaltracks,
    this.totaldiscs,
    this.movementTotal,
    this.compilation,
    this.rating,
    this.bpm,
    this.mood,
    this.media,
    this.catalognumber,
    this.tvShow,
    this.tvShowSort,
    this.tvSeason,
    this.tvEpisode,
    this.tvEpisodeId,
    this.tvNetwork,
    this.podcast,
    this.podcasturl,
    this.releasestatus,
    this.releasetype,
    this.releasecountry,
    this.script,
    this.language,
    this.copyright,
    this.license,
    this.encodedby,
    this.encodersettings,
    this.gapless,
    this.barcode,
    this.isrc,
    this.asin,
    this.musicbrainz_recordingid,
    this.musicbrainz_trackid,
    this.musicbrainz_albumid,
    this.musicbrainz_artistid,
    this.musicbrainz_albumartistid,
    this.musicbrainz_releasegroupid,
    this.musicbrainz_workid,
    this.musicbrainz_trmid,
    this.musicbrainz_discid,
    this.acoustid_id,
    this.acoustid_fingerprint,
    this.musicip_puid,
    this.musicip_fingerprint,
    this.website,
    this.performerInstrument,
    this.averageLevel,
    this.peakLevel,
    this.notes,
    this.originalalbum,
    this.originalartist,
    this.discogs_artist_id,
    this.discogs_release_id,
    this.discogs_label_id,
    this.discogs_master_release_id,
    this.discogs_votes,
    this.discogs_rating,
    this.replaygain_track_gain_ratio,
    this.replaygain_track_peak_ratio,
    this.replaygain_track_gain,
    this.replaygain_track_peak,
    this.replaygain_album_gain,
    this.replaygain_album_peak,
    this.replaygain_undo,
    this.replaygain_track_minmax,
    this.replaygain_album_minmax,
    this.key,
    this.category,
    this.hdVideo,
    this.keywords,
    this.movement,
    this.podcastId,
    this.showMovement,
    this.stik,
    this.playCounter,
  });
  /// Track number
  final TrackNo track;

  /// Disk/disc number
  final TrackNo disk;

  /// Release year
  final int? year;

  /// Track title
  final String? title;

  /// Artist name
  final String? artist;

  /// Multiple artists
  final List<String>? artists;

  /// Album artist
  final String? albumartist;

  /// Multiple album artists
  final List<String>? albumartists;

  /// Album title
  final String? album;

  /// Date
  final String? date;

  /// Original release date
  final String? originaldate;

  /// Original release year
  final int? originalyear;

  /// Release date
  final String? releasedate;

  /// Comments
  final List<Comment>? comment;

  /// Genre(s)
  final List<String>? genre;

  /// Cover art images
  final List<Picture>? picture;

  /// Composer(s)
  final List<String>? composer;

  /// Lyrics
  final List<LyricsTag>? lyrics;

  /// Album sort name
  final String? albumsort;

  /// Title sort name
  final String? titlesort;

  /// Canonical work title
  final String? work;

  /// Artist sort name
  final String? artistsort;

  /// Album artist sort name
  final String? albumartistsort;

  /// Composer sort name
  final String? composersort;

  /// Lyricist(s)
  final List<String>? lyricist;

  /// Writer(s)
  final List<String>? writer;

  /// Conductor(s)
  final List<String>? conductor;

  /// Remixer(s)
  final List<String>? remixer;

  /// Arranger(s)
  final List<String>? arranger;

  /// Engineer(s)
  final List<String>? engineer;

  /// Publisher(s)
  final List<String>? publisher;

  /// Producer(s)
  final List<String>? producer;

  /// DJ mixer(s)
  final List<String>? djmixer;

  /// Mixed by
  final List<String>? mixer;

  /// Technician(s)
  final List<String>? technician;

  /// Label(s)
  final List<String>? label;

  /// Grouping
  final String? grouping;

  /// Subtitle(s)
  final List<String>? subtitle;

  /// Description(s)
  final List<String>? description;

  /// Long description
  final String? longDescription;

  /// Disc subtitle(s)
  final List<String>? discsubtitle;

  /// Total tracks
  final String? totaltracks;

  /// Total discs
  final String? totaldiscs;

  /// Movement total
  final int? movementTotal;

  /// Compilation flag
  final bool? compilation;

  /// Ratings
  final List<Rating>? rating;

  /// BPM
  final int? bpm;

  /// Mood
  final String? mood;

  /// Media type
  final String? media;

  /// Catalog number(s)
  final List<String>? catalognumber;

  /// TV show title
  final String? tvShow;

  /// TV show sort title
  final String? tvShowSort;

  /// TV season number
  final int? tvSeason;

  /// TV episode number
  final int? tvEpisode;

  /// TV episode ID
  final String? tvEpisodeId;

  /// TV network
  final String? tvNetwork;

  /// Podcast flag
  final bool? podcast;

  /// Podcast URL
  final String? podcasturl;

  /// Release status
  final String? releasestatus;

  /// Release type(s)
  final List<String>? releasetype;

  /// Release country
  final String? releasecountry;

  /// Script
  final String? script;

  /// Language
  final String? language;

  /// Copyright
  final String? copyright;

  /// License
  final String? license;

  /// Encoded by
  final String? encodedby;

  /// Encoder settings
  final String? encodersettings;

  /// Gapless flag
  final bool? gapless;

  /// Barcode
  final String? barcode;

  /// ISRC code(s)
  final List<String>? isrc;

  /// ASIN
  final String? asin;

  /// MusicBrainz recording ID
  final String? musicbrainz_recordingid;

  /// MusicBrainz track ID
  final String? musicbrainz_trackid;

  /// MusicBrainz album ID
  final String? musicbrainz_albumid;

  /// MusicBrainz artist ID(s)
  final List<String>? musicbrainz_artistid;

  /// MusicBrainz album artist ID(s)
  final List<String>? musicbrainz_albumartistid;

  /// MusicBrainz release group ID
  final String? musicbrainz_releasegroupid;

  /// MusicBrainz work ID
  final String? musicbrainz_workid;

  /// MusicBrainz TRM ID
  final String? musicbrainz_trmid;

  /// MusicBrainz disc ID
  final String? musicbrainz_discid;

  /// AcoustID ID
  final String? acoustid_id;

  /// AcoustID fingerprint
  final String? acoustid_fingerprint;

  /// MusicIP PUID
  final String? musicip_puid;

  /// MusicIP fingerprint
  final String? musicip_fingerprint;

  /// Website
  final String? website;

  /// Performer instruments
  final List<String>? performerInstrument;

  /// Average level
  final double? averageLevel;

  /// Peak level
  final double? peakLevel;

  /// Notes
  final List<String>? notes;

  /// Original album
  final String? originalalbum;

  /// Original artist
  final String? originalartist;

  /// Discogs artist ID(s)
  final List<int>? discogs_artist_id;

  /// Discogs release ID
  final int? discogs_release_id;

  /// Discogs label ID
  final int? discogs_label_id;

  /// Discogs master release ID
  final int? discogs_master_release_id;

  /// Discogs votes
  final int? discogs_votes;

  /// Discogs rating
  final double? discogs_rating;

  /// ReplayGain track gain ratio [0..1]
  final double? replaygain_track_gain_ratio;

  /// ReplayGain track peak ratio [0..1]
  final double? replaygain_track_peak_ratio;

  /// ReplayGain track gain
  final Ratio? replaygain_track_gain;

  /// ReplayGain track peak
  final Ratio? replaygain_track_peak;

  /// ReplayGain album gain
  final Ratio? replaygain_album_gain;

  /// ReplayGain album peak
  final Ratio? replaygain_album_peak;

  /// ReplayGain undo (channel gains)
  final Map<String, double>? replaygain_undo;

  /// ReplayGain track minmax
  final List<double>? replaygain_track_minmax;

  /// ReplayGain album minmax
  final List<double>? replaygain_album_minmax;

  /// Musical key
  final String? key;

  /// Podcast category(ies)
  final List<String>? category;

  /// HD video quality (iTunes)
  final int? hdVideo;

  /// Podcast keywords
  final List<String>? keywords;

  /// Movement
  final String? movement;

  /// Movement index/total
  final TrackNo movementIndex;

  /// Podcast ID
  final String? podcastId;

  /// Show movement flag
  final bool? showMovement;

  /// iTunes media type
  final int? stik;

  /// Play counter
  final int? playCounter;

  @override
  String toString() =>
      'CommonTags(title: $title, artist: $artist, album: $album)';
}

/// Quality information with parser warnings
class QualityInformation {

  /// Create QualityInformation
  const QualityInformation({this.warnings = const []});
  /// Parser warnings
  final List<ParserWarning> warnings;

  @override
  String toString() => 'QualityInformation(warnings: ${warnings.length})';
}

/// Map of native tags by type
typedef NativeTags = Map<String, List<Tag>>;

/// Information about the audio file being parsed
///
/// Corresponds to the FileInfo concept used for parsing hints
class FileInfo {

  /// Create FileInfo from file metadata
  const FileInfo({this.path, this.mimeType, this.size, this.url});

  /// Create FileInfo from a local file path
  factory FileInfo.fromPath(String path) => FileInfo(path: path);

  /// Create FileInfo from a URL
  factory FileInfo.fromUrl(String url) => FileInfo(url: url);

  /// Create FileInfo with MIME type hint
  factory FileInfo.withMimeType(String? path, String mimeType) =>
      FileInfo(path: path, mimeType: mimeType);
  /// File path of the audio file
  final String? path;

  /// MIME type hint for the audio file
  ///
  /// Example: 'audio/mpeg', 'audio/flac'
  final String? mimeType;

  /// File size in bytes
  final int? size;

  /// Source URL if the audio data comes from a stream or remote source
  final String? url;
}

/// Options for parsing audio metadata
///
/// Controls parsing behavior and what metadata to extract
class ParseOptions {

  /// Create ParseOptions with custom parsing configuration
  const ParseOptions({
    this.skipCovers = false,
    this.skipPostHeaders = false,
    this.includeChapters = false,
    this.duration = false,
    this.observer,
  });

  /// Create ParseOptions with all parsing enabled
  factory ParseOptions.all({MetadataObserver? observer}) =>
      ParseOptions(includeChapters: true, duration: true, observer: observer);

  /// Create ParseOptions for minimal parsing (fast mode)
  factory ParseOptions.minimal() =>
      const ParseOptions(skipCovers: true, skipPostHeaders: true);

  /// Create ParseOptions for metadata-only parsing
  factory ParseOptions.metadataOnly() =>
      const ParseOptions(skipPostHeaders: true);
  /// Skip reading cover art / picture tags
  ///
  /// Default: false
  final bool skipCovers;

  /// Skip searching for headers after initial metadata
  ///
  /// Useful for streaming scenarios
  /// Default: false
  final bool skipPostHeaders;

  /// Include chapter information if available
  ///
  /// Default: false
  final bool includeChapters;

  /// Calculate/parse duration information
  ///
  /// May require parsing the entire file
  /// Default: false
  final bool duration;

  /// Observer callback for incremental metadata updates
  ///
  /// Called as metadata is discovered during parsing
  final MetadataObserver? observer;
}

/// Event representing a metadata change during parsing
class MetadataEvent {
  /// Create a metadata event
  const MetadataEvent();
}

/// Complete audio metadata including format, native tags, and common tags
class AudioMetadata {

  /// Create AudioMetadata
  const AudioMetadata({
    required this.format,
    required this.native,
    required this.common,
    required this.quality,
  });
  /// Audio format information
  final Format format;

  /// Native tags organized by type
  final NativeTags native;

  /// Common tags (standardized)
  final CommonTags common;

  /// Quality information including warnings
  final QualityInformation quality;

  @override
  String toString() =>
      'AudioMetadata(format: ${format.container}, title: ${common.title}, artist: ${common.artist})';
}
