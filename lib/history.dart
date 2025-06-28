import 'dart:io';

class ReplHistory {
  final List<String> _history = [];
  int _currentIndex = 0;
  final String _historyFilePath;

  ReplHistory({String? historyFilePath})
    : _historyFilePath =
          historyFilePath ??
          '${Platform.environment['HOME'] ?? ''}/.lualike_history';

  int get length => _history.length;

  void add(String command) {
    // Don't add empty commands or duplicates of the last command
    if (command.trim().isEmpty ||
        (_history.isNotEmpty && _history.last == command)) {
      return;
    }
    _history.add(command);
    _currentIndex = _history.length;
  }

  String? getPrevious() {
    if (_history.isEmpty) return null;
    _currentIndex = (_currentIndex > 0) ? _currentIndex - 1 : 0;
    return _currentIndex < _history.length ? _history[_currentIndex] : null;
  }

  String? getNext() {
    if (_history.isEmpty) return null;
    _currentIndex =
        (_currentIndex < _history.length) ? _currentIndex + 1 : _history.length;
    return _currentIndex < _history.length ? _history[_currentIndex] : "";
  }

  void loadFromFile() {
    final file = File(_historyFilePath);
    if (file.existsSync()) {
      try {
        final lines = file.readAsLinesSync();
        _history.addAll(lines.where((line) => line.trim().isNotEmpty));
        _currentIndex = _history.length;
      } catch (e) {
        print('Failed to load history: $e');
      }
    }
  }

  void saveToFile() {
    try {
      final file = File(_historyFilePath);
      // Limit history to last 1000 commands
      final historyToSave =
          _history.length > 1000
              ? _history.sublist(_history.length - 1000)
              : _history;
      file.writeAsStringSync(historyToSave.join('\n'));
      print('Saved ${historyToSave.length} commands to history file');
    } catch (e) {
      print('Failed to save history: $e');
    }
  }

  void reset() {
    _currentIndex = _history.length;
  }
}
