# Dart vs TypeScript Metadata Comparison

## Summary of Differences

This document summarizes the discrepancies found between the Dart `audio_metadata` and TypeScript `music-metadata` implementations.

---

## Format Differences

| Field          | TypeScript          | Dart                 | Priority |
| -------------- | ------------------- | -------------------- | -------- |
| `container`    | `"MPEG"`            | `"mp3"`              | Low      |
| `codec`        | `"MPEG 1 Layer 3"`  | `"MPEG 1.0 Layer 3"` | Low      |
| `duration`     | Calculated for all  | `null` for many      | **High**  |
| `bitrate`      | Accurate VBR        | Fixed `32000`         | **High**  |

---

## Metadata Differences by File

### mp3/id3v2.3.mp3

| Field          | TypeScript                         | Dart        | Issue                    |
| -------------- | ----------------------------------- | ----------- | ----------------------- |
| `duration`     | 0.784s                              | 0.810s      | Minor calculation diff  |
| `albumartist`  | `"Soundtrack"`                      | `null`      | **TPE2 frame not mapped** |
| `disk.of`      | `1`                                 | `null`      | **TPOS frame not mapped** |

### mp3/id3v1.mp3

| Field       | TypeScript                   | Dart        | Issue                    |
| ----------- | ---------------------------- | ----------- | ----------------------- |
| `duration`  | 33.384s                       | `null`      | **Duration not calculated** |
| `bitrate`    | 5203 (calculated)             | 32000       | **Bitrate not calculated** |
| `artist`     | `null`                        | `null`      | OK                      |
| `album`      | `null`                        | `null`      | OK                      |

### mp3/no-tags.mp3

| Field      | TypeScript   | Dart    | Issue                    |
| ---------- | ------------ | ------- | ----------------------- |
| `duration` | 2.168s       | `null`  | **Duration not calculated** |
| `bitrate`   | 155962       | 32000   | **Bitrate not calculated** |

---

## Root Causes

### 1. Duration Calculation Missing
**Location**: `lib/src/mpeg/mpeg_parser.dart`
**Issue**: Duration is only calculated when `options.duration` is enabled AND file has enough frames
**Fix**: Enable duration calculation by default or ensure frame counting works correctly

### 2. Bitrate Calculation Incorrect
**Location**: `lib/src/mpeg/mpeg_parser.dart`
**Issue**: Returns fixed bitrate instead of calculating from frames
**Fix**: Calculate average bitrate from frame sizes

### 3. TPE2 Frame Not Mapped
**Location**: `lib/src/id3v2/id3v2_tag_map.dart`
**Issue**: `TPE2` (Band/Orchestra/Accompaniment) not mapped to `albumartist`
**Fix**: Add mapping: `registerTagMapping('TPE2', 'albumartist');`

### 4. TPOS Frame Not Mapped
**Location**: `lib/src/id3v2/id3v2_tag_map.dart`
**Issue**: `TPOS` (Part of a set) not mapped to `disk.of`
**Fix**: Add mapping: `registerTagMapping('TPOS', 'disk.of');`

### 5. Container/Codec Naming
**Location**: `lib/src/mpeg/mpeg_parser.dart`
**Issue**: Uses lowercase `"mp3"` instead of `"MPEG"`
**Fix**: Update container to `"MPEG"` and codec format to match upstream

---

## Test Command

```bash
# Run comparison
cd /Users/ketanchoyal/CascadeProjects/audio-metadata-dart
dart run tool/compare_metadata.dart > /tmp/dart_output.json
cd comparison && npm run test:ts > /tmp/ts_output.json
diff -u /tmp/ts_output.json /tmp/dart_output.json
```

---

## Priority Order for Fixes

1. **High**: Duration calculation (affects all MP3 files)
2. **High**: Bitrate calculation (affects all MP3 files)
3. **Medium**: TPE2 → albumartist mapping
4. **Medium**: TPOS → disk.of mapping
5. **Low**: Container/codec naming standardization
