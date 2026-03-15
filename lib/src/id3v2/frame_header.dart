library;

import 'dart:convert';

import 'package:metadata_audio/src/id3v2/id3v2_token.dart';

typedef WarningCollector = void Function(String warning);

class FrameStatusFlags {

  const FrameStatusFlags({
    required this.tagAlterPreservation,
    required this.fileAlterPreservation,
    required this.readOnly,
  });
  final bool tagAlterPreservation;
  final bool fileAlterPreservation;
  final bool readOnly;
}

class FrameFormatFlags {

  const FrameFormatFlags({
    required this.groupingIdentity,
    required this.compression,
    required this.encryption,
    required this.unsynchronisation,
    required this.dataLengthIndicator,
  });
  final bool groupingIdentity;
  final bool compression;
  final bool encryption;
  final bool unsynchronisation;
  final bool dataLengthIndicator;
}

class FrameFlags {

  const FrameFlags({required this.status, required this.format});
  final FrameStatusFlags status;
  final FrameFormatFlags format;
}

class FrameHeader {

  const FrameHeader({required this.id, required this.length, this.flags});
  final String id;
  final int length;
  final FrameFlags? flags;

  bool get isPadding => id.trim().isEmpty || id.codeUnits.every((c) => c == 0);

  static int getFrameHeaderLength(Id3v2MajorVersion majorVersion) {
    switch (majorVersion) {
      case 2:
        return 6;
      case 3:
      case 4:
        return 10;
      default:
        throw Id3v2ContentError(
          'Unexpected ID3v2 major version: $majorVersion',
        );
    }
  }

  static FrameHeader parse(
    List<int> bytes,
    Id3v2MajorVersion majorVersion, {
    WarningCollector? warningCollector,
  }) {
    switch (majorVersion) {
      case 2:
        return _parseV22(bytes, warningCollector);
      case 3:
      case 4:
        return _parseV23V24(bytes, majorVersion, warningCollector);
      default:
        throw Id3v2ContentError(
          'Unexpected ID3v2 major version: $majorVersion',
        );
    }
  }

  static FrameHeader _parseV22(
    List<int> bytes,
    WarningCollector? warningCollector,
  ) {
    if (bytes.length < 6) {
      throw const Id3v2ContentError('ID3v2.2 frame header must be 6 bytes');
    }

    final id = ascii.decode(bytes.sublist(0, 3), allowInvalid: true);
    final length = ID3v2Token.uint24Be(bytes, 3);

    if (!RegExp(r'^[A-Z0-9]{3}$').hasMatch(id)) {
      warningCollector?.call('Invalid ID3v2.2 frame header ID: $id');
    }

    return FrameHeader(id: id, length: length);
  }

  static FrameHeader _parseV23V24(
    List<int> bytes,
    Id3v2MajorVersion majorVersion,
    WarningCollector? warningCollector,
  ) {
    if (bytes.length < 10) {
      throw Id3v2ContentError(
        'ID3v2.$majorVersion frame header must be 10 bytes',
      );
    }

    final id = ascii.decode(bytes.sublist(0, 4), allowInvalid: true);
    final length = majorVersion == 4
        ? ID3v2Token.uint32Synchsafe(bytes, 4)
        : ID3v2Token.uint32Be(bytes, 4);

    if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(id)) {
      warningCollector?.call(
        'Invalid ID3v2.$majorVersion frame header ID: $id',
      );
    }

    final flags = _readFrameFlags(bytes[8], bytes[9]);
    return FrameHeader(id: id, length: length, flags: flags);
  }

  static FrameFlags _readFrameFlags(int statusByte, int formatByte) => FrameFlags(
      status: FrameStatusFlags(
        tagAlterPreservation: _bit(statusByte, 6),
        fileAlterPreservation: _bit(statusByte, 5),
        readOnly: _bit(statusByte, 4),
      ),
      format: FrameFormatFlags(
        groupingIdentity: _bit(formatByte, 7),
        compression: _bit(formatByte, 3),
        encryption: _bit(formatByte, 2),
        unsynchronisation: _bit(formatByte, 1),
        dataLengthIndicator: _bit(formatByte, 0),
      ),
    );

  static bool _bit(int value, int bitIndexFromLsb) =>
      (value & (1 << bitIndexFromLsb)) != 0;
}
