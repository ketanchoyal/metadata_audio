use symphonia::core::meta::Tag;
use crate::api::*;

pub(crate) fn extension_from_mime(mime: &str) -> Option<&'static str> {
    match mime {
        "audio/mpeg" | "audio/mp3" | "audio/mpeg3" => Some("mp3"),
        "audio/flac" | "audio/x-flac" => Some("flac"),
        "audio/mp4" | "audio/x-m4a" | "audio/m4a" => Some("m4a"),
        "audio/ogg" | "audio/vorbis" | "audio/ogg; codecs=vorbis" => Some("ogg"),
        _ => None,
    }
}

pub(crate) fn some_non_empty(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

pub(crate) fn parse_float(value: &str) -> Option<f64> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }

    if let Ok(parsed) = trimmed.parse::<f64>() {
        return Some(parsed);
    }

    let mut number = String::new();
    for (index, ch) in trimmed.chars().enumerate() {
        let allowed = ch.is_ascii_digit() || ch == '.' || (index == 0 && matches!(ch, '+' | '-'));
        if allowed {
            number.push(ch);
        } else if !number.is_empty() {
            break;
        }
    }

    number.parse::<f64>().ok()
}

pub(crate) fn parse_u32(value: &str) -> Option<u32> {
    value.trim().parse::<u32>().ok()
}

pub(crate) fn u32_from_u64(value: u64) -> Option<u32> {
    u32::try_from(value).ok()
}

pub(crate) fn nonzero_u32_from_u64(value: u64) -> Option<u32> {
    let value = u32_from_u64(value)?;
    if value == 0 { None } else { Some(value) }
}

pub(crate) fn push_unique(values: &mut Vec<String>, value: String) {
    if !values.iter().any(|existing| existing == &value) {
        values.push(value);
    }
}

pub(crate) fn dedup_strings(values: &mut Vec<String>) {
    let mut deduped = Vec::new();
    for value in values.drain(..) {
        push_unique(&mut deduped, value);
    }
    *values = deduped;
}

pub(crate) fn raw_sub_field_value(tag: &Tag, suffixes: &[&str]) -> Option<String> {
    tag.raw.sub_fields.as_ref().and_then(|sub_fields| {
        sub_fields.iter().find_map(|sub_field| {
            let field_upper = sub_field.field.to_ascii_uppercase();
            if suffixes.iter().any(|suffix| field_upper.ends_with(suffix)) {
                some_non_empty(&sub_field.value.to_string())
            } else {
                None
            }
        })
    })
}

pub(crate) fn set_option_string(target: &mut Option<String>, value: &str) {
    if target.is_none() {
        *target = some_non_empty(value);
    }
}

pub(crate) fn set_option_i32(target: &mut Option<i32>, value: i64) {
    if target.is_none() {
        *target = i32::try_from(value).ok();
    }
}

pub(crate) fn set_option_i32_from_str(target: &mut Option<i32>, value: &str) {
    if target.is_none() {
        *target = value.trim().parse::<i32>().ok();
    }
}

pub(crate) fn assign_option_from_value(target: &mut Option<f64>, value: &str) {
    if target.is_none() {
        *target = parse_float(value);
    }
}

pub(crate) fn to_ffi_metadata(value: ExtractedMetadata) -> FfiBasicMetadata {
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

pub(crate) fn count_chapter_group_items(group: &symphonia::core::meta::ChapterGroup) -> u32 {
    group
        .items
        .iter()
        .map(|item| match item {
            symphonia::core::meta::ChapterGroupItem::Chapter(_) => 1,
            symphonia::core::meta::ChapterGroupItem::Group(group) => count_chapter_group_items(group),
        })
        .sum()
}
