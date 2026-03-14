library;

// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

import 'package:audio_metadata/src/common/case_insensitive_tag_map.dart';
import 'package:audio_metadata/src/common/generic_tag_mapper.dart';
import 'package:audio_metadata/src/model/types.dart';

const Map<String, String> _matroskaTagMap = <String, String>{
  'segment:title': 'title',
  'album:ARTIST': 'albumartist',
  'album:ARTISTSORT': 'albumartistsort',
  'album:TITLE': 'album',
  'album:DATE_RECORDED': 'originaldate',
  'album:DATE_RELEASED': 'releasedate',
  'album:PART_NUMBER': 'disk',
  'album:TOTAL_PARTS': 'totaltracks',
  'track:ARTIST': 'artist',
  'track:ARTISTSORT': 'artistsort',
  'track:TITLE': 'title',
  'track:PART_NUMBER': 'track',
  'track:MUSICBRAINZ_TRACKID': 'musicbrainz_recordingid',
  'track:MUSICBRAINZ_ALBUMID': 'musicbrainz_albumid',
  'track:MUSICBRAINZ_ARTISTID': 'musicbrainz_artistid',
  'track:PUBLISHER': 'label',
  'track:GENRE': 'genre',
  'track:ENCODER': 'encodedby',
  'track:ENCODER_OPTIONS': 'encodersettings',
  'edition:TOTAL_PARTS': 'totaldiscs',
  'picture': 'picture',
};

class MatroskaTagMapper extends GenericTagMapper {
  @override
  CaseInsensitiveTagMap<String> get tagMap {
    final map = CaseInsensitiveTagMap<String>();
    for (final entry in _matroskaTagMap.entries) {
      map[entry.key] = entry.value;
    }
    return map;
  }

  @override
  Map<String, dynamic> mapTags(Map<String, dynamic> nativeTags) {
    final result = <String, dynamic>{};

    for (final entry in nativeTags.entries) {
      final mapped = mapTag(entry.key, entry.value);
      if (mapped == null) {
        continue;
      }

      final value = _normalize(mapped, entry.value);
      if (value == null) {
        continue;
      }

      result[mapped] = value;
    }

    return result;
  }

  dynamic _normalize(String mappedTag, dynamic value) {
    switch (mappedTag) {
      case 'artist':
      case 'artistsort':
      case 'title':
      case 'album':
      case 'albumartist':
      case 'albumartistsort':
      case 'originaldate':
      case 'releasedate':
      case 'musicbrainz_recordingid':
      case 'musicbrainz_albumid':
      case 'encodedby':
      case 'encodersettings':
        return _singleString(value);
      case 'track':
      case 'disk':
      case 'totaltracks':
      case 'totaldiscs':
        return _parseLeadingInt(_singleString(value));
      case 'genre':
      case 'label':
      case 'musicbrainz_artistid':
        final text = _singleString(value);
        return text == null ? null : <String>[text];
      case 'picture':
        if (value is Picture) {
          return <Picture>[value];
        }
        return null;
      default:
        return null;
    }
  }

  static String? _singleString(dynamic value) {
    if (value is String) {
      return value;
    }
    if (value is Uint8List) {
      return String.fromCharCodes(value);
    }
    return null;
  }

  static int? _parseLeadingInt(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final delimiterIndex = normalized.indexOf('/');
    final numberPart = delimiterIndex == -1
        ? normalized
        : normalized.substring(0, delimiterIndex);
    return int.tryParse(numberPart);
  }
}
