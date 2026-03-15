library;

import 'package:metadata_audio/src/common/case_insensitive_tag_map.dart';
import 'package:metadata_audio/src/common/generic_tag_mapper.dart';
import 'package:metadata_audio/src/model/types.dart';

final Map<String, String> _aiffTagMap = <String, String>{
  'NAME': 'title',
  'AUTH': 'artist',
  '(c) ': 'copyright',
  'ANNO': 'comment',
};

class AiffTagMapper extends GenericTagMapper {
  @override
  CaseInsensitiveTagMap<String> get tagMap {
    final map = CaseInsensitiveTagMap<String>();
    map.addAll(_aiffTagMap);
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
      case 'copyright':
        return _singleString(value);
      case 'comment':
        final text = _singleString(value);
        return text == null ? null : <Comment>[Comment(text: text)];
      default:
        return null;
    }
  }

  static String? _singleString(dynamic value) {
    if (value is String && value.isNotEmpty) {
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
}
