/// Combined tag mapper that dispatches to format-specific mappers.
///
/// Acts as a registry and dispatcher for format-specific tag mappers.
/// Maps tags from various audio formats (ID3v2, Vorbis, MP4, APEv2, etc.)
/// to a common generic tag format.
///
/// Based on upstream: https://github.com/Borewit/music-metadata/blob/master/lib/common/CombinedTagMapper.ts
library;

import 'package:audio_metadata/src/common/generic_tag_mapper.dart';

/// Exception thrown when attempting to map tags for an unknown format.
class UnknownFormatException implements Exception {
  final String formatId;

  UnknownFormatException(this.formatId);

  @override
  String toString() =>
      'UnknownFormatException: No tag mapper registered for format "$formatId"';
}

/// Combines multiple format-specific tag mappers into a single dispatcher.
///
/// This class maintains a registry of [GenericTagMapper] implementations,
/// each responsible for mapping tags from a specific audio format to generic tags.
///
/// Usage:
/// ```dart
/// final combined = CombinedTagMapper();
/// combined.registerMapper('id3v2', Id3v2Mapper());
/// combined.registerMapper('vorbis', VorbisMapper());
///
/// // Map tags from a specific format
/// final genericTags = combined.mapTags('id3v2', {
///   'TIT2': 'Song Title',
///   'TPE1': 'Artist Name',
/// });
/// ```
class CombinedTagMapper {
  /// Internal registry of format-specific tag mappers.
  ///
  /// Maps format IDs (like "id3v2", "vorbis", "mp4") to their corresponding
  /// tag mapper implementations.
  final Map<String, GenericTagMapper> _mappers = {};

  /// Registers a tag mapper for a specific format.
  ///
  /// Associates the given [mapper] with the [formatId]. If a mapper is already
  /// registered for this format, it will be replaced.
  ///
  /// Parameters:
  /// - [formatId]: Unique identifier for the format (e.g., "id3v2", "vorbis", "mp4")
  /// - [mapper]: The [GenericTagMapper] implementation for this format
  ///
  /// Example:
  /// ```dart
  /// mapper.registerMapper('id3v2', Id3v2Mapper());
  /// mapper.registerMapper('vorbis', VorbisCommentMapper());
  /// ```
  void registerMapper(String formatId, GenericTagMapper mapper) {
    _mappers[formatId] = mapper;
  }

  /// Maps native tags to generic tags using the appropriate format-specific mapper.
  ///
  /// Looks up the mapper for the given [formatId] and uses it to convert
  /// the [nativeTags] to generic tag format.
  ///
  /// Parameters:
  /// - [formatId]: The format of the native tags (e.g., "id3v2", "vorbis")
  /// - [nativeTags]: Map of format-specific tag identifiers to values
  ///
  /// Returns:
  /// A map of generic tag names to their values, as determined by the format-specific mapper.
  ///
  /// Throws:
  /// - [UnknownFormatException] if no mapper is registered for the given [formatId]
  ///
  /// Example:
  /// ```dart
  /// try {
  ///   final genericTags = combined.mapTags('id3v2', {
  ///     'TIT2': 'My Song',
  ///     'TPE1': 'The Artist',
  ///   });
  ///   print(genericTags); // {title: My Song, artist: The Artist}
  /// } on UnknownFormatException catch (e) {
  ///   print('Format not supported: $e');
  /// }
  /// ```
  Map<String, dynamic> mapTags(
    String formatId,
    Map<String, dynamic> nativeTags,
  ) {
    final mapper = _mappers[formatId];

    if (mapper == null) {
      throw UnknownFormatException(formatId);
    }

    return mapper.mapTags(nativeTags);
  }

  /// Checks if a mapper is registered for the given format.
  ///
  /// Returns `true` if a [GenericTagMapper] has been registered for [formatId],
  /// `false` otherwise.
  ///
  /// Example:
  /// ```dart
  /// if (combined.hasMapper('id3v2')) {
  ///   final tags = combined.mapTags('id3v2', nativeTags);
  /// }
  /// ```
  bool hasMapper(String formatId) => _mappers.containsKey(formatId);

  /// Returns the number of registered mappers.
  int get mapperCount => _mappers.length;

  /// Returns an unmodifiable view of all registered format IDs.
  Set<String> get registeredFormats => _mappers.keys.toSet();

  /// Clears all registered mappers.
  ///
  /// This is primarily useful for testing or resetting state.
  /// After calling this method, the combined mapper will have no mappers
  /// and all subsequent [mapTags] calls will throw [UnknownFormatException].
  void clear() => _mappers.clear();
}
