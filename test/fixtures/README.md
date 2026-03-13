# Test Fixtures

This directory contains test fixtures for audio metadata parsing validation.

## Adding Fixtures

### Legal Considerations

Before adding fixture files:
1. Ensure files are public domain, CC0, or have explicit permission
2. Do NOT use copyrighted commercial music
3. Prefer generated test files or properly licensed samples

### Fixture Process

1. Create subdirectory for format: `test/fixtures/{format}/`
2. Add fixture with clear naming: `test/fixtures/{format}/{description}.{ext}`
3. Update manifest in `test/fixtures/MANIFEST.json`:
   ```json
   {
     "format": "MP3",
     "file": "mp3/id3v2-4-with-artwork.mp3",
     "description": "MP3 with ID3v2.4 tags",
     "source": "Generated test file",
     "license": "CC0",
     "characteristics": ["ID3v2.4", "artwork"]
   }
   ```

## Manifest Fields

| Field | Required | Description |
|-------|----------|-------------|
| format | yes | Audio format (MP3, FLAC, OGG, etc.) |
| file | yes | Relative path from test/fixtures/ |
| description | yes | Human-readable description |
| source | yes | Where fixture came from |
| license | yes | License type (CC0, MIT, Generated) |
| characteristics | no | Array of special properties |

## Guidelines

- Keep fixtures under 1MB
- Cover edge cases: empty tags, special characters, encoding issues
- Include legacy formats (ID3v1, ID3v2.2) and modern standards

## Organization

```
test/fixtures/
├── MANIFEST.json
├── README.md
├── mp3/
├── flac/
└── ogg/
```

---

See main [CONTRIBUTING.md](../../CONTRIBUTING.md) for TDD approach.
