library;

import 'package:metadata_audio/src/apev2/apev2_token.dart';
import 'package:metadata_audio/src/common/case_insensitive_tag_map.dart';
import 'package:metadata_audio/src/common/generic_tag_mapper.dart';
import 'package:metadata_audio/src/model/types.dart';

final _apev2TagMap = <String, String>{
  'Title': 'title',
  'Artist': 'artist',
  'Artists': 'artists',
  'Album Artist': 'albumartist',
  'Album': 'album',
  'Year': 'year',
  'Originalyear': 'originalyear',
  'Originaldate': 'originaldate',
  'Releasedate': 'releasedate',
  'Comment': 'comment',
  'Track': 'track',
  'Disc': 'disk',
  'DISCNUMBER': 'disk',
  'Genre': 'genre',
  'Cover Art (Front)': 'picture',
  'Cover Art (Back)': 'picture',
  'Composer': 'composer',
  'Lyricist': 'lyricist',
  'Writer': 'writer',
  'Conductor': 'conductor',
  'MixArtist': 'remixer',
  'Arranger': 'arranger',
  'Engineer': 'engineer',
  'Producer': 'producer',
  'DJMixer': 'djmixer',
  'Mixer': 'mixer',
  'Label': 'label',
  'Grouping': 'grouping',
  'Subtitle': 'subtitle',
  'DiscSubtitle': 'discsubtitle',
  'Compilation': 'compilation',
  'BPM': 'bpm',
  'Mood': 'mood',
  'Media': 'media',
  'CatalogNumber': 'catalognumber',
  'MUSICBRAINZ_ALBUMSTATUS': 'releasestatus',
  'MUSICBRAINZ_ALBUMTYPE': 'releasetype',
  'RELEASECOUNTRY': 'releasecountry',
  'Script': 'script',
  'Language': 'language',
  'Copyright': 'copyright',
  'LICENSE': 'license',
  'EncodedBy': 'encodedby',
  'EncoderSettings': 'encodersettings',
  'Barcode': 'barcode',
  'ISRC': 'isrc',
  'ASIN': 'asin',
  'musicbrainz_trackid': 'musicbrainz_recordingid',
  'musicbrainz_releasetrackid': 'musicbrainz_trackid',
  'MUSICBRAINZ_ALBUMID': 'musicbrainz_albumid',
  'MUSICBRAINZ_ARTISTID': 'musicbrainz_artistid',
  'MUSICBRAINZ_ALBUMARTISTID': 'musicbrainz_albumartistid',
  'MUSICBRAINZ_RELEASEGROUPID': 'musicbrainz_releasegroupid',
  'MUSICBRAINZ_WORKID': 'musicbrainz_workid',
  'MUSICBRAINZ_TRMID': 'musicbrainz_trmid',
  'MUSICBRAINZ_DISCID': 'musicbrainz_discid',
  'Acoustid_Id': 'acoustid_id',
  'ACOUSTID_FINGERPRINT': 'acoustid_fingerprint',
  'MUSICIP_PUID': 'musicip_puid',
  'Weblink': 'website',
};

class Apev2TagMapper extends GenericTagMapper {
  @override
  CaseInsensitiveTagMap<String> get tagMap {
    final map = CaseInsensitiveTagMap<String>();
    map.addAll(_apev2TagMap);
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

      final normalized = _normalize(mappedTag, entry.value, entry.key);
      if (normalized != null) {
        result[mappedTag] = normalized;
      }
    }

    return result;
  }

  dynamic _normalize(String mappedTag, dynamic value, String nativeKey) {
    switch (mappedTag) {
      case 'title':
      case 'artist':
      case 'albumartist':
      case 'album':
      case 'originaldate':
      case 'releasedate':
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
      case 'website':
        return _singleString(value);

      case 'year':
      case 'originalyear':
      case 'track':
      case 'disk':
      case 'bpm':
        return _parseLeadingInt(_singleString(value));

      case 'artists':
      case 'genre':
      case 'composer':
      case 'lyricist':
      case 'writer':
      case 'conductor':
      case 'remixer':
      case 'arranger':
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

      case 'compilation':
        return _parseBool(_singleString(value));

      case 'picture':
        if (value is! ApePicture) {
          return null;
        }
        return <Picture>[
          Picture(
            format: _detectPictureMime(value.data),
            data: value.data,
            description: value.description.isEmpty ? null : value.description,
            type: _pictureTypeFromNativeKey(nativeKey),
            name: value.description.isEmpty ? null : value.description,
          ),
        ];

      default:
        return null;
    }
  }

  static String? _singleString(dynamic value) {
    if (value is String) {
      return value;
    }

    if (value is List) {
      for (final entry in value) {
        if (entry is String && entry.isNotEmpty) {
          return entry;
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
      final items = value
          .whereType<String>()
          .where((item) => item.isNotEmpty)
          .toList();
      return items.isEmpty ? null : items;
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

    final slashIndex = trimmed.indexOf('/');
    final numberPart = slashIndex == -1
        ? trimmed
        : trimmed.substring(0, slashIndex);
    return int.tryParse(numberPart);
  }

  static bool? _parseBool(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
      return true;
    }
    if (normalized == '0' || normalized == 'false' || normalized == 'no') {
      return false;
    }

    return null;
  }

  static String _detectPictureMime(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }

    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }

    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return 'image/gif';
    }

    return 'application/octet-stream';
  }

  static String? _pictureTypeFromNativeKey(String nativeKey) {
    final key = nativeKey.toLowerCase();
    if (key.contains('(front)')) {
      return 'Cover (front)';
    }
    if (key.contains('(back)')) {
      return 'Cover (back)';
    }
    return null;
  }
}
