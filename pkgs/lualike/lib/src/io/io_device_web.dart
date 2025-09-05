import 'dart:async';
import 'package:lualike/lualike.dart';
import 'io_device_shared.dart';
import 'virtual_io_device.dart';

/// Web implementation for file operations - uses VirtualIODevice as fallback
class FileIODevice extends VirtualIODevice {
  FileIODevice._(String mode) : super(mode) {
    Logger.debug('Created FileIODevice (web) with mode: $mode', category: 'IO');
  }

  static Future<FileIODevice> open(String path, String mode) async {
    Logger.debug(
      'FileIODevice.open called on web - creating virtual device',
      category: 'IO',
    );
    // On web, we can't access real files, so we create a virtual device
    // This allows code to run without errors, though file operations won't persist
    return FileIODevice._(mode);
  }
}

/// Web implementation for stdin - uses VirtualIODevice
class StdinDevice extends VirtualIODevice {
  StdinDevice() : super("r") {
    Logger.debug('Created StdinDevice (web)', category: 'IO');
  }

  @override
  Future<ReadResult> read([String format = "l"]) async {
    Logger.debug(
      'StdinDevice.read called on web - no input available',
      category: 'IO',
    );
    // On web, stdin is not available, so return EOF immediately
    return ReadResult(null);
  }

  @override
  Future<bool> isEOF() async {
    Logger.debug(
      'StdinDevice.isEOF called on web - always EOF',
      category: 'IO',
    );
    return true; // Always EOF on web since there's no stdin
  }
}

/// Web-compatible stdout implementation using print
class StdoutDevice extends BaseIODevice {
  StdoutDevice([dynamic sink, bool? allowFlush]) : super("w") {
    Logger.debug('Created StdoutDevice (web)', category: 'StdoutDevice');
  }

  @override
  Future<void> close() async {
    Logger.debug('Closing stdout (web) - no-op', category: 'StdoutDevice');
    // Do not actually close stdout; keep it available for the entire
    // interpreter lifecycle.
  }

  @override
  Future<void> flush() async {
    checkOpen();
    Logger.debug('Flushing stdout (web) - no-op', category: 'StdoutDevice');
    // No explicit flush needed for print on web
  }

  @override
  Future<ReadResult> read([String format = "l"]) async {
    return ReadResult(null, "Cannot read from stdout");
  }

  @override
  Future<WriteResult> write(String data) async {
    checkOpen();
    try {
      Logger.debug(
        'Writing to stdout (web): "$data"',
        category: 'StdoutDevice',
      );
      print(data);
      Logger.debug('Write successful (web)', category: 'StdoutDevice');
      return WriteResult(true);
    } catch (e) {
      Logger.error('Write failed (web): $e', error: 'LuaFile');
      return WriteResult(false, e.toString());
    }
  }

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async {
    checkOpen();
    try {
      final str = String.fromCharCodes(bytes);
      Logger.debug(
        'Writing raw bytes to stdout (web): ${bytes.length}',
        category: 'StdoutDevice',
      );
      print(str);
      return WriteResult(true);
    } catch (e) {
      Logger.error('Raw write failed (web): $e', error: 'LuaFile');
      return WriteResult(false, e.toString());
    }
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    Logger.debug('Seeking in stdout (ignored) - web', category: 'StdoutDevice');
    throw UnsupportedError("Cannot seek in stdout");
  }

  @override
  Future<int> getPosition() async {
    Logger.debug(
      'Getting position in stdout (always 0) - web',
      category: 'StdoutDevice',
    );
    throw UnsupportedError("Cannot get position in stdout");
  }

  @override
  Future<bool> isEOF() async {
    Logger.debug(
      'Checking if at EOF (always false for stdout) - web',
      category: 'StdoutDevice',
    );
    return false;
  }
}
