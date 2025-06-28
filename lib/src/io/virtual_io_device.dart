import 'dart:convert';
import 'dart:typed_data';

import 'package:lualike/lualike.dart';

import 'io_device.dart';

/// A virtual IO device that operates on a string buffer.
/// Useful for testing and REPL mode.
class VirtualIODevice extends BaseIODevice {
  final StringBuffer _buffer = StringBuffer();
  int _position = 0;
  final bool _isReadOnly;
  final bool _isWriteOnly;

  VirtualIODevice([String? initialContent])
    : _isReadOnly = initialContent == null || initialContent.startsWith('r'),
      _isWriteOnly = initialContent == null || initialContent.startsWith('w'),
      super(initialContent ?? 'r+') {
    if (initialContent != null) {
      Logger.debug('Initializing virtual device with content: $initialContent');
      _buffer.write(initialContent);
    }
  }

  String get content => _buffer.toString();

  @override
  Future<void> close() async {
    Logger.debug('Closing virtual device');
    checkOpen();
    isClosed = true;
  }

  @override
  Future<bool> isEOF() async {
    Logger.debug('Checking EOF at position $_position');
    checkOpen();
    return _position >= _buffer.toString().length;
  }

  @override
  Future<ReadResult> read([String format = 'a']) async {
    Logger.debug("Reading from virtual device with format: $format");
    checkOpen();
    validateReadFormat(format);

    final content = _buffer.toString();
    if (_position >= content.length) {
      Logger.debug('Read position beyond content length, returning null');
      return ReadResult(null);
    }

    String result;
    if (format == 'n') {
      // Read a number
      final match = RegExp(r'-?\d+\.?\d*').matchAsPrefix(content, _position);
      if (match == null) {
        Logger.debug('No number found at current position');
        return ReadResult(null);
      }
      result = match.group(0)!;
      _position = match.end;
      Logger.debug('Read number: $result');
    } else if (format == 'a') {
      // Read all remaining content
      result = content.substring(_position);
      _position = content.length;
      Logger.debug('Read all remaining content: $result');
    } else if (format == 'l' || format == 'L') {
      // Read line
      final newlineIndex = content.indexOf('\n', _position);
      if (newlineIndex == -1) {
        if (_position >= content.length) {
          Logger.debug('No more lines to read');
          return ReadResult(null);
        }
        result = content.substring(_position);
        _position = content.length;
      } else {
        result = content.substring(
          _position,
          newlineIndex + (format == 'L' ? 1 : 0),
        );
        _position = newlineIndex + 1;
      }
      Logger.debug('Read line: $result');
    } else {
      // Read n bytes
      final n = int.parse(format);
      if (_position + n > content.length) {
        Logger.debug('Not enough bytes left to read');
        return ReadResult(null);
      }
      result = content.substring(_position, _position + n);
      _position += n;
      Logger.debug('Read $n bytes: $result');
    }

    return ReadResult(result);
  }

  @override
  Future<WriteResult> write(Object? data) async {
    Logger.debug('Writing to virtual device: $data');
    checkOpen();

    if (data == null) {
      Logger.debug('Write data is null, returning');
      return WriteResult(true);
    }

    String str;
    if (data is List<int>) {
      str = utf8.decode(data);
    } else if (data is ByteData) {
      str = utf8.decode(data.buffer.asUint8List());
    } else {
      str = data.toString();
    }

    Logger.debug('Converted data to string: $str');
    _buffer.write(str);
    return WriteResult(true);
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    Logger.debug('Seeking with whence: $whence, offset: $offset');
    checkOpen();

    final length = _buffer.toString().length;
    switch (whence) {
      case SeekWhence.set:
        _position = offset;
        break;
      case SeekWhence.cur:
        _position += offset;
        break;
      case SeekWhence.end:
        _position = length + offset;
        break;
    }

    // Clamp position to valid range
    _position = _position.clamp(0, length);
    Logger.debug('New position after seek: $_position');
    return _position;
  }

  @override
  Future<int> getPosition() async {
    Logger.debug('Getting current position: $_position');
    checkOpen();
    return _position;
  }

  @override
  Future<void> flush() async {
    Logger.debug('Flushing virtual device');
    checkOpen();
    // No-op for virtual device
  }
}
