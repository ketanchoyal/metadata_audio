library;

// ignore_for_file: public_member_api_docs

import 'package:audio_metadata/src/ebml/types.dart';

/// Matroska/WebM EBML document type definition.
///
/// Derived from:
/// - https://github.com/tungol/EBML/blob/master/doctypes/matroska.dtd
/// - https://www.matroska.org/technical/specs/index.html
const EbmlElementType matroskaDtd = EbmlElementType(
  name: 'dtd',
  container: <int, EbmlElementType>{
    0x1A45DFA3: EbmlElementType(
      name: 'ebml',
      container: <int, EbmlElementType>{
        0x4286: EbmlElementType(name: 'ebmlVersion', value: EbmlDataType.uint),
        0x42F7: EbmlElementType(
          name: 'ebmlReadVersion',
          value: EbmlDataType.uint,
        ),
        0x42F2: EbmlElementType(
          name: 'ebmlMaxIDWidth',
          value: EbmlDataType.uint,
        ),
        0x42F3: EbmlElementType(
          name: 'ebmlMaxSizeWidth',
          value: EbmlDataType.uint,
        ),
        0x4282: EbmlElementType(name: 'docType', value: EbmlDataType.string),
        0x4287: EbmlElementType(
          name: 'docTypeVersion',
          value: EbmlDataType.uint,
        ),
        0x4285: EbmlElementType(
          name: 'docTypeReadVersion',
          value: EbmlDataType.uint,
        ),
      },
    ),
    0x18538067: EbmlElementType(
      name: 'segment',
      container: <int, EbmlElementType>{
        0x114D9B74: EbmlElementType(
          name: 'seekHead',
          container: <int, EbmlElementType>{
            0x4DBB: EbmlElementType(
              name: 'seek',
              multiple: true,
              container: <int, EbmlElementType>{
                0x53AB: EbmlElementType(name: 'id', value: EbmlDataType.binary),
                0x53AC: EbmlElementType(
                  name: 'position',
                  value: EbmlDataType.uint,
                ),
              },
            ),
          },
        ),
        0x1549A966: EbmlElementType(
          name: 'info',
          container: <int, EbmlElementType>{
            0x73A4: EbmlElementType(name: 'uid', value: EbmlDataType.uid),
            0x7384: EbmlElementType(
              name: 'filename',
              value: EbmlDataType.string,
            ),
            0x3CB923: EbmlElementType(name: 'prevUID', value: EbmlDataType.uid),
            0x3C83AB: EbmlElementType(
              name: 'prevFilename',
              value: EbmlDataType.string,
            ),
            0x3EB923: EbmlElementType(name: 'nextUID', value: EbmlDataType.uid),
            0x3E83BB: EbmlElementType(
              name: 'nextFilename',
              value: EbmlDataType.string,
            ),
            0x2AD7B1: EbmlElementType(
              name: 'timecodeScale',
              value: EbmlDataType.uint,
            ),
            0x4489: EbmlElementType(
              name: 'duration',
              value: EbmlDataType.float,
            ),
            0x4461: EbmlElementType(name: 'dateUTC', value: EbmlDataType.uint),
            0x7BA9: EbmlElementType(name: 'title', value: EbmlDataType.string),
            0x4D80: EbmlElementType(
              name: 'muxingApp',
              value: EbmlDataType.string,
            ),
            0x5741: EbmlElementType(
              name: 'writingApp',
              value: EbmlDataType.string,
            ),
          },
        ),
        0x1F43B675: EbmlElementType(
          name: 'cluster',
          multiple: true,
          container: <int, EbmlElementType>{
            0xE7: EbmlElementType(name: 'timecode', value: EbmlDataType.uid),
            0x58D7: EbmlElementType(name: 'silentTracks', multiple: true),
            0xA7: EbmlElementType(name: 'position', value: EbmlDataType.uid),
            0xAB: EbmlElementType(name: 'prevSize', value: EbmlDataType.uid),
            0xA0: EbmlElementType(name: 'blockGroup'),
            0xA3: EbmlElementType(name: 'simpleBlock'),
          },
        ),
        0x1654AE6B: EbmlElementType(
          name: 'tracks',
          container: <int, EbmlElementType>{
            0xAE: EbmlElementType(
              name: 'entries',
              multiple: true,
              container: <int, EbmlElementType>{
                0xD7: EbmlElementType(
                  name: 'trackNumber',
                  value: EbmlDataType.uint,
                ),
                0x73C5: EbmlElementType(name: 'uid', value: EbmlDataType.uid),
                0x83: EbmlElementType(
                  name: 'trackType',
                  value: EbmlDataType.uint,
                ),
                0xB9: EbmlElementType(
                  name: 'flagEnabled',
                  value: EbmlDataType.bool,
                ),
                0x88: EbmlElementType(
                  name: 'flagDefault',
                  value: EbmlDataType.bool,
                ),
                0x55AA: EbmlElementType(
                  name: 'flagForced',
                  value: EbmlDataType.bool,
                ),
                0x9C: EbmlElementType(
                  name: 'flagLacing',
                  value: EbmlDataType.bool,
                ),
                0x6DE7: EbmlElementType(
                  name: 'minCache',
                  value: EbmlDataType.uint,
                ),
                0x6DE8: EbmlElementType(
                  name: 'maxCache',
                  value: EbmlDataType.uint,
                ),
                0x23E383: EbmlElementType(
                  name: 'defaultDuration',
                  value: EbmlDataType.uint,
                ),
                0x23314F: EbmlElementType(
                  name: 'timecodeScale',
                  value: EbmlDataType.float,
                ),
                0x536E: EbmlElementType(
                  name: 'name',
                  value: EbmlDataType.string,
                ),
                0x22B59C: EbmlElementType(
                  name: 'language',
                  value: EbmlDataType.string,
                ),
                0x86: EbmlElementType(
                  name: 'codecID',
                  value: EbmlDataType.string,
                ),
                0x63A2: EbmlElementType(
                  name: 'codecPrivate',
                  value: EbmlDataType.binary,
                ),
                0x258688: EbmlElementType(
                  name: 'codecName',
                  value: EbmlDataType.string,
                ),
                0x3A9697: EbmlElementType(
                  name: 'codecSettings',
                  value: EbmlDataType.string,
                ),
                0x3B4040: EbmlElementType(
                  name: 'codecInfoUrl',
                  value: EbmlDataType.string,
                ),
                0x26B240: EbmlElementType(
                  name: 'codecDownloadUrl',
                  value: EbmlDataType.string,
                ),
                0xAA: EbmlElementType(
                  name: 'codecDecodeAll',
                  value: EbmlDataType.bool,
                ),
                0x6FAB: EbmlElementType(
                  name: 'trackOverlay',
                  value: EbmlDataType.uint,
                ),
                0xE0: EbmlElementType(
                  name: 'video',
                  container: <int, EbmlElementType>{
                    0x9A: EbmlElementType(
                      name: 'flagInterlaced',
                      value: EbmlDataType.bool,
                    ),
                    0x53B8: EbmlElementType(
                      name: 'stereoMode',
                      value: EbmlDataType.uint,
                    ),
                    0xB0: EbmlElementType(
                      name: 'pixelWidth',
                      value: EbmlDataType.uint,
                    ),
                    0xBA: EbmlElementType(
                      name: 'pixelHeight',
                      value: EbmlDataType.uint,
                    ),
                    0x54B0: EbmlElementType(
                      name: 'displayWidth',
                      value: EbmlDataType.uint,
                    ),
                    0x54BA: EbmlElementType(
                      name: 'displayHeight',
                      value: EbmlDataType.uint,
                    ),
                    0x54B2: EbmlElementType(
                      name: 'displayUnit',
                      value: EbmlDataType.uint,
                    ),
                    0x54B3: EbmlElementType(
                      name: 'aspectRatioType',
                      value: EbmlDataType.uint,
                    ),
                    0x2EB524: EbmlElementType(
                      name: 'colourSpace',
                      value: EbmlDataType.binary,
                    ),
                    0x2FB523: EbmlElementType(
                      name: 'gammaValue',
                      value: EbmlDataType.float,
                    ),
                  },
                ),
                0xE1: EbmlElementType(
                  name: 'audio',
                  container: <int, EbmlElementType>{
                    0xB5: EbmlElementType(
                      name: 'samplingFrequency',
                      value: EbmlDataType.float,
                    ),
                    0x78B5: EbmlElementType(
                      name: 'outputSamplingFrequency',
                      value: EbmlDataType.float,
                    ),
                    0x9F: EbmlElementType(
                      name: 'channels',
                      value: EbmlDataType.uint,
                    ),
                    0x94: EbmlElementType(
                      name: 'channels',
                      value: EbmlDataType.uint,
                    ),
                    0x7D7B: EbmlElementType(
                      name: 'channelPositions',
                      value: EbmlDataType.binary,
                    ),
                    0x6264: EbmlElementType(
                      name: 'bitDepth',
                      value: EbmlDataType.uint,
                    ),
                  },
                ),
              },
            ),
          },
        ),
        0x1C53BB6B: EbmlElementType(
          name: 'cues',
          container: <int, EbmlElementType>{
            0xBB: EbmlElementType(
              name: 'cuePoint',
              multiple: true,
              container: <int, EbmlElementType>{
                0xB3: EbmlElementType(name: 'cueTime', value: EbmlDataType.uid),
                0xB7: EbmlElementType(
                  name: 'positions',
                  container: <int, EbmlElementType>{
                    0xF7: EbmlElementType(
                      name: 'track',
                      value: EbmlDataType.uint,
                    ),
                    0xF1: EbmlElementType(
                      name: 'clusterPosition',
                      value: EbmlDataType.uint,
                    ),
                    0x5378: EbmlElementType(
                      name: 'blockNumber',
                      value: EbmlDataType.uint,
                    ),
                    0xEA: EbmlElementType(
                      name: 'codecState',
                      value: EbmlDataType.uint,
                    ),
                    0xF0: EbmlElementType(
                      name: 'relativePosition',
                      value: EbmlDataType.uint,
                    ),
                  },
                ),
              },
            ),
          },
        ),
        0x1941A469: EbmlElementType(
          name: 'attachments',
          container: <int, EbmlElementType>{
            0x61A7: EbmlElementType(
              name: 'attachedFiles',
              multiple: true,
              container: <int, EbmlElementType>{
                0x467E: EbmlElementType(
                  name: 'description',
                  value: EbmlDataType.string,
                ),
                0x466E: EbmlElementType(
                  name: 'name',
                  value: EbmlDataType.string,
                ),
                0x4660: EbmlElementType(
                  name: 'mimeType',
                  value: EbmlDataType.string,
                ),
                0x465C: EbmlElementType(
                  name: 'data',
                  value: EbmlDataType.binary,
                ),
                0x46AE: EbmlElementType(name: 'uid', value: EbmlDataType.uid),
              },
            ),
          },
        ),
        0x1043A770: EbmlElementType(
          name: 'chapters',
          container: <int, EbmlElementType>{
            0x45B9: EbmlElementType(
              name: 'editionEntry',
              multiple: true,
              container: <int, EbmlElementType>{
                0xB6: EbmlElementType(
                  name: 'chapterAtom',
                  multiple: true,
                  container: <int, EbmlElementType>{
                    0x73C4: EbmlElementType(
                      name: 'uid',
                      value: EbmlDataType.uid,
                    ),
                    0x91: EbmlElementType(
                      name: 'timeStart',
                      value: EbmlDataType.uint,
                    ),
                    0x92: EbmlElementType(
                      name: 'timeEnd',
                      value: EbmlDataType.uid,
                    ),
                    0x98: EbmlElementType(
                      name: 'hidden',
                      value: EbmlDataType.bool,
                    ),
                    0x4598: EbmlElementType(
                      name: 'enabled',
                      value: EbmlDataType.bool,
                    ),
                    0x8F: EbmlElementType(
                      name: 'track',
                      container: <int, EbmlElementType>{
                        0x89: EbmlElementType(
                          name: 'trackNumber',
                          value: EbmlDataType.uid,
                        ),
                        0x80: EbmlElementType(
                          name: 'display',
                          container: <int, EbmlElementType>{
                            0x85: EbmlElementType(
                              name: 'string',
                              value: EbmlDataType.string,
                            ),
                            0x437C: EbmlElementType(
                              name: 'language',
                              value: EbmlDataType.string,
                            ),
                            0x437E: EbmlElementType(
                              name: 'country',
                              value: EbmlDataType.string,
                            ),
                          },
                        ),
                      },
                    ),
                  },
                ),
              },
            ),
          },
        ),
        0x1254C367: EbmlElementType(
          name: 'tags',
          container: <int, EbmlElementType>{
            0x7373: EbmlElementType(
              name: 'tag',
              multiple: true,
              container: <int, EbmlElementType>{
                0x63C0: EbmlElementType(
                  name: 'target',
                  container: <int, EbmlElementType>{
                    0x63C5: EbmlElementType(
                      name: 'tagTrackUID',
                      value: EbmlDataType.uid,
                    ),
                    0x63C4: EbmlElementType(
                      name: 'tagChapterUID',
                      value: EbmlDataType.uint,
                    ),
                    0x63C6: EbmlElementType(
                      name: 'tagAttachmentUID',
                      value: EbmlDataType.uid,
                    ),
                    0x63CA: EbmlElementType(
                      name: 'targetType',
                      value: EbmlDataType.string,
                    ),
                    0x68CA: EbmlElementType(
                      name: 'targetTypeValue',
                      value: EbmlDataType.uint,
                    ),
                    0x63C9: EbmlElementType(
                      name: 'tagEditionUID',
                      value: EbmlDataType.uid,
                    ),
                  },
                ),
                0x67C8: EbmlElementType(
                  name: 'simpleTags',
                  multiple: true,
                  container: <int, EbmlElementType>{
                    0x45A3: EbmlElementType(
                      name: 'name',
                      value: EbmlDataType.string,
                    ),
                    0x4487: EbmlElementType(
                      name: 'string',
                      value: EbmlDataType.string,
                    ),
                    0x4485: EbmlElementType(
                      name: 'binary',
                      value: EbmlDataType.binary,
                    ),
                    0x447A: EbmlElementType(
                      name: 'language',
                      value: EbmlDataType.string,
                    ),
                    0x447B: EbmlElementType(
                      name: 'languageIETF',
                      value: EbmlDataType.string,
                    ),
                    0x4484: EbmlElementType(
                      name: 'default',
                      value: EbmlDataType.bool,
                    ),
                  },
                ),
              },
            ),
          },
        ),
      },
    ),
  },
);
