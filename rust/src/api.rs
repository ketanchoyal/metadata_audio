#![allow(non_snake_case)]
#![allow(unexpected_cfgs)]

use std::fs::File;
use std::io::Cursor;
use std::path::Path;

use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, FormatReader};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::{MetadataRevision, StandardTag};

use crate::common_tags::{self, extract_common_tags};
use crate::format_info::extract_format;
use crate::native_tags::collect_native_tags;
use crate::pictures::extract_pictures;
use crate::track_details::{extract_track_details};
use crate::utils::*;

#[derive(Debug)]
pub(crate) struct ExtractedMetadata {
    pub(crate) format_short_name: String,
    pub(crate) track_codec: Option<String>,
    pub(crate) duration_secs: Option<f64>,
    pub(crate) sample_rate: Option<u32>,
    pub(crate) channels: Option<u32>,
    pub(crate) bits_per_sample: Option<u32>,
    pub(crate) title: Option<String>,
    pub(crate) artist: Option<String>,
    pub(crate) album: Option<String>,
    pub(crate) native_tag_count: u32,
    pub(crate) has_pictures: bool,
    pub(crate) chapter_count: u32,
    pub(crate) warnings: Vec<String>,
}

#[flutter_rust_bridge::frb]
pub struct FfiBasicMetadata {
    pub container: Option<String>,
    pub codec: Option<String>,
    pub duration_secs: Option<f64>,
    pub sample_rate: Option<u32>,
    pub channels: Option<u32>,
    pub bits_per_sample: Option<u32>,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub native_tag_count: u32,
    pub has_pictures: bool,
    pub chapter_count: u32,
    pub warnings: Vec<String>,
}

#[derive(Clone, Debug, Default)]
#[flutter_rust_bridge::frb]
pub struct FfiTrackNo {
    pub no: Option<u32>,
    pub of: Option<u32>,
}

#[derive(Clone, Debug, Default)]
#[flutter_rust_bridge::frb]
pub struct FfiComment {
    pub descriptor: Option<String>,
    pub language: Option<String>,
    pub text: Option<String>,
}

#[derive(Clone, Debug, Default)]
#[flutter_rust_bridge::frb]
pub struct FfiRating {
    pub source: Option<String>,
    pub rating: Option<f64>,
}

#[derive(Clone, Debug, Default)]
#[flutter_rust_bridge::frb]
pub struct FfiPicture {
    pub format: Option<String>,
    pub data: Vec<u8>,
    pub description: Option<String>,
    pub r#type: Option<String>,
    pub name: Option<String>,
}

#[derive(Clone, Debug, Default)]
#[flutter_rust_bridge::frb]
pub struct FfiFormat {
    pub container: String,
    pub tag_types: Vec<String>,
    pub duration: Option<f64>,
    pub bitrate: Option<u32>,
    pub sample_rate: Option<u32>,
    pub bits_per_sample: Option<u32>,
    pub tool: Option<String>,
    pub codec: Option<String>,
    pub codec_profile: Option<String>,
    pub lossless: Option<bool>,
    pub number_of_channels: Option<u32>,
    pub number_of_samples: Option<u64>,
    pub has_audio: Option<bool>,
    pub has_video: Option<bool>,
    pub track_gain: Option<f64>,
    pub track_peak_level: Option<f64>,
    pub album_gain: Option<f64>,
}

#[derive(Clone, Debug, Default)]
#[flutter_rust_bridge::frb]
pub struct FfiAudioMetadata {
    pub format: FfiFormat,
    pub common: FfiCommonTags,
    pub native: Vec<FfiNativeTag>,
    pub pictures: Vec<FfiPicture>,
    pub warnings: Vec<String>,
}

#[derive(Clone, Debug, Default)]
#[flutter_rust_bridge::frb]
pub struct FfiLyricsTag {
    pub descriptor: Option<String>,
    pub language: Option<String>,
    pub text: Option<String>,
}

#[derive(Clone, Debug, Default)]
#[flutter_rust_bridge::frb]
pub struct FfiCommonTags {
    pub track: FfiTrackNo,
    pub disk: FfiTrackNo,
    pub year: Option<i32>,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub artists: Vec<String>,
    pub albumartist: Option<String>,
    pub albumartists: Vec<String>,
    pub album: Option<String>,
    pub date: Option<String>,
    pub originaldate: Option<String>,
    pub originalyear: Option<i32>,
    pub releasedate: Option<String>,
    pub comment: Vec<FfiComment>,
    pub genre: Vec<String>,
    pub picture: Vec<FfiPicture>,
    pub composer: Vec<String>,
    pub lyrics: Vec<FfiLyricsTag>,
    pub albumsort: Option<String>,
    pub titlesort: Option<String>,
    pub work: Option<String>,
    pub artistsort: Option<String>,
    pub albumartistsort: Option<String>,
    pub composersort: Option<String>,
    pub lyricist: Vec<String>,
    pub writer: Vec<String>,
    pub conductor: Vec<String>,
    pub remixer: Vec<String>,
    pub arranger: Vec<String>,
    pub engineer: Vec<String>,
    pub publisher: Vec<String>,
    pub producer: Vec<String>,
    pub djmixer: Vec<String>,
    pub mixer: Vec<String>,
    pub technician: Vec<String>,
    pub label: Vec<String>,
    pub grouping: Option<String>,
    pub subtitle: Vec<String>,
    pub description: Vec<String>,
    pub discsubtitle: Vec<String>,
    pub longDescription: Option<String>,
    pub totaltracks: Option<String>,
    pub totaldiscs: Option<String>,
    pub movementTotal: Option<i32>,
    pub compilation: Option<bool>,
    pub rating: Vec<FfiRating>,
    pub bpm: Option<i32>,
    pub mood: Option<String>,
    pub media: Option<String>,
    pub catalognumber: Vec<String>,
    pub tvShow: Option<String>,
    pub tvShowSort: Option<String>,
    pub tvEpisodeId: Option<String>,
    pub tvNetwork: Option<String>,
    pub tvSeason: Option<i32>,
    pub tvEpisode: Option<i32>,
    pub podcast: Option<bool>,
    pub podcasturl: Option<String>,
    pub releasestatus: Option<String>,
    pub releasecountry: Option<String>,
    pub script: Option<String>,
    pub language: Option<String>,
    pub copyright: Option<String>,
    pub license: Option<String>,
    pub encodedby: Option<String>,
    pub encodersettings: Option<String>,
    pub gapless: Option<String>,
    pub barcode: Option<String>,
    pub isrc: Option<String>,
    pub asin: Option<String>,
    pub website: Option<String>,
    pub notes: Option<String>,
    pub originalalbum: Option<String>,
    pub originalartist: Option<String>,
    pub releasetype: Vec<String>,
    pub keywords: Vec<String>,
    pub category: Vec<String>,
    pub musicbrainz_recordingid: Option<String>,
    pub musicbrainz_trackid: Option<String>,
    pub musicbrainz_albumid: Option<String>,
    pub musicbrainz_artistid: Option<String>,
    pub musicbrainz_albumartistid: Option<String>,
    pub musicbrainz_releasegroupid: Option<String>,
    pub musicbrainz_workid: Option<String>,
    pub musicbrainz_trmid: Option<String>,
    pub musicbrainz_discid: Option<String>,
    pub acoustid_id: Option<String>,
    pub acoustid_fingerprint: Option<String>,
    pub musicip_puid: Option<String>,
    pub musicip_fingerprint: Option<String>,
    pub discogs_artist_id: Option<String>,
    pub discogs_release_id: Option<String>,
    pub discogs_label_id: Option<String>,
    pub discogs_master_release_id: Option<String>,
    pub discogs_votes: Option<f64>,
    pub discogs_rating: Option<f64>,
    pub replaygain_track_gain: Option<f64>,
    pub replaygain_track_peak: Option<f64>,
    pub replaygain_album_gain: Option<f64>,
    pub replaygain_album_peak: Option<f64>,
    pub replaygain_track_gain_ratio: Option<f64>,
    pub replaygain_track_peak_ratio: Option<f64>,
    pub replaygain_album_minmax: Option<f64>,
    pub replaygain_track_minmax: Option<f64>,
    pub replaygain_undo: Option<f64>,
    pub performerInstrument: Option<String>,
    pub key: Option<String>,
    pub movement: Option<String>,
    pub stik: Option<String>,
    pub showMovement: Option<String>,
    pub playCounter: Option<String>,
    pub hdVideo: Option<String>,
    pub movementIndex: Option<i32>,
    pub podcastId: Option<String>,
}

#[derive(Clone, Debug)]
#[flutter_rust_bridge::frb]
pub struct FfiNativeTag {
    pub key: String,
    pub value: String,
    pub std_key: Option<String>,
}

#[flutter_rust_bridge::frb]
pub fn health_check() -> String {
    "symphonia-native-ok".to_string()
}

#[flutter_rust_bridge::frb]
pub fn parse_from_path(path: String) -> Result<FfiAudioMetadata, String> {
    let mut format = probe_format_from_path(&path)?;

    let format_info = extract_format(&mut *format);
    let common = extract_common_tags(&mut *format);
    let native = collect_native_tags(&mut *format);
    let pictures = extract_pictures(&mut *format);

    let warnings = collect_audio_warnings(&native, &common);

    Ok(FfiAudioMetadata {
        format: format_info,
        common,
        native,
        pictures,
        warnings,
    })
}

#[flutter_rust_bridge::frb]
pub fn parse_from_bytes(bytes: Vec<u8>, mime_hint: Option<String>) -> Result<FfiAudioMetadata, String> {
    let mut format = probe_format_from_bytes(bytes, mime_hint)?;

    let format_info = extract_format(&mut *format);
    let common = extract_common_tags(&mut *format);
    let native = collect_native_tags(&mut *format);
    let pictures = extract_pictures(&mut *format);

    let warnings = collect_audio_warnings(&native, &common);

    Ok(FfiAudioMetadata {
        format: format_info,
        common,
        native,
        pictures,
        warnings,
    })
}

#[flutter_rust_bridge::frb]
pub fn poc_parse_file(path: String) -> Result<FfiBasicMetadata, String> {
    let file = File::open(&path).map_err(|err| format!("failed to open file '{path}': {err}"))?;

    let mut hint = Hint::new();
    if let Some(extension) = Path::new(&path).extension().and_then(|value| value.to_str()) {
        hint.with_extension(extension);
    }

    let stream = MediaSourceStream::new(Box::new(file), Default::default());
    let extracted = extract_basic_metadata(stream, hint)?;
    Ok(to_ffi_metadata(extracted))
}

#[flutter_rust_bridge::frb]
pub fn poc_parse_bytes(bytes: Vec<u8>, mime_hint: Option<String>) -> Result<FfiBasicMetadata, String> {
    let cursor = std::io::Cursor::new(bytes);
    let mut hint = Hint::new();

    if let Some(mime_hint) = mime_hint.as_deref() {
        hint.mime_type(mime_hint);
        if let Some(extension) = extension_from_mime(mime_hint) {
            hint.with_extension(extension);
        }
    }

    let stream = MediaSourceStream::new(Box::new(cursor), Default::default());
    let extracted = extract_basic_metadata(stream, hint)?;
    Ok(to_ffi_metadata(extracted))
}

#[flutter_rust_bridge::frb]
pub fn poc_get_common_tags(path: String) -> Result<FfiCommonTags, String> {
    let mut format = probe_format_from_path(&path)?;

    Ok(extract_common_tags(&mut *format))
}

#[flutter_rust_bridge::frb]
pub fn poc_get_native_tags(path: String) -> Result<Vec<FfiNativeTag>, String> {
    let mut format = probe_format_from_path(&path)?;

    Ok(collect_native_tags(&mut *format))
}

#[flutter_rust_bridge::frb]
pub fn poc_get_format(path: String) -> Result<FfiFormat, String> {
    let mut format = probe_format_from_path(&path)?;

    Ok(extract_format(&mut *format))
}

#[flutter_rust_bridge::frb]
pub fn poc_get_pictures(path: String) -> Result<Vec<FfiPicture>, String> {
    let mut format = probe_format_from_path(&path)?;

    Ok(extract_pictures(&mut *format))
}

fn probe_format_from_path(path: &str) -> Result<Box<dyn FormatReader>, String> {
    let file = File::open(path).map_err(|err| format!("failed to open file '{path}': {err}"))?;

    let mut hint = Hint::new();
    if let Some(extension) = Path::new(path).extension().and_then(|value| value.to_str()) {
        hint.with_extension(extension);
    }

    let stream = MediaSourceStream::new(Box::new(file), Default::default());
    symphonia::default::get_probe()
        .probe(&hint, stream, FormatOptions::default(), Default::default())
        .map_err(|err| format!("failed to probe media source stream: {err}"))
}

fn probe_format_from_bytes(bytes: Vec<u8>, mime_hint: Option<String>) -> Result<Box<dyn FormatReader>, String> {
    let cursor = Cursor::new(bytes);

    let mut hint = Hint::new();
    if let Some(mime_hint) = mime_hint.as_deref() {
        hint.mime_type(mime_hint);
        if let Some(extension) = extension_from_mime(mime_hint) {
            hint.with_extension(extension);
        }
    }

    let stream = MediaSourceStream::new(Box::new(cursor), Default::default());
    symphonia::default::get_probe()
        .probe(&hint, stream, FormatOptions::default(), Default::default())
        .map_err(|err| format!("failed to probe media source stream: {err}"))
}

fn collect_audio_warnings(native: &[FfiNativeTag], common: &FfiCommonTags) -> Vec<String> {
    let mut warnings = Vec::new();
    if native.is_empty() {
        warnings.push("no native tags found in metadata revisions".to_string());
    }
    if common.title.is_none() && common.artist.is_none() && common.album.is_none() {
        warnings.push("common tags did not expose title, artist, or album".to_string());
    }
    warnings
}

fn extract_basic_metadata(stream: MediaSourceStream, hint: Hint) -> Result<ExtractedMetadata, String> {
    let mut format = symphonia::default::get_probe()
        .probe(&hint, stream, FormatOptions::default(), Default::default())
        .map_err(|err| format!("failed to probe media source stream: {err}"))?;

    let format_short_name = format.format_info().short_name.to_string();
    let track = format
        .tracks()
        .first()
        .ok_or_else(|| "no tracks discovered by Symphonia".to_string())?;

    let (track_codec, duration_secs, sample_rate, channels, bits_per_sample, track_warnings) =
        extract_track_details(
            track.codec_params.as_ref(),
            track.time_base,
            track.duration,
            track.num_frames,
        );

    let (title, artist, album, native_tag_count, has_pictures, metadata_warnings) =
        extract_metadata_details(&mut *format);

    let chapter_count = format.chapters().map(count_chapter_group_items).unwrap_or(0);

    let mut warnings = Vec::new();
    warnings.extend(track_warnings);
    warnings.extend(metadata_warnings);

    Ok(ExtractedMetadata {
        format_short_name,
        track_codec,
        duration_secs,
        sample_rate,
        channels,
        bits_per_sample,
        title,
        artist,
        album,
        native_tag_count,
        has_pictures,
        chapter_count,
        warnings,
    })
}

fn extract_metadata_details(
    format: &mut dyn FormatReader,
) -> (Option<String>, Option<String>, Option<String>, u32, bool, Vec<String>) {
    let mut metadata = format.metadata();
    let mut title = None;
    let mut artist = None;
    let mut album = None;
    let mut native_tag_count = 0u32;
    let mut has_pictures = false;
    let mut warnings = Vec::new();
    let mut revision_count = 0u32;

    while let Some(revision) = metadata.current() {
        revision_count += 1;
        let snapshot = summarize_revision(revision);
        native_tag_count = native_tag_count.saturating_add(snapshot.3);
        has_pictures |= snapshot.4;

        if title.is_none() {
            title = snapshot.0;
        }
        if artist.is_none() {
            artist = snapshot.1;
        }
        if album.is_none() {
            album = snapshot.2;
        }

        if metadata.pop().is_none() {
            break;
        }
    }

    if revision_count == 0 {
        warnings.push("metadata log contained no revisions".to_string());
    }
    if native_tag_count == 0 {
        warnings.push("no native tags found in metadata revisions".to_string());
    }

    (title, artist, album, native_tag_count, has_pictures, warnings)
}

fn summarize_revision(revision: &MetadataRevision) -> (Option<String>, Option<String>, Option<String>, u32, bool) {
    let mut title = None;
    let mut artist = None;
    let mut album = None;
    let mut tag_count = revision.media.tags.len() as u32;
    let mut has_pictures = !revision.media.visuals.is_empty();

    for tag in common_tags::iter_revision_tags(revision) {
        if title.is_none() {
            title = extract_standard_tag_value(&tag.std, StandardTagKind::Title);
        }
        if artist.is_none() {
            artist = extract_standard_tag_value(&tag.std, StandardTagKind::Artist);
        }
        if album.is_none() {
            album = extract_standard_tag_value(&tag.std, StandardTagKind::Album);
        }
        tag_count = tag_count.saturating_add(1);
    }

    for per_track in &revision.per_track {
        has_pictures |= !per_track.metadata.visuals.is_empty();
    }

    (
        title,
        artist,
        album,
        tag_count.saturating_sub(1),
        has_pictures,
    )
}

fn extract_standard_tag_value(tag: &Option<StandardTag>, kind: StandardTagKind) -> Option<String> {
    match (tag, kind) {
        (Some(StandardTag::TrackTitle(value)), StandardTagKind::Title) => Some(value.to_string()),
        (Some(StandardTag::Artist(value)), StandardTagKind::Artist) => Some(value.to_string()),
        (Some(StandardTag::Album(value)), StandardTagKind::Album) => Some(value.to_string()),
        _ => None,
    }
}

#[derive(Copy, Clone)]
pub(crate) enum StandardTagKind {
    Title,
    Artist,
    Album,
    AlbumArtist,
    Genre,
    Composer,
    Lyricist,
    Writer,
    Conductor,
    Remixer,
    Arranger,
    Engineer,
    Publisher,
    Producer,
    DjMixer,
    Mixer,
    Label,
    Subtitle,
    Description,
    DiscSubtitle,
    CatalogNumber,
    Category,
    Keywords,
    ReleaseType,
}
