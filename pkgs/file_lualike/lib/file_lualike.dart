/// Adapters to bridge [package:file] `FileSystem` implementations into the
/// lualike scripting runtime.
///
/// Provides:
/// - [PackageFileIODevice] — opens a [package:file] `File` as a lualike
///   [IODevice], enabling `io.open()`, `io.lines()`, etc. over any
///   [package:file] `FileSystem` (SFTP, memory, local).
/// - [PackageFileSystemBackend] — implements [FileSystemBackend] using a
///   [package:file] `FileSystem`, enabling `os.remove()`, `dofile()`, module
///   loading, and other metadata operations.
/// - [useFileSystem] — one-call setup that wires both adapters into the
///   current lualike runtime.
library;

export 'src/config.dart';
export 'src/package_file_io_device.dart';
export 'src/package_file_system_backend.dart';
