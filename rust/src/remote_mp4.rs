use std::collections::HashMap;
use std::time::{Duration, Instant};

use reqwest::blocking::Client;
use reqwest::header::{ACCEPT_RANGES, CONTENT_LENGTH, RANGE, USER_AGENT};

use crate::api::{FfiAudioMetadata, FfiChapter, FfiCommonTags, FfiFormat};

#[derive(Clone, Debug, Default)]
struct SampleDescription {
    data_format: String,
    number_of_channels: Option<u32>,
    bits_per_sample: Option<u32>,
    sample_rate: Option<u32>,
}

#[derive(Clone, Debug)]
struct SttsEntry {
    count: u32,
    duration: u32,
}

#[derive(Clone, Debug)]
struct StscEntry {
    first_chunk: u32,
    samples_per_chunk: u32,
}

#[derive(Clone, Debug, Default)]
struct TrackDescription {
    track_id: u32,
    handler_type: Option<String>,
    time_scale: Option<u32>,
    duration_units: Option<u64>,
    sample_size: Option<u32>,
    sample_descriptions: Vec<SampleDescription>,
    time_to_sample_table: Vec<SttsEntry>,
    sample_to_chunk_table: Vec<StscEntry>,
    sample_size_table: Vec<u32>,
    chunk_offset_table: Vec<u64>,
    chapter_track_ids: Vec<u32>,
}

impl TrackDescription {
    fn is_audio(&self) -> bool {
        matches!(self.handler_type.as_deref(), Some("soun") | Some("audi"))
    }

    fn is_video(&self) -> bool {
        matches!(self.handler_type.as_deref(), Some("vide"))
    }
}

#[derive(Clone, Debug)]
struct ChplChapter {
    timestamp: u64,
    title: String,
}

#[derive(Clone, Debug)]
struct ChapterSampleRequest {
    index: usize,
    offset: u64,
    size: usize,
}

#[derive(Clone, Debug)]
struct BatchedRange {
    start: u64,
    end: u64,
    requests: Vec<ChapterSampleRequest>,
}

#[derive(Clone, Debug)]
struct AtomHeader {
    length: u64,
    header_length: usize,
    name: String,
}

pub(crate) fn parse_mp4_from_url(
    url: &str,
    include_chapters: bool,
    timeout: Option<Duration>,
    file_size_hint: Option<u64>,
) -> Result<FfiAudioMetadata, String> {
    let reader = HttpRangeReader::new(url, timeout, file_size_hint)?;
    let parser = RemoteMp4Parser::new(reader, include_chapters);
    parser.parse()
}

struct RemoteMp4Parser {
    reader: HttpRangeReader,
    include_chapters: bool,
    format: FfiFormat,
    tracks: HashMap<u32, TrackDescription>,
    chpl_chapters: Vec<ChplChapter>,
    mvhd_time_scale: Option<u32>,
    mvhd_duration: Option<u64>,
    warnings: Vec<String>,
}

impl RemoteMp4Parser {
    fn new(reader: HttpRangeReader, include_chapters: bool) -> Self {
        Self {
            reader,
            include_chapters,
            format: FfiFormat {
                container: "mp4".to_string(),
                tag_types: vec![],
                duration: None,
                bitrate: None,
                sample_rate: None,
                bits_per_sample: None,
                tool: None,
                codec: None,
                codec_profile: None,
                lossless: None,
                number_of_channels: None,
                number_of_samples: None,
                has_audio: None,
                has_video: None,
                track_gain: None,
                track_peak_level: None,
                album_gain: None,
                chapters: vec![],
            },
            tracks: HashMap::new(),
            chpl_chapters: vec![],
            mvhd_time_scale: None,
            mvhd_duration: None,
            warnings: vec![],
        }
    }

    fn parse(mut self) -> Result<FfiAudioMetadata, String> {
        self.parse_root_atoms()?;
        self.populate_format_from_tracks();

        if self.include_chapters {
            if !self.process_chpl_chapters()? {
                let _ = self.try_parse_chapters_from_track_references()?;
            }
        }

        Ok(FfiAudioMetadata {
            format: self.format,
            common: FfiCommonTags::default(),
            native: vec![],
            pictures: vec![],
            warnings: self.warnings,
        })
    }

    fn parse_root_atoms(&mut self) -> Result<(), String> {
        let mut offset = 0u64;
        let file_len = self.reader.size;

        while offset + 8 <= file_len {
            let header = self.reader.read_atom_header(offset, file_len - offset)?;
            if header.length == 0 {
                break;
            }

            let payload_offset = offset + header.header_length as u64;
            let payload_length = header
                .length
                .checked_sub(header.header_length as u64)
                .ok_or_else(|| format!("invalid atom payload length for {}", header.name))?;

            match header.name.as_str() {
                "ftyp" => {
                    let payload = self.reader.read_exact_at(payload_offset, payload_length as usize)?;
                    self.parse_ftyp(&payload);
                }
                "moov" => {
                    let payload = self.reader.read_exact_at(payload_offset, payload_length as usize)?;
                    self.parse_moov(&payload)?;
                }
                _ => {}
            }

            if header.length == u64::MAX || header.length == 0 {
                break;
            }
            offset = offset.saturating_add(header.length);
        }

        Ok(())
    }

    fn parse_ftyp(&mut self, payload: &[u8]) {
        let mut brands = Vec::new();
        let mut offset = 0usize;
        while offset + 4 <= payload.len() {
            let brand = String::from_utf8_lossy(&payload[offset..offset + 4]).to_string();
            let normalized: String = brand.chars().filter(|ch| ch.is_ascii_alphanumeric()).collect();
            if !normalized.is_empty() && !brands.contains(&normalized) {
                brands.push(normalized);
            }
            offset += 4;
        }

        if !brands.is_empty() {
            self.format.container = brands.join("/");
        }
    }

    fn parse_moov(&mut self, payload: &[u8]) -> Result<(), String> {
        let mut offset = 0usize;
        while offset + 8 <= payload.len() {
            let header = parse_atom_header_from_slice(payload, offset, payload.len() - offset)?;
            let payload_start = offset + header.header_length;
            let payload_end = offset + header.length as usize;
            if payload_end > payload.len() || payload_end < payload_start {
                return Err(format!("invalid moov child atom {} bounds", header.name));
            }
            let child_payload = &payload[payload_start..payload_end];

            match header.name.as_str() {
                "mvhd" => self.parse_mvhd(child_payload)?,
                "trak" => self.parse_trak(child_payload)?,
                "udta" => self.parse_udta(child_payload)?,
                _ => {}
            }

            offset = payload_end;
        }

        Ok(())
    }

    fn parse_udta(&mut self, payload: &[u8]) -> Result<(), String> {
        let mut offset = 0usize;
        while offset + 8 <= payload.len() {
            let header = parse_atom_header_from_slice(payload, offset, payload.len() - offset)?;
            let payload_start = offset + header.header_length;
            let payload_end = offset + header.length as usize;
            if payload_end > payload.len() || payload_end < payload_start {
                return Err(format!("invalid udta child atom {} bounds", header.name));
            }

            if header.name == "chpl" {
                self.parse_chpl(&payload[payload_start..payload_end])?;
            }

            offset = payload_end;
        }
        Ok(())
    }

    fn parse_trak(&mut self, payload: &[u8]) -> Result<(), String> {
        let mut track = TrackDescription::default();
        self.parse_trak_container(payload, &mut track)?;
        if track.track_id != 0 {
            self.tracks.insert(track.track_id, track);
        }
        Ok(())
    }

    fn parse_trak_container(
        &mut self,
        payload: &[u8],
        track: &mut TrackDescription,
    ) -> Result<(), String> {
        let mut offset = 0usize;
        while offset + 8 <= payload.len() {
            let header = parse_atom_header_from_slice(payload, offset, payload.len() - offset)?;
            let payload_start = offset + header.header_length;
            let payload_end = offset + header.length as usize;
            if payload_end > payload.len() || payload_end < payload_start {
                return Err(format!("invalid track child atom {} bounds", header.name));
            }

            let child_payload = &payload[payload_start..payload_end];
            match header.name.as_str() {
                "tkhd" => self.parse_tkhd(child_payload, track)?,
                "mdhd" => self.parse_mdhd(child_payload, track)?,
                "hdlr" => self.parse_hdlr(child_payload, track)?,
                "stsd" => self.parse_stsd(child_payload, track)?,
                "stts" => self.parse_stts(child_payload, track)?,
                "stsc" => self.parse_stsc(child_payload, track)?,
                "stsz" => self.parse_stsz(child_payload, track)?,
                "stco" => self.parse_stco(child_payload, track)?,
                "co64" => self.parse_co64(child_payload, track)?,
                "chap" => self.parse_chap(child_payload, track)?,
                "mdia" | "minf" | "stbl" | "tref" => {
                    self.parse_trak_container(child_payload, track)?;
                }
                _ => {}
            }

            offset = payload_end;
        }
        Ok(())
    }

    fn parse_mvhd(&mut self, payload: &[u8]) -> Result<(), String> {
        ensure_len(payload, 24, "mvhd atom payload too short")?;
        let version = payload[0];
        if version == 1 {
            ensure_len(payload, 32, "mvhd version 1 payload too short")?;
            let time_scale = read_u32_be(payload, 20)?;
            let duration = read_u64_be(payload, 24)?;
            self.mvhd_time_scale = Some(time_scale);
            self.mvhd_duration = Some(duration);
        } else {
            let time_scale = read_u32_be(payload, 12)?;
            let duration = read_u32_be(payload, 16)? as u64;
            self.mvhd_time_scale = Some(time_scale);
            self.mvhd_duration = Some(duration);
        }

        if let (Some(time_scale), Some(duration)) = (self.mvhd_time_scale, self.mvhd_duration) {
            if time_scale > 0 {
                self.format.duration = Some(duration as f64 / time_scale as f64);
            }
        }

        Ok(())
    }

    fn parse_tkhd(&mut self, payload: &[u8], track: &mut TrackDescription) -> Result<(), String> {
        ensure_len(payload, 24, "tkhd atom payload too short")?;
        let version = payload[0];
        let track_id_offset = if version == 1 { 20 } else { 12 };
        track.track_id = read_u32_be(payload, track_id_offset)?;
        Ok(())
    }

    fn parse_mdhd(&mut self, payload: &[u8], track: &mut TrackDescription) -> Result<(), String> {
        ensure_len(payload, 24, "mdhd atom payload too short")?;
        let version = payload[0];
        if version == 1 {
            ensure_len(payload, 36, "mdhd version 1 payload too short")?;
            track.time_scale = Some(read_u32_be(payload, 20)?);
            track.duration_units = Some(read_u64_be(payload, 24)?);
        } else {
            track.time_scale = Some(read_u32_be(payload, 12)?);
            track.duration_units = Some(read_u32_be(payload, 16)? as u64);
        }
        Ok(())
    }

    fn parse_hdlr(&mut self, payload: &[u8], track: &mut TrackDescription) -> Result<(), String> {
        ensure_len(payload, 12, "hdlr atom payload too short")?;
        track.handler_type = Some(String::from_utf8_lossy(&payload[8..12]).to_string());
        Ok(())
    }

    fn parse_stsd(&mut self, payload: &[u8], track: &mut TrackDescription) -> Result<(), String> {
        ensure_len(payload, 8, "stsd atom payload too short")?;
        let entry_count = read_u32_be(payload, 4)? as usize;
        let mut offset = 8usize;

        for _ in 0..entry_count {
            ensure_len_at(payload, offset, 8, "stsd entry header out of bounds")?;
            let entry_size = read_u32_be(payload, offset)? as usize;
            if entry_size < 8 || offset + entry_size > payload.len() {
                return Err(format!("invalid stsd entry size: {entry_size}"));
            }

            let format = String::from_utf8_lossy(&payload[offset + 4..offset + 8]).to_string();
            let sample_entry_offset = offset + 8;
            let sample_entry_length = entry_size - 8;
            let (channels, bits_per_sample, sample_rate) = if sample_entry_length >= 28 {
                (
                    Some(read_u16_be(payload, sample_entry_offset + 16)? as u32),
                    Some(read_u16_be(payload, sample_entry_offset + 18)? as u32),
                    Some(read_u32_be(payload, sample_entry_offset + 24)? >> 16),
                )
            } else {
                (None, None, None)
            };

            track.sample_descriptions.push(SampleDescription {
                data_format: format,
                number_of_channels: channels,
                bits_per_sample,
                sample_rate,
            });

            offset += entry_size;
        }

        Ok(())
    }

    fn parse_stts(&mut self, payload: &[u8], track: &mut TrackDescription) -> Result<(), String> {
        ensure_len(payload, 8, "stts atom payload too short")?;
        let entry_count = read_u32_be(payload, 4)? as usize;
        let mut offset = 8usize;
        for _ in 0..entry_count {
            ensure_len_at(payload, offset, 8, "stts entry out of bounds")?;
            track.time_to_sample_table.push(SttsEntry {
                count: read_u32_be(payload, offset)?,
                duration: read_u32_be(payload, offset + 4)?,
            });
            offset += 8;
        }
        Ok(())
    }

    fn parse_stsc(&mut self, payload: &[u8], track: &mut TrackDescription) -> Result<(), String> {
        ensure_len(payload, 8, "stsc atom payload too short")?;
        let entry_count = read_u32_be(payload, 4)? as usize;
        let mut offset = 8usize;
        for _ in 0..entry_count {
            ensure_len_at(payload, offset, 12, "stsc entry out of bounds")?;
            track.sample_to_chunk_table.push(StscEntry {
                first_chunk: read_u32_be(payload, offset)?,
                samples_per_chunk: read_u32_be(payload, offset + 4)?,
            });
            offset += 12;
        }
        Ok(())
    }

    fn parse_stsz(&mut self, payload: &[u8], track: &mut TrackDescription) -> Result<(), String> {
        ensure_len(payload, 12, "stsz atom payload too short")?;
        let sample_size = read_u32_be(payload, 4)?;
        let entry_count = read_u32_be(payload, 8)? as usize;
        let mut offset = 12usize;
        track.sample_size = Some(sample_size);
        for _ in 0..entry_count {
            ensure_len_at(payload, offset, 4, "stsz entry out of bounds")?;
            track.sample_size_table.push(read_u32_be(payload, offset)?);
            offset += 4;
        }
        Ok(())
    }

    fn parse_stco(&mut self, payload: &[u8], track: &mut TrackDescription) -> Result<(), String> {
        ensure_len(payload, 8, "stco atom payload too short")?;
        let entry_count = read_u32_be(payload, 4)? as usize;
        let mut offset = 8usize;
        for _ in 0..entry_count {
            ensure_len_at(payload, offset, 4, "stco entry out of bounds")?;
            track.chunk_offset_table.push(read_u32_be(payload, offset)? as u64);
            offset += 4;
        }
        Ok(())
    }

    fn parse_co64(&mut self, payload: &[u8], track: &mut TrackDescription) -> Result<(), String> {
        ensure_len(payload, 8, "co64 atom payload too short")?;
        let entry_count = read_u32_be(payload, 4)? as usize;
        let mut offset = 8usize;
        for _ in 0..entry_count {
            ensure_len_at(payload, offset, 8, "co64 entry out of bounds")?;
            track.chunk_offset_table.push(read_u64_be(payload, offset)?);
            offset += 8;
        }
        Ok(())
    }

    fn parse_chap(&mut self, payload: &[u8], track: &mut TrackDescription) -> Result<(), String> {
        let mut offset = 0usize;
        while offset + 4 <= payload.len() {
            track.chapter_track_ids.push(read_u32_be(payload, offset)?);
            offset += 4;
        }
        Ok(())
    }

    fn parse_chpl(&mut self, payload: &[u8]) -> Result<(), String> {
        if !self.include_chapters {
            return Ok(());
        }

        ensure_len(payload, 9, "chpl atom too small")?;
        let version = payload[0];
        let mut offset = 9usize;
        let chapter_count = read_u32_be(payload, 5)? as usize;

        for _ in 0..chapter_count {
            if offset + 9 > payload.len() {
                break;
            }

            let timestamp = if version == 1 {
                read_u64_be(payload, offset)?
            } else {
                read_u32_be(payload, offset + 4)? as u64
            };
            offset += 8;

            let title_len = payload[offset] as usize;
            offset += 1;
            if offset + title_len > payload.len() {
                break;
            }
            let title = String::from_utf8_lossy(&payload[offset..offset + title_len]).to_string();
            offset += title_len;

            self.chpl_chapters.push(ChplChapter { timestamp, title });
        }

        Ok(())
    }

    fn populate_format_from_tracks(&mut self) {
        let primary_audio_track = self.tracks.values().find(|track| track.is_audio());
        let has_audio = self.tracks.values().any(|track| track.is_audio());
        let has_video = self.tracks.values().any(|track| track.is_video());
        self.format.has_audio = Some(has_audio);
        self.format.has_video = Some(has_video);

        if let Some(track) = primary_audio_track {
            if let Some(description) = track.sample_descriptions.first() {
                self.format.codec = Some(format_codec(&description.data_format));
                self.format.sample_rate = description.sample_rate;
                self.format.bits_per_sample = description.bits_per_sample;
                self.format.number_of_channels = description.number_of_channels;
                self.format.lossless = Some(is_lossless(&description.data_format));
            }

            if self.format.duration.is_none() {
                if let (Some(time_scale), Some(duration_units)) = (track.time_scale, track.duration_units) {
                    if time_scale > 0 {
                        self.format.duration = Some(duration_units as f64 / time_scale as f64);
                    }
                }
            }
        }
    }

    fn process_chpl_chapters(&mut self) -> Result<bool, String> {
        if self.chpl_chapters.is_empty() {
            return Ok(false);
        }

        let Some(file_duration) = self.format.duration else {
            return Ok(false);
        };
        if file_duration <= 0.0 {
            return Ok(false);
        }

        let Some(inferred_time_base) = infer_chpl_time_base(&self.chpl_chapters, file_duration) else {
            return Ok(false);
        };

        let max_duration = (file_duration * 1000.0 + 5000.0).round() as u64;
        let mut chapters = Vec::new();
        for chapter in &self.chpl_chapters {
            let timestamp_ms = ((chapter.timestamp as u128) * 1000u128 / inferred_time_base as u128) as u64;
            if timestamp_ms > max_duration {
                continue;
            }
            chapters.push(FfiChapter {
                id: None,
                title: if chapter.title.is_empty() {
                    format!("Chapter {}", chapters.len() + 1)
                } else {
                    chapter.title.clone()
                },
                start: timestamp_ms,
                end: None,
                sample_offset: None,
                time_scale: Some(1000),
            });
        }

        chapters.sort_by_key(|chapter| chapter.start);
        for index in 0..chapters.len() {
            let end = if index + 1 < chapters.len() {
                Some(chapters[index + 1].start)
            } else {
                Some((file_duration * 1000.0).round() as u64)
            };
            chapters[index].end = end;
        }

        if !chapters.is_empty() {
            self.format.chapters = chapters;
            return Ok(true);
        }

        Ok(false)
    }

    fn try_parse_chapters_from_track_references(&mut self) -> Result<bool, String> {
        let owner_ids: Vec<u32> = self
            .tracks
            .iter()
            .filter_map(|(id, track)| {
                if !track.chapter_track_ids.is_empty() {
                    Some(*id)
                } else {
                    None
                }
            })
            .collect();
        if owner_ids.len() != 1 {
            return Ok(false);
        }

        let owner_track = self
            .tracks
            .get(&owner_ids[0])
            .cloned()
            .ok_or_else(|| "missing chapter owner track".to_string())?;

        let chapter_track_ids: Vec<u32> = self
            .tracks
            .iter()
            .filter_map(|(id, _track)| {
                if owner_track.chapter_track_ids.contains(id) {
                    Some(*id)
                } else {
                    None
                }
            })
            .collect();
        if chapter_track_ids.len() != 1 {
            return Ok(false);
        }

        let chapter_track = self
            .tracks
            .get(&chapter_track_ids[0])
            .cloned()
            .ok_or_else(|| "missing chapter track".to_string())?;

        let Some(chapters) = self.parse_chapter_track_by_absolute_offsets(&chapter_track, &owner_track)? else {
            return Ok(false);
        };
        if chapters.is_empty() {
            return Ok(false);
        }

        self.format.chapters = chapters;
        Ok(true)
    }

    fn parse_chapter_track_by_absolute_offsets(
        &mut self,
        chapter_track: &TrackDescription,
        referenced_track: &TrackDescription,
    ) -> Result<Option<Vec<FfiChapter>>, String> {
        if chapter_track.chunk_offset_table.is_empty() || chapter_track.sample_size.is_none() {
            return Ok(None);
        }
        if chapter_track.sample_size == Some(0)
            && chapter_track.chunk_offset_table.len() != chapter_track.sample_size_table.len()
        {
            self.warnings
                .push("Invalid MP4 chapter track sample sizing".to_string());
            return Ok(None);
        }

        let referenced_time_scale = match referenced_track.time_scale {
            Some(value) if value > 0 => value,
            _ => return Ok(None),
        };

        let mut sample_requests = Vec::with_capacity(chapter_track.chunk_offset_table.len());
        for (index, chunk_offset) in chapter_track.chunk_offset_table.iter().enumerate() {
            let sample_size = if chapter_track.sample_size.unwrap_or(0) > 0 {
                chapter_track.sample_size.unwrap_or(0)
            } else {
                *chapter_track
                    .sample_size_table
                    .get(index)
                    .ok_or_else(|| "missing MP4 chapter sample size".to_string())?
            } as usize;

            sample_requests.push(ChapterSampleRequest {
                index,
                offset: *chunk_offset,
                size: sample_size,
            });
        }

        let title_bytes_by_index = self.read_chapter_samples(&sample_requests)?;

        let mut chapters = Vec::with_capacity(sample_requests.len());
        for request in &sample_requests {
            let title_bytes = title_bytes_by_index
                .get(request.index)
                .ok_or_else(|| "missing prefetched MP4 chapter sample".to_string())?;

            let title = parse_chapter_text(&title_bytes)?;

            let (chapter_offset, start_ms) = if let Some(offset_from_stts) =
                get_sample_offset_from_stts(chapter_track, request.index)
            {
                if let Some(time_scale) = chapter_track.time_scale {
                    if time_scale > 0 {
                        (
                            offset_from_stts,
                            ((offset_from_stts as f64 * 1000.0) / time_scale as f64).round() as u64,
                        )
                    } else {
                        let offset = find_sample_offset(referenced_track, request.offset)?;
                        (
                            offset,
                            ((offset as f64 * 1000.0) / referenced_time_scale as f64).round() as u64,
                        )
                    }
                } else {
                    let offset = find_sample_offset(referenced_track, request.offset)?;
                    (
                        offset,
                        ((offset as f64 * 1000.0) / referenced_time_scale as f64).round() as u64,
                    )
                }
            } else {
                let offset = find_sample_offset(referenced_track, request.offset)?;
                (
                    offset,
                    ((offset as f64 * 1000.0) / referenced_time_scale as f64).round() as u64,
                )
            };

            chapters.push(FfiChapter {
                id: None,
                title,
                start: start_ms,
                end: None,
                sample_offset: Some(chapter_offset),
                time_scale: Some(1000),
            });
        }

        for index in 0..chapters.len() {
            let current_start = chapters[index].start;
            let mut end = if index + 1 < chapters.len() {
                Some(chapters[index + 1].start)
            } else {
                referenced_track.duration_units.and_then(|duration_units| {
                    referenced_track.time_scale.map(|time_scale| {
                        ((duration_units as f64 * 1000.0) / time_scale as f64).round() as u64
                    })
                })
            };

            if let Some(value) = end {
                if value < current_start {
                    let fallback = self
                        .format
                        .duration
                        .map(|duration| (duration * 1000.0).round() as u64);
                    end = fallback
                        .filter(|fallback_end| *fallback_end >= current_start)
                        .or(Some(current_start));
                }
            }

            chapters[index].end = end;
        }

        Ok(Some(chapters))
    }

    fn read_chapter_samples(
        &self,
        requests: &[ChapterSampleRequest],
    ) -> Result<Vec<Vec<u8>>, String> {
        if requests.is_empty() {
            return Ok(Vec::new());
        }

        let mut sorted_requests = requests.to_vec();
        sorted_requests.sort_by_key(|request| request.offset);

        let batches = build_batched_ranges(&sorted_requests);
        let mut output = vec![Vec::new(); requests.len()];

        for batch in batches {
            let bytes = self
                .reader
                .read_exact_at(batch.start, (batch.end - batch.start) as usize)?;

            for request in batch.requests {
                let relative_start = (request.offset - batch.start) as usize;
                let relative_end = relative_start + request.size;
                output[request.index] = bytes[relative_start..relative_end].to_vec();
            }
        }

        Ok(output)
    }
}

fn build_batched_ranges(requests: &[ChapterSampleRequest]) -> Vec<BatchedRange> {
    if requests.is_empty() {
        return Vec::new();
    }

    const MAX_GAP_BYTES: u64 = 64 * 1024;
    const MAX_BATCH_SPAN_BYTES: u64 = 512 * 1024;

    let mut batches = Vec::new();
    let mut current = BatchedRange {
        start: requests[0].offset,
        end: requests[0].offset + requests[0].size as u64,
        requests: vec![requests[0].clone()],
    };

    for request in requests.iter().skip(1) {
        let request_end = request.offset + request.size as u64;
        let gap = request.offset.saturating_sub(current.end);
        let proposed_end = current.end.max(request_end);
        let proposed_span = proposed_end.saturating_sub(current.start);

        if gap <= MAX_GAP_BYTES && proposed_span <= MAX_BATCH_SPAN_BYTES {
            current.end = proposed_end;
            current.requests.push(request.clone());
        } else {
            batches.push(current);
            current = BatchedRange {
                start: request.offset,
                end: request_end,
                requests: vec![request.clone()],
            };
        }
    }

    batches.push(current);
    batches
}

struct HttpRangeReader {
    client: Client,
    url: String,
    size: u64,
    deadline: Option<Instant>,
}

impl HttpRangeReader {
    fn new(url: &str, timeout: Option<Duration>, file_size_hint: Option<u64>) -> Result<Self, String> {
        validate_url_scheme(url)?;

        let client = Client::builder()
            .connect_timeout(timeout.unwrap_or(Duration::from_secs(30)))
            .build()
            .map_err(|err| format!("failed to build HTTP client: {err}"))?;

        let deadline = timeout.map(|value| Instant::now() + value);
        if let Some(size) = file_size_hint.filter(|value| *value > 0) {
            return Ok(Self {
                client,
                url: url.to_string(),
                size,
                deadline,
            });
        }

        let display_url = redact_url(url);

        let request_timeout = remaining_timeout(deadline)?;
        let response = client
            .head(url)
            .header(USER_AGENT, "metadata-audio-rust-url-parser")
            .timeout(request_timeout)
            .send()
            .map_err(|err| format!("failed to HEAD '{display_url}': {err}"))?;

        if !response.status().is_success() {
            return Err(format!(
                "unexpected HEAD status {} for '{}'",
                response.status(),
                display_url
            ));
        }

        let accept_ranges = response
            .headers()
            .get(ACCEPT_RANGES)
            .and_then(|value| value.to_str().ok())
            .unwrap_or_default()
            .to_ascii_lowercase();
        if !accept_ranges.contains("bytes") {
            return Err(format!(
                "URL does not advertise byte range support: {}",
                display_url
            ));
        }

        let size = response
            .headers()
            .get(CONTENT_LENGTH)
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse::<u64>().ok())
            .ok_or_else(|| format!("missing content-length for '{}'", display_url))?;

        Ok(Self {
            client,
            url: url.to_string(),
            size,
            deadline,
        })
    }

    fn read_atom_header(&self, offset: u64, remaining: u64) -> Result<AtomHeader, String> {
        let base = self.read_exact_at(offset, 8)?;
        parse_atom_header_from_bytes(&base, remaining, |extended| {
            if extended {
                self.read_exact_at(offset, 16)
            } else {
                Ok(base.clone())
            }
        })
    }

    fn read_exact_at(&self, offset: u64, len: usize) -> Result<Vec<u8>, String> {
        if len == 0 {
            return Ok(Vec::new());
        }

        let end = offset
            .checked_add(len as u64)
            .and_then(|value| value.checked_sub(1))
            .ok_or_else(|| "range overflow while reading URL".to_string())?;
        if end >= self.size {
            return Err(format!(
                "requested URL range {offset}-{end} exceeds file size {}",
                self.size
            ));
        }

        let response = self
            .client
            .get(&self.url)
            .header(USER_AGENT, "metadata-audio-rust-url-parser")
            .header(RANGE, format!("bytes={offset}-{end}"))
            .timeout(remaining_timeout(self.deadline)?)
            .send()
            .map_err(|err| format!("failed to fetch range {offset}-{end}: {err}"))?;

        if response.status() != reqwest::StatusCode::PARTIAL_CONTENT {
            return Err(format!(
                "unexpected range status {} for {}-{}",
                response.status(),
                offset,
                end
            ));
        }

        let bytes = response
            .bytes()
            .map_err(|err| format!("failed to read response body for range {offset}-{end}: {err}"))?;
        if bytes.len() != len {
            return Err(format!(
                "short read for range {offset}-{end}: expected {len} bytes, got {}",
                bytes.len()
            ));
        }
        Ok(bytes.to_vec())
    }
}

fn remaining_timeout(deadline: Option<Instant>) -> Result<Duration, String> {
    let Some(deadline) = deadline else {
        return Ok(Duration::from_secs(30));
    };

    match deadline.checked_duration_since(Instant::now()) {
        Some(duration) if !duration.is_zero() => Ok(duration),
        _ => Err("remote MP4 parsing exceeded timeout budget".to_string()),
    }
}

fn validate_url_scheme(url: &str) -> Result<(), String> {
    let parsed = reqwest::Url::parse(url).map_err(|err| format!("invalid URL: {err}"))?;
    match parsed.scheme() {
        "http" | "https" => Ok(()),
        scheme => Err(format!("unsupported URL scheme: {scheme}")),
    }
}

fn redact_url(url: &str) -> String {
    let Ok(mut parsed) = reqwest::Url::parse(url) else {
        return url.split('?').next().unwrap_or(url).to_string();
    };
    let _ = parsed.set_username("");
    let _ = parsed.set_password(None);
    parsed.set_query(None);
    parsed.set_fragment(None);
    parsed.to_string()
}

fn parse_atom_header_from_bytes<F>(
    base: &[u8],
    remaining: u64,
    mut load_bytes: F,
) -> Result<AtomHeader, String>
where
    F: FnMut(bool) -> Result<Vec<u8>, String>,
{
    ensure_len(base, 8, "invalid MP4 atom header length")?;
    let length32 = read_u32_be(base, 0)? as u64;
    let name = String::from_utf8_lossy(&base[4..8]).to_string();

    if length32 == 1 {
        let full = load_bytes(true)?;
        ensure_len(&full, 16, "invalid MP4 extended atom header length")?;
        let length = read_u64_be(&full, 8)?;
        return Ok(AtomHeader {
            length,
            header_length: 16,
            name,
        });
    }

    let length = if length32 == 0 { remaining } else { length32 };
    Ok(AtomHeader {
        length,
        header_length: 8,
        name,
    })
}

fn parse_atom_header_from_slice(
    bytes: &[u8],
    offset: usize,
    remaining: usize,
) -> Result<AtomHeader, String> {
    ensure_len_at(bytes, offset, 8, "invalid MP4 atom header length")?;
    let length32 = read_u32_be(bytes, offset)? as u64;
    let name = String::from_utf8_lossy(&bytes[offset + 4..offset + 8]).to_string();
    if length32 == 1 {
        ensure_len_at(bytes, offset, 16, "invalid MP4 extended atom header length")?;
        return Ok(AtomHeader {
            length: read_u64_be(bytes, offset + 8)?,
            header_length: 16,
            name,
        });
    }

    Ok(AtomHeader {
        length: if length32 == 0 { remaining as u64 } else { length32 },
        header_length: 8,
        name,
    })
}

fn parse_chapter_text(bytes: &[u8]) -> Result<String, String> {
    if bytes.len() < 2 {
        return Ok(String::new());
    }
    let title_length = read_u16_be(bytes, 0)? as usize;
    let available_length = bytes.len() - 2;
    let actual_length = title_length.min(available_length);
    Ok(String::from_utf8_lossy(&bytes[2..2 + actual_length]).to_string())
}

fn get_sample_offset_from_stts(track: &TrackDescription, sample_index: usize) -> Option<u64> {
    if track.time_to_sample_table.is_empty() {
        return None;
    }

    let mut remaining = sample_index as u32;
    let mut offset = 0u64;
    for entry in &track.time_to_sample_table {
        if remaining == 0 {
            return Some(offset);
        }

        let take = remaining.min(entry.count);
        offset = offset.saturating_add(take as u64 * entry.duration as u64);
        remaining -= take;
    }

    if remaining == 0 {
        Some(offset)
    } else {
        None
    }
}

fn find_sample_offset(track: &TrackDescription, chapter_offset: u64) -> Result<u64, String> {
    let mut chunk_index = 0usize;
    while chunk_index < track.chunk_offset_table.len()
        && track.chunk_offset_table[chunk_index] < chapter_offset
    {
        chunk_index += 1;
    }

    let chunk_id = if chunk_index == 0 {
        1
    } else {
        chunk_index as u32
    };
    get_chunk_duration(chunk_id, track)
}

fn get_chunk_duration(chunk_id: u32, track: &TrackDescription) -> Result<u64, String> {
    if track.time_to_sample_table.is_empty() || track.sample_to_chunk_table.is_empty() {
        return Ok(0);
    }

    let mut time_to_sample_index = 0usize;
    let mut remaining_count = track.time_to_sample_table[time_to_sample_index].count;
    let mut sample_duration = track.time_to_sample_table[time_to_sample_index].duration;
    let mut current_chunk_id = 1u32;
    let mut samples_per_chunk = get_samples_per_chunk(current_chunk_id, track)?;
    let mut total_duration = 0u64;

    while current_chunk_id < chunk_id {
        let number_of_samples = remaining_count.min(samples_per_chunk);
        total_duration = total_duration
            .saturating_add(number_of_samples as u64 * sample_duration as u64);
        remaining_count -= number_of_samples;
        samples_per_chunk -= number_of_samples;

        if samples_per_chunk == 0 {
            current_chunk_id += 1;
            samples_per_chunk = get_samples_per_chunk(current_chunk_id, track)?;
        } else if remaining_count == 0 {
            time_to_sample_index += 1;
            if time_to_sample_index >= track.time_to_sample_table.len() {
                break;
            }
            remaining_count = track.time_to_sample_table[time_to_sample_index].count;
            sample_duration = track.time_to_sample_table[time_to_sample_index].duration;
        }
    }

    Ok(total_duration)
}

fn get_samples_per_chunk(chunk_id: u32, track: &TrackDescription) -> Result<u32, String> {
    let table = &track.sample_to_chunk_table;
    if table.is_empty() {
        return Err("missing sample-to-chunk table".to_string());
    }

    for index in 0..table.len().saturating_sub(1) {
        if chunk_id >= table[index].first_chunk && chunk_id < table[index + 1].first_chunk {
            return Ok(table[index].samples_per_chunk);
        }
    }

    Ok(table.last().map(|entry| entry.samples_per_chunk).unwrap_or(0))
}

fn infer_chpl_time_base(chapters: &[ChplChapter], file_duration_seconds: f64) -> Option<u64> {
    if chapters.is_empty() || file_duration_seconds <= 0.0 {
        return None;
    }

    let max_timestamp = chapters.iter().map(|chapter| chapter.timestamp).max()?;
    if max_timestamp == 0 {
        return None;
    }

    let inferred = (max_timestamp as f64 / file_duration_seconds).round() as u64;
    if inferred == 0 {
        return None;
    }

    Some(normalize_time_base(inferred))
}

fn normalize_time_base(inferred: u64) -> u64 {
    const CANDIDATES: [u64; 7] = [1000, 22050, 44100, 48000, 90000, 1000000, 10000000];

    let mut best = inferred;
    let mut best_rel_error = f64::INFINITY;
    for candidate in CANDIDATES {
        let rel_error = ((candidate as f64) - (inferred as f64)).abs() / inferred as f64;
        if rel_error < best_rel_error {
            best_rel_error = rel_error;
            best = candidate;
        }
    }

    if best_rel_error <= 0.02 {
        best
    } else {
        inferred
    }
}

fn format_codec(data_format: &str) -> String {
    match data_format {
        "mp4a" => "MPEG-4/AAC".to_string(),
        "alac" => "ALAC".to_string(),
        "ac-3" => "AC-3".to_string(),
        other => other.to_string(),
    }
}

fn is_lossless(data_format: &str) -> bool {
    matches!(data_format, "alac" | "raw")
}

fn ensure_len(bytes: &[u8], length: usize, message: &str) -> Result<(), String> {
    if bytes.len() < length {
        Err(message.to_string())
    } else {
        Ok(())
    }
}

fn ensure_len_at(bytes: &[u8], offset: usize, length: usize, message: &str) -> Result<(), String> {
    if offset.checked_add(length).map(|end| end <= bytes.len()).unwrap_or(false) {
        Ok(())
    } else {
        Err(message.to_string())
    }
}

fn read_u16_be(bytes: &[u8], offset: usize) -> Result<u16, String> {
    ensure_len_at(bytes, offset, 2, "requested token range is out of bounds")?;
    Ok(((bytes[offset] as u16) << 8) | bytes[offset + 1] as u16)
}

fn read_u32_be(bytes: &[u8], offset: usize) -> Result<u32, String> {
    ensure_len_at(bytes, offset, 4, "requested token range is out of bounds")?;
    Ok(((bytes[offset] as u32) << 24)
        | ((bytes[offset + 1] as u32) << 16)
        | ((bytes[offset + 2] as u32) << 8)
        | bytes[offset + 3] as u32)
}

fn read_u64_be(bytes: &[u8], offset: usize) -> Result<u64, String> {
    ensure_len_at(bytes, offset, 8, "requested token range is out of bounds")?;
    Ok(((bytes[offset] as u64) << 56)
        | ((bytes[offset + 1] as u64) << 48)
        | ((bytes[offset + 2] as u64) << 40)
        | ((bytes[offset + 3] as u64) << 32)
        | ((bytes[offset + 4] as u64) << 24)
        | ((bytes[offset + 5] as u64) << 16)
        | ((bytes[offset + 6] as u64) << 8)
        | bytes[offset + 7] as u64)
}
