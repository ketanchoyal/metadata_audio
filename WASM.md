# WASM support

This package has experimental WASM/web registration.

## Build

```bash
cargo build --manifest-path rust/Cargo.toml --target wasm32-unknown-unknown
```

## Current limitations

- No filesystem access in WASM
- `parse_from_path` does not work on web
- `parse_from_bytes` works through the generated WASM bindings
- `parseUrl()` is available on web via the Dart HTTP tokenizers (subject to CORS / range support)

## Future work

- wasm-pack integration
- Web bundling and packaging
- Web-specific I/O adapters
