library;

import 'package:metadata_audio/src/common/case_insensitive_tag_map.dart';
import 'package:metadata_audio/src/common/generic_tag_mapper.dart';
import 'package:metadata_audio/src/model/types.dart';

final _asfTagMap = <String, String>{
  'Title': 'title',
  'Author': 'artist',
  'WM/AlbumArtist': 'albumartist',
  'WM/AlbumTitle': 'album',
  'WM/Year': 'date',
  'WM/OriginalReleaseTime': 'originaldate',
  'WM/OriginalReleaseYear': 'originalyear',
  'Description': 'comment',
  'WM/TrackNumber': 'track',
  'WM/PartOfSet': 'disk',
  'WM/Genre': 'genre',
  'WM/Composer': 'composer',
  'WM/Lyrics': 'lyrics',
  'WM/AlbumSortOrder': 'albumsort',
  'WM/TitleSortOrder': 'titlesort',
  'WM/ArtistSortOrder': 'artistsort',
  'WM/AlbumArtistSortOrder': 'albumartistsort',
  'WM/ComposerSortOrder': 'composersort',
  'WM/Writer': 'lyricist',
  'WM/Conductor': 'conductor',
  'WM/ModifiedBy': 'remixer',
  'WM/Engineer': 'engineer',
  'WM/Producer': 'producer',
  'WM/DJMixer': 'djmixer',
  'WM/Mixer': 'mixer',
  'WM/Publisher': 'label',
  'WM/ContentGroupDescription': 'grouping',
  'WM/SubTitle': 'subtitle',
  'WM/SetSubTitle': 'discsubtitle',
  'WM/IsCompilation': 'compilation',
  'WM/SharedUserRating': 'rating',
  'WM/BeatsPerMinute': 'bpm',
  'WM/Mood': 'mood',
  'WM/Media': 'media',
  'WM/CatalogNo': 'catalognumber',
  'MusicBrainz/Album Status': 'releasestatus',
  'MusicBrainz/Album Type': 'releasetype',
  'MusicBrainz/Album Release Country': 'releasecountry',
  'WM/Script': 'script',
  'WM/Language': 'language',
  'Copyright': 'copyright',
  'LICENSE': 'license',
  'WM/EncodedBy': 'encodedby',
  'WM/EncodingSettings': 'encodersettings',
  'WM/Barcode': 'barcode',
  'WM/ISRC': 'isrc',
  'MusicBrainz/Track Id': 'musicbrainz_recordingid',
  'MusicBrainz/Release Track Id': 'musicbrainz_trackid',
  'MusicBrainz/Album Id': 'musicbrainz_albumid',
  'MusicBrainz/Artist Id': 'musicbrainz_artistid',
  'MusicBrainz/Album Artist Id': 'musicbrainz_albumartistid',
  'MusicBrainz/Release Group Id': 'musicbrainz_releasegroupid',
  'MusicBrainz/Work Id': 'musicbrainz_workid',
  'MusicBrainz/TRM Id': 'musicbrainz_trmid',
  'MusicBrainz/Disc Id': 'musicbrainz_discid',
  'Acoustid/Id': 'acoustid_id',
  'Acoustid/Fingerprint': 'acoustid_fingerprint',
  'MusicIP/PUID': 'musicip_puid',
  'WM/ARTISTS': 'artists',
  'WM/InitialKey': 'key',
  'ASIN': 'asin',
  'WM/Work': 'work',
  'WM/AuthorURL': 'website',
  'WM/Picture': 'picture',
};

class AsfTagMapper extends GenericTagMapper {
  @override
  CaseInsensitiveTagMap<String> get tagMap {
    final map = CaseInsensitiveTagMap<String>();
    map.addAll(_asfTagMap);
    return map;
  }

  @override
  Map<String, dynamic> mapTags(Map<String, dynamic> nativeTags) {
    final result = <String, dynamic>{};

    for (final entry in nativeTags.entries) {
      final mappedTag = mapTag(entry.key, entry.value);
      if (mappedTag == null) {
        continue;
      }

      final normalized = _normalize(mappedTag, entry.value);
      if (normalized != null) {
        result[mappedTag] = normalized;
      }
    }

    return result;
  }

  dynamic _normalize(String mappedTag, dynamic value) {
    switch (mappedTag) {
      case 'title':
      case 'artist':
      case 'albumartist':
      case 'album':
      case 'date':
      case 'originaldate':
      case 'albumsort':
      case 'titlesort':
      case 'artistsort':
      case 'albumartistsort':
      case 'composersort':
      case 'grouping':
      case 'mood':
      case 'media':
      case 'releasestatus':
      case 'releasecountry':
      case 'script':
      case 'language':
      case 'copyright':
      case 'license':
      case 'encodedby':
      case 'encodersettings':
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
      case 'musicip_puid':
      case 'key':
      case 'work':
      case 'website':
        return _singleString(value);

      case 'originalyear':
      case 'track':
      case 'disk':
      case 'bpm':
        return _parseLeadingInt(_singleString(value));

      case 'artists':
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
      case 'catalognumber':
      case 'releasetype':
      case 'isrc':
      case 'musicbrainz_artistid':
      case 'musicbrainz_albumartistid':
        return _stringList(value);

      case 'comment':
        final comment = _singleString(value);
        return comment == null ? null : <Comment>[Comment(text: comment)];

      case 'lyrics':
        final text = _singleString(value);
        if (text == null) {
          return null;
        }
        return <LyricsTag>[
          LyricsTag(
            contentType: 'lyrics',
            timeStampFormat: 'none',
            syncText: const [],
            text: text,
          ),
        ];

      case 'compilation':
        return _parseBool(_singleString(value));

      case 'rating':
        return _toRating(value);

      case 'picture':
        if (value is Picture) {
          return <Picture>[value];
        }
        return null;

      default:
        return null;
    }
  }

  static List<Rating>? _toRating(dynamic value) {
    final text = _singleString(value);
    if (text == null) {
      return null;
    }

    final raw = double.tryParse(text.trim());
    if (raw == null) {
      return null;
    }

    final normalized = (raw / 100.0).clamp(0.0, 1.0);
    return <Rating>[Rating(rating: normalized)];
  }

  static String? _singleString(dynamic value) {
    if (value is String) {
      return value;
    }
    if (value is List) {
      for (final item in value) {
        if (item is String && item.isNotEmpty) {
          return item;
        }
      }
    }
    return null;
  }

  static List<String>? _stringList(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return <String>[value];
    }
    if (value is List) {
      final values = value
          .whereType<String>()
          .where((item) => item.isNotEmpty)
          .toList();
      return values.isEmpty ? null : values;
    }
    return null;
  }

  static int? _parseLeadingInt(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final slash = trimmed.indexOf('/');
    final number = slash == -1 ? trimmed : trimmed.substring(0, slash);
    return int.tryParse(number);
  }

  static bool? _parseBool(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.trim().toLowerCase();
    if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
      return true;
    }
    if (normalized == '0' || normalized == 'false' || normalized == 'no') {
      return false;
    }
    return null;
  }
}
