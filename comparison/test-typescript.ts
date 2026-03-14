import * as mm from 'music-metadata';
import * as path from 'path';
import * as fs from 'fs';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const samplesDir = path.join(__dirname, '..', 'test', 'samples');

interface TestResult {
  file: string;
  format: {
    container: string | undefined;
    codec: string | undefined;
    duration: number | undefined;
    sampleRate: number | undefined;
    numberOfChannels: number | undefined;
    bitrate: number | undefined;
  };
  common: {
    title: string | undefined;
    artist: string | undefined;
    album: string | undefined;
    year: number | undefined;
    track: { no: number | null; of: number | null } | undefined;
    genre: string[] | undefined;
  };
  native: string[];
}

async function parseFile(relativePath: string): Promise<TestResult | null> {
  const filePath = path.join(samplesDir, relativePath);
  
  if (!fs.existsSync(filePath)) {
    console.log(`SKIP: ${relativePath} (not found)`);
    return null;
  }
  
  try {
    const metadata = await mm.parseFile(filePath);
    
    return {
      file: relativePath,
      format: {
        container: metadata.format.container,
        codec: metadata.format.codec,
        duration: metadata.format.duration,
        sampleRate: metadata.format.sampleRate,
        numberOfChannels: metadata.format.numberOfChannels,
        bitrate: metadata.format.bitrate,
      },
      common: {
        title: metadata.common.title,
        artist: metadata.common.artist,
        album: metadata.common.album,
        year: metadata.common.year,
        track: metadata.common.track,
        genre: metadata.common.genre,
      },
      native: Object.keys(metadata.native),
    };
  } catch (error) {
    console.error(`ERROR parsing ${relativePath}:`, error);
    return null;
  }
}

async function main() {
  console.log('='.repeat(60));
  console.log('TypeScript music-metadata Comparison Test');
  console.log('='.repeat(60));
  console.log();

  const testFiles = [
    // MP3
    'mp3/id3v2.3.mp3',
    'mp3/id3v1.mp3',
    'mp3/no-tags.mp3',
    'mp3/issue-347.mp3',
    'mp3/adts-0-frame.mp3',
    // FLAC
    'flac/sample.flac',
    'flac/flac-multiple-album-artists-tags.flac',
    'flac/testcase.flac',
    // OGG
    'ogg/vorbis.ogg',
    'ogg/opus.ogg',
    // MP4
    'mp4/sample.m4a',
    // WAV
    'wav/issue-819.wav',
    'wav/odd-list-type.wav',
    // AIFF
    'aiff/sample.aiff',
  ];

  const results: TestResult[] = [];

  for (const file of testFiles) {
    const result = await parseFile(file);
    if (result) {
      results.push(result);
      console.log(`✓ ${file}`);
      console.log(`  Format: ${result.format.container} / ${result.format.codec}`);
      if (result.common.title) {
        console.log(`  Title: ${result.common.title}`);
      }
      if (result.common.artist) {
        console.log(`  Artist: ${result.common.artist}`);
      }
      console.log();
    }
  }

  console.log('='.repeat(60));
  console.log(`Parsed ${results.length}/${testFiles.length} files successfully`);
  console.log('='.repeat(60));
  
  // Output full JSON for comparison
  console.log('\nFull JSON Output:\n');
  console.log(JSON.stringify(results, null, 2));
}

main().catch(console.error);
