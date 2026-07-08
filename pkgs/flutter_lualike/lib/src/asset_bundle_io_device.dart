/// A read-only [IODevice] backed by a [AssetBundle] byte buffer.
///
/// Supports only mode `"r"`. Write/append modes throw a [LuaError].
/// All read operations (`read`, `seek`, `getPosition`, `isEOF`) work as
/// expected on the in-memory buffer.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle;
import 'package:lualike/lualike.dart'
    show BaseIODevice, LuaError, LuaString, ReadResult, SeekWhence, WriteResult;

String _normalizeReadFormat(String format) {
  if (format.startsWith('*')) return format.substring(1);
  return format == 'all' ? 'a' : format;
}

/// A read-only [IODevice] that serves file contents from a Flutter
/// [AssetBundle].
///
/// The entire file is loaded into memory on open. Only mode `"r"` is
/// supported.
class AssetBundleIODevice extends BaseIODevice {
  final Uint8List _data;
  int _position = 0;
  bool _isClosed = false;

  AssetBundleIODevice._(this._data, String mode) : super(mode);

  /// Opens [path] from [bundle] and returns a read-only IO device.
  ///
  /// Throws a [LuaError] if [mode] is not `"r"` or any of its variants
  /// (`"rb"`, `"r b"`, etc.).
  static Future<AssetBundleIODevice> open(
    AssetBundle bundle,
    String path,
    String mode,
  ) async {
    var effectiveMode = mode.trim();
    if (effectiveMode.endsWith('b')) {
      effectiveMode = effectiveMode.substring(0, effectiveMode.length - 1);
    }
    if (effectiveMode != 'r') {
      throw LuaError('AssetBundleIODevice only supports mode "r"');
    }

    final data = await bundle.load(path);
    final bytes = data.buffer.asUint8List();
    return AssetBundleIODevice._(bytes, mode);
  }

  @override
  bool get isClosed => _isClosed;

  @override
  Future<void> close() async {
    _isClosed = true;
  }

  @override
  Future<void> flush() async {
    // no-op: read-only
  }

  @override
  Future<ReadResult> read([String format = 'l']) async {
    checkOpen();
    if (!RegExp(r'^(\*?n|\*?a|\*?all|\*?l|\*?L|\d+)$').hasMatch(format)) {
      throw LuaError("invalid format: $format");
    }
    final normalizedFormat = _normalizeReadFormat(format);

    try {
      switch (normalizedFormat) {
        case 'a':
          final content = _data.sublist(_position);
          _position = _data.length;
          return ReadResult(LuaString.fromBytes(content));

        case 'l':
        case 'L': {
          if (_position >= _data.length) return ReadResult(null);
          final start = _position;
          while (_position < _data.length && _data[_position] != 10) {
            _position++;
          }
          if (normalizedFormat == 'L' && _position < _data.length) {
            _position++; // include newline
          }
          final line = _data.sublist(start, _position);
          if (normalizedFormat != 'L' && line.isNotEmpty && line.last == 10) {
            // strip trailing newline for 'l'
            _position--;
            return ReadResult(
              LuaString.fromBytes(_data.sublist(start, _position)),
            );
          }
          return ReadResult(LuaString.fromBytes(line));
        }

        case 'n': {
          if (_position >= _data.length) return ReadResult(null);
          final buffer = <int>[];
          while (_position < _data.length && _data[_position] <= 32) {
            _position++;
          }
          if (_position >= _data.length) return ReadResult(null);
          const digits = {45, 43, 46, 101, 69, 120, 88};
          while (_position < _data.length &&
              (_data[_position] >= 48 && _data[_position] <= 57 ||
                  digits.contains(_data[_position]))) {
            buffer.add(_data[_position]);
            _position++;
          }
          if (buffer.isEmpty) return ReadResult(null);
          final numStr = String.fromCharCodes(buffer);
          try {
            return ReadResult(num.parse(numStr));
          } catch (_) {
            return ReadResult(null);
          }
        }

        default: {
          final n = int.parse(normalizedFormat);
          if (n == 0) {
            return _position >= _data.length ? ReadResult(null) : ReadResult('');
          }
          if (_position >= _data.length) return ReadResult(null);
          final end = (_position + n) > _data.length
              ? _data.length
              : _position + n;
          final chunk = _data.sublist(_position, end);
          _position = end;
          return ReadResult(LuaString.fromBytes(chunk));
        }
      }
    } catch (e) {
      return ReadResult(null, e.toString());
    }
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    checkOpen();
    switch (whence) {
      case SeekWhence.set:
        _position = offset.clamp(0, _data.length);
      case SeekWhence.cur:
        _position = (_position + offset).clamp(0, _data.length);
      case SeekWhence.end:
        _position = (_data.length + offset).clamp(0, _data.length);
    }
    return _position;
  }

  @override
  Future<int> getPosition() async => _position;

  @override
  Future<bool> isEOF() async => _position >= _data.length;

  @override
  Future<WriteResult> write(String data) async {
    return WriteResult(false, 'Cannot write to read-only asset bundle', 9);
  }

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async {
    return WriteResult(false, 'Cannot write to read-only asset bundle', 9);
  }
}
