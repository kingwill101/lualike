part of 'love_filesystem_bindings.dart';

/// In-memory line iterator for byte buffers returned by filesystem reads.
class _LoveFilesystemLineCursor {
  /// Creates a line cursor over [bytes] starting at [startOffset].
  _LoveFilesystemLineCursor(List<int> bytes, {required int startOffset})
    : _bytes = List<int>.unmodifiable(bytes),
      _offset = startOffset.clamp(0, bytes.length);

  /// The immutable byte buffer being iterated.
  final List<int> _bytes;

  /// The next unread byte offset in [_bytes].
  int _offset;

  /// Returns the next line without trailing line terminators, if any remain.
  List<int>? next() {
    if (_offset >= _bytes.length) {
      return null;
    }

    final start = _offset;
    var end = start;
    while (end < _bytes.length && _bytes[end] != 10) {
      end++;
    }

    _offset = end < _bytes.length ? end + 1 : _bytes.length;

    var lineEnd = end;
    if (lineEnd > start && _bytes[lineEnd - 1] == 13) {
      lineEnd--;
    }

    return _bytes.sublist(start, lineEnd);
  }
}

/// File-backed line iterator that preserves user-visible file position when needed.
class _LoveFilesystemFileLineCursor {
  /// Creates a line cursor over [file].
  _LoveFilesystemFileLineCursor({
    required this.file,
    required this.restoreUserPosition,
    required this.userPosition,
  });

  /// The file being iterated line by line.
  final LoveFilesystemFile file;

  /// Whether iteration should restore the caller's visible file position.
  final bool restoreUserPosition;

  /// The user-visible file position captured before iteration began.
  final int userPosition;

  /// The iterator's private read position within [file].
  int _iteratorPosition = 0;

  /// Whether iteration has already reached EOF or failed permanently.
  bool _exhausted = false;

  /// Returns the next line without trailing line terminators, if any remain.
  Future<List<int>?> next() async {
    if (_exhausted) {
      return null;
    }

    if (file.mode != 'r') {
      throw LuaError('File needs to stay in read mode.');
    }

    try {
      var currentUserPosition = userPosition;
      if (restoreUserPosition) {
        currentUserPosition = await file.tell();
        if (currentUserPosition != _iteratorPosition) {
          await file.seek(_iteratorPosition);
        }
      }

      final line = await file.readLineBytes();
      if (line == null) {
        _exhausted = true;
        if (file.isOpen) {
          await file.close();
        }
        return null;
      }

      if (restoreUserPosition && file.isOpen) {
        _iteratorPosition = await file.tell();
        await file.seek(currentUserPosition);
      }

      if (line.isNotEmpty && line.last == 13) {
        return line.sublist(0, line.length - 1);
      }

      return line;
    } on StateError catch (error) {
      _exhausted = true;
      throw LuaError(error.message);
    }
  }
}
