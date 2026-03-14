/// ID3v1 tag mapping to generic tags.
///
/// Maps ID3v1 tag fields to generic common tag names.
/// ID3v1 has fixed fields: title, artist, album, year, comment, track, genre.
///
/// Based on upstream: https://github.com/Borewit/music-metadata/blob/master/lib/id3v1/ID3v1TagMap.ts
library;

import 'package:audio_metadata/src/common/case_insensitive_tag_map.dart';
import 'package:audio_metadata/src/common/generic_tag_mapper.dart';

/// ID3v1 tag field names mapping to generic tag names.
///
/// ID3v1 fields map directly to common tags:
/// - "title" → "title"
/// - "artist" → "artist"
/// - "album" → "album"
/// - "year" → "year"
/// - "comment" → "comment"
/// - "track" → "track"
/// - "genre" → "genre"
final _id3v1TagMap = {
  'title': 'title',
  'artist': 'artist',
  'album': 'album',
  'year': 'year',
  'comment': 'comment',
  'track': 'track',
  'genre': 'genre',
};

/// Tag mapper for ID3v1 format.
///
/// Maps ID3v1 native tags to generic/common tag names.
///
/// Example:
/// ```dart
/// final mapper = Id3v1TagMapper();
/// final nativeTags = {
///   'title': 'My Song',
///   'artist': 'The Artist',
///   'album': 'My Album',
///   'track': 1,
///   'genre': 'Rock',
/// };
/// final genericTags = mapper.mapTags(nativeTags);
/// // Result: {title: My Song, artist: The Artist, album: My Album, track: 1, genre: Rock}
/// ```
class Id3v1TagMapper extends GenericTagMapper {
  @override
  CaseInsensitiveTagMap<String> get tagMap {
    final map = CaseInsensitiveTagMap<String>();
    for (final entry in _id3v1TagMap.entries) {
      map[entry.key] = entry.value;
    }
    return map;
  }
}
