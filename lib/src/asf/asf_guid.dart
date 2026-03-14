library;

/// ASF GUID wrapper with helpers to decode/encode ASF binary GUIDs.
class AsfGuid {
  const AsfGuid(this.str);

  final String str;

  static const AsfGuid headerObject = AsfGuid(
    '75B22630-668E-11CF-A6D9-00AA0062CE6C',
  );
  static const AsfGuid filePropertiesObject = AsfGuid(
    '8CABDCA1-A947-11CF-8EE4-00C00C205365',
  );
  static const AsfGuid streamPropertiesObject = AsfGuid(
    'B7DC0791-A9B7-11CF-8EE6-00C00C205365',
  );
  static const AsfGuid headerExtensionObject = AsfGuid(
    '5FBF03B5-A92E-11CF-8EE3-00C00C205365',
  );
  static const AsfGuid codecListObject = AsfGuid(
    '86D15240-311D-11D0-A3A4-00A0C90348F6',
  );
  static const AsfGuid contentDescriptionObject = AsfGuid(
    '75B22633-668E-11CF-A6D9-00AA0062CE6C',
  );
  static const AsfGuid extendedContentDescriptionObject = AsfGuid(
    'D2D0A440-E307-11D2-97F0-00A0C95EA850',
  );
  static const AsfGuid streamBitratePropertiesObject = AsfGuid(
    '7BF875CE-468D-11D1-8D82-006097C9A2B2',
  );
  static const AsfGuid paddingObject = AsfGuid(
    '1806D474-CADF-4509-A4BA-9AABCB96AAE8',
  );

  static const AsfGuid extendedStreamPropertiesObject = AsfGuid(
    '14E6A5CB-C672-4332-8399-A96952065B5A',
  );
  static const AsfGuid metadataObject = AsfGuid(
    'C5F8CBEA-5BAF-4877-8467-AA8C44FA4CCA',
  );
  static const AsfGuid metadataLibraryObject = AsfGuid(
    '44231C94-9498-49D1-A141-1D134E457054',
  );
  static const AsfGuid compatibilityObject = AsfGuid(
    '26F18B5D-4584-47EC-9F5F-0E651F0452C9',
  );
  static const AsfGuid asfIndexPlaceholderObject = AsfGuid(
    'D9AADE20-7C17-4F9C-BC28-8555DD98E2A2',
  );

  static const AsfGuid audioMedia = AsfGuid(
    'F8699E40-5B4D-11CF-A8FD-00805F5C442B',
  );
  static const AsfGuid videoMedia = AsfGuid(
    'BC19EFC0-5B4D-11CF-A8FD-00805F5C442B',
  );
  static const AsfGuid commandMedia = AsfGuid(
    '59DACFC0-59E6-11D0-A3AC-00A0C90348F6',
  );
  static const AsfGuid degradableJpegMedia = AsfGuid(
    '35907DE0-E415-11CF-A917-00805F5C442B',
  );
  static const AsfGuid fileTransferMedia = AsfGuid(
    '91BD222C-F21C-497A-8B6D-5AA86BFC0185',
  );
  static const AsfGuid binaryMedia = AsfGuid(
    '3AFB65E2-47EF-40F2-AC2C-70A90D71D343',
  );

  static AsfGuid fromBytes(List<int> bytes, [int offset = 0]) {
    final guidBytes = bytes.sublist(offset, offset + 16);
    return AsfGuid(decode(guidBytes));
  }

  static String decode(List<int> bytes) {
    if (bytes.length < 16) {
      throw ArgumentError('GUID requires 16 bytes, got ${bytes.length}');
    }

    final b = bytes;
    final d1 =
        _hexByte(b[3]) + _hexByte(b[2]) + _hexByte(b[1]) + _hexByte(b[0]);
    final d2 = _hexByte(b[5]) + _hexByte(b[4]);
    final d3 = _hexByte(b[7]) + _hexByte(b[6]);
    final d4 = _hexByte(b[8]) + _hexByte(b[9]);
    final d5 =
        _hexByte(b[10]) +
        _hexByte(b[11]) +
        _hexByte(b[12]) +
        _hexByte(b[13]) +
        _hexByte(b[14]) +
        _hexByte(b[15]);

    return '$d1-$d2-$d3-$d4-$d5';
  }

  static List<int> encode(String guid) {
    final normalized = guid.toUpperCase();
    final parts = normalized.split('-');
    if (parts.length != 5) {
      throw ArgumentError('Invalid GUID format: $guid');
    }

    final d1 = _parseHex(parts[0], 8);
    final d2 = _parseHex(parts[1], 4);
    final d3 = _parseHex(parts[2], 4);
    final d4 = _parseHex(parts[3], 4);
    final d5 = _parseHex(parts[4], 12);

    return <int>[
      d1[3],
      d1[2],
      d1[1],
      d1[0],
      d2[1],
      d2[0],
      d3[1],
      d3[0],
      d4[0],
      d4[1],
      ...d5,
    ];
  }

  List<int> toBytes() => encode(str);

  static String? decodeMediaType(AsfGuid mediaType) {
    switch (mediaType.str) {
      case 'F8699E40-5B4D-11CF-A8FD-00805F5C442B':
        return 'audio';
      case 'BC19EFC0-5B4D-11CF-A8FD-00805F5C442B':
        return 'video';
      case '59DACFC0-59E6-11D0-A3AC-00A0C90348F6':
        return 'command';
      case '35907DE0-E415-11CF-A917-00805F5C442B':
        return 'degradable-jpeg';
      case '91BD222C-F21C-497A-8B6D-5AA86BFC0185':
        return 'file-transfer';
      case '3AFB65E2-47EF-40F2-AC2C-70A90D71D343':
        return 'binary';
      default:
        return null;
    }
  }

  bool equals(AsfGuid other) => str == other.str;

  @override
  bool operator ==(Object other) => other is AsfGuid && other.str == str;

  @override
  int get hashCode => str.hashCode;

  @override
  String toString() => str;

  static String _hexByte(int value) =>
      value.toRadixString(16).padLeft(2, '0').toUpperCase();

  static List<int> _parseHex(String value, int expectedLength) {
    if (value.length != expectedLength) {
      throw ArgumentError(
        'Invalid GUID part length: expected $expectedLength, got ${value.length}',
      );
    }

    final out = <int>[];
    for (var i = 0; i < value.length; i += 2) {
      out.add(int.parse(value.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}
