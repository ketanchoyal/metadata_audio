#!/bin/bash
set -e

echo "============================================================"
echo "Comparing Dart vs TypeScript music-metadata output"
echo "============================================================"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Run TypeScript
echo "Running TypeScript music-metadata..."
cd "$SCRIPT_DIR"
npm run test:ts > output_ts.json 2>/dev/null || true

# Run Dart
echo "Running Dart audio_metadata..."
cd "$PROJECT_ROOT"
dart run tool/compare_metadata.dart > comparison/output_dart.json 2>/dev/null || true

cd "$SCRIPT_DIR"

# Compare
echo ""
echo "============================================================"
echo "DIFF RESULTS"
echo "============================================================"
echo ""

if diff -u output_ts.json output_dart.json > diff.txt 2>&1; then
  echo "✅ Outputs are IDENTICAL!"
  echo ""
  echo "Files:"
  echo "  - comparison/output_ts.json (TypeScript output)"
  echo "  - comparison/output_dart.json (Dart output)"
else
  echo "⚠️  Differences found:"
  echo ""
  cat diff.txt | head -100
  if [ $(wc -l < diff.txt) -gt 100 ]; then
    echo ""
    echo "... (truncated, full diff saved to diff.txt)"
  fi
  echo ""
  echo "Files:"
  echo "  - comparison/output_ts.json (TypeScript output)"
  echo "  - comparison/output_dart.json (Dart output)"
  echo "  - comparison/diff.txt (full differences)"
fi
