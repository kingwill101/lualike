part of 'love_filesystem_bindings.dart';

class _LoveFilesystemLineCursor {
  _LoveFilesystemLineCursor(List<int> bytes, {required int startOffset})
    : _bytes = List<int>.unmodifiable(bytes),
      _offset = startOffset.clamp(0, bytes.length);

  final List<int> _bytes;
  int _offset;

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

class _LoveFilesystemFileLineCursor {
  _LoveFilesystemFileLineCursor({
    required this.file,
    required this.restoreUserPosition,
    required this.userPosition,
  });

  final LoveFilesystemFile file;
  final bool restoreUserPosition;
  final int userPosition;
  int _iteratorPosition = 0;
  bool _exhausted = false;

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
