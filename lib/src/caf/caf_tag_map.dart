/// CAF-native tag mapping, ported from upstream `lib/caf/CafTagMap.ts`
/// (Borewit/music-metadata).
///
/// "time signature", "nominal bit rate" and channel layout keys have no
/// common equivalent and stay native. Undocumented keys pass through as
/// native CAF tags only.
library;

import 'package:metadata_audio/src/common/case_insensitive_tag_map.dart';
import 'package:metadata_audio/src/common/generic_tag_mapper.dart';
import 'package:metadata_audio/src/model/types.dart';

const Map<String, String> _infoTagMap = <String, String>{
  'tempo': 'bpm',
  'key signature': 'key',
  'artist': 'artist',
  'album': 'album',
  'track number': 'track',
  'year': 'year',
  'composer': 'composer',
  'lyricist': 'lyricist',
  'genre': 'genre',
  'title': 'title',
  'recorded date': 'date',
  'comments': 'comment',
  'copyright': 'copyright',
  'source encoder': 'encodersettings',
  'encoding application': 'encodedby',
};

/// Keys whose value is a comma-separated artist list.
const Set<String> _commaSeparatedKeys = <String>{
  'artist',
  'composer',
  'lyricist',
  'genre',
};

class CafTagMapper extends GenericTagMapper {
  @override
  CaseInsensitiveTagMap<String> get tagMap {
    final map = CaseInsensitiveTagMap<String>();
    map.addAll(_infoTagMap);
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

      var value = entry.value;

      // Artist/composer/lyricist values are comma-separated lists.
      if (_commaSeparatedKeys.contains(entry.key) && entry.value is String) {
        final parts = (entry.value as String)
            .split(',')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();
        if (parts.length > 1) {
          value = parts;
        }
      }

      final normalized = _normalize(mappedTag, value);
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
      case 'album':
      case 'composer':
      case 'lyricist':
      case 'key':
      case 'copyright':
      case 'date':
      case 'encodersettings':
      case 'encodedby':
        return _singleString(value);
      case 'bpm':
        return _parseInt(_singleString(value));
      case 'track':
        return _parseLeadingInt(_singleString(value));
      case 'year':
        return _parseYear(_singleString(value));
      case 'genre':
        if (value is List) {
          return value.map((e) => e.toString()).toList();
        }
        final text = _singleString(value);
        return text == null ? null : <String>[text];
      case 'comment':
        final text = _singleString(value);
        return text == null ? null : <Comment>[Comment(text: text)];
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

  static int? _parseInt(String? value) {
    if (value == null) {
      return null;
    }
    return int.tryParse(value.trim());
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

  static int? _parseYear(String? value) {
    if (value == null) {
      return null;
    }
    final year = int.tryParse(value.trim());
    if (year == null || year <= 0 || year > 9999) {
      return null;
    }
    return year;
  }
}
