library;

import 'package:audio_metadata/src/common/case_insensitive_tag_map.dart';
import 'package:audio_metadata/src/common/generic_tag_mapper.dart';
import 'package:audio_metadata/src/flac/flac_token.dart';
import 'package:audio_metadata/src/model/types.dart';

final _vorbisTagMap = {
  'TITLE': 'title',
  'ARTIST': 'artist',
  'ALBUM': 'album',
  'DATE': 'year',
  'TRACKNUMBER': 'track',
  'DISCNUMBER': 'disk',
  'GENRE': 'genre',
  'ALBUMARTIST': 'albumartist',
  'ALBUM ARTIST': 'albumartist',
  'METADATA_BLOCK_PICTURE': 'picture',
};

class FlacVorbisTagMapper extends GenericTagMapper {
  @override
  CaseInsensitiveTagMap<String> get tagMap {
    final map = CaseInsensitiveTagMap<String>();
    for (final entry in _vorbisTagMap.entries) {
      map[entry.key] = entry.value;
    }
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

      final value = _normalize(mappedTag, entry.value);
      if (value == null) {
        continue;
      }

      result[mappedTag] = value;
    }

    return result;
  }

  dynamic _normalize(String mappedTag, dynamic value) {
    switch (mappedTag) {
      case 'title':
      case 'artist':
      case 'album':
      case 'albumartist':
        return _singleString(value);
      case 'year':
      case 'track':
      case 'disk':
        return _parseLeadingInt(_singleString(value));
      case 'genre':
        final genre = _singleString(value);
        return genre == null ? null : <String>[genre];
      case 'picture':
        if (value is FlacPicture) {
          return <Picture>[FlacToken.toCommonPicture(value)];
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
