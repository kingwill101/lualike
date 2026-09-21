/// One-call setup for bridging a [package:file] [FileSystem] into lualike.
///
/// {@category Configuration}
library;

import 'package:file/file.dart' as pkg_file;
import 'package:lualike/lualike.dart';

import 'package_file_io_device.dart';
import 'package_file_system_backend.dart';

/// Configures lualike to use [fs] as its filesystem backend for all file
/// operations. Supply [interpreter] to isolate this filesystem to one runtime.
///
/// Wires three integration points with a single call:
///   1. [setFileSystemProvider] — so `io.open()`, `io.lines()`, etc. create
///      [PackageFileIODevice] instances backed by [fs].
///   2. [FileSystemProvider] — the provider instance itself is configured with
///      the [PackageFileIODevice] factory.
///   3. [setFileSystemBackend] — so metadata operations (`os.remove()`,
///      `dofile()`, module loading, etc.) delegate to [fs].
///
/// Use [interpreter] when multiple Lua runtimes need separate filesystems.
/// [provider] can be supplied to retain and configure a specific IO provider.
///
/// ```dart
/// import 'package:file_lualike/file_lualike.dart';
/// import 'package:file_sftp/file_sftp.dart';
///
/// final sftp = SftpFileSystem(SftpConfig(
///   host: 'example.com',
///   username: 'alice',
///   password: 'secret',
///   root: '/home/alice/project',
/// ));
///
/// await useFileSystem(sftp);
/// ```
Future<void> useFileSystem(
  pkg_file.FileSystem fs, {
  FileSystemProvider? provider,
  LuaRuntime? interpreter,
}) async {
  final target = provider ?? FileSystemProvider();
  target.setIODeviceFactory(
    (path, mode) => PackageFileIODevice.open(fs, path, mode),
    providerName: fs.runtimeType.toString(),
  );

  setFileSystemProvider(target, interpreter: interpreter);

  setFileSystemBackend(PackageFileSystemBackend(fs), interpreter: interpreter);
}
