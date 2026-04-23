use std::fs::File;
use std::path::Path;

use symphonia::core::codecs::CodecParameters;
use symphonia::core::formats::FormatOptions;
use symphonia::core::formats::probe::Hint;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::{
    ChapterGroup, ChapterGroupItem, MetadataRevision, StandardTag, Tag,
};
use symphonia::core::units::{TimeBase, Timestamp};

#[derive(Debug)]
struct ExtractedMetadata {
    format_short_name: String,
    track_codec: Option<String>,
    duration_secs: Option<f64>,
    sample_rate: Option<u32>,
    channels: Option<u32>,
    bits_per_sample: Option<u32>,
    title: Option<String>,
    artist: Option<String>,
    album: Option<String>,
    native_tag_count: u32,
    has_pictures: bool,
    chapter_count: u32,
    warnings: Vec<String>,
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
pub fn poc_get_native_tags(path: String) -> Result<Vec<FfiNativeTag>, String> {
    let file = File::open(&path).map_err(|err| format!("failed to open file '{path}': {err}"))?;

    let mut hint = Hint::new();
    if let Some(extension) = Path::new(&path).extension().and_then(|value| value.to_str()) {
        hint.with_extension(extension);
    }

    let stream = MediaSourceStream::new(Box::new(file), Default::default());
    let mut format = symphonia::default::get_probe()
        .probe(&hint, stream, FormatOptions::default(), Default::default())
        .map_err(|err| format!("failed to probe media source stream: {err}"))?;

    Ok(collect_native_tags(&mut *format))
}

fn extract_basic_metadata(
    stream: MediaSourceStream,
    hint: Hint,
) -> Result<ExtractedMetadata, String> {
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

    let chapter_count = format
        .chapters()
        .map(count_chapter_group_items)
        .unwrap_or(0);

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

fn extract_track_details(
    codec_params: Option<&CodecParameters>,
    time_base: Option<TimeBase>,
    duration: Option<symphonia::core::units::Duration>,
    num_frames: Option<u64>,
) -> (
    Option<String>,
    Option<f64>,
    Option<u32>,
    Option<u32>,
    Option<u32>,
    Vec<String>,
) {
    let mut warnings = Vec::new();

    let Some(codec_params) = codec_params else {
        warnings.push("first track is missing codec parameters".to_string());
        return (None, None, None, None, None, warnings);
    };

    let Some(audio) = codec_params.audio() else {
        warnings.push("first track codec parameters are not audio".to_string());
        return (Some(format!("{:?}", codec_params)), None, None, None, None, warnings);
    };

    let codec = Some(audio_codec_name(audio.codec));
    let sample_rate = audio.sample_rate;
    let channels = audio.channels.as_ref().map(|value| value.count() as u32);
    let bits_per_sample = audio.bits_per_sample.or(audio.bits_per_coded_sample);
    let duration_secs = match (time_base, duration, num_frames, sample_rate) {
        (Some(time_base), Some(duration), _, _) => duration
            .timestamp_from(Timestamp::ZERO)
            .and_then(|value| time_base.calc_time(value))
            .map(|value| value.as_secs_f64()),
        (_, None, Some(num_frames), Some(sample_rate)) if sample_rate > 0 => {
            Some(num_frames as f64 / sample_rate as f64)
        }
        (None, Some(_), _, _) => {
            warnings.push("track duration present without time base".to_string());
            None
        }
        _ => None,
    };

    if sample_rate.is_none() {
        warnings.push("sample rate unavailable on first track".to_string());
    }
    if channels.is_none() {
        warnings.push("channel count unavailable on first track".to_string());
    }
    if bits_per_sample.is_none() {
        warnings.push("bits per sample unavailable on first track".to_string());
    }
    if duration_secs.is_none() {
        warnings.push("duration unavailable from first track".to_string());
    }

    (codec, duration_secs, sample_rate, channels, bits_per_sample, warnings)
}

fn extract_metadata_details(
    format: &mut dyn symphonia::core::formats::FormatReader,
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

fn summarize_revision(
    revision: &MetadataRevision,
) -> (Option<String>, Option<String>, Option<String>, u32, bool) {
    let mut title = None;
    let mut artist = None;
    let mut album = None;

    for tag in &revision.media.tags {
        if title.is_none() {
            title = extract_standard_tag_value(&tag.std, StandardTagKind::Title);
        }
        if artist.is_none() {
            artist = extract_standard_tag_value(&tag.std, StandardTagKind::Artist);
        }
        if album.is_none() {
            album = extract_standard_tag_value(&tag.std, StandardTagKind::Album);
        }
    }

    (
        title,
        artist,
        album,
        revision.media.tags.len() as u32,
        !revision.media.visuals.is_empty(),
    )
}

fn collect_native_tags(format: &mut dyn symphonia::core::formats::FormatReader) -> Vec<FfiNativeTag> {
    let mut metadata = format.metadata();
    let mut native_tags = Vec::new();

    while let Some(revision) = metadata.current() {
        native_tags.extend(revision.media.tags.iter().map(tag_to_ffi_native_tag));
        for per_track in &revision.per_track {
            native_tags.extend(per_track.metadata.tags.iter().map(tag_to_ffi_native_tag));
        }

        if metadata.pop().is_none() {
            break;
        }
    }

    native_tags
}

fn tag_to_ffi_native_tag(tag: &Tag) -> FfiNativeTag {
    let std_key = tag.std.as_ref().map(standard_tag_key_name);
    let key = if tag.raw.key.is_empty() {
        tag.std
            .as_ref()
            .and_then(mp4_atom_key_from_standard_tag)
            .unwrap_or_default()
    }
    else {
        tag.raw.key.clone()
    };

    FfiNativeTag {
        key,
        value: tag.raw.value.to_string(),
        std_key,
    }
}

fn standard_tag_key_name(tag: &StandardTag) -> String {
    let debug = format!("{tag:?}");
    debug
        .split_once('(')
        .map(|(key, _)| key)
        .unwrap_or(debug.as_str())
        .to_string()
}

fn mp4_atom_key_from_standard_tag(tag: &StandardTag) -> Option<String> {
    let atom = match tag {
        StandardTag::AlbumArtist(_) => "aART",
        StandardTag::Album(_) => "©alb",
        StandardTag::Arranger(_) => "©arg",
        StandardTag::Artist(_) => "©ART",
        StandardTag::Author(_) => "©aut",
        StandardTag::Bpm(_) => "tmpo",
        StandardTag::Comment(_) => "©cmt",
        StandardTag::CompilationFlag(_) => "cpil",
        StandardTag::Composer(_) => "©wrt",
        StandardTag::Conductor(_) => "©con",
        StandardTag::Copyright(_) => "cprt",
        StandardTag::Description(_) => "desc",
        StandardTag::DiscNumber(_) => "disk",
        StandardTag::DiscTotal(_) => "disk",
        StandardTag::EncodedBy(_) => "©enc",
        StandardTag::Encoder(_) => "©too",
        StandardTag::Genre(_) => "©gen",
        StandardTag::Grouping(_) => "©grp",
        StandardTag::IdentIsrc(_) => "©isr",
        StandardTag::IdentPodcast(_) => "egid",
        StandardTag::Label(_) => "©lab",
        StandardTag::Lyrics(_) => "©lyr",
        StandardTag::MovementName(_) => "©mvn",
        StandardTag::MovementNumber(_) => "©mvi",
        StandardTag::MovementTotal(_) => "©mvc",
        StandardTag::Narrator(_) => "©nrt",
        StandardTag::OriginalArtist(_) => "©ope",
        StandardTag::Owner(_) => "ownr",
        StandardTag::PodcastCategory(_) => "catg",
        StandardTag::PodcastFlag(_) => "pcst",
        StandardTag::PodcastKeywords(_) => "keyw",
        StandardTag::Producer(_) => "©prd",
        StandardTag::ProductionCopyright(_) => "©phg",
        StandardTag::PurchaseDate(_) => "purd",
        StandardTag::ReleaseDate(_) => "©day",
        StandardTag::Soloist(_) => "©sol",
        StandardTag::SortAlbum(_) => "soal",
        StandardTag::SortAlbumArtist(_) => "soaa",
        StandardTag::SortArtist(_) => "soar",
        StandardTag::SortComposer(_) => "soco",
        StandardTag::SortTrackTitle(_) => "sonm",
        StandardTag::TrackNumber(_) => "trkn",
        StandardTag::TrackTitle(_) => "©nam",
        StandardTag::TrackTotal(_) => "trkn",
        StandardTag::TvEpisodeNumber(_) => "tves",
        StandardTag::TvEpisodeTitle(_) => "tven",
        StandardTag::TvNetwork(_) => "tvnn",
        StandardTag::TvSeasonNumber(_) => "tvsn",
        StandardTag::TvSeriesTitle(_) => "tvsh",
        StandardTag::UrlArtist(_) => "©prl",
        StandardTag::UrlLabel(_) => "©lal",
        StandardTag::UrlPodcast(_) => "purl",
        StandardTag::Work(_) => "©wrk",
        StandardTag::Writer(_) => "©wrt",
        _ => return None,
    };

    Some(atom.to_string())
}

fn extract_standard_tag_value(tag: &Option<StandardTag>, kind: StandardTagKind) -> Option<String> {
    match (tag, kind) {
        (Some(StandardTag::TrackTitle(value)), StandardTagKind::Title) => Some(value.to_string()),
        (Some(StandardTag::Artist(value)), StandardTagKind::Artist) => Some(value.to_string()),
        (Some(StandardTag::Album(value)), StandardTagKind::Album) => Some(value.to_string()),
        _ => None,
    }
}

fn count_chapter_group_items(group: &ChapterGroup) -> u32 {
    group
        .items
        .iter()
        .map(|item| match item {
            ChapterGroupItem::Chapter(_) => 1,
            ChapterGroupItem::Group(group) => count_chapter_group_items(group),
        })
        .sum()
}

fn to_ffi_metadata(value: ExtractedMetadata) -> FfiBasicMetadata {
    FfiBasicMetadata {
        container: Some(value.format_short_name),
        codec: value.track_codec,
        duration_secs: value.duration_secs,
        sample_rate: value.sample_rate,
        channels: value.channels,
        bits_per_sample: value.bits_per_sample,
        title: value.title,
        artist: value.artist,
        album: value.album,
        native_tag_count: value.native_tag_count,
        has_pictures: value.has_pictures,
        chapter_count: value.chapter_count,
        warnings: value.warnings,
    }
}

fn audio_codec_name(codec: symphonia::core::codecs::audio::AudioCodecId) -> String {
    use symphonia::core::codecs::audio::well_known::{
        CODEC_ID_AAC, CODEC_ID_ALAC, CODEC_ID_FLAC, CODEC_ID_MP3, CODEC_ID_VORBIS,
    };

    if codec == CODEC_ID_MP3 {
        "MPEG Layer 3".to_string()
    }
    else if codec == CODEC_ID_FLAC {
        "FLAC".to_string()
    }
    else if codec == CODEC_ID_VORBIS {
        "Vorbis".to_string()
    }
    else if codec == CODEC_ID_AAC {
        "AAC".to_string()
    }
    else if codec == CODEC_ID_ALAC {
        "ALAC".to_string()
    }
    else {
        codec.to_string()
    }
}

fn extension_from_mime(mime: &str) -> Option<&'static str> {
    match mime {
        "audio/mpeg" | "audio/mp3" | "audio/mpeg3" => Some("mp3"),
        "audio/flac" | "audio/x-flac" => Some("flac"),
        "audio/mp4" | "audio/x-m4a" | "audio/m4a" => Some("m4a"),
        "audio/ogg" | "audio/vorbis" | "audio/ogg; codecs=vorbis" => Some("ogg"),
        _ => None,
    }
}

#[derive(Copy, Clone)]
enum StandardTagKind {
    Title,
    Artist,
    Album,
}
