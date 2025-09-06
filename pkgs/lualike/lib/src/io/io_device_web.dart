library;

/// Web stubs for IO devices.
///
/// On the web platform, file system and process I/O are not available.
/// These stub implementations satisfy the interfaces used by the stdlib
/// so code can compile; operations either no-op or return errors.
import 'dart:async';

import 'package:lualike/lualike.dart';

import 'io_device_shared.dart';
import 'lua_file.dart';

/// Stub file device for web (no real filesystem).
class FileIODevice extends BaseIODevice {
  FileIODevice._(super.mode);

  static Future<FileIODevice> open(String path, String mode) async {
    throw LuaError('file I/O not supported on web');
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  @override
  Future<ReadResult> read([String format = 'l']) async {
    return ReadResult(null, 'file I/O not supported on web');
  }

  @override
  Future<WriteResult> write(String data) async {
    return WriteResult(false, 'file I/O not supported on web');
  }

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async {
    return WriteResult(false, 'file I/O not supported on web');
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    throw UnsupportedError('file I/O not supported on web');
  }

  @override
  Future<int> getPosition() async => 0;

  @override
  Future<bool> isEOF() async => true;
}

/// Stub stdin device for web.
class StdinDevice extends BaseIODevice {
  StdinDevice() : super('r');

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  @override
  Future<ReadResult> read([String format = 'l']) async {
    return ReadResult(null, 'stdin not supported on web');
  }

  @override
  Future<WriteResult> write(String data) async {
    return WriteResult(false, 'Cannot write to stdin', 9);
  }

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async {
    return WriteResult(false, 'Cannot write to stdin', 9);
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    throw UnsupportedError('Cannot seek in stdin');
  }

  @override
  Future<int> getPosition() async {
    throw UnsupportedError('Cannot get position in stdin');
  }

  @override
  Future<bool> isEOF() async => true;
}

/// Stub stdout/stderr device for web. Writes are accepted and ignored.
class StdoutDevice extends BaseIODevice {
  // ignore: unused_field
  final dynamic _sink; // ignored on web
  // ignore: unused_field
  final bool _allowFlush; // ignored on web

  StdoutDevice([this._sink, bool? allowFlush])
    : _allowFlush = allowFlush ?? true,
      super('w');

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  @override
  Future<ReadResult> read([String format = 'l']) async {
    return ReadResult(null, 'Cannot read from stdout');
  }

  @override
  Future<WriteResult> write(String data) async {
    // No-op on web, pretend success to keep program flow.
    return WriteResult(true);
  }

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async {
    return WriteResult(true);
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    throw UnsupportedError('Cannot seek in stdout');
  }

  @override
  Future<int> getPosition() async {
    throw UnsupportedError('Cannot get position in stdout');
  }

  @override
  Future<bool> isEOF() async => false;
}

/// Stub process-backed IO device for io.popen on web.
class ProcessIODevice extends BaseIODevice {
  ProcessIODevice._(super.mode);

  static Future<ProcessIODevice> start(String command, String mode) async {
    throw LuaError('popen not supported on web');
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  @override
  Future<ReadResult> read([String format = 'l']) async {
    return ReadResult(null, 'popen not supported on web');
  }

  @override
  Future<WriteResult> write(String data) async {
    return WriteResult(false, 'popen not supported on web');
  }

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async {
    return WriteResult(false, 'popen not supported on web');
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    throw UnsupportedError('Cannot seek in a pipe');
  }

  @override
  Future<int> getPosition() async => 0;

  @override
  Future<bool> isEOF() async => true;

  Future<List<Object?>> finalizeStatus() async => [
    false,
    'error',
    'popen not supported on web',
  ];
}

/// Stub LuaFile for popen handles on web (never actually created).
class PopenLuaFile extends LuaFile {
  PopenLuaFile(super.device);

  @override
  Future<List<Object?>> close() async {
    // On web, popen is unsupported; return an error triple.
    return [null, 'popen not supported on web'];
  }
}
