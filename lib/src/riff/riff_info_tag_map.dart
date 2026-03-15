library;

import 'package:metadata_audio/src/common/case_insensitive_tag_map.dart';
import 'package:metadata_audio/src/common/generic_tag_mapper.dart';
import 'package:metadata_audio/src/model/types.dart';

final Map<String, String> _riffInfoTagMap = <String, String>{
  'IART': 'artist',
  'ICRD': 'date',
  'INAM': 'title',
  'TITL': 'title',
  'IPRD': 'album',
  'IRPD': 'album',
  'ITRK': 'track',
  'IPRT': 'track',
  'COMM': 'comment',
  'ICMT': 'comment',
  'ICNT': 'releasecountry',
  'GNRE': 'genre',
  'IGNR': 'genre',
  'IWRI': 'writer',
  'RATE': 'rating',
  'YEAR': 'year',
  'ISFT': 'encodedby',
  'CODE': 'encodedby',
  'TURL': 'website',
  'IENG': 'engineer',
  'ITCH': 'technician',
  'IMED': 'media',
};

class RiffInfoTagMapper extends GenericTagMapper {
  @override
  CaseInsensitiveTagMap<String> get tagMap {
    final map = CaseInsensitiveTagMap<String>();
    map.addAll(_riffInfoTagMap);
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
      case 'date':
      case 'album':
      case 'releasecountry':
      case 'encodedby':
      case 'website':
      case 'media':
        return _singleString(value);
      case 'track':
      case 'year':
        return _parseLeadingInt(_singleString(value));
      case 'genre':
      case 'writer':
      case 'engineer':
      case 'technician':
        final text = _singleString(value);
        return text == null ? null : <String>[text];
      case 'comment':
        final text = _singleString(value);
        return text == null ? null : <Comment>[Comment(text: text)];
      case 'rating':
        final numeric = _parseLeadingInt(_singleString(value));
        if (numeric == null) {
          return null;
        }
        final clamped = numeric.clamp(0, 100);
        return <Rating>[Rating(rating: clamped / 100.0)];
      default:
        return null;
    }
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

  static int? _parseLeadingInt(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final delimiter = normalized.indexOf('/');
    final numberText = delimiter == -1
        ? normalized
        : normalized.substring(0, delimiter);
    return int.tryParse(numberText.trim());
  }
}
