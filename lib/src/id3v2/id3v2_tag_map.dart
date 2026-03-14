library;

import 'package:audio_metadata/src/common/case_insensitive_tag_map.dart';
import 'package:audio_metadata/src/common/generic_tag_mapper.dart';
import 'package:audio_metadata/src/model/types.dart';

final _id3v2TagMap = {
  'TT2': 'title',
  'TIT2': 'title',
  'TP1': 'artist',
  'TPE1': 'artist',
  'TAL': 'album',
  'TALB': 'album',
  'TYE': 'year',
  'TYER': 'year',
  'TDRC': 'year',
  'TRK': 'track',
  'TRCK': 'track',
  'TPA': 'disk',
  'TPOS': 'disk',
  'TCO': 'genre',
  'TCON': 'genre',
  'COM': 'comment',
  'COMM': 'comment',
  'TSOT': 'titlesort',
  'TSOA': 'albumsort',
  'TSOP': 'artistsort',
  'TSO2': 'albumartistsort',
  'TCOM': 'composer',
  'TEXT': 'lyricist',
  'TENC': 'encoder',
  'TPUB': 'publisher',
  'TIT1': 'grouping',
  'TMOO': 'mood',
  'MVIN': 'movementindex',
  'PCST': 'podcast',
  'PCS': 'podcastid',
  'TLAN': 'language',
  'TCOP': 'copyright',
};

class Id3v2TagMapper extends GenericTagMapper {
  @override
  CaseInsensitiveTagMap<String> get tagMap {
    final map = CaseInsensitiveTagMap<String>();
    for (final entry in _id3v2TagMap.entries) {
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

      final value = _normalizeValue(mappedTag, entry.value);
      if (value != null) {
        result[mappedTag] = value;
      }
    }

    return result;
  }

  dynamic _normalizeValue(String mappedTag, dynamic value) {
    switch (mappedTag) {
      case 'title':
      case 'artist':
      case 'album':
        return _singleString(value);
      case 'year':
        return _parseLeadingInt(_singleString(value));
      case 'track':
      case 'disk':
        final text = _singleString(value);
        if (text == null) {
          return null;
        }
        return _parseLeadingInt(text.split('/').first);
      case 'genre':
        return _stringList(value);
      case 'comment':
        if (value is Comment) {
          return [value];
        }
        return null;
      // Extended ID3v2 mappings - string singletons
      case 'titlesort':
      case 'albumsort':
      case 'artistsort':
      case 'albumartistsort':
      case 'grouping':
      case 'mood':
      case 'language':
      case 'copyright':
        return _singleString(value);
      // Extended ID3v2 mappings - string lists (creator roles)
      case 'composer':
      case 'lyricist':
      case 'encoder':
      case 'publisher':
        return _stringList(value);
      // Extended ID3v2 mappings (string list values)
      case 'podcastid':
        return _stringList(value);
      // Extended ID3v2 mappings (numeric/boolean values)
      case 'movementindex':
        return _parseLeadingInt(_singleString(value));
      case 'podcast':
        final intVal = _parseLeadingInt(_singleString(value));
        return intVal != null ? intVal != 0 : null;
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

  static List<String>? _stringList(dynamic value) {
    if (value is String) {
      return [value];
    }
    if (value is List) {
      final values = value
          .whereType<String>()
          .where((v) => v.isNotEmpty)
          .toList();
      return values.isEmpty ? null : values;
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
    return int.tryParse(normalized);
  }
}
