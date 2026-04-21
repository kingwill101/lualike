// ignore_for_file: implementation_imports

import 'dart:convert';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/io/io_device.dart';

/// Shared read-only byte-backed device used for bundled assets and mounted
/// virtual filesystem entries.
class LoveReadonlyBytesIODevice extends BaseIODevice {
  LoveReadonlyBytesIODevice(List<int> bytes)
    : _bytes = List<int>.unmodifiable(bytes),
      super('r') {
    isClosed = false;
  }

  final List<int> _bytes;
  int _position = 0;

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  Future<void> flush() async {
    checkOpen();
  }

  @override
  Future<ReadResult> read([String format = 'l']) async {
    checkOpen();
    validateReadFormat(format);

    final normalizedFormat = normalizeReadFormat(format);
    try {
      return switch (normalizedFormat) {
        'a' => ReadResult(_readRemainingBytes()),
        'l' => ReadResult(_readLineBytes(includeLineTerminator: false)),
        'L' => ReadResult(_readLineBytes(includeLineTerminator: true)),
        'n' => ReadResult(_readNumber()),
        _ => ReadResult(_readFixedBytes(int.parse(normalizedFormat))),
      };
    } catch (error) {
      return ReadResult(null, error.toString());
    }
  }

  @override
  Future<WriteResult> write(String data) async {
    checkOpen();
    return WriteResult(false, 'File not open for writing');
  }

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async {
    checkOpen();
    return WriteResult(false, 'File not open for writing');
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    checkOpen();

    switch (whence) {
      case SeekWhence.set:
        _position = offset.clamp(0, _bytes.length);
      case SeekWhence.cur:
        _position = (_position + offset).clamp(0, _bytes.length);
      case SeekWhence.end:
        _position = (_bytes.length + offset).clamp(0, _bytes.length);
    }

    return _position;
  }

  @override
  Future<int> getPosition() async {
    checkOpen();
    return _position;
  }

  @override
  Future<bool> isEOF() async {
    checkOpen();
    return _position >= _bytes.length;
  }

  List<int> _readRemainingBytes() {
    if (_position >= _bytes.length) {
      return const <int>[];
    }

    final remaining = _bytes.sublist(_position);
    _position = _bytes.length;
    return remaining;
  }

  List<int>? _readLineBytes({required bool includeLineTerminator}) {
    if (_position >= _bytes.length) {
      return null;
    }

    final start = _position;
    var end = start;
    while (end < _bytes.length && _bytes[end] != 10) {
      end++;
    }

    final hadNewline = end < _bytes.length;
    _position = hadNewline ? end + 1 : _bytes.length;

    final resultEnd = includeLineTerminator ? _position : end;
    return _bytes.sublist(start, resultEnd);
  }

  num? _readNumber() {
    final buffer = <int>[];
    var count = 0;
    var hex = false;
    var invalidNumber = false;
    const maxLenNum = 200;

    var lookAhead = _readByte();
    while (lookAhead != -1 && _isWhitespace(lookAhead)) {
      lookAhead = _readByte();
    }

    if (lookAhead == -1) {
      return null;
    }

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
      if (!addChar(lookAhead)) {
        _unreadByte();
        return null;
      }
      lookAhead = _readByte();
    }

    if (lookAhead == 48) {
      if (!addChar(lookAhead)) {
        _unreadByte();
        return null;
      }
      lookAhead = _readByte();
      if (lookAhead == 120 || lookAhead == 88) {
        if (!addChar(lookAhead)) {
          _unreadByte();
          return null;
        }
        lookAhead = _readByte();
        hex = true;
      } else {
        count = 1;
      }
    }

    while (lookAhead != -1 &&
        (hex ? _isHexDigit(lookAhead) : _isDigit(lookAhead))) {
      if (!addChar(lookAhead)) {
        break;
      }
      lookAhead = _readByte();
      count++;
    }

    if (lookAhead == 46) {
      if (!addChar(lookAhead)) {
        invalidNumber = true;
      } else {
        lookAhead = _readByte();
      }

      while (!invalidNumber &&
          lookAhead != -1 &&
          (hex ? _isHexDigit(lookAhead) : _isDigit(lookAhead))) {
        if (!addChar(lookAhead)) {
          break;
        }
        lookAhead = _readByte();
        count++;
      }
    }

    if (!invalidNumber &&
        count > 0 &&
        (hex
            ? (lookAhead == 112 || lookAhead == 80)
            : (lookAhead == 101 || lookAhead == 69))) {
      if (!addChar(lookAhead)) {
        invalidNumber = true;
      } else {
        lookAhead = _readByte();
      }

      if (!invalidNumber && (lookAhead == 45 || lookAhead == 43)) {
        if (!addChar(lookAhead)) {
          invalidNumber = true;
        } else {
          lookAhead = _readByte();
        }
      }

      while (!invalidNumber && lookAhead != -1 && _isDigit(lookAhead)) {
        if (!addChar(lookAhead)) {
          break;
        }
        lookAhead = _readByte();
      }
    }

    if (lookAhead != -1) {
      _unreadByte();
    }

    if (invalidNumber || buffer.isEmpty) {
      return null;
    }

    try {
      return LuaNumberParser.parse(utf8.decode(buffer));
    } catch (_) {
      return null;
    }
  }

  List<int>? _readFixedBytes(int length) {
    if (_position >= _bytes.length) {
      return null;
    }

    final end = (_position + length).clamp(0, _bytes.length);
    final result = _bytes.sublist(_position, end);
    _position = end;
    return result;
  }

  int _readByte() {
    if (_position >= _bytes.length) {
      return -1;
    }

    return _bytes[_position++];
  }

  void _unreadByte() {
    if (_position > 0) {
      _position--;
    }
  }

  bool _isWhitespace(int byte) {
    return byte == 32 || byte == 9 || byte == 10 || byte == 13;
  }

  bool _isDigit(int byte) {
    return byte >= 48 && byte <= 57;
  }

  bool _isHexDigit(int byte) {
    return (byte >= 48 && byte <= 57) ||
        (byte >= 65 && byte <= 70) ||
        (byte >= 97 && byte <= 102);
  }
}
