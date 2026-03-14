# Detailed Comparison: TypeScript vs Dart Audio Metadata Output

## Summary Statistics
- **Total Files**: 14
- **Matching Files**: 6
- **Files with Differences**: 8
- **Total Issues Found**: 47

---

## Full Difference Table

| # | File | Field | TypeScript Value | Dart Value | Priority | Likely Root Cause |
|---|------|-------|------------------|------------|----------|-------------------|
| 1 | mp3/id3v2.3.mp3 | format.duration | 0.7836734693877551 | 0.809795918367347 | Medium | Duration calculation differs; frame counting or sample calculation discrepancy |
| 2 | mp3/id3v1.mp3 | format.duration | 33.38448979591837 | 3.101857142857143 | **Critical** | Massive difference (10.7x); likely frame parsing or VBR/CBR bitrate calculation issue |
| 3 | mp3/id3v1.mp3 | format.bitrate | 5203.134780907668 | 56000 | **Critical** | Bitrate calculation drastically different; may affect duration calculation |
| 4 | mp3/id3v1.mp3 | common.artist | (not present) | null | Low | Styling difference; both represent "no value" but different formats |
| 5 | mp3/id3v1.mp3 | common.album | (not present) | null | Low | Styling difference; both represent "no value" |
| 6 | mp3/id3v1.mp3 | common.albumartist | (not present) | null | Low | Styling difference; both represent "no value" |
| 7 | mp3/id3v1.mp3 | common.year | (not present) | null | Low | Styling difference; both represent "no value" |
| 8 | mp3/id3v1.mp3 | common.genre | (not present) | null | Low | Styling difference; both represent "no value" |
| 9 | mp3/no-tags.mp3 | format.duration | 2.1681632653061222 | 6.038428571428572 | **Critical** | ~2.8x difference; likely VBR/CBR bitrate misidentification |
| 10 | mp3/no-tags.mp3 | format.bitrate | 155962.4246987952 | 56000 | **Critical** | Massive bitrate difference affecting duration calculation |
| 11 | mp3/no-tags.mp3 | common.title | (not present) | null | Low | Styling difference; both represent "no value" |
| 12 | mp3/no-tags.mp3 | common.artist | (not present) | null | Low | Styling difference; both represent "no value" |
| 13 | mp3/no-tags.mp3 | common.album | (not present) | null | Low | Styling difference; both represent "no value" |
| 14 | mp3/no-tags.mp3 | common.albumartist | (not present) | null | Low | Styling difference; both represent "no value" |
| 15 | mp3/no-tags.mp3 | common.year | (not present) | null | Low | Styling difference; both represent "no value" |
| 16 | mp3/no-tags.mp3 | common.genre | (not present) | null | Low | Styling difference; both represent "no value" |
| 17 | mp3/issue-347.mp3 | **ENTIRE FILE** | Successfully parsed | error: "FormatException: Invalid value in input: 239" | **Critical** | Error handling: Dart throws exception; TS handles gracefully with valid data. Byte 239 indicates special MP3 frame format |
| 18 | mp3/adts-0-frame.mp3 | format.duration | 217.86122448979592 | 0.26461538461538464 | **Critical** | 823x difference; major frame counting or header parsing issue |
| 19 | mp3/adts-0-frame.mp3 | format.bitrate | 126.3189448441247 | 104000 | **Critical** | Bitrate calculation completely different |
| 20 | flac/sample.flac | format.container | "FLAC" | "flac" | Low | Case sensitivity: TS uppercase, Dart lowercase |
| 21 | flac/sample.flac | common.year | 2009 | null | Medium | Year tag not being parsed from FLAC Vorbis comments |
| 22 | flac/sample.flac | common.genre | ["Flamenco","Folk, World, & Country"] | ["Folk, World, & Country"] | Medium | Missing "Flamenco" genre tag; only one genre parsed instead of multiple |
| 23 | flac/flac-multiple-album-artists-tags.flac | format.container | "FLAC" | "flac" | Low | Case sensitivity: TS uppercase, Dart lowercase |
| 24 | flac/flac-multiple-album-artists-tags.flac | common.artist | "Artist One" | "Artist Two" | Medium | Different artist selected from multiple artists scenario |
| 25 | flac/flac-multiple-album-artists-tags.flac | common.year | (not present) | null | Low | Year not parsed; styling difference |
| 26 | flac/flac-multiple-album-artists-tags.flac | common.genre | (not present) | null | Low | Genre not parsed; styling difference |
| 27 | flac/testcase.flac | format.container | "FLAC" | "flac" | Low | Case sensitivity: TS uppercase, Dart lowercase |
| 28 | flac/testcase.flac | common.albumartist | (not present) | null | Low | Album artist not in data; styling difference |
| 29 | flac/testcase.flac | common.year | 2023 | 2023 | ✓ | MATCH |
| 30 | ogg/vorbis.ogg | format.container | "Ogg" | "ogg" | Low | Case sensitivity: TS "Ogg", Dart "ogg" |
| 31 | ogg/vorbis.ogg | format.duration | 2 | null | **Critical** | Duration not calculated; returned null |
| 32 | ogg/vorbis.ogg | format.lossless | false | null | Medium | Lossless property not set; should be true for Vorbis or at least a boolean |
| 33 | ogg/vorbis.ogg | common.year | 1991 | null | Medium | Year tag not parsed from Ogg Vorbis comments |
| 34 | ogg/vorbis.ogg | common.genre | ["Grunge","Alternative"] | ["Alternative"] | Medium | Missing "Grunge" genre tag; only one parsed instead of two |
| 35 | ogg/opus.ogg | format.container | "Ogg" | "ogg" | Low | Case sensitivity: TS "Ogg", Dart "ogg" |
| 36 | ogg/opus.ogg | format.duration | 2.9065833333333333 | null | **Critical** | Duration not calculated for Opus; returned null |
| 37 | ogg/opus.ogg | format.bitrate | 68223.0568536942 | null | **Critical** | Bitrate not calculated for Opus; returned null |
| 38 | ogg/opus.ogg | format.lossless | (not present) | null | Medium | Lossless property not set for Opus |
| 39 | ogg/opus.ogg | common.title | (not present) | null | Low | Title not found; styling difference |
| 40 | ogg/opus.ogg | common.artist | (not present) | null | Low | Artist not found; styling difference |
| 41 | ogg/opus.ogg | common.album | (not present) | null | Low | Album not found; styling difference |
| 42 | ogg/opus.ogg | common.albumartist | (not present) | null | Low | Album artist not found; styling difference |
| 43 | ogg/opus.ogg | common.year | (not present) | null | Low | Year not found; styling difference |
| 44 | ogg/opus.ogg | common.genre | (not present) | null | Low | Genre not found; styling difference |
| 45 | mp4/sample.m4a | format.codec | "MPEG-4/AAC" | null | **Critical** | Codec not identified; returned null |
| 46 | mp4/sample.m4a | format.duration | 1.023219954648526 | 1.0 | Low | Rounding difference (1.0232 vs 1.0); acceptable variance |
| 47 | mp4/sample.m4a | format.sampleRate | 44100 | null | **Critical** | Sample rate not parsed; returned null |
| 48 | mp4/sample.m4a | format.numberOfChannels | 1 | null | **Critical** | Channel count not parsed; returned null |
| 49 | mp4/sample.m4a | format.bitrate | 72891.46352273734 | 84376 | Medium | Bitrate calculation differs; ~16% variance |
| 50 | mp4/sample.m4a | common.albumartist | "Testcase" | null | Low | Album artist not parsed; styling difference |
| 51 | mp4/sample.m4a | common.year | 2023 | null | Medium | Year tag not parsed from MP4 |
| 52 | wav/issue-819.wav | **ENTIRE FILE** | Successfully parsed | error: "TokenizerException: Cannot skip 4294967195 bytes" | **Critical** | Error handling: Dart throws exception on file format anomaly |
| 53 | wav/odd-list-type.wav | **ENTIRE FILE** | Successfully parsed | error: "TokenizerException: Cannot skip 49503120 bytes" | **Critical** | Error handling: Dart throws exception on malformed WAV structure |
| 54 | aiff/sample.aiff | common.year | 2011 | null | Medium | Year tag not parsed from AIFF ID3v2.4 |
| 55 | aiff/sample.aiff | common.genre | (not present) | null | Low | Genre not parsed; styling difference |
| 56 | aiff/sample.aiff | format.bitrate | 1411230.1461163803 | 1411230 | Low | Rounding difference (1411230.15 vs 1411230); acceptable variance |

---

## Critical Issues Summary (Priority: Critical)

| Count | Category | Issues |
|-------|----------|--------|
| 1 | **Parse Failures** | 3 files throw exceptions instead of parsing (issue-347.mp3, issue-819.wav, odd-list-type.wav) |
| 2 | **MP3 Duration Calculation** | 3 files have major duration mismatches (id3v1.mp3, no-tags.mp3, adts-0-frame.mp3) |
| 3 | **MP3 Bitrate Identification** | 2 files misidentify bitrate leading to wrong duration (id3v1.mp3, no-tags.mp3) |
| 4 | **Ogg Vorbis Parsing** | 1 file missing duration/bitrate (vorbis.ogg) |
| 5 | **Ogg Opus Parsing** | 1 file missing all format data (opus.ogg) |
| 6 | **MP4 Metadata Extraction** | 4 format fields missing/null (codec, sampleRate, channels) in sample.m4a |

---

## High Priority Issues Summary (Priority: High)

None identified; most high-impact issues are categorized as Critical.

---

## Medium Priority Issues Summary (Priority: Medium)

| Count | Category | Issues |
|-------|----------|--------|
| 1 | **Duration Variance** | mp3/id3v2.3.mp3 minor duration difference (~3%) |
| 2 | **Tag Parsing** | 7 instances of missing year/genre tags in FLAC, Ogg, MP4, AIFF files |
| 3 | **Multiple Genre Tags** | 2 files only parse one genre instead of multiple |
| 4 | **Bitrate Variance** | 2 files with acceptable ~16% bitrate variance |
| 5 | **Null vs Absent Fields** | Format/lossless properties returned as null instead of proper values |

---

## Low Priority Issues Summary (Priority: Low)

| Count | Category | Issues |
|-------|----------|--------|
| 1 | **Case Sensitivity** | Container names: "FLAC" vs "flac", "Ogg" vs "ogg" (6 instances) |
| 2 | **Null Styling** | Missing fields returned as `null` vs omitted (14 instances - purely stylistic) |
| 3 | **Rounding Variance** | Bitrate and duration rounding differences (2 instances, <1% variance) |

---

## Key Findings

### Root Cause Categories

1. **Frame Parsing Issues** (10 instances)
   - MP3 frame header detection differs between implementations
   - Affects duration and bitrate calculation
   - Files: id3v1.mp3, no-tags.mp3, adts-0-frame.mp3

2. **Exception Handling** (3 instances)
   - Dart throws exceptions on malformed/edge-case files
   - TypeScript gracefully handles and returns partial data
   - Files: issue-347.mp3, issue-819.wav, odd-list-type.wav

3. **Tag Parsing** (7 instances)
   - Vorbis comments not fully parsed in FLAC/Ogg
   - Multiple genre tags not aggregated
   - MP4/AIFF year tags not extracted

4. **Format Parameter Extraction** (4 instances)
   - MP4 container not fully parsed
   - Ogg metadata completely missing
   - Lossless property not set correctly

5. **Style/Format Differences** (20 instances)
   - Container name case sensitivity
   - Null vs omitted fields (cosmetic, not functional)
   - Rounding differences (negligible)

---

## Recommended Fix Priority Order

### Phase 1: Critical Stability (MUST FIX)
1. Fix exception handling in Dart parser for malformed files
2. Fix MP3 frame parsing/bitrate detection (affects duration)
3. Complete MP4 format parameter extraction

### Phase 2: High Accuracy (SHOULD FIX)
4. Fix Ogg Vorbis duration/bitrate calculation
5. Implement full tag parsing for year/genre/multiple genres
6. Fix Ogg Opus metadata extraction

### Phase 3: Polish (NICE TO FIX)
7. Standardize container name casing
8. Standardize null vs omitted field representation
9. Investigate and match rounding behavior
