part of 'types.dart';

/// Category of incremental metadata updates emitted during parsing.
enum MetadataEventTagType {
  /// A normalized/common tag changed.
  common,

  /// A format field changed.
  format,
}

/// Strongly typed identifier for common metadata updates.
extension type const MetadataCommonId<T>(String rawValue) {
  static const track = MetadataCommonId<TrackNo>('track');
  static const disk = MetadataCommonId<TrackNo>('disk');
  static const year = MetadataCommonId<int?>('year');
  static const title = MetadataCommonId<String?>('title');
  static const artist = MetadataCommonId<String?>('artist');

  String get path => rawValue;
}

/// Strongly typed identifier for format metadata updates.
extension type const MetadataFormatId<T>(String rawValue) {
  static const container = MetadataFormatId<String?>('container');
  static const duration = MetadataFormatId<double?>('duration');
  static const bitrate = MetadataFormatId<num?>('bitrate');
  static const sampleRate = MetadataFormatId<int?>('sampleRate');
  static const bitsPerSample = MetadataFormatId<int?>('bitsPerSample');
  static const codec = MetadataFormatId<String?>('codec');
  static const numberOfChannels = MetadataFormatId<int?>('numberOfChannels');
  static const tool = MetadataFormatId<String?>('tool');
  static const codecProfile = MetadataFormatId<String?>('codecProfile');
  static const lossless = MetadataFormatId<bool?>('lossless');
  static const numberOfSamples = MetadataFormatId<int?>('numberOfSamples');
  static const audioMD5 = MetadataFormatId<List<int>?>('audioMD5');
  static const chapters = MetadataFormatId<List<Chapter>?>('chapters');
  static const creationTime = MetadataFormatId<DateTime?>('creationTime');
  static const modificationTime = MetadataFormatId<DateTime?>(
    'modificationTime',
  );
  static const trackGain = MetadataFormatId<double?>('trackGain');
  static const trackPeakLevel = MetadataFormatId<double?>('trackPeakLevel');
  static const albumGain = MetadataFormatId<double?>('albumGain');
  static const hasAudio = MetadataFormatId<bool?>('hasAudio');
  static const hasVideo = MetadataFormatId<bool?>('hasVideo');
  static const trackInfo = MetadataFormatId<List<TrackInfo>?>('trackInfo');

  String get path => rawValue;
}

/// Tag payload attached to a [MetadataEvent].
sealed class MetadataEventTag {
  const MetadataEventTag();

  /// Whether the update targets common or format metadata.
  MetadataEventTagType get type;

  /// Strongly typed identifier.
  dynamic get id;

  /// Updated value.
  Object? get value;

  /// Raw string identifier.
  String get key;
}

/// Common metadata update payload.
class CommonMetadataEventTag<T> extends MetadataEventTag {
  /// Create a common metadata event tag payload.
  const CommonMetadataEventTag({required this.id, required this.value});

  @override
  final MetadataCommonId<T> id;

  @override
  final T value;

  @override
  MetadataEventTagType get type => MetadataEventTagType.common;

  @override
  String get key => id.path;

  @override
  String toString() => 'CommonMetadataEventTag(id: ${id.path}, value: $value)';
}

/// Format metadata update payload.
class FormatMetadataEventTag<T> extends MetadataEventTag {
  /// Create a format metadata event tag payload.
  const FormatMetadataEventTag({required this.id, required this.value});

  @override
  final MetadataFormatId<T> id;

  @override
  final T value;

  @override
  MetadataEventTagType get type => MetadataEventTagType.format;

  @override
  String get key => id.path;

  @override
  String toString() => 'FormatMetadataEventTag(id: ${id.path}, value: $value)';
}

/// Event representing a metadata change during parsing.
class MetadataEvent {
  /// Create a metadata event.
  ///
  /// The default empty constructor is kept for backwards compatibility with
  /// existing tests and callers.
  const MetadataEvent({this.tag, this.metadata});

  /// Updated field description.
  final MetadataEventTag? tag;

  /// Snapshot of the metadata after the update was applied.
  final AudioMetadata? metadata;

  @override
  String toString() => 'MetadataEvent(tag: $tag, metadata: $metadata)';
}
