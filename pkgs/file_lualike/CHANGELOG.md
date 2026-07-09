## 0.1.2

- Re-export `CompositeFileSystemBackend` from `package:lualike` for
  convenience when building layered filesystem backends.

## 0.1.1

- `useFileSystem()` now wires the configured `FileSystemProvider` into lualike's
  `IOLib.fileSystemProvider`, fixing `io.open()` so it routes to the remote
  filesystem (SFTP, memory, etc.) instead of local `dart:io`.
- Bump `lualike` dependency to `^0.2.4`.

## 0.1.0

- Initial release.
- `PackageFileIODevice` — bridge any `package:file` `File` into lualike's `IODevice` interface.
- `PackageFileSystemBackend` — bridge any `package:file` `FileSystem` into lualike's `FileSystemBackend` metadata interface.
- `useFileSystem()` — one-call setup wiring both adapters into the lualike runtime.
- Supports local, in-memory (`MemoryFileSystem`), SFTP (`file_sftp`), and custom `package:file` filesystems.
