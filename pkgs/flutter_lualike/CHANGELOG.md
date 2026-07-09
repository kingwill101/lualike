## 0.1.0

- Initial release.
- `AssetBundleFileSystemBackend` — `FileSystemBackend` backed by `AssetBundle` + `AssetManifest`.
- `AssetBundleIODevice` — read-only `IODevice` for `io.open()` from Flutter assets.
- `useAssetBundle()` — one-call setup wiring both integration points into the lualike runtime.
- `CompositeFileSystemBackend` for layering `AssetBundle` with local filesystem fallback.
- Support for `dofile()`, `require()`, `io.open()`, and module loading from Flutter assets.
