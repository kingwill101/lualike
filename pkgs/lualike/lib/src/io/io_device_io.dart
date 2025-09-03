import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path_lib;

import 'package:lualike/lualike.dart';

import 'io_device.dart';

/// Implementation for real files using dart:io
class FileIODevice extends BaseIODevice {
  RandomAccessFile? _file;

  FileIODevice._(RandomAccessFile file, String mode) : super(mode) {
    _file = file;
    Logger.debug('Created FileIODevice with mode: $mode', category: 'IO');
  }

  static Future<FileIODevice> open(String path, String mode) async {
    // Normalize the path to handle mixed separators, ".." segments, etc.
    final normalizedPath = path_lib.normalize(path);
    Logger.debug(
      'Opening file: $normalizedPath with mode: $mode',
      category: 'IO',
    );
    FileMode fileMode;
    switch (mode) {
      case "r":
        fileMode = FileMode.read;
        break;
      case "w":
        fileMode = FileMode.write;
        break;
      case "a":
        fileMode = FileMode.append;
        break;
      case "r+":
        fileMode = FileMode.append;
        break;
      case "w+":
        fileMode = FileMode.writeOnly;
        break;
      case "a+":
        fileMode = FileMode.append;
        break;
      default:
        Logger.debug('Invalid file mode: $mode', category: 'IO');
        throw LuaError("Invalid file mode: $mode");
    }

    try {
      Logger.debug('Attempting to open file: $normalizedPath', category: 'IO');
      // Ensure the directory exists when writing
      if (fileMode == FileMode.write ||
          fileMode == FileMode.writeOnly ||
          fileMode == FileMode.writeOnlyAppend ||
          fileMode == FileMode.append) {
        final dir = Directory(path_lib.dirname(normalizedPath));
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }
      final file = await File(normalizedPath).open(mode: fileMode);
      Logger.debug('Successfully opened file: $normalizedPath', category: 'IO');
      return FileIODevice._(file, mode);
    } catch (e, s) {
      Logger.debug(
        'Failed to open file: $normalizedPath, error: $e',
        category: 'IO',
      );
      throw LuaError("Could not open file: $e", stackTrace: s);
    }
  }

  @override
  Future<void> close() async {
    Logger.debug('Closing file', category: 'IO');
    if (!isClosed && _file != null) {
      await _file!.close();
      _file = null;
      isClosed = true;
      Logger.debug('File closed successfully', category: 'IO');
    } else {
      Logger.debug('File already closed or null', category: 'IO');
    }
  }

  @override
  Future<void> flush() async {
    Logger.debug('Flushing file', category: 'IO');
    checkOpen();
    await _file?.flush();
    Logger.debug('File flushed successfully', category: 'IO');
  }

  @override
  Future<ReadResult> read([String format = "l"]) async {
    Logger.debug('Reading file with format: $format', category: 'IO');
    checkOpen();
    validateReadFormat(format);

    try {
      if (format == "a") {
        // Read entire file
        Logger.debug('Reading entire file', category: 'IO');
        final length = await _file!.length();
        Logger.debug('File length: $length bytes', category: 'IO');
        final bytes = await _file!.read(length);
        Logger.debug('Read ${bytes.length} bytes from file', category: 'IO');
        final result = utf8.decode(bytes);
        Logger.debug('Decoded ${result.length} characters', category: 'IO');
        return ReadResult(result);
      } else if (format == "l" || format == "L") {
        // Read line
        Logger.debug('Reading line from file', category: 'IO');
        final buffer = <int>[];
        int byte;
        while ((byte = await _file!.readByte()) != -1) {
          if (byte == 10) {
            // \n
            Logger.debug('Found newline character', category: 'IO');
            if (format == "L") buffer.add(byte);
            break;
          }
          buffer.add(byte);
        }
        Logger.debug('Read ${buffer.length} bytes for line', category: 'IO');
        if (buffer.isEmpty) {
          Logger.debug('Read empty line (EOF)', category: 'IO');
          return ReadResult(null);
        }
        final result = utf8.decode(buffer);
        Logger.debug('Decoded line: "$result"', category: 'IO');
        return ReadResult(result);
      } else if (format == "n") {
        // Read number
        Logger.debug('Reading number from file', category: 'IO');
        final line = await read("l");
        if (!line.isSuccess || line.value == null) {
          Logger.debug('Failed to read line for number', category: 'IO');
          return line;
        }
        Logger.debug('Parsing "${line.value}" as number', category: 'IO');
        final number = num.tryParse(line.value as String);
        if (number == null) {
          Logger.debug('Failed to parse as number', category: 'IO');
        } else {
          Logger.debug('Parsed number: $number', category: 'IO');
        }
        return ReadResult(number);
      } else {
        // Read n bytes
        final n = int.parse(format);
        Logger.debug('Reading $n bytes from file', category: 'IO');
        final bytes = await _file!.read(n);
        Logger.debug('Read ${bytes.length} bytes', category: 'IO');
        final result = utf8.decode(bytes);
        Logger.debug('Decoded ${result.length} characters', category: 'IO');
        return ReadResult(result);
      }
    } catch (e) {
      Logger.debug('Error reading from file: $e', category: 'IO');
      return ReadResult(null, e.toString());
    }
  }

  @override
  Future<WriteResult> write(String data) async {
    Logger.debug(
      'Writing to file: "${data.length} characters"',
      category: 'IO',
    );
    checkOpen();
    try {
      final bytes = utf8.encode(data);
      Logger.debug('Encoded ${bytes.length} bytes to write', category: 'IO');
      await _file!.writeFrom(bytes);
      Logger.debug('Successfully wrote ${bytes.length} bytes', category: 'IO');
      return WriteResult(true);
    } catch (e) {
      Logger.debug('Error writing to file: $e', category: 'IO');
      return WriteResult(false, e.toString());
    }
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    Logger.debug(
      'Seeking in file: whence=$whence, offset=$offset',
      category: 'IO',
    );
    checkOpen();
    switch (whence) {
      case SeekWhence.set:
        Logger.debug('Seeking to absolute position: $offset', category: 'IO');
        await _file!.setPosition(offset);
        final pos = await _file!.position();
        Logger.debug('New position: $pos', category: 'IO');
        return pos;
      case SeekWhence.cur:
        final currentPos = await _file!.position();
        Logger.debug('Current position: $currentPos', category: 'IO');
        final newPos = currentPos + offset;
        Logger.debug('Seeking to relative position: $newPos', category: 'IO');
        await _file!.setPosition(newPos);
        final pos = await _file!.position();
        Logger.debug('New position: $pos', category: 'IO');
        return pos;
      case SeekWhence.end:
        final length = await _file!.length();
        Logger.debug('File length: $length', category: 'IO');
        final newPos = length + offset;
        Logger.debug(
          'Seeking to end-relative position: $newPos',
          category: 'IO',
        );
        await _file!.setPosition(newPos);
        final pos = await _file!.position();
        Logger.debug('New position: $pos', category: 'IO');
        return pos;
    }
  }

  @override
  Future<int> getPosition() async {
    Logger.debug('Getting file position', category: 'IO');
    checkOpen();
    final pos = await _file!.position();
    Logger.debug('Current position: $pos', category: 'IO');
    return pos;
  }

  @override
  Future<bool> isEOF() async {
    Logger.debug('Checking if at EOF', category: 'IO');
    checkOpen();
    final currentPos = await _file!.position();
    final length = await _file!.length();
    final isEof = currentPos >= length;
    Logger.debug(
      'EOF check: pos=$currentPos, length=$length, EOF=$isEof',
      category: 'IO',
    );
    return isEof;
  }
}

/// Implementation for stdin
class StdinDevice extends BaseIODevice {
  StdinDevice() : super("r") {
    Logger.debug('Created StdinDevice', category: 'IO');
  }

  @override
  Future<void> close() async {
    Logger.debug('Closing StdinDevice', category: 'IO');
    isClosed = true;
    Logger.debug('StdinDevice closed', category: 'IO');
  }

  @override
  Future<void> flush() async {
    Logger.debug('Flush called on StdinDevice (no-op)', category: 'IO');
    // No-op for stdin
  }

  @override
  Future<ReadResult> read([String format = "l"]) async {
    Logger.debug('Reading from stdin with format: $format', category: 'IO');
    checkOpen();
    validateReadFormat(format);

    try {
      if (format == "l" || format == "L") {
        Logger.debug('Reading line from stdin', category: 'IO');
        final line = stdin.readLineSync(encoding: utf8);
        if (line == null) {
          Logger.debug('Read null line from stdin (EOF)', category: 'IO');
          return ReadResult(null);
        }
        final result = format == "L" ? "$line\n" : line;
        Logger.debug('Read line from stdin: "$result"', category: 'IO');
        return ReadResult(result);
      } else if (format == "a") {
        // Read until EOF
        Logger.debug(
          'Reading all content from stdin until EOF',
          category: 'IO',
        );
        final buffer = StringBuffer();
        String? line;
        int lineCount = 0;
        while ((line = stdin.readLineSync(encoding: utf8)) != null) {
          buffer.writeln(line);
          lineCount++;
        }
        Logger.debug('Read $lineCount lines from stdin', category: 'IO');
        final result = buffer.toString();
        Logger.debug(
          'Read ${result.length} characters from stdin',
          category: 'IO',
        );
        return ReadResult(result);
      } else if (format == "n") {
        Logger.debug('Reading number from stdin', category: 'IO');
        final line = await read("l");
        if (!line.isSuccess || line.value == null) {
          Logger.debug(
            'Failed to read line for number from stdin',
            category: 'IO',
          );
          return line;
        }
        final inputStr = line.value as String;
        Logger.debug('Parsing "$inputStr" as number', category: 'IO');
        final number = num.tryParse(inputStr);
        if (number == null) {
          Logger.debug('Failed to parse as number', category: 'IO');
        } else {
          Logger.debug('Parsed number: $number', category: 'IO');
        }
        return ReadResult(number);
      } else {
        throw LuaError("Unsupported format for stdin: $format");
      }
    } catch (e) {
      return ReadResult(null, e.toString());
    }
  }

  @override
  Future<WriteResult> write(String data) async {
    return WriteResult(false, "Cannot write to stdin");
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    throw UnsupportedError("Cannot seek in stdin");
  }

  @override
  Future<int> getPosition() async {
    throw UnsupportedError("Cannot get position in stdin");
  }

  @override
  Future<bool> isEOF() async {
    try {
      return stdin.readLineSync() == null;
    } catch (e) {
      return true; // If we can't read, treat as EOF
    }
  }
}

/// Stdout device using dart:io
class StdoutDevice extends BaseIODevice {
  final IOSink _sink;
  final bool _allowFlush;
  final Object _lock = Object();

  StdoutDevice([IOSink? sink, bool? allowFlush])
    : _sink = sink ?? stdout,
      _allowFlush = allowFlush ?? true,
      super("w") {
    Logger.debug('Created StdoutDevice', category: 'StdoutDevice');
  }

  @override
  Future<void> close() async {
    Logger.debug('Closing stdout', category: 'StdoutDevice');
    // Do not actually close stdout; keep it available for the entire
    // interpreter lifecycle.
  }

  @override
  Future<void> flush() async {
    checkOpen();
    if (_allowFlush) {
      synchronized(_lock, () async => await _sink.flush());
    }
  }

  @override
  Future<ReadResult> read([String format = "l"]) async {
    return ReadResult(null, "Cannot read from stdout");
  }

  @override
  Future<WriteResult> write(String data) async {
    checkOpen();
    try {
      Logger.debug('Writing to stdout: "$data"', category: 'StdoutDevice');

      // Synchronize the write and flush operations
      await synchronized(_lock, () async {
        _sink.write(data);
        if (_allowFlush) await _sink.flush();
      });

      Logger.debug('Write successful', category: 'StdoutDevice');
      return WriteResult(true);
    } catch (e) {
      Logger.error('Write failed: $e', error: 'LuaFile');
      return WriteResult(false, e.toString());
    }
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    Logger.debug('Seeking in stdout (ignored)', category: 'StdoutDevice');
    throw UnsupportedError("Cannot seek in stdout");
  }

  @override
  Future<int> getPosition() async {
    Logger.debug(
      'Getting position in stdout (always 0)',
      category: 'StdoutDevice',
    );
    throw UnsupportedError("Cannot get position in stdout");
  }

  @override
  Future<bool> isEOF() async {
    Logger.debug(
      'Checking if at EOF (always false for stdout)',
      category: 'StdoutDevice',
    );
    return false;
  }
}
