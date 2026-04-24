# WASM support

This package has experimental WASM/web registration.

## Build

```bash
cargo build --manifest-path rust/Cargo.toml --target wasm32-unknown-unknown
```

## Current limitations

- No filesystem access in WASM
- `parse_from_path` does not work on web
- `parse_from_bytes` is the only supported parsing path for now

## Future work

- wasm-pack integration
- Web bundling and packaging
- Web-specific I/O adapters
