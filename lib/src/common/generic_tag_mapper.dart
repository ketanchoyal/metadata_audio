/// Generic tag mapper for mapping format-specific tags to generic tags.
///
/// Defines an abstract interface for mapping tags from format-specific
/// identifiers (like ID3v2 "TIT2") to generic tag types (like "title").
///
/// Based on upstream: https://github.com/Borewit/music-metadata/blob/master/lib/common/GenericTagMapper.ts
library;

import 'package:audio_metadata/src/common/case_insensitive_tag_map.dart';

/// Abstract base class for format-specific tag mappers.
///
/// Subclasses implement [tagMap] to define the mapping from format-specific
/// tag IDs to generic tag IDs, and optionally override [mapTag] to provide
/// custom tag value transformation logic.
///
/// Example implementation:
/// ```dart
/// class Id3v2Mapper extends GenericTagMapper {
///   @override
///   CaseInsensitiveTagMap<String> get tagMap {
///     final map = CaseInsensitiveTagMap<String>();
///     map['TIT2'] = 'title';
///     map['TPE1'] = 'artist';
///     map['TALB'] = 'album';
///     return map;
///   }
/// }
/// ```
abstract class GenericTagMapper {
  /// Returns the mapping of format-specific tag IDs to generic tag IDs.
  ///
  /// The map keys are format-specific tag identifiers (e.g., ID3v2 frame IDs),
  /// and the values are generic tag type names (e.g., "title", "artist").
  CaseInsensitiveTagMap<String> get tagMap;

  /// Maps a single tag from format-specific to generic representation.
  ///
  /// Takes a format-specific [tag] identifier and the [value] associated
  /// with it, and returns either:
  /// - A mapped value if a mapping exists
  /// - null if no mapping is defined for this tag
  /// - A transformed/normalized version of the value if needed
  ///
  /// Subclasses can override this to provide custom value transformation.
  /// The default implementation returns the value as-is if a mapping exists.
  String? mapTag(String tag, dynamic value) {
    final mapped = tagMap[tag];
    return mapped;
  }

  /// Maps all tags from a format-specific tag collection to generic tags.
  ///
  /// Takes a map of format-specific tags [nativeTags] and returns a map
  /// of generic tags where:
  /// - Keys are generic tag names (from [mapTag])
  /// - Values are the original values from [nativeTags] for mapped tags
  /// - Only tags that have a mapping are included in the result
  ///
  /// Example:
  /// ```dart
  /// final nativeTags = {
  ///   'TIT2': 'My Song',
  ///   'TPE1': 'Artist Name',
  ///   'TXXX': 'Custom Frame' // No mapping defined
  /// };
  /// final genericTags = mapper.mapTags(nativeTags);
  /// // Result: {'title': 'My Song', 'artist': 'Artist Name'}
  /// ```
  Map<String, dynamic> mapTags(Map<String, dynamic> nativeTags) {
    final result = <String, dynamic>{};

    for (final entry in nativeTags.entries) {
      final formatTag = entry.key;
      final value = entry.value;

      final mappedTag = mapTag(formatTag, value);
      if (mappedTag != null) {
        result[mappedTag] = value;
      }
    }

    return result;
  }
}
