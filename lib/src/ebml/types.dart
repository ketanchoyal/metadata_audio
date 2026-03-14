library;

/// Generic EBML tree representation used by the iterator.
///
/// Values in this map are one of: `String`, `int`, `double`, `bool`,
/// `Uint8List`, nested [EbmlTree], or `List<EbmlTree>`.
typedef EbmlTree = Map<String, Object?>;

/// EBML value payload union representation.
typedef EbmlValue = Object?;

/// Element value type used to decode raw EBML element payload bytes.
enum EbmlDataType {
  /// UTF-8 string payload.
  string,

  /// Unsigned integer payload.
  uint,

  /// Unique identifier payload represented as raw bytes.
  uid,

  /// Boolean payload represented as integer 0/1.
  bool,

  /// Opaque binary payload.
  binary,

  /// IEEE-754 floating-point payload.
  float,
}

/// EBML element header.
class EbmlHeader {
  /// Creates an [EbmlHeader].
  const EbmlHeader({required this.id, required this.len});

  /// Decoded element identifier.
  final int id;

  /// Decoded payload length in bytes.
  final int len;
}

/// Top-level EBML document element values.
class EbmlElements {
  /// Creates [EbmlElements].
  const EbmlElements({
    this.version,
    this.readVersion,
    this.maxIDWidth,
    this.maxSizeWidth,
    this.docType,
    this.docTypeVersion,
    this.docTypeReadVersion,
  });

  /// EBML version.
  final int? version;

  /// Minimum EBML read version.
  final int? readVersion;

  /// Maximum element ID width.
  final int? maxIDWidth;

  /// Maximum element size width.
  final int? maxSizeWidth;

  /// Document type identifier.
  final String? docType;

  /// Document type version.
  final int? docTypeVersion;

  /// Document type read version.
  final int? docTypeReadVersion;
}

/// EBML DTD element definition.
class EbmlElementType {
  /// Creates an [EbmlElementType].
  const EbmlElementType({
    required this.name,
    this.value,
    this.container,
    this.multiple = false,
  });

  /// Logical name used as map key in parsed trees.
  final String name;

  /// Scalar decoder type for non-container elements.
  final EbmlDataType? value;

  /// Child element definitions keyed by EBML element ID.
  final Map<int, EbmlElementType>? container;

  /// Whether this element may occur multiple times.
  final bool multiple;
}

/// Root EBML document representation.
class EbmlDocument {
  /// Creates an [EbmlDocument].
  const EbmlDocument({required this.ebml});

  /// Parsed EBML header section values.
  final EbmlElements ebml;
}

/// Runtime-linked EBML element definition with parent and id information.
class LinkedEbmlElementType {
  /// Creates a [LinkedEbmlElementType].
  const LinkedEbmlElementType({
    required this.id,
    required this.name,
    required this.parent,
    this.value,
    this.container,
    this.multiple = false,
  });

  /// Element ID in parent container map.
  final int id;

  /// Logical element name.
  final String name;

  /// Linked parent element; null for root.
  final LinkedEbmlElementType? parent;

  /// Scalar decoder type for non-container elements.
  final EbmlDataType? value;

  /// Linked child element map.
  final Map<int, LinkedEbmlElementType>? container;

  /// Whether this element may occur multiple times.
  final bool multiple;
}

/// Callback invoked before reading the next element payload.
typedef EbmlStartNextListener = ParseAction Function(LinkedEbmlElementType dtd);

/// Callback invoked after an element value has been decoded.
typedef EbmlElementValueListener =
    Future<void> Function(
      LinkedEbmlElementType dtd,
      EbmlValue value,
      int offset,
    );

/// Parsing control actions returned by [EbmlStartNextListener].
enum ParseAction {
  /// Continue reading and parsing the current element payload.
  readNext,

  /// Skip reading this element payload.
  ignoreElement,

  /// Skip all remaining sibling elements in the current container.
  skipSiblings,

  /// Stop parsing immediately.
  terminateParsing,

  /// Element payload is already consumed by the caller.
  skipElement,
}

/// EBML iterator callbacks.
class EbmlElementListener {
  /// Creates an [EbmlElementListener].
  const EbmlElementListener({
    required this.startNext,
    required this.elementValue,
  });

  /// Called before parsing each known element.
  final EbmlStartNextListener startNext;

  /// Called after parsing an element value.
  final EbmlElementValueListener elementValue;
}

/// Link element definitions with parent references and numeric ids.
LinkedEbmlElementType linkParents(
  EbmlElementType element, {
  LinkedEbmlElementType? parent,
  int id = 0,
}) {
  final linked = LinkedEbmlElementType(
    id: id,
    name: element.name,
    parent: parent,
    value: element.value,
    multiple: element.multiple,
  );

  if (element.container == null) {
    return linked;
  }

  final linkedChildren = <int, LinkedEbmlElementType>{};
  for (final entry in element.container!.entries) {
    linkedChildren[entry.key] = linkParents(
      entry.value,
      parent: linked,
      id: entry.key,
    );
  }

  return LinkedEbmlElementType(
    id: linked.id,
    name: linked.name,
    parent: linked.parent,
    value: linked.value,
    multiple: linked.multiple,
    container: linkedChildren,
  );
}

/// Return slash-separated DTD path of [element].
String getElementPath(LinkedEbmlElementType element) {
  if (element.parent == null || element.parent!.name == 'dtd') {
    return element.name;
  }
  return '${getElementPath(element.parent!)}/${element.name}';
}
