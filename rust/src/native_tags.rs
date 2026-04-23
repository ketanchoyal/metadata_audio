use symphonia::core::formats::FormatReader;
use symphonia::core::meta::{StandardTag, Tag};

use crate::api::*;

pub(crate) fn collect_native_tags(format: &mut dyn FormatReader) -> Vec<FfiNativeTag> {
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

pub(crate) fn tag_to_ffi_native_tag(tag: &Tag) -> FfiNativeTag {
    let std_key = tag.std.as_ref().map(standard_tag_key_name);
    let key = if tag.raw.key.is_empty() {
        tag.std.as_ref().and_then(mp4_atom_key_from_standard_tag).unwrap_or_default()
    } else {
        tag.raw.key.clone()
    };

    FfiNativeTag {
        key,
        value: tag.raw.value.to_string(),
        std_key,
    }
}

pub(crate) fn standard_tag_key_name(tag: &StandardTag) -> String {
    let debug = format!("{tag:?}");
    debug
        .split_once('(')
        .map(|(key, _)| key)
        .unwrap_or(debug.as_str())
        .to_string()
}

pub(crate) fn mp4_atom_key_from_standard_tag(tag: &StandardTag) -> Option<String> {
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
        StandardTag::DiscNumber(_) | StandardTag::DiscTotal(_) => "disk",
        StandardTag::EncodedBy(_) => "©enc",
        StandardTag::Encoder(_) | StandardTag::EncoderSettings(_) => "©too",
        StandardTag::Genre(_) => "©gen",
        StandardTag::Grouping(_) => "©grp",
        StandardTag::IdentIsrc(_) => "©isr",
        StandardTag::IdentPodcast(_) => "egid",
        StandardTag::Label(_) => "©lab",
        StandardTag::Lyrics(_) => "©lyr",
        StandardTag::MovementName(_) => "©mvn",
        StandardTag::MovementNumber(_) => "©mvi",
        StandardTag::MovementTotal(_) => "©mvc",
        StandardTag::OriginalArtist(_) => "©ope",
        StandardTag::PodcastCategory(_) => "catg",
        StandardTag::PodcastFlag(_) => "pcst",
        StandardTag::PodcastKeywords(_) => "keyw",
        StandardTag::Producer(_) => "©prd",
        StandardTag::ProductionCopyright(_) => "©phg",
        StandardTag::PurchaseDate(_) => "purd",
        StandardTag::ReleaseDate(_) => "©day",
        StandardTag::SortAlbum(_) => "soal",
        StandardTag::SortAlbumArtist(_) => "soaa",
        StandardTag::SortArtist(_) => "soar",
        StandardTag::SortComposer(_) => "soco",
        StandardTag::SortTrackTitle(_) => "sonm",
        StandardTag::TrackNumber(_) | StandardTag::TrackTotal(_) => "trkn",
        StandardTag::TrackTitle(_) => "©nam",
        StandardTag::TvEpisodeNumber(_) => "tves",
        StandardTag::TvEpisodeTitle(_) => "tven",
        StandardTag::TvNetwork(_) => "tvnn",
        StandardTag::TvSeasonNumber(_) => "tvsn",
        StandardTag::TvSeriesTitle(_) => "tvsh",
        StandardTag::UrlPodcast(_) => "purl",
        StandardTag::Work(_) => "©wrk",
        StandardTag::Writer(_) => "©wrt",
        _ => return None,
    };

    Some(atom.to_string())
}
