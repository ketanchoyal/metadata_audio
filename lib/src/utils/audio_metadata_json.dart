import 'dart:convert';

import 'package:metadata_audio/src/flac/flac_token.dart';
import 'package:metadata_audio/src/model/types.dart';

// ── helpers ────────────────────────────────────────────────────────────────

String _b64Encode(List<int> bytes) => base64Encode(bytes);
List<int> _b64Decode(String s) => base64Decode(s);

Map<String, dynamic> _pictureToJson(Picture p) => {
      'format': p.format,
      'data': const <int>[], // binary cover data is not cached (memory safety)
      'description': p.description,
      'type': p.type,
      'name': p.name,
    };

Picture _pictureFromJson(Map<String, dynamic> m) => Picture(
      format: m['format'] as String,
      data: _b64Decode(m['data'] as String),
      description: m['description'] as String?,
      type: m['type'] as String?,
      name: m['name'] as String?,
    );

Map<String, dynamic> _flacPictureToJson(FlacPicture p) => {
      'type': p.type,
      'format': p.format,
      'description': p.description,
      'width': p.width,
      'height': p.height,
      'colourDepth': p.colourDepth,
      'indexedColor': p.indexedColor,
      'data': const <int>[], // binary cover data is not cached (memory safety)
    };

FlacPicture _flacPictureFromJson(Map<String, dynamic> m) => FlacPicture(
      type: m['type'] as String,
      format: m['format'] as String,
      description: m['description'] as String,
      width: m['width'] as int,
      height: m['height'] as int,
      colourDepth: m['colourDepth'] as int,
      indexedColor: m['indexedColor'] as int,
      data: _b64Decode(m['data'] as String),
    );

Map<String, dynamic> _commentToJson(Comment c) => {
      'descriptor': c.descriptor,
      'language': c.language,
      'text': c.text,
    };

Comment _commentFromJson(Map<String, dynamic> m) => Comment(
      descriptor: m['descriptor'] as String?,
      language: m['language'] as String?,
      text: m['text'] as String?,
    );

Map<String, dynamic> _lyricsTextToJson(LyricsText t) => {
      'text': t.text,
      'timestamp': t.timestamp,
    };

LyricsText _lyricsTextFromJson(Map<String, dynamic> m) => LyricsText(
      text: m['text'] as String,
      timestamp: m['timestamp'] as int?,
    );

Map<String, dynamic> _lyricsTagToJson(LyricsTag l) => {
      ..._commentToJson(l),
      'contentType': l.contentType,
      'timeStampFormat': l.timeStampFormat,
      'syncText': l.syncText.map(_lyricsTextToJson).toList(),
    };

LyricsTag _lyricsTagFromJson(Map<String, dynamic> m) => LyricsTag(
      descriptor: m['descriptor'] as String?,
      language: m['language'] as String?,
      text: m['text'] as String?,
      contentType: m['contentType'] as String? ?? 'lyrics',
      timeStampFormat: m['timeStampFormat'] as String? ?? 'none',
      syncText: (m['syncText'] as List?)
              ?.map((e) => _lyricsTextFromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _ratingToJson(Rating r) => {
      'source': r.source,
      'rating': r.rating,
    };

Rating _ratingFromJson(Map<String, dynamic> m) => Rating(
      source: m['source'] as String?,
      rating: (m['rating'] as num?)?.toDouble(),
    );

Map<String, dynamic> _trackNoToJson(TrackNo t) => {'no': t.no, 'of': t.of};

TrackNo _trackNoFromJson(Map<String, dynamic> m) =>
    TrackNo(no: m['no'] as int?, of: m['of'] as int?);

Map<String, dynamic> _urlToJson(Url u) => {'url': u.url, 'description': u.description};

Url _urlFromJson(Map<String, dynamic> m) =>
    Url(url: m['url'] as String, description: m['description'] as String);

Map<String, dynamic> _ratioToJson(Ratio r) => {'ratio': r.ratio, 'dB': r.dB};

Ratio _ratioFromJson(Map<String, dynamic> m) =>
    Ratio(ratio: (m['ratio'] as num).toDouble(), dB: (m['dB'] as num?)?.toDouble());

Map<String, dynamic> _privToJson(PrivFrame p) => {
      'owner': p.owner,
      'data': const <int>[], // binary data is not cached (memory safety)
    };

PrivFrame _privFromJson(Map<String, dynamic> m) => PrivFrame(
      owner: m['owner'] as String,
      data: _b64Decode(m['data'] as String),
    );

Map<String, dynamic> _tagToJson(Tag t) {
  final v = t.value;
  return {'id': t.id, 'value': _encodeValue(v)};
}

Tag _tagFromJson(Map<String, dynamic> m) =>
    Tag(id: m['id'] as String, value: _decodeValue(m['value']));

Map<String, dynamic> _chapterToJson(Chapter c) => {
      'id': c.id,
      'title': c.title,
      'url': c.url == null ? null : _urlToJson(c.url!),
      'byteOffset': c.byteOffset,
      'endByteOffset': c.endByteOffset,
      'start': c.start,
      'end': c.end,
      'timeScale': c.timeScale,
      'image': c.image == null ? null : _pictureToJson(c.image!),
    };

Chapter _chapterFromJson(Map<String, dynamic> m) => Chapter(
      id: m['id'] as String?,
      title: m['title'] as String,
      url: m['url'] == null ? null : _urlFromJson(m['url'] as Map<String, dynamic>),
      byteOffset: m['byteOffset'] as int?,
      endByteOffset: m['endByteOffset'] as int?,
      start: m['start'] as int,
      end: m['end'] as int?,
      timeScale: m['timeScale'] as int?,
      image: m['image'] == null ? null : _pictureFromJson(m['image'] as Map<String, dynamic>),
    );

Map<String, dynamic> _trackInfoToJson(TrackInfo t) => {
      'type': t.type,
      'codecName': t.codecName,
      'codecSettings': t.codecSettings,
      'flagEnabled': t.flagEnabled,
      'flagDefault': t.flagDefault,
      'flagLacing': t.flagLacing,
      'name': t.name,
      'language': t.language,
      'audio': t.audio == null ? null : _audioTrackToJson(t.audio!),
      'video': t.video == null ? null : _videoTrackToJson(t.video!),
      'id': t.id,
      'codecId': t.codecId,
      'codecProfile': t.codecProfile,
      'duration': t.duration,
      'bitrate': t.bitrate,
      'lossless': t.lossless,
    };

TrackInfo _trackInfoFromJson(Map<String, dynamic> m) => TrackInfo(
      type: m['type'] as String?,
      codecName: m['codecName'] as String?,
      codecSettings: m['codecSettings'] as String?,
      flagEnabled: m['flagEnabled'] as bool?,
      flagDefault: m['flagDefault'] as bool?,
      flagLacing: m['flagLacing'] as bool?,
      name: m['name'] as String?,
      language: m['language'] as String?,
      audio: m['audio'] == null ? null : _audioTrackFromJson(m['audio'] as Map<String, dynamic>),
      video: m['video'] == null ? null : _videoTrackFromJson(m['video'] as Map<String, dynamic>),
      id: m['id'] as int?,
      codecId: m['codecId'] as String?,
      codecProfile: m['codecProfile'] as String?,
      duration: (m['duration'] as num?)?.toDouble(),
      bitrate: (m['bitrate'] as num?)?.toDouble(),
      lossless: m['lossless'] as bool?,
    );

Map<String, dynamic> _audioTrackToJson(AudioTrack a) => {
      'samplingFrequency': a.samplingFrequency,
      'outputSamplingFrequency': a.outputSamplingFrequency,
      'channels': a.channels,
      'channelPositions': a.channelPositions,
      'bitDepth': a.bitDepth,
      'numberOfSamples': a.numberOfSamples,
    };

AudioTrack _audioTrackFromJson(Map<String, dynamic> m) => AudioTrack(
      samplingFrequency: m['samplingFrequency'] as int?,
      outputSamplingFrequency: m['outputSamplingFrequency'] as int?,
      channels: m['channels'] as int?,
      channelPositions: (m['channelPositions'] as List?)?.map((e) => e as int).toList(),
      bitDepth: m['bitDepth'] as int?,
      numberOfSamples: m['numberOfSamples'] as int?,
    );

Map<String, dynamic> _videoTrackToJson(VideoTrack v) => {
      'flagInterlaced': v.flagInterlaced,
      'stereoMode': v.stereoMode,
      'pixelWidth': v.pixelWidth,
      'pixelHeight': v.pixelHeight,
      'displayWidth': v.displayWidth,
      'displayHeight': v.displayHeight,
      'displayUnit': v.displayUnit,
      'aspectRatioType': v.aspectRatioType,
      'colourSpace': v.colourSpace,
      'gammaValue': v.gammaValue,
      'frameRate': v.frameRate,
    };

VideoTrack _videoTrackFromJson(Map<String, dynamic> m) => VideoTrack(
      flagInterlaced: m['flagInterlaced'] as bool?,
      stereoMode: m['stereoMode'] as int?,
      pixelWidth: m['pixelWidth'] as int?,
      pixelHeight: m['pixelHeight'] as int?,
      displayWidth: m['displayWidth'] as int?,
      displayHeight: m['displayHeight'] as int?,
      displayUnit: m['displayUnit'] as int?,
      aspectRatioType: m['aspectRatioType'] as int?,
      colourSpace: (m['colourSpace'] as List?)?.map((e) => e as int).toList(),
      gammaValue: (m['gammaValue'] as num?)?.toDouble(),
      frameRate: (m['frameRate'] as num?)?.toDouble(),
    );

// ── dynamic value (de)serialization ────────────────────────────────────────

dynamic _encodeValue(dynamic v) {
  if (v == null) return null;
  if (v is Picture) return {'__t': 'Picture', ..._pictureToJson(v)};
  if (v is FlacPicture) return {'__t': 'FlacPicture', ..._flacPictureToJson(v)};
  if (v is PrivFrame) return {'__t': 'PrivFrame', ..._privToJson(v)};
  if (v is Rating) return {'__t': 'Rating', ..._ratingToJson(v)};
  if (v is Url) return {'__t': 'Url', ..._urlToJson(v)};
  if (v is Comment) return {'__t': 'Comment', ..._commentToJson(v)};
  if (v is LyricsTag) return {'__t': 'LyricsTag', ..._lyricsTagToJson(v)};
  if (v is LyricsText) return {'__t': 'LyricsText', ..._lyricsTextToJson(v)};
  if (v is Ratio) return {'__t': 'Ratio', ..._ratioToJson(v)};
  if (v is DateTime) return {'__t': 'DateTime', 'v': v.toIso8601String()};
  if (v is List<int>) return {'__t': 'bytes', 'v': _b64Encode(v)};
  if (v is List) return v.map(_encodeValue).toList();
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), _encodeValue(val)));
  return v; // primitives
}

dynamic _decodeValue(dynamic v) {
  if (v == null) return null;
  if (v is Map) {
    final m = v as Map<String, dynamic>;
    final t = m['__t'] as String?;
    if (t == 'Picture') return _pictureFromJson(m);
    if (t == 'FlacPicture') return _flacPictureFromJson(m);
    if (t == 'PrivFrame') return _privFromJson(m);
    if (t == 'Rating') return _ratingFromJson(m);
    if (t == 'Url') return _urlFromJson(m);
    if (t == 'Comment') return _commentFromJson(m);
    if (t == 'LyricsTag') return _lyricsTagFromJson(m);
    if (t == 'LyricsText') return _lyricsTextFromJson(m);
    if (t == 'Ratio') return _ratioFromJson(m);
    if (t == 'DateTime') return DateTime.tryParse(m['v'] as String);
    if (t == 'bytes') return _b64Decode(m['v'] as String);
    // plain map (e.g. native tag values that were maps) — decode recursively
    return m.map((k, val) => MapEntry(k, _decodeValue(val)));
  }
  if (v is List) return v.map(_decodeValue).toList();
  return v;
}

// ── Format ──────────────────────────────────────────────────────────────────

Map<String, dynamic> _formatToJson(Format f) => {
      'container': f.container,
      'tagTypes': f.tagTypes,
      'duration': f.duration,
      'bitrate': f.bitrate,
      'sampleRate': f.sampleRate,
      'bitsPerSample': f.bitsPerSample,
      'tool': f.tool,
      'codec': f.codec,
      'codecProfile': f.codecProfile,
      'lossless': f.lossless,
      'numberOfChannels': f.numberOfChannels,
      'numberOfSamples': f.numberOfSamples,
      'audioMD5': null, // not cached (memory safety)
      'chapters': f.chapters?.map(_chapterToJson).toList(),
      'creationTime': f.creationTime?.toIso8601String(),
      'modificationTime': f.modificationTime?.toIso8601String(),
      'trackGain': f.trackGain,
      'trackPeakLevel': f.trackPeakLevel,
      'albumGain': f.albumGain,
      'hasAudio': f.hasAudio,
      'hasVideo': f.hasVideo,
      'trackInfo': f.trackInfo.map(_trackInfoToJson).toList(),
      'containerDuration': f.containerDuration,
      'overallBitrate': f.overallBitrate,
    };

Format _formatFromJson(Map<String, dynamic> m) => Format(
      container: m['container'] as String?,
      tagTypes: (m['tagTypes'] as List?)?.map((e) => e as String).toList() ?? const [],
      duration: (m['duration'] as num?)?.toDouble(),
      bitrate: m['bitrate'] as num?,
      sampleRate: m['sampleRate'] as int?,
      bitsPerSample: m['bitsPerSample'] as int?,
      tool: m['tool'] as String?,
      codec: m['codec'] as String?,
      codecProfile: m['codecProfile'] as String?,
      lossless: m['lossless'] as bool?,
      numberOfChannels: m['numberOfChannels'] as int?,
      numberOfSamples: m['numberOfSamples'] as int?,
      audioMD5: m['audioMD5'] == null ? null : _b64Decode(m['audioMD5'] as String),
      chapters: (m['chapters'] as List?)?.map((e) => _chapterFromJson(e as Map<String, dynamic>)).toList(),
      creationTime: m['creationTime'] == null ? null : DateTime.tryParse(m['creationTime'] as String),
      modificationTime: m['modificationTime'] == null ? null : DateTime.tryParse(m['modificationTime'] as String),
      trackGain: (m['trackGain'] as num?)?.toDouble(),
      trackPeakLevel: (m['trackPeakLevel'] as num?)?.toDouble(),
      albumGain: (m['albumGain'] as num?)?.toDouble(),
      hasAudio: m['hasAudio'] as bool?,
      hasVideo: m['hasVideo'] as bool?,
      trackInfo: (m['trackInfo'] as List?)?.map((e) => _trackInfoFromJson(e as Map<String, dynamic>)).toList() ?? const [],
      containerDuration: (m['containerDuration'] as num?)?.toDouble(),
      overallBitrate: m['overallBitrate'] as num?,
    );

// ── CommonTags ──────────────────────────────────────────────────────────────

Map<String, dynamic> _commonTagsToJson(CommonTags c) {
  final m = <String, dynamic>{};
  // primitives / lists handled generically below
  // TrackNo
  if (c.track.no != null || c.track.of != null) m['track'] = _trackNoToJson(c.track);
  if (c.disk.no != null || c.disk.of != null) m['disk'] = _trackNoToJson(c.disk);
  if (c.movementIndex.no != null || c.movementIndex.of != null) {
    m['movementIndex'] = _trackNoToJson(c.movementIndex);
  }
  // all other fields via reflection-free listing
  final enc = <String, dynamic>{
    'year': c.year,
    'title': c.title,
    'artist': c.artist,
    'artists': c.artists,
    'albumartist': c.albumartist,
    'albumartists': c.albumartists,
    'album': c.album,
    'date': c.date,
    'originaldate': c.originaldate,
    'originalyear': c.originalyear,
    'releasedate': c.releasedate,
    'comment': c.comment?.map(_commentToJson).toList(),
    'genre': c.genre,
    'picture': c.picture?.map(_pictureToJson).toList(),
    'composer': c.composer,
    'lyrics': c.lyrics?.map(_lyricsTagToJson).toList(),
    'albumsort': c.albumsort,
    'titlesort': c.titlesort,
    'work': c.work,
    'artistsort': c.artistsort,
    'albumartistsort': c.albumartistsort,
    'composersort': c.composersort,
    'lyricist': c.lyricist,
    'writer': c.writer,
    'conductor': c.conductor,
    'remixer': c.remixer,
    'arranger': c.arranger,
    'engineer': c.engineer,
    'publisher': c.publisher,
    'producer': c.producer,
    'djmixer': c.djmixer,
    'mixer': c.mixer,
    'technician': c.technician,
    'label': c.label,
    'grouping': c.grouping,
    'subtitle': c.subtitle,
    'description': c.description,
    'longDescription': c.longDescription,
    'discsubtitle': c.discsubtitle,
    'totaltracks': c.totaltracks,
    'totaldiscs': c.totaldiscs,
    'movementTotal': c.movementTotal,
    'compilation': c.compilation,
    'rating': c.rating?.map(_ratingToJson).toList(),
    'bpm': c.bpm,
    'mood': c.mood,
    'media': c.media,
    'catalognumber': c.catalognumber,
    'tvShow': c.tvShow,
    'tvShowSort': c.tvShowSort,
    'tvSeason': c.tvSeason,
    'tvEpisode': c.tvEpisode,
    'tvEpisodeId': c.tvEpisodeId,
    'tvNetwork': c.tvNetwork,
    'podcast': c.podcast,
    'podcasturl': c.podcasturl,
    'releasestatus': c.releasestatus,
    'releasetype': c.releasetype,
    'releasecountry': c.releasecountry,
    'script': c.script,
    'language': c.language,
    'copyright': c.copyright,
    'license': c.license,
    'encodedby': c.encodedby,
    'encodersettings': c.encodersettings,
    'gapless': c.gapless,
    'barcode': c.barcode,
    'isrc': c.isrc,
    'asin': c.asin,
    'musicbrainz_recordingid': c.musicbrainz_recordingid,
    'musicbrainz_trackid': c.musicbrainz_trackid,
    'musicbrainz_albumid': c.musicbrainz_albumid,
    'musicbrainz_artistid': c.musicbrainz_artistid,
    'musicbrainz_albumartistid': c.musicbrainz_albumartistid,
    'musicbrainz_releasegroupid': c.musicbrainz_releasegroupid,
    'musicbrainz_workid': c.musicbrainz_workid,
    'musicbrainz_trmid': c.musicbrainz_trmid,
    'musicbrainz_discid': c.musicbrainz_discid,
    'acoustid_id': c.acoustid_id,
    'acoustid_fingerprint': c.acoustid_fingerprint,
    'musicip_puid': c.musicip_puid,
    'musicip_fingerprint': c.musicip_fingerprint,
    'website': c.website,
    'performerInstrument': c.performerInstrument,
    'averageLevel': c.averageLevel,
    'peakLevel': c.peakLevel,
    'notes': c.notes,
    'originalalbum': c.originalalbum,
    'originalartist': c.originalartist,
    'discogs_artist_id': c.discogs_artist_id,
    'discogs_release_id': c.discogs_release_id,
    'discogs_label_id': c.discogs_label_id,
    'discogs_master_release_id': c.discogs_master_release_id,
    'discogs_votes': c.discogs_votes,
    'discogs_rating': c.discogs_rating,
    'replaygain_track_gain_ratio': c.replaygain_track_gain_ratio,
    'replaygain_track_peak_ratio': c.replaygain_track_peak_ratio,
    'replaygain_track_gain': c.replaygain_track_gain == null ? null : _ratioToJson(c.replaygain_track_gain!),
    'replaygain_track_peak': c.replaygain_track_peak == null ? null : _ratioToJson(c.replaygain_track_peak!),
    'replaygain_album_gain': c.replaygain_album_gain == null ? null : _ratioToJson(c.replaygain_album_gain!),
    'replaygain_album_peak': c.replaygain_album_peak == null ? null : _ratioToJson(c.replaygain_album_peak!),
    'replaygain_track_minmax': c.replaygain_track_minmax,
    'replaygain_album_minmax': c.replaygain_album_minmax,
    'key': c.key,
    'category': c.category,
    'hdVideo': c.hdVideo,
    'keywords': c.keywords,
    'movement': c.movement,
    'podcastId': c.podcastId,
    'showMovement': c.showMovement,
    'stik': c.stik,
    'playCounter': c.playCounter,
  };
  for (final e in enc.entries) {
    if (e.value != null) m[e.key] = e.value;
  }
  return m;
}

CommonTags _commonTagsFromJson(Map<String, dynamic> m) => CommonTags(
  track: m['track'] == null ? const TrackNo() : _trackNoFromJson(m['track'] as Map<String, dynamic>),
  disk: m['disk'] == null ? const TrackNo() : _trackNoFromJson(m['disk'] as Map<String, dynamic>),
  movementIndex: m['movementIndex'] == null ? const TrackNo() : _trackNoFromJson(m['movementIndex'] as Map<String, dynamic>),
  year: m['year'] as int?,
  title: m['title'] as String?,
  artist: m['artist'] as String?,
  artists: (m['artists'] as List?)?.map((e) => e as String).toList(),
  albumartist: m['albumartist'] as String?,
  albumartists: (m['albumartists'] as List?)?.map((e) => e as String).toList(),
  album: m['album'] as String?,
  date: m['date'] as String?,
  originaldate: m['originaldate'] as String?,
  originalyear: m['originalyear'] as int?,
  releasedate: m['releasedate'] as String?,
  comment: (m['comment'] as List?)?.map((e) => _commentFromJson(e as Map<String, dynamic>)).toList(),
  genre: (m['genre'] as List?)?.map((e) => e as String).toList(),
  picture: (m['picture'] as List?)?.map((e) => _pictureFromJson(e as Map<String, dynamic>)).toList(),
  composer: (m['composer'] as List?)?.map((e) => e as String).toList(),
  lyrics: (m['lyrics'] as List?)?.map((e) => _lyricsTagFromJson(e as Map<String, dynamic>)).toList(),
  albumsort: m['albumsort'] as String?,
  titlesort: m['titlesort'] as String?,
  work: m['work'] as String?,
  artistsort: m['artistsort'] as String?,
  albumartistsort: m['albumartistsort'] as String?,
  composersort: m['composersort'] as String?,
  lyricist: (m['lyricist'] as List?)?.map((e) => e as String).toList(),
  writer: (m['writer'] as List?)?.map((e) => e as String).toList(),
  conductor: (m['conductor'] as List?)?.map((e) => e as String).toList(),
  remixer: (m['remixer'] as List?)?.map((e) => e as String).toList(),
  arranger: (m['arranger'] as List?)?.map((e) => e as String).toList(),
  engineer: (m['engineer'] as List?)?.map((e) => e as String).toList(),
  publisher: (m['publisher'] as List?)?.map((e) => e as String).toList(),
  producer: (m['producer'] as List?)?.map((e) => e as String).toList(),
  djmixer: (m['djmixer'] as List?)?.map((e) => e as String).toList(),
  mixer: (m['mixer'] as List?)?.map((e) => e as String).toList(),
  technician: (m['technician'] as List?)?.map((e) => e as String).toList(),
  label: (m['label'] as List?)?.map((e) => e as String).toList(),
  grouping: m['grouping'] as String?,
  subtitle: (m['subtitle'] as List?)?.map((e) => e as String).toList(),
  description: (m['description'] as List?)?.map((e) => e as String).toList(),
  longDescription: m['longDescription'] as String?,
  discsubtitle: (m['discsubtitle'] as List?)?.map((e) => e as String).toList(),
  totaltracks: m['totaltracks'] as String?,
  totaldiscs: m['totaldiscs'] as String?,
  movementTotal: m['movementTotal'] as int?,
  compilation: m['compilation'] as bool?,
  rating: (m['rating'] as List?)?.map((e) => _ratingFromJson(e as Map<String, dynamic>)).toList(),
  bpm: m['bpm'] as int?,
  mood: m['mood'] as String?,
  media: m['media'] as String?,
  catalognumber: (m['catalognumber'] as List?)?.map((e) => e as String).toList(),
  tvShow: m['tvShow'] as String?,
  tvShowSort: m['tvShowSort'] as String?,
  tvSeason: m['tvSeason'] as int?,
  tvEpisode: m['tvEpisode'] as int?,
  tvEpisodeId: m['tvEpisodeId'] as String?,
  tvNetwork: m['tvNetwork'] as String?,
  podcast: m['podcast'] as bool?,
  podcasturl: m['podcasturl'] as String?,
  releasestatus: m['releasestatus'] as String?,
  releasetype: (m['releasetype'] as List?)?.map((e) => e as String).toList(),
  releasecountry: m['releasecountry'] as String?,
  script: m['script'] as String?,
  language: m['language'] as String?,
  copyright: m['copyright'] as String?,
  license: m['license'] as String?,
  encodedby: m['encodedby'] as String?,
  encodersettings: m['encodersettings'] as String?,
  gapless: m['gapless'] as bool?,
  barcode: m['barcode'] as String?,
  isrc: (m['isrc'] as List?)?.map((e) => e as String).toList(),
  asin: m['asin'] as String?,
  musicbrainz_recordingid: m['musicbrainz_recordingid'] as String?,
  musicbrainz_trackid: m['musicbrainz_trackid'] as String?,
  musicbrainz_albumid: m['musicbrainz_albumid'] as String?,
  musicbrainz_artistid: (m['musicbrainz_artistid'] as List?)?.map((e) => e as String).toList(),
  musicbrainz_albumartistid: (m['musicbrainz_albumartistid'] as List?)?.map((e) => e as String).toList(),
  musicbrainz_releasegroupid: m['musicbrainz_releasegroupid'] as String?,
  musicbrainz_workid: m['musicbrainz_workid'] as String?,
  musicbrainz_trmid: m['musicbrainz_trmid'] as String?,
  musicbrainz_discid: m['musicbrainz_discid'] as String?,
  acoustid_id: m['acoustid_id'] as String?,
  acoustid_fingerprint: m['acoustid_fingerprint'] as String?,
  musicip_puid: m['musicip_puid'] as String?,
  musicip_fingerprint: m['musicip_fingerprint'] as String?,
  website: m['website'] as String?,
  performerInstrument: (m['performerInstrument'] as List?)?.map((e) => e as String).toList(),
  averageLevel: (m['averageLevel'] as num?)?.toDouble(),
  peakLevel: (m['peakLevel'] as num?)?.toDouble(),
  notes: (m['notes'] as List?)?.map((e) => e as String).toList(),
  originalalbum: m['originalalbum'] as String?,
  originalartist: m['originalartist'] as String?,
  discogs_artist_id: (m['discogs_artist_id'] as List?)?.map((e) => e as int).toList(),
  discogs_release_id: m['discogs_release_id'] as int?,
  discogs_label_id: m['discogs_label_id'] as int?,
  discogs_master_release_id: m['discogs_master_release_id'] as int?,
  discogs_votes: m['discogs_votes'] as int?,
  discogs_rating: (m['discogs_rating'] as num?)?.toDouble(),
  replaygain_track_gain_ratio: (m['replaygain_track_gain_ratio'] as num?)?.toDouble(),
  replaygain_track_peak_ratio: (m['replaygain_track_peak_ratio'] as num?)?.toDouble(),
  replaygain_track_gain: m['replaygain_track_gain'] == null ? null : _ratioFromJson(m['replaygain_track_gain'] as Map<String, dynamic>),
  replaygain_track_peak: m['replaygain_track_peak'] == null ? null : _ratioFromJson(m['replaygain_track_peak'] as Map<String, dynamic>),
  replaygain_album_gain: m['replaygain_album_gain'] == null ? null : _ratioFromJson(m['replaygain_album_gain'] as Map<String, dynamic>),
  replaygain_album_peak: m['replaygain_album_peak'] == null ? null : _ratioFromJson(m['replaygain_album_peak'] as Map<String, dynamic>),
  replaygain_track_minmax: (m['replaygain_track_minmax'] as List?)?.map((e) => (e as num).toDouble()).toList(),
  replaygain_album_minmax: (m['replaygain_album_minmax'] as List?)?.map((e) => (e as num).toDouble()).toList(),
  key: m['key'] as String?,
  category: (m['category'] as List?)?.map((e) => e as String).toList(),
  hdVideo: m['hdVideo'] as int?,
  keywords: (m['keywords'] as List?)?.map((e) => e as String).toList(),
  movement: m['movement'] as String?,
  podcastId: m['podcastId'] as String?,
  showMovement: m['showMovement'] as bool?,
  stik: m['stik'] as int?,
  playCounter: m['playCounter'] as int?,
  // keep warnings in common? CommonTags has warnings field per list above
);

// ── QualityInformation ──────────────────────────────────────────────────────

Map<String, dynamic> _qualityToJson(QualityInformation q) => {
      'warnings': q.warnings.map((w) => w.message).toList(),
    };

QualityInformation _qualityFromJson(Map<String, dynamic> m) => QualityInformation(
      warnings: (m['warnings'] as List?)?.map((e) => ParserWarning(message: e as String)).toList() ?? const [],
    );

// ── NativeTags ──────────────────────────────────────────────────────────────

Map<String, dynamic> _nativeToJson(NativeTags n) => n.map(
      (k, v) => MapEntry(k, v.map(_tagToJson).toList()),
    );

NativeTags _nativeFromJson(Map<String, dynamic> m) => m.map(
      (k, v) => MapEntry(k, (v as List).map((e) => _tagFromJson(e as Map<String, dynamic>)).toList()),
    );

// ── AudioMetadata ───────────────────────────────────────────────────────────

Map<String, dynamic> audioMetadataToJson(AudioMetadata meta) => {
      'format': _formatToJson(meta.format),
      'native': _nativeToJson(meta.native),
      'common': _commonTagsToJson(meta.common),
      'quality': _qualityToJson(meta.quality),
    };

AudioMetadata? audioMetadataFromJson(Map<String, dynamic> m) {
  try {
    return AudioMetadata(
      format: _formatFromJson(m['format'] as Map<String, dynamic>),
      native: _nativeFromJson(m['native'] as Map<String, dynamic>),
      common: _commonTagsFromJson(m['common'] as Map<String, dynamic>),
      quality: _qualityFromJson(m['quality'] as Map<String, dynamic>),
    );
  } catch (_) {
    return null;
  }
}
