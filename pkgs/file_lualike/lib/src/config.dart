/// One-call setup for bridging a [package:file] [FileSystem] into lualike.
///
/// {@category Configuration}
library;

import 'package:file/file.dart' as pkg_file;
import 'package:lualike/lualike.dart';

import 'package_file_io_device.dart';
import 'package_file_system_backend.dart';

/// Configures the current lualike runtime to use [fs] as its filesystem
/// backend for all file operations.
///
/// Wires three integration points with a single call:
///   1. [setFileSystemProvider] — so `io.open()`, `io.lines()`, etc. create
///      [PackageFileIODevice] instances backed by [fs].
///   2. [FileSystemProvider] — the provider instance itself is configured with
///      the [PackageFileIODevice] factory.
///   3. [setFileSystemBackend] — so metadata operations (`os.remove()`,
///      `dofile()`, module loading, etc.) delegate to [fs].
///
/// Use [provider] to target a specific [FileSystemProvider] instead of the
/// global default. This is useful in testing or when multiple providers are
/// active.
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
}) async {
  final target = provider ?? FileSystemProvider();
  target.setIODeviceFactory(
    (path, mode) => PackageFileIODevice.open(fs, path, mode),
    providerName: fs.runtimeType.toString(),
  );

  setFileSystemProvider(target);

  setFileSystemBackend(PackageFileSystemBackend(fs));
}
