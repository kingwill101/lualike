/// Adapter that bridges a [package:file] [FileSystem] into lualike's
/// [IODevice] interface.
///
/// {@category IO}
library;

import 'dart:async';

import 'package:file/file.dart' as pkg_file;
import 'package:lualike/lualike.dart';

/// Adapts a [package:file] [File] into lualike's [IODevice] interface.
///
/// Works with any [pkg_file.FileSystem] implementation — local, SFTP,
/// in-memory, etc. Use [open] to create an instance from a filesystem, path,
/// and mode.
///
/// Implements buffered I/O with support for [BufferMode.none],
/// [BufferMode.full], and [BufferMode.line] buffering strategies. Pending
/// writes are flushed to the underlying [RandomAccessFile] before any read
/// operation, which is critical for remote filesystems like SFTP.
///
/// ```dart
/// final fs = SftpFileSystem(...);
/// final device = await PackageFileIODevice.open(fs, '/remote/file.txt', 'r');
/// ```
class PackageFileIODevice extends BaseIODevice {
  pkg_file.RandomAccessFile? _raf;
  final int _openMode; // bitfield: 1=read, 2=write, 4=append
  final List<int> _writeBuffer = <int>[];
  Future<void> _pendingOperation = Future<void>.value();
  bool _isClosed = false;

  PackageFileIODevice._(this._raf, this._openMode, String mode) : super(mode);

  /// Whether this device has been closed.
  ///
  /// Once closed, all subsequent read and write operations throw a [LuaError].
  @override
  bool get isClosed => _isClosed;

  // -- mode bitfield helpers ------------------------------------------------

  static const int _modeRead = 1;
  static const int _modeWrite = 2;
  static const int _modeAppend = 4;

  bool get _canRead => (_openMode & _modeRead) != 0;
  bool get _canWrite =>
      (_openMode & _modeWrite) != 0 || (_openMode & _modeAppend) != 0;

  // -- factory ---------------------------------------------------------------

  /// Opens a file on [fs] and returns a [PackageFileIODevice] configured for
  /// the given lualike [mode].
  ///
  /// Supported modes: `"r"`, `"w"`, `"a"`, `"r+"`, `"w+"`, `"a+"`. Append
  /// `"b"` to any mode for binary access (ignored; all I/O is binary).
  ///
  /// Automatically creates parent directories when opening a file for writing.
  static Future<PackageFileIODevice> open(
    pkg_file.FileSystem fs,
    String path,
    String mode,
  ) async {
    var effectiveMode = mode;
    if (effectiveMode.endsWith('b')) {
      effectiveMode = effectiveMode.substring(0, effectiveMode.length - 1);
    } else if (effectiveMode.contains('b')) {
      throw LuaError('invalid mode');
    }

    final openMode = _parseOpenMode(effectiveMode);
    final file = fs.file(path);

    if (_bitsCanWrite(openMode) || _bitsIsAppend(openMode)) {
      final dir = fs.directory(
        (fs.path.isAbsolute(path) ? fs.path.dirname(path) : '.').toString(),
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    pkg_file.RandomAccessFile? raf;
    if ((openMode & _modeRead) != 0 ||
        (openMode & _modeWrite) != 0 ||
        (openMode & _modeAppend) != 0) {
      // Determine the FileMode for opening
      final fileMode = _toFileMode(openMode);
      raf = await file.open(mode: fileMode);

      if (_bitsIsAppend(openMode)) {
        final len = await raf.length();
        await raf.setPosition(len);
      } else if (effectiveMode == 'r+') {
        await raf.setPosition(0);
      }
    }

    return PackageFileIODevice._(raf, openMode, mode);
  }

  static int _parseOpenMode(String mode) {
    switch (mode) {
      case 'r':
        return _modeRead;
      case 'w':
        return _modeWrite;
      case 'a':
        return _modeAppend;
      case 'r+':
        return _modeRead | _modeWrite;
      case 'w+':
        return _modeWrite | _modeRead;
      case 'a+':
        return _modeAppend | _modeRead;
      default:
        throw LuaError('invalid mode');
    }
  }

  static bool _bitsCanWrite(int bits) => (bits & _modeWrite) != 0;
  static bool _bitsIsAppend(int bits) => (bits & _modeAppend) != 0;

  static pkg_file.FileMode _toFileMode(int bits) {
    if ((bits & _modeWrite) != 0) {
      // For write modes, we use writeOnlyAppend to allow both read and write
      return pkg_file.FileMode.write;
    }
    if ((bits & _modeAppend) != 0) {
      return pkg_file.FileMode.append;
    }
    return pkg_file.FileMode.read;
  }

  // -- exclusive execution ---------------------------------------------------

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final next = _pendingOperation.then<T>(
      (_) => action(),
      onError: (_) => action(),
    );
    _pendingOperation = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }

  // -- IODevice interface ----------------------------------------------------

  /// Closes the underlying file handle.
  ///
  /// Flushes any buffered writes before closing. Subsequent operations on a
  /// closed device throw a [LuaError].
  @override
  Future<void> close() async {
    await _runExclusive(() async {
      if (!_isClosed && _raf != null) {
        if (_writeBuffer.isNotEmpty) {
          await _raf!.writeFrom(_writeBuffer);
          _writeBuffer.clear();
        }
        await _raf!.close();
        _raf = null;
        _isClosed = true;
      }
    });
  }

  /// Flushes buffered data to the underlying file.
  ///
  /// Writes any pending buffered bytes to the [RandomAccessFile], then
  /// delegates to the filesystem's native `flush()` call.
  @override
  Future<void> flush() async {
    await _runExclusive(() async {
      checkOpen();
      if (_writeBuffer.isNotEmpty) {
        final pending = _writeBuffer.toList();
        _writeBuffer.clear();
        await _raf!.writeFrom(pending);
      }
      try {
        await _raf?.flush();
      } catch (_) {}
    });
  }

  /// Reads data from the file according to [format].
  ///
  /// Supported formats:
  /// - `"a"` — read the entire file as a [LuaString].
  /// - `"l"` — read one line (without newline) as a [LuaString].
  /// - `"L"` — read one line (with newline) as a [LuaString].
  /// - `"n"` — read a number from the current position.
  /// - `"*"` followed by a number — read that many bytes.
  ///
  /// Returns [ReadResult.withValue] on success, or [ReadResult.withError] on
  /// failure (including end-of-file).
  ///
  /// Flushes pending writes before reading so the underlying
  /// [RandomAccessFile] sees all data. This is required for remote
  /// filesystems like SFTP that may buffer writes on the server side.
  @override
  Future<ReadResult> read([String format = 'l']) async {
    return _runExclusive(() async {
      checkOpen();
      validateReadFormat(format);

      if (!_canRead) {
        return ReadResult(null, 'Cannot read from write-only file', 9);
      }

      // Flush pending writes before reading so the underlying
      // RandomAccessFile sees all data (important for remote file systems
      // like SFTP, but also correct locally).
      if (_writeBuffer.isNotEmpty) {
        await _raf!.writeFrom(_writeBuffer);
        _writeBuffer.clear();
      }

      final normalizedFormat = normalizeReadFormat(format);

      try {
        if (normalizedFormat == 'a') {
          final length = await _raf!.length();
          final bytes = await _raf!.read(length);
          return ReadResult(LuaString.fromBytes(bytes));
        } else if (normalizedFormat == 'l' || normalizedFormat == 'L') {
          final buffer = <int>[];
          int byte;

          while ((byte = await _raf!.readByte()) != -1) {
            if (byte == 10) {
              if (normalizedFormat == 'L') buffer.add(byte);
              break;
            }
            buffer.add(byte);
          }

          if (buffer.isEmpty && byte == -1) {
            return ReadResult(null);
          }
          return ReadResult(LuaString.fromBytes(buffer));
        } else if (normalizedFormat == 'n') {
          final result = await _readNumber();
          return ReadResult(result);
        } else {
          final n = int.parse(normalizedFormat);
          if (n == 0) {
            final currentPos = await _raf!.position();
            final length = await _raf!.length();
            return currentPos >= length ? ReadResult(null) : ReadResult('');
          }

          final currentPos = await _raf!.position();
          final length = await _raf!.length();
          if (currentPos >= length) {
            return ReadResult(null);
          }

          final bytes = await _raf!.read(n);
          if (bytes.isEmpty) return ReadResult(null);
          return ReadResult(LuaString.fromBytes(bytes));
        }
      } catch (e) {
        return ReadResult(null, e.toString());
      }
    });
  }

  Future<Object?> _readNumber() async {
    final buffer = <int>[];
    bool hex = false;
    bool invalidNumber = false;
    const maxLenNum = 200;

    // Skip leading whitespace
    int lookAhead;
    do {
      lookAhead = await _raf!.readByte();
    } while (lookAhead != -1 && _isWhitespace(lookAhead));

    if (lookAhead == -1) return null;

    bool addChar(int byte) {
      if (buffer.length >= maxLenNum) {
        buffer.clear();
        invalidNumber = true;
        return false;
      }
      buffer.add(byte);
      return true;
    }

    if (lookAhead == 45 || lookAhead == 43) {
      if (!addChar(lookAhead)) return null;
      lookAhead = await _raf!.readByte();
    }

    if (lookAhead == 48) {
      if (!addChar(lookAhead)) return null;
      lookAhead = await _raf!.readByte();
      if (lookAhead == 120 || lookAhead == 88) {
        if (!addChar(lookAhead)) return null;
        lookAhead = await _raf!.readByte();
        hex = true;
      }
    }

    while (lookAhead != -1 &&
        (hex ? _isHexDigit(lookAhead) : _isDigit(lookAhead))) {
      if (!addChar(lookAhead)) break;
      lookAhead = await _raf!.readByte();
    }

    if (lookAhead == 46) {
      if (!addChar(lookAhead)) {
        invalidNumber = true;
      } else {
        lookAhead = await _raf!.readByte();
      }
      while (!invalidNumber &&
          lookAhead != -1 &&
          (hex ? _isHexDigit(lookAhead) : _isDigit(lookAhead))) {
        if (!addChar(lookAhead)) break;
        lookAhead = await _raf!.readByte();
      }
    }

    if (!invalidNumber &&
        (hex
            ? (lookAhead == 112 || lookAhead == 80)
            : (lookAhead == 101 || lookAhead == 69))) {
      if (!addChar(lookAhead)) {
        invalidNumber = true;
      } else {
        lookAhead = await _raf!.readByte();
      }
      if (!invalidNumber && (lookAhead == 45 || lookAhead == 43)) {
        if (!addChar(lookAhead)) {
          invalidNumber = true;
        } else {
          lookAhead = await _raf!.readByte();
        }
      }
      while (!invalidNumber && lookAhead != -1 && _isDigit(lookAhead)) {
        if (!addChar(lookAhead)) break;
        lookAhead = await _raf!.readByte();
      }
    }

    if (lookAhead != -1) {
      final currentPos = await _raf!.position();
      await _raf!.setPosition(currentPos - 1);
    }

    if (invalidNumber || buffer.isEmpty) return null;

    final numberStr = String.fromCharCodes(buffer);
    try {
      return LuaNumberParser.parse(numberStr);
    } catch (_) {
      return null;
    }
  }

  /// Writes [data] to the file.
  ///
  /// The write may be buffered depending on the current [BufferMode].
  /// Returns [WriteResult.withSuccess] on success, or
  /// [WriteResult.withError] if the device is not writable.
  ///
  /// Throws a [LuaError] if the device is closed.
  @override
  Future<WriteResult> write(String data) async {
    return _runExclusive(() async {
      checkOpen();
      if (!_canWrite) {
        return WriteResult(false, 'Cannot write to read-only file', 9);
      }
      try {
        final bytes = data.codeUnits;
        await _bufferedWrite(bytes);
        return WriteResult(true);
      } catch (e) {
        return WriteResult(false, e.toString(), 0);
      }
    });
  }

  /// Writes raw [bytes] to the file.
  ///
  /// Unlike [write], this method accepts a list of integer byte values
  /// directly. The write may be buffered depending on the current
  /// [BufferMode]. Returns [WriteResult.withSuccess] on success, or
  /// [WriteResult.withError] if the device is not writable.
  @override
  Future<WriteResult> writeBytes(List<int> bytes) async {
    return _runExclusive(() async {
      checkOpen();
      if (!_canWrite) {
        return WriteResult(false, 'Cannot write to read-only file', 9);
      }
      try {
        await _bufferedWrite(bytes);
        return WriteResult(true);
      } catch (e) {
        return WriteResult(false, e.toString(), 0);
      }
    });
  }

  Future<void> _bufferedWrite(List<int> bytes) async {
    switch (bufferMode) {
      case BufferMode.none:
        await _raf!.writeFrom(bytes);
        break;
      case BufferMode.full:
        _writeBuffer.addAll(bytes);
        if (_writeBuffer.length >= bufferSize) {
          await _raf!.writeFrom(_writeBuffer);
          _writeBuffer.clear();
        }
        break;
      case BufferMode.line:
        _writeBuffer.addAll(bytes);
        final idx = _writeBuffer.lastIndexOf(10);
        if (idx != -1) {
          final toFlush = _writeBuffer.sublist(0, idx + 1);
          await _raf!.writeFrom(toFlush);
          final remaining = _writeBuffer.sublist(idx + 1);
          _writeBuffer
            ..clear()
            ..addAll(remaining);
        }
        break;
    }
  }

  /// Seeks to a new position in the file.
  ///
  /// [whence] determines the reference point:
  /// - [SeekWhence.set] — relative to the beginning of the file.
  /// - [SeekWhence.cur] — relative to the current position.
  /// - [SeekWhence.end] — relative to the end of the file.
  ///
  /// Returns the new position (in bytes) from the beginning of the file.
  /// Flushes buffered writes before seeking.
  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    return _runExclusive(() async {
      checkOpen();
      if (bufferMode != BufferMode.none && _writeBuffer.isNotEmpty) {
        final pending = _writeBuffer.toList();
        _writeBuffer.clear();
        await _raf!.writeFrom(pending);
      }
      switch (whence) {
        case SeekWhence.set:
          await _raf!.setPosition(offset);
          return await _raf!.position();
        case SeekWhence.cur:
          final currentPos = await _raf!.position();
          await _raf!.setPosition(currentPos + offset);
          return await _raf!.position();
        case SeekWhence.end:
          final length = await _raf!.length();
          await _raf!.setPosition(length + offset);
          return await _raf!.position();
      }
    });
  }

  /// Returns the current read/write position in the file, in bytes from the
  /// beginning.
  ///
  /// Accounts for buffered-but-not-yet-flushed data by adding the buffer
  /// length to the underlying [RandomAccessFile] position.
  @override
  Future<int> getPosition() async {
    return _runExclusive(() async {
      checkOpen();
      var pos = await _raf!.position();
      if (bufferMode != BufferMode.none && _writeBuffer.isNotEmpty) {
        pos += _writeBuffer.length;
      }
      return pos;
    });
  }

  /// Whether the file position is at the end of the file.
  ///
  /// Peeks at the next byte without consuming it. Returns `true` if the
  /// current position is at or beyond the file length, or if the next byte
  /// read returns -1 (EOF).
  @override
  Future<bool> isEOF() async {
    return _runExclusive(() async {
      checkOpen();
      final currentPos = await _raf!.position();
      final length = await _raf!.length();
      if (currentPos >= length) return true;

      try {
        final savedPos = currentPos;
        final peekByte = await _raf!.readByte();
        await _raf!.setPosition(savedPos);
        return peekByte == -1;
      } catch (_) {
        return currentPos >= length;
      }
    });
  }

  // -- helpers ---------------------------------------------------------------

  static bool _isWhitespace(int byte) {
    return byte == 32 || byte == 9 || byte == 10 || byte == 13;
  }

  static bool _isDigit(int byte) => byte >= 48 && byte <= 57;

  static bool _isHexDigit(int byte) =>
      (byte >= 48 && byte <= 57) ||
      (byte >= 65 && byte <= 70) ||
      (byte >= 97 && byte <= 102);
}
