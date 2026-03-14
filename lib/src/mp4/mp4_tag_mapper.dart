library;

import 'package:audio_metadata/src/common/case_insensitive_tag_map.dart';
import 'package:audio_metadata/src/common/generic_tag_mapper.dart';
import 'package:audio_metadata/src/model/types.dart';

final Map<String, String> _mp4TagMap = <String, String>{
  '©nam': 'title',
  '©art': 'artist',
  'aart': 'albumartist',
  '----:com.apple.itunes:band': 'albumartist',
  '©alb': 'album',
  '©day': 'date',
  '©cmt': 'comment',
  '©com': 'comment',
  'trkn': 'track',
  'disk': 'disk',
  '©gen': 'genre',
  'gnre': 'genre',
  'covr': 'picture',
  '©wrt': 'composer',
  '©lyr': 'lyrics',
  'cpil': 'compilation',
  'tmpo': 'bpm',
  'pgap': 'gapless',
  'tvsh': 'tvShow',
  'tvsn': 'tvSeason',
  'tves': 'tvEpisode',
  'sosn': 'tvShowSort',
  'tven': 'tvEpisodeId',
  'tvnn': 'tvNetwork',
  'pcst': 'podcast',
  'purl': 'podcasturl',
  '©too': 'encodedby',
  'cprt': 'copyright',
  '©cpy': 'copyright',
  'stik': 'stik',
  'rate': 'rating',
  '©grp': 'grouping',
  'soal': 'albumsort',
  'sonm': 'titlesort',
  'soar': 'artistsort',
  'soaa': 'albumartistsort',
  'soco': 'composersort',
  '©wrk': 'work',
  '©mvn': 'movement',
  '©mvi': 'movementIndex',
  '©mvc': 'movementTotal',
  'keyw': 'keywords',
  'catg': 'category',
  'hdvd': 'hdVideo',
  'shwm': 'showMovement',
  'egid': 'podcastId',
  '----:com.apple.itunes:lyricist': 'lyricist',
  '----:com.apple.itunes:conductor': 'conductor',
  '----:com.apple.itunes:remixer': 'remixer',
  '----:com.apple.itunes:engineer': 'engineer',
  '----:com.apple.itunes:producer': 'producer',
  '----:com.apple.itunes:djmixer': 'djmixer',
  '----:com.apple.itunes:mixer': 'mixer',
  '----:com.apple.itunes:label': 'label',
  '----:com.apple.itunes:subtitle': 'subtitle',
  '----:com.apple.itunes:discsubtitle': 'discsubtitle',
  '----:com.apple.itunes:mood': 'mood',
  '----:com.apple.itunes:media': 'media',
  '----:com.apple.itunes:catalognumber': 'catalognumber',
  '----:com.apple.itunes:language': 'language',
  '----:com.apple.itunes:script': 'script',
  '----:com.apple.itunes:license': 'license',
  '----:com.apple.itunes:barcode': 'barcode',
  '----:com.apple.itunes:isrc': 'isrc',
  '----:com.apple.itunes:asin': 'asin',
  '----:com.apple.itunes:notes': 'comment',
  '----:com.apple.itunes:musicbrainz track id': 'musicbrainz_recordingid',
  '----:com.apple.itunes:musicbrainz release track id': 'musicbrainz_trackid',
  '----:com.apple.itunes:musicbrainz album id': 'musicbrainz_albumid',
  '----:com.apple.itunes:musicbrainz artist id': 'musicbrainz_artistid',
  '----:com.apple.itunes:musicbrainz album artist id':
      'musicbrainz_albumartistid',
  '----:com.apple.itunes:musicbrainz release group id':
      'musicbrainz_releasegroupid',
  '----:com.apple.itunes:musicbrainz work id': 'musicbrainz_workid',
  '----:com.apple.itunes:musicbrainz trm id': 'musicbrainz_trmid',
  '----:com.apple.itunes:musicbrainz disc id': 'musicbrainz_discid',
  '----:com.apple.itunes:acoustid id': 'acoustid_id',
  '----:com.apple.itunes:acoustid fingerprint': 'acoustid_fingerprint',
};

class Mp4TagMapper extends GenericTagMapper {
  @override
  CaseInsensitiveTagMap<String> get tagMap {
    final map = CaseInsensitiveTagMap<String>();
    map.addAll(_mp4TagMap);
    return map;
  }

  @override
  Map<String, dynamic> mapTags(Map<String, dynamic> nativeTags) {
    final result = <String, dynamic>{};

    for (final entry in nativeTags.entries) {
      final nativeTag = entry.key;
      final mappedTag = mapTag(nativeTag, entry.value);
      if (mappedTag == null) {
        continue;
      }

      if (mappedTag == 'track' || mappedTag == 'disk') {
        final pair = _parseNumberPair(entry.value);
        if (pair != null) {
          result[mappedTag] = pair.$1;
        }
        continue;
      }

      final normalized = _normalizeValue(mappedTag, entry.value);
      if (normalized != null) {
        result[mappedTag] = normalized;
      }
    }

    return result;
  }

  dynamic _normalizeValue(String mappedTag, dynamic value) {
    switch (mappedTag) {
      case 'title':
      case 'artist':
      case 'albumartist':
      case 'album':
      case 'date':
      case 'encodedby':
      case 'copyright':
      case 'work':
      case 'podcasturl':
      case 'tvShow':
      case 'tvShowSort':
      case 'tvEpisodeId':
      case 'tvNetwork':
      case 'grouping':
      case 'mood':
      case 'media':
      case 'language':
      case 'script':
      case 'license':
      case 'barcode':
      case 'asin':
      case 'musicbrainz_recordingid':
      case 'musicbrainz_trackid':
      case 'musicbrainz_albumid':
      case 'musicbrainz_releasegroupid':
      case 'musicbrainz_workid':
      case 'musicbrainz_trmid':
      case 'musicbrainz_discid':
      case 'acoustid_id':
      case 'acoustid_fingerprint':
      case 'podcastId':
        return _singleString(value);
      case 'genre':
      case 'composer':
      case 'lyricist':
      case 'conductor':
      case 'remixer':
      case 'engineer':
      case 'producer':
      case 'djmixer':
      case 'mixer':
      case 'label':
      case 'subtitle':
      case 'discsubtitle':
      case 'keywords':
      case 'category':
      case 'musicbrainz_artistid':
      case 'musicbrainz_albumartistid':
      case 'catalognumber':
      case 'isrc':
        return _stringList(value);
      case 'picture':
        if (value is Picture) {
          return <Picture>[value];
        }
        return null;
      case 'rating':
        final numeric = _toInt(value);
        if (numeric == null) {
          return null;
        }
        return <Rating>[Rating(rating: numeric / 100.0)];
      case 'comment':
        final text = _singleString(value);
        return text == null ? null : <Comment>[Comment(text: text)];
      case 'compilation':
      case 'podcast':
      case 'gapless':
      case 'showMovement':
        return _toBool(value);
      case 'bpm':
      case 'tvSeason':
      case 'tvEpisode':
      case 'stik':
      case 'movementIndex':
      case 'movementTotal':
      case 'hdVideo':
        return _toInt(value);
      case 'movement':
        return _singleString(value);
      default:
        return value;
    }
  }

  static String? _singleString(dynamic value) {
    if (value is String) {
      return value;
    }
    if (value is List && value.isNotEmpty && value.first is String) {
      return value.first as String;
    }
    return null;
  }

  static List<String>? _stringList(dynamic value) {
    if (value is String) {
      return <String>[value];
    }
    if (value is List) {
      final strings = value
          .whereType<String>()
          .where((entry) => entry.isNotEmpty)
          .toList();
      return strings.isEmpty ? null : strings;
    }
    return null;
  }

  static (int, int?)? _parseNumberPair(dynamic value) {
    if (value is int) {
      return (value, null);
    }

    final text = _singleString(value);
    if (text == null || text.isEmpty) {
      return null;
    }

    final parts = text.split('/');
    final first = int.tryParse(parts.first.trim());
    if (first == null) {
      return null;
    }

    if (parts.length < 2) {
      return (first, null);
    }

    final second = int.tryParse(parts[1].trim());
    return (first, second);
  }

  static int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static bool? _toBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    final asInt = _toInt(value);
    if (asInt != null) {
      return asInt > 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
    }
    return null;
  }
}
