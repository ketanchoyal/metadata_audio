use symphonia::core::formats::FormatReader;
use symphonia::core::meta::{MetadataRevision, StandardTag, StandardVisualKey, Visual};

use crate::api::FfiPicture;

pub fn extract_pictures(format: &mut dyn FormatReader) -> Vec<FfiPicture> {
    let mut metadata = format.metadata();
    let mut pictures = Vec::new();

    while let Some(revision) = metadata.current() {
        pictures.extend(extract_revision_pictures(revision));

        if metadata.pop().is_none() {
            break;
        }
    }

    pictures
}

fn extract_revision_pictures(revision: &MetadataRevision) -> Vec<FfiPicture> {
    let mut pictures = Vec::new();

    pictures.extend(revision.media.visuals.iter().map(visual_to_ffi_picture));

    for per_track in &revision.per_track {
        pictures.extend(per_track.metadata.visuals.iter().map(visual_to_ffi_picture));
    }

    pictures
}

fn visual_to_ffi_picture(visual: &Visual) -> FfiPicture {
    FfiPicture {
        format: visual.media_type.clone(),
        data: visual.data.to_vec(),
        description: visual_description(visual),
        r#type: visual.usage.map(visual_usage_to_string),
        name: None,
    }
}

fn visual_description(visual: &Visual) -> Option<String> {
    visual.tags.iter().find_map(|tag| match &tag.std {
        Some(StandardTag::Description(value)) => Some(value.to_string()),
        _ => None,
    })
}

fn visual_usage_to_string(usage: StandardVisualKey) -> String {
    match usage {
        StandardVisualKey::FileIcon => "32x32 pixels 'file icon' (PNG only)",
        StandardVisualKey::OtherIcon => "Other file icon",
        StandardVisualKey::FrontCover => "Cover (front)",
        StandardVisualKey::BackCover => "Cover (back)",
        StandardVisualKey::Leaflet => "Leaflet page",
        StandardVisualKey::Media => "Media (e.g. label side of CD)",
        StandardVisualKey::LeadArtistPerformerSoloist => "Lead artist/lead performer/soloist",
        StandardVisualKey::ArtistPerformer => "Artist/performer",
        StandardVisualKey::Conductor => "Conductor",
        StandardVisualKey::BandOrchestra => "Band/Orchestra",
        StandardVisualKey::Composer => "Composer",
        StandardVisualKey::Lyricist => "Lyricist/text writer",
        StandardVisualKey::RecordingLocation => "Recording Location",
        StandardVisualKey::RecordingSession => "During recording",
        StandardVisualKey::Performance => "During performance",
        StandardVisualKey::ScreenCapture => "Movie/video screen capture",
        StandardVisualKey::Illustration => "Illustration",
        StandardVisualKey::BandArtistLogo => "Band/artist logotype",
        StandardVisualKey::PublisherStudioLogo => "Publisher/Studio logotype",
        StandardVisualKey::Other => "Other",
        _ => "Other",
    }
    .to_string()
}
