/// Metadata collector that aggregates format, native tags, common tags,
/// and warnings.
///
/// Collects metadata from various sources and resolves tag priorities.
/// Higher-priority formats override lower-priority formats.
///
/// Based on upstream:
/// https://github.com/Borewit/music-metadata/blob/master/lib/common/MetadataCollector.ts
library;

import 'package:metadata_audio/src/common/combined_tag_mapper.dart';
import 'package:metadata_audio/src/common/generic_tag_types.dart';
import 'package:metadata_audio/src/model/types.dart';

/// Collects audio metadata from multiple sources and formats.
///
/// Accumulates format information, native tags from different audio formats,
/// and converts them to common tags using CombinedTagMapper.
/// Tracks warnings that occur during metadata collection.
///
/// Usage:
/// ```dart
/// final collector = MetadataCollector(CombinedTagMapper());
/// collector.setFormat(container: 'mp3');
/// collector.addNativeTag('id3v2', 'TIT2', 'Song Title');
/// collector.addNativeTag('id3v2', 'TPE1', 'Artist');
/// collector.addWarning('ID3v2 frame with invalid encoding detected');
///
/// final metadata = collector.toAudioMetadata();
/// print(metadata.common.title); // 'Song Title'
/// ```
class MetadataCollector {

  /// Create a MetadataCollector with a tag mapper.
  ///
  /// Parameters:
  /// - [tagMapper]: CombinedTagMapper to convert native to common tags
  MetadataCollector(this._tagMapper) {
    // Initialize with default empty format
    _format = const Format();
  }
  static const Map<String, int> _formatPriority = {
    'ID3v1': 1,
    'ID3v2.2': 2,
    'ID3v2.3': 3,
    'ID3v2.4': 4,
  };

  final CombinedTagMapper _tagMapper;

  /// Audio format information
  late Format _format;

  /// Native tags organized by format ID
  /// E.g., {'id3v2': {'TIT2': 'Title', ...}, 'vorbis': {...}}
  final Map<String, Map<String, dynamic>> _nativeTagsByFormat = {};

  /// Aggregated common tags (with priority applied)
  /// Values from higher-priority formats override lower-priority formats
  final Map<String, dynamic> _commonTags = {};

  /// Tracks the source format used for each common tag key
  final Map<String, String> _commonTagSource = {};

  /// Collected warnings
  final List<String> _warnings = [];

  /// Sets the audio format information.
  ///
  /// Parameters:
  /// - [container]: Container format (e.g., 'mp3', 'flac', 'ogg')
  /// - [duration]: Duration in seconds
  /// - [bitrate]: Bitrate in bits per second
  /// - [sampleRate]: Sample rate in Hz
  /// - [bitsPerSample]: Bits per sample
  /// - [codec]: Codec name
  /// - [numberOfChannels]: Number of audio channels
  /// - Additional format properties via named parameters
  void setFormat({
    String? container,
    double? duration,
    num? bitrate,
    int? sampleRate,
    int? bitsPerSample,
    String? codec,
    int? numberOfChannels,
    String? tool,
    String? codecProfile,
    bool? lossless,
    int? numberOfSamples,
    List<int>? audioMD5,
    List<Chapter>? chapters,
    DateTime? creationTime,
    DateTime? modificationTime,
    double? trackGain,
    double? trackPeakLevel,
    double? albumGain,
    bool? hasAudio,
    bool? hasVideo,
    List<TrackInfo>? trackInfo,
  }) {
    _format = Format(
      container: container ?? _format.container,
      tagTypes: _format.tagTypes,
      duration: duration ?? _format.duration,
      bitrate: bitrate ?? _format.bitrate,
      sampleRate: sampleRate ?? _format.sampleRate,
      bitsPerSample: bitsPerSample ?? _format.bitsPerSample,
      tool: tool ?? _format.tool,
      codec: codec ?? _format.codec,
      codecProfile: codecProfile ?? _format.codecProfile,
      lossless: lossless ?? _format.lossless,
      numberOfChannels: numberOfChannels ?? _format.numberOfChannels,
      numberOfSamples: numberOfSamples ?? _format.numberOfSamples,
      audioMD5: audioMD5 ?? _format.audioMD5,
      chapters: chapters ?? _format.chapters,
      creationTime: creationTime ?? _format.creationTime,
      modificationTime: modificationTime ?? _format.modificationTime,
      trackGain: trackGain ?? _format.trackGain,
      trackPeakLevel: trackPeakLevel ?? _format.trackPeakLevel,
      albumGain: albumGain ?? _format.albumGain,
      hasAudio: hasAudio ?? _format.hasAudio,
      hasVideo: hasVideo ?? _format.hasVideo,
      trackInfo: trackInfo ?? _format.trackInfo,
    );
  }

  /// Adds a native tag from a specific format.
  ///
  /// Later calls with the same formatId and tagId override earlier ones.
  /// The tag is immediately converted to common tag(s) if a mapper exists.
  ///
  /// Parameters:
  /// - [formatId]: Format identifier (e.g., 'id3v2', 'vorbis', 'mp4')
  /// - [tagId]: Format-specific tag identifier (e.g., 'TIT2', 'TITLE')
  /// - [value]: Tag value (can be String, int, List, etc.)
  ///
  /// Example:
  /// ```dart
  /// collector.addNativeTag('id3v2', 'TIT2', 'My Song');
  /// collector.addNativeTag('id3v2', 'TPE1', 'The Artist');
  /// ```
  void addNativeTag(String formatId, String tagId, dynamic value) {
    final formatTags = _nativeTagsByFormat.putIfAbsent(formatId, () => {});
    final existingNativeValue = formatTags[tagId];
    if (existingNativeValue == null) {
      formatTags[tagId] = value;
    } else if (existingNativeValue is List) {
      formatTags[tagId] = <dynamic>[...existingNativeValue, value];
    } else {
      formatTags[tagId] = <dynamic>[existingNativeValue, value];
    }

    // Try to convert and merge into common tags if mapper exists
    if (_tagMapper.hasMapper(formatId)) {
      try {
        final genericTags = _tagMapper.mapTags(formatId, {tagId: value});
        for (final entry in genericTags.entries) {
          _mergeCommonTag(formatId, entry.key, entry.value);
        }
      } on UnknownFormatException catch (e) {
        // If mapping fails, just store the native tag
        addWarning('Failed to map $formatId:$tagId to common tag: $e');
      }
    }
  }

  int _getPriority(String formatId) => _formatPriority[formatId] ?? 0;

  void _mergeCommonTag(String formatId, String tagKey, dynamic value) {
    if (value == null) {
      return;
    }

    if (tagKey == 'date') {
      final derivedYear = _deriveYear(value);
      if (derivedYear != null) {
        _mergeCommonTag(formatId, 'year', derivedYear);
      }
    }

    final semantics = GenericTagTypes.getSemantics(tagKey);
    final currentSource = _commonTagSource[tagKey];
    final currentPriority = currentSource == null
        ? -1
        : _getPriority(currentSource);
    final newPriority = _getPriority(formatId);

    if (semantics.isSingleton) {
      if (tagKey == 'artist' &&
          currentSource != null &&
          currentSource == formatId &&
          _commonTags[tagKey] != null) {
        return;
      }

      if (currentSource == null || newPriority >= currentPriority) {
        _commonTags[tagKey] = value;
        _commonTagSource[tagKey] = formatId;
      }
      return;
    }

    if (currentSource != null && newPriority < currentPriority) {
      return;
    }

    final merged = <dynamic>[];
    if (currentSource != null && newPriority == currentPriority) {
      merged.addAll(_asList(_commonTags[tagKey]));
    }
    merged.addAll(_asList(value));

    final normalized = semantics.isUnique
        ? _dedupeValues(merged)
        : List<dynamic>.from(merged);

    _commonTags[tagKey] = normalized;
    _commonTagSource[tagKey] = formatId;
  }

  static List<dynamic> _asList(dynamic value) {
    if (value == null) {
      return const <dynamic>[];
    }
    if (value is List) {
      return List<dynamic>.from(value);
    }
    return <dynamic>[value];
  }

  static List<dynamic> _dedupeValues(List<dynamic> values) {
    final deduped = <dynamic>[];
    final seen = <String>{};
    for (final value in values) {
      final key = value.toString();
      if (seen.add(key)) {
        deduped.add(value);
      }
    }
    return deduped;
  }

  static int? _deriveYear(dynamic value) {
    if (value is! String) {
      return null;
    }
    if (value.length < 4) {
      return null;
    }
    return int.tryParse(value.substring(0, 4));
  }

  /// Converts an int or String to String, returns null if neither.
  static String? _intToString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is int) return value.toString();
    return null;
  }

  static List<T>? _typedList<T>(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is List) {
      final typed = value.whereType<T>().toList();
      return typed.isEmpty ? null : typed;
    }
    return value is T ? <T>[value] : null;
  }

  /// Adds a warning message.
  ///
  /// Parameters:
  /// - [message]: Warning message
  ///
  /// Example:
  /// ```dart
  /// collector.addWarning('Invalid ID3v2 frame encoding');
  /// ```
  void addWarning(String message) {
    _warnings.add(message);
  }

  /// Builds the final AudioMetadata from collected data.
  ///
  /// Converts collected native and common tags into the final AudioMetadata
  /// structure. Returns a complete AudioMetadata object with:
  /// - Format information
  /// - Native tags organized by type
  /// - Common tags (standardized)
  /// - Quality information with warnings
  ///
  /// Returns:
  /// - [AudioMetadata] with all collected and processed metadata
  ///
  /// Example:
  /// ```dart
  /// final collector = MetadataCollector(tagMapper);
  /// collector.setFormat(container: 'mp3');
  /// collector.addNativeTag('id3v2', 'TIT2', 'Song');
  /// final metadata = collector.toAudioMetadata();
  /// ```
  AudioMetadata toAudioMetadata() {
    // Convert native tags to Tag objects organized by format
    final nativeTags = _buildNativeTags();

    // Build common tags from collected data
    final commonTags = _buildCommonTags();

    // Build quality information from warnings
    final quality = QualityInformation(
      warnings: _warnings.map((msg) => ParserWarning(message: msg)).toList(),
    );

    return AudioMetadata(
      format: _format,
      native: nativeTags,
      common: commonTags,
      quality: quality,
    );
  }

  /// Converts native tags map to NativeTags format
  /// (Map&lt;String, List&lt;Tag&gt;&gt;).
  Map<String, List<Tag>> _buildNativeTags() {
    final result = <String, List<Tag>>{};

    for (final formatEntry in _nativeTagsByFormat.entries) {
      final formatId = formatEntry.key;
      final tagsMap = formatEntry.value;

      result[formatId] = [
        for (final tagEntry in tagsMap.entries)
          Tag(id: tagEntry.key, value: tagEntry.value),
      ];
    }

    return result;
  }

  /// Builds CommonTags from collected data.
  ///
  /// Uses default values for required fields and maps collected common tags
  /// to the CommonTags structure.
  CommonTags _buildCommonTags() => CommonTags(
    track: TrackNo(
      no: _commonTags['track'] as int?,
      of: _commonTags['totaltracks'] as int?,
    ),
    disk: TrackNo(
      no: _commonTags['disk'] as int?,
      of: _commonTags['totaldiscs'] as int?,
    ),
    movementIndex: TrackNo(
      no: _commonTags['movement'] as int?,
      of: _commonTags['movementTotal'] as int?,
    ),
    year: _commonTags['year'] as int?,
    title: _commonTags['title'] as String?,
    artist: _commonTags['artist'] as String?,
    artists: _typedList<String>(_commonTags['artists']),
    albumartist: _commonTags['albumartist'] as String?,
    albumartists: _commonTags['albumartists'] as List<String>?,
    album: _commonTags['album'] as String?,
    date: _commonTags['date'] as String?,
    originaldate: _commonTags['originaldate'] as String?,
    originalyear: _commonTags['originalyear'] as int?,
    releasedate: _commonTags['releasedate'] as String?,
    comment: _typedList<Comment>(_commonTags['comment']),
    genre: _typedList<String>(_commonTags['genre']),
    picture: _typedList<Picture>(_commonTags['picture']),
    composer: _typedList<String>(_commonTags['composer']),
    lyrics: _typedList<LyricsTag>(_commonTags['lyrics']),
    albumsort: _commonTags['albumsort'] as String?,
    titlesort: _commonTags['titlesort'] as String?,
    work: _commonTags['work'] as String?,
    artistsort: _commonTags['artistsort'] as String?,
    albumartistsort: _commonTags['albumartistsort'] as String?,
    composersort: _commonTags['composersort'] as String?,
    lyricist: _typedList<String>(_commonTags['lyricist']),
    writer: _typedList<String>(_commonTags['writer']),
    conductor: _typedList<String>(_commonTags['conductor']),
    remixer: _typedList<String>(_commonTags['remixer']),
    arranger: _typedList<String>(_commonTags['arranger']),
    engineer: _typedList<String>(_commonTags['engineer']),
    publisher: _typedList<String>(_commonTags['publisher']),
    producer: _typedList<String>(_commonTags['producer']),
    djmixer: _typedList<String>(_commonTags['djmixer']),
    mixer: _typedList<String>(_commonTags['mixer']),
    technician: _typedList<String>(_commonTags['technician']),
    label: _typedList<String>(_commonTags['label']),
    grouping: _commonTags['grouping'] as String?,
    subtitle: _typedList<String>(_commonTags['subtitle']),
    description: _typedList<String>(_commonTags['description']),
    longDescription: _commonTags['longDescription'] as String?,
    discsubtitle: _commonTags['discsubtitle'] as List<String>?,
    totaltracks: _intToString(_commonTags['totaltracks']),
    totaldiscs: _intToString(_commonTags['totaldiscs']),
    movementTotal: _commonTags['movementTotal'] as int?,
    compilation: _commonTags['compilation'] as bool?,
    rating: _typedList<Rating>(_commonTags['rating']),
    bpm: _commonTags['bpm'] as int?,
    mood: _commonTags['mood'] as String?,
    media: _commonTags['media'] as String?,
    catalognumber: _typedList<String>(_commonTags['catalognumber']),
    tvShow: _commonTags['tvShow'] as String?,
    tvShowSort: _commonTags['tvShowSort'] as String?,
    tvSeason: _commonTags['tvSeason'] as int?,
    tvEpisode: _commonTags['tvEpisode'] as int?,
    tvEpisodeId: _commonTags['tvEpisodeId'] as String?,
    tvNetwork: _commonTags['tvNetwork'] as String?,
    podcast: _commonTags['podcast'] as bool?,
    podcasturl: _commonTags['podcasturl'] as String?,
    releasestatus: _commonTags['releasestatus'] as String?,
    releasetype: _typedList<String>(_commonTags['releasetype']),
    releasecountry: _commonTags['releasecountry'] as String?,
    script: _commonTags['script'] as String?,
    language: _commonTags['language'] as String?,
    copyright: _commonTags['copyright'] as String?,
    license: _commonTags['license'] as String?,
    encodedby: _commonTags['encodedby'] as String?,
    encodersettings: _commonTags['encodersettings'] as String?,
    gapless: _commonTags['gapless'] as bool?,
    barcode: _commonTags['barcode'] as String?,
    isrc: _typedList<String>(_commonTags['isrc']),
    asin: _commonTags['asin'] as String?,
    musicbrainz_recordingid: _commonTags['musicbrainz_recordingid'] as String?,
    musicbrainz_trackid: _commonTags['musicbrainz_trackid'] as String?,
    musicbrainz_albumid: _commonTags['musicbrainz_albumid'] as String?,
    musicbrainz_artistid: _typedList<String>(
      _commonTags['musicbrainz_artistid'],
    ),
    musicbrainz_albumartistid: _typedList<String>(
      _commonTags['musicbrainz_albumartistid'],
    ),
    musicbrainz_releasegroupid:
        _commonTags['musicbrainz_releasegroupid'] as String?,
    musicbrainz_workid: _commonTags['musicbrainz_workid'] as String?,
    musicbrainz_trmid: _commonTags['musicbrainz_trmid'] as String?,
    musicbrainz_discid: _commonTags['musicbrainz_discid'] as String?,
    acoustid_id: _commonTags['acoustid_id'] as String?,
    acoustid_fingerprint: _commonTags['acoustid_fingerprint'] as String?,
    musicip_puid: _commonTags['musicip_puid'] as String?,
    musicip_fingerprint: _commonTags['musicip_fingerprint'] as String?,
    website: _commonTags['website'] as String?,
    performerInstrument: _typedList<String>(_commonTags['performerInstrument']),
    averageLevel: _commonTags['averageLevel'] as double?,
    peakLevel: _commonTags['peakLevel'] as double?,
    notes: _typedList<String>(_commonTags['notes']),
    originalalbum: _commonTags['originalalbum'] as String?,
    originalartist: _commonTags['originalartist'] as String?,
    discogs_artist_id: _typedList<int>(_commonTags['discogs_artist_id']),
    discogs_release_id: _commonTags['discogs_release_id'] as int?,
    discogs_label_id: _commonTags['discogs_label_id'] as int?,
    discogs_master_release_id: _commonTags['discogs_master_release_id'] as int?,
    discogs_votes: _commonTags['discogs_votes'] as int?,
    discogs_rating: _commonTags['discogs_rating'] as double?,
    replaygain_track_gain_ratio:
        _commonTags['replaygain_track_gain_ratio'] as double?,
    replaygain_track_peak_ratio:
        _commonTags['replaygain_track_peak_ratio'] as double?,
    replaygain_track_gain: _commonTags['replaygain_track_gain'] as Ratio?,
    replaygain_track_peak: _commonTags['replaygain_track_peak'] as Ratio?,
    replaygain_album_gain: _commonTags['replaygain_album_gain'] as Ratio?,
    replaygain_album_peak: _commonTags['replaygain_album_peak'] as Ratio?,
    replaygain_undo: _commonTags['replaygain_undo'] as Map<String, double>?,
    replaygain_track_minmax: _typedList<double>(
      _commonTags['replaygain_track_minmax'],
    ),
    replaygain_album_minmax: _typedList<double>(
      _commonTags['replaygain_album_minmax'],
    ),
    key: _commonTags['key'] as String?,
    category: _typedList<String>(_commonTags['category']),
    hdVideo: _commonTags['hdVideo'] as int?,
    keywords: _typedList<String>(_commonTags['keywords']),
    movement: _commonTags['movement'] as String?,
    podcastId: _commonTags['podcastId'] as String?,
    showMovement: _commonTags['showMovement'] as bool?,
    stik: _commonTags['stik'] as int?,
    playCounter: _commonTags['playCounter'] as int?,
  );

  /// Returns the current format information.
  Format get format => _format;

  /// Returns the current common tags map.
  Map<String, dynamic> get commonTags => Map.unmodifiable(_commonTags);

  /// Returns the current warnings list.
  List<String> get warnings => List.unmodifiable(_warnings);

  /// Returns native tags by format.
  Map<String, Map<String, dynamic>> get nativeTagsByFormat =>
      Map.unmodifiable(_nativeTagsByFormat);
}
