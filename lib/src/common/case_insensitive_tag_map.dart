/// Case-insensitive tag mapping utility.
///
/// Provides a map-like interface where keys are matched case-insensitively.
/// All keys are normalized to lowercase internally.
///
/// Based on upstream: https://github.com/Borewit/music-metadata/blob/master/lib/common/CaseInsensitiveTagMap.ts
library;

/// A case-insensitive map for storing tag mappings.
///
/// Internally normalizes all keys to lowercase, allowing lookups to work
/// regardless of the case of the input key.
///
/// Example:
/// ```dart
/// final map = CaseInsensitiveTagMap<String>();
/// map['TIT2'] = 'title';
/// map['tit2']; // Returns 'title'
/// map['TIT2']; // Also returns 'title'
/// ```
class CaseInsensitiveTagMap<V> {
  final Map<String, V> _internalMap = {};

  /// Returns the value associated with the given [key], normalized to
  /// lowercase. Returns null if the key is not found.
  V? operator [](String key) => _internalMap[key.toLowerCase()];

  /// Sets the value for the given [key], normalized to lowercase.
  void operator []=(String key, V value) =>
      _internalMap[key.toLowerCase()] = value;

  /// Adds all key-value pairs from [other] to this map.
  /// Keys are normalized to lowercase.
  void addAll(Map<String, V> other) {
    for (final entry in other.entries) {
      _internalMap[entry.key.toLowerCase()] = entry.value;
    }
  }

  /// Returns whether this map contains the given [key] (case-insensitive).
  bool containsKey(String key) => _internalMap.containsKey(key.toLowerCase());

  /// Removes the entry for the given [key] (case-insensitive).
  /// Returns the value that was associated with the key, or null if not found.
  V? remove(String key) => _internalMap.remove(key.toLowerCase());

  /// Returns the number of key-value pairs in this map.
  int get length => _internalMap.length;

  /// Returns whether this map is empty.
  bool get isEmpty => _internalMap.isEmpty;

  /// Returns whether this map is not empty.
  bool get isNotEmpty => _internalMap.isNotEmpty;

  /// Returns a set of all keys (in lowercase) in this map.
  Set<String> get keys => _internalMap.keys.toSet();

  /// Returns a list of all values in this map.
  Iterable<V> get values => _internalMap.values;

  /// Returns all entries (key-value pairs) in this map.
  Iterable<MapEntry<String, V>> get entries => _internalMap.entries;

  /// Clears all entries from this map.
  void clear() {
    _internalMap.clear();
  }

  /// Applies [f] to each key-value pair in this map.
  void forEach(void Function(String key, V value) f) => _internalMap.forEach(f);

  /// Returns the value for [key] or calls [ifAbsent] to create a default
  /// value.
  V putIfAbsent(String key, V Function() ifAbsent) =>
      _internalMap.putIfAbsent(key.toLowerCase(), ifAbsent);

  /// Updates the value for [key] using [update] function.
  V update(String key, V Function(V value) update, {V Function()? ifAbsent}) =>
      _internalMap.update(key.toLowerCase(), update, ifAbsent: ifAbsent);

  /// Converts this map to a regular case-sensitive map (lowercase keys).
  Map<String, V> toMap() => Map.from(_internalMap);

  @override
  String toString() => _internalMap.toString();
}
