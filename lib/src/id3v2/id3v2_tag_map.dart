library;

import 'package:metadata_audio/src/common/case_insensitive_tag_map.dart';
import 'package:metadata_audio/src/common/generic_tag_mapper.dart';
import 'package:metadata_audio/src/model/types.dart';

final _id3v2TagMap = {
  'TT2': 'title',
  'TIT2': 'title',
  'TP1': 'artist',
  'TPE1': 'artist',
  'TP2': 'albumartist',
  'TPE2': 'albumartist',
  'TAL': 'album',
  'TALB': 'album',
  'TYE': 'year',
  'TYER': 'year',
  'TDRC': 'date',
  'TDOR': 'originaldate',
  'TRK': 'track',
  'TRCK': 'track',
  'TPA': 'disk',
  'TPOS': 'disk',
  'TCO': 'genre',
  'TCON': 'genre',
  'COM': 'comment',
  'COMM': 'comment',
  'USLT': 'lyrics', // Unsynchronized lyrics
  'ULT': 'lyrics', // v2.2: Unsynchronized lyrics
  'IPL:arranger': 'arranger',
  'IPL:engineer': 'engineer',
  'IPL:producer': 'producer',
  'IPL:DJ-mix': 'djmixer',
  'IPL:mix': 'mixer',
  'IPLS:arranger': 'arranger',
  'IPLS:engineer': 'engineer',
  'IPLS:producer': 'producer',
  'IPLS:DJ-mix': 'djmixer',
  'IPLS:mix': 'mixer',
  'TIPL:arranger': 'arranger',
  'TIPL:engineer': 'engineer',
  'TIPL:producer': 'producer',
  'TIPL:DJ-mix': 'djmixer',
  'TIPL:mix': 'mixer',
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
  'MVNM': 'movement',
  'MVIN': 'movementIndex',
  'PCNT': 'playCounter',
  'PRIV:AverageLevel': 'averageLevel',
  'PRIV:PeakLevel': 'peakLevel',
  'PRIV:PeakValue': 'peakLevel',
  'PCST': 'podcast',
  'PCS': 'podcastId',
  'TGID': 'podcastId',
  'TCAT': 'category',
  'TDES': 'description',
  'TDRL': 'releasedate',
  'TKWD': 'keywords',
  'WFED': 'podcasturl',
  'TLAN': 'language',
  'TCOP': 'copyright',
};

class Id3v2TagMapper extends GenericTagMapper {
  /// ID3v2 frames carrying role-to-people credit maps, parsed by
  /// [FrameParser] (upstream `functionList`).
  static const _creditsFrameIds = {'IPL', 'IPLS', 'TMCL', 'TIPL'};

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
      final tagId = entry.key.toUpperCase();
      final rawValue = entry.value;

      // Involved-person credits (TMCL/TIPL/IPL/IPLS) are neither mapped
      // wholesale nor replicated as synthetic native tags; each role is
      // expanded to `<frameId>:<role>` lookups instead (upstream parity,
      // #2862: "Expand involved-person roles for mapping without adding
      // synthetic native tags").
      if (_creditsFrameIds.contains(entry.key) &&
          rawValue is Map<String, dynamic>) {
        rawValue.forEach((role, people) {
          if (people is! List) {
            return;
          }
          for (final person in people) {
            if (person is! String || person.isEmpty) {
              continue;
            }
            final mappedRole = mapTag('${entry.key}:$role', person);
            if (mappedRole == null) {
              continue;
            }
            final normalizedPeople = _normalizeValue(mappedRole, person);
            if (normalizedPeople == null) {
              continue;
            }
            if (normalizedPeople is! List) {
              continue;
            }
            // Multiple people per role must aggregate (upstream emits one
            // mapped tag per person).
            final existing = result[mappedRole];
            if (existing is List<String>) {
              for (final normalizedPerson in normalizedPeople) {
                if (!existing.contains(normalizedPerson)) {
                  existing.add(normalizedPerson);
                }
              }
            } else if (existing != null) {
              result[mappedRole] = [
                ...existing.whereType<String>(),
                ...normalizedPeople.whereType<String>(),
              ];
            } else {
              result[mappedRole] = normalizedPeople
                  .whereType<String>()
                  .toList();
            }
          }
        });
        continue;
      }

      final mappedTag = mapTag(entry.key, rawValue);
      if (mappedTag == null) {
        continue;
      }

      // Handle TPOS (disk position) specially to extract totaldiscs
      if (tagId == 'TPOS' || tagId == 'TPA') {
        final parsed = _parsePositionWithTotal(rawValue);
        if (parsed.$1 != null) {
          result['disk'] = parsed.$1;
        }
        if (parsed.$2 != null) {
          result['totaldiscs'] = parsed.$2;
        }
        continue;
      }

      // Handle TRCK (track position) specially to extract totaltracks
      if (tagId == 'TRCK' || tagId == 'TRK') {
        final parsed = _parsePositionWithTotal(rawValue);
        if (parsed.$1 != null) {
          result['track'] = parsed.$1;
        }
        if (parsed.$2 != null) {
          result['totaltracks'] = parsed.$2;
        }
        continue;
      }

      final value = _normalizeValue(mappedTag, rawValue);
      if (value != null) {
        result[mappedTag] = value;
      }
    }

    return result;
  }

  /// Parses a position string like "1" or "1/2" into (position, total).
  (int?, int?) _parsePositionWithTotal(dynamic value) {
    final text = _singleString(value);
    if (text == null) {
      return (null, null);
    }
    final parts = text.split('/');
    final position = _parseLeadingInt(parts.first);
    final total = parts.length > 1 ? _parseLeadingInt(parts[1]) : null;
    return (position, total);
  }

  dynamic _normalizeValue(String mappedTag, dynamic value) {
    switch (mappedTag) {
      case 'title':
      case 'artist':
      case 'album':
      case 'albumartist':
      case 'date':
      case 'originaldate':
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
      case 'lyrics':
        if (value is LyricsTag) {
          return [value];
        }
        return null;
      // Involved-person credits (expanded from TMCL/TIPL/IPL/IPLS role maps)
      case 'arranger':
      case 'engineer':
      case 'producer':
      case 'djmixer':
      case 'mixer':
        return _stringList(value);
      // Extended ID3v2 mappings - string singletons
      case 'titlesort':
      case 'albumsort':
      case 'artistsort':
      case 'albumartistsort':
      case 'grouping':
      case 'mood':
      case 'language':
      case 'copyright':
      case 'movement':
      case 'releasedate':
      case 'podcasturl':
      case 'podcastId':
        return _singleString(value);
      // Extended ID3v2 mappings - string lists (creator roles)
      case 'composer':
      case 'lyricist':
      case 'encoder':
      case 'publisher':
      case 'category':
      case 'description':
      case 'keywords':
        return _stringList(value);
      // Extended ID3v2 mappings (numeric/boolean values)
      case 'movementIndex':
        return _parseCounter(value);
      case 'playCounter':
        return _parseCounter(value);
      case 'averageLevel':
      case 'peakLevel':
        return value is num ? value.toDouble() : null;
      case 'podcast':
        final intVal = _parseLeadingInt(_singleString(value));
        return intVal != null ? intVal != 0 : null;
      default:
        return null;
    }
  }

  int? _parseCounter(dynamic value) {
    if (value is int) {
      return value >= 0 ? value : null;
    }
    return _parseLeadingInt(_singleString(value));
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
