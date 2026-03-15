# Contributing to audio_metadata

Thank you for your interest in contributing! This document outlines the process and guidelines.

## Getting Started

### Fork and Branch

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/audio-metadata.git
   cd audio-metadata
   ```
3. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

### Development Setup

1. Install Dart SDK (3.10.7 or higher): https://dart.dev/get-dart
2. Install dependencies:
   ```bash
   dart pub get
   ```
3. Verify setup:
   ```bash
   dart test
   ```

## Code Style

This project follows Dart conventions:
- Use trailing commas for multi-line function signatures
- Follow linting rules in `analysis_options.yaml`
- Run before committing:
  ```bash
  dart format lib/ test/
  dart analyze
  ```

## Test-Driven Development (TDD)

This project follows TDD principles:

1. Write tests first for all new functionality
2. Test organization:
   - Unit tests: `test/core/`, `test/formats/`
   - Integration tests: `test/regression/`
   - Streaming tests: `test/streaming/`
3. Test naming:
   ```dart
   test('should parse MP3 with ID3v2 tags', () {});
   ```
4. Run tests:
   ```bash
   dart test
   ```

## Commit Guidelines

- Use clear, descriptive commit messages
- Start with a verb: "Add", "Fix", "Refactor", "Update"
- Reference issues: "Fixes #123"
- Keep commits atomic

Examples:
```
Add ID3v2.4 frame parsing
Fix encoding detection in FLAC parser
Refactor vorbis comment parsing
```

## Pull Request Process

1. Ensure CI passes
2. Push to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```
3. Create PR with:
   - Clear title
   - Description referencing issues
   - List of changes

### PR Checklist

- [ ] Tests added/updated
- [ ] All tests pass (`dart test`)
- [ ] Code analysis passes (`dart analyze`)
- [ ] Code formatted (`dart format`)
- [ ] Documentation updated if needed
- [ ] Commit messages are clear

## Reporting Issues

- Use GitHub Issues for bugs and feature requests
- Provide reproduction steps
- Include environment details (Dart SDK version, OS)

---

Thank you for contributing! 🎵
