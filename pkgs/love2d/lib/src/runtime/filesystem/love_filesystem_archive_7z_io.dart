import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

String? _cachedSevenZipExecutable;
bool _resolvedSevenZipExecutable = false;

Archive? decode7zArchive(List<int> bytes) {
  final executable = _sevenZipExecutable();
  if (executable == null) {
    return null;
  }

  final tempDirectory = Directory.systemTemp.createTempSync('love2d-7z-');
  try {
    final archivePath = path.join(tempDirectory.path, 'archive.7z');
    File(archivePath).writeAsBytesSync(bytes, flush: true);

    final listResult = Process.runSync(
      executable,
      <String>['l', '-slt', archivePath],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (listResult.exitCode != 0 || listResult.stdout is! String) {
      return null;
    }

    final entries = _parseListedEntries(listResult.stdout as String);
    if (entries.isEmpty) {
      return null;
    }

    final archive = Archive();
    for (final entry in entries) {
      if (entry.isDirectory) {
        final directory = ArchiveFile.directory(entry.path);
        if (entry.modified != null) {
          directory.lastModTime = _dateTimeToDosTimestamp(entry.modified!);
        }
        archive.add(directory);
        continue;
      }

      final extractResult = Process.runSync(
        executable,
        <String>['x', '-spd', '-so', archivePath, '--', entry.path],
        stdoutEncoding: null,
        stderrEncoding: utf8,
      );
      if (extractResult.exitCode != 0 || extractResult.stdout is! List<int>) {
        return null;
      }

      final content = List<int>.from(extractResult.stdout as List<int>);
      final file = ArchiveFile(entry.path, content.length, content);
      if (entry.modified != null) {
        file.lastModTime = _dateTimeToDosTimestamp(entry.modified!);
      }
      archive.add(file);
    }

    return archive;
  } on ProcessException {
    return null;
  } on FileSystemException {
    return null;
  } finally {
    try {
      tempDirectory.deleteSync(recursive: true);
    } on FileSystemException {
      // Best-effort cleanup for temporary 7z extraction state.
    }
  }
}

String? _sevenZipExecutable() {
  if (_resolvedSevenZipExecutable) {
    return _cachedSevenZipExecutable;
  }

  _resolvedSevenZipExecutable = true;
  for (final candidate in const <String>['7z', '7za', '7zr']) {
    try {
      final result = Process.runSync(
        candidate,
        const <String>['i'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode == 0) {
        _cachedSevenZipExecutable = candidate;
        return candidate;
      }
    } on ProcessException {
      continue;
    }
  }

  return null;
}

List<_SevenZipListedEntry> _parseListedEntries(String output) {
  final entries = <_SevenZipListedEntry>[];
  Map<String, String> current = <String, String>{};
  var inEntries = false;

  void flush() {
    final entryPath = current['Path'];
    if (entryPath == null || entryPath.isEmpty) {
      current = <String, String>{};
      return;
    }

    final attributes = current['Attributes'] ?? '';
    final isDirectory = attributes.startsWith('D ');
    final modified = _parseModifiedDateTime(current['Modified']);
    entries.add(
      _SevenZipListedEntry(
        path: entryPath,
        isDirectory: isDirectory,
        modified: modified,
      ),
    );
    current = <String, String>{};
  }

  for (final line in const LineSplitter().convert(output)) {
    if (!inEntries) {
      if (line.trim() == '----------') {
        inEntries = true;
      }
      continue;
    }

    if (line.trim().isEmpty) {
      flush();
      continue;
    }

    final separatorIndex = line.indexOf(' = ');
    if (separatorIndex <= 0) {
      continue;
    }

    final key = line.substring(0, separatorIndex);
    final value = line.substring(separatorIndex + 3);
    current[key] = value;
  }

  flush();
  return entries;
}

DateTime? _parseModifiedDateTime(String? rawValue) {
  if (rawValue == null || rawValue.isEmpty) {
    return null;
  }

  final trimmed = rawValue.trim();
  final withoutFraction = trimmed.split('.').first;
  try {
    return DateTime.parse(withoutFraction.replaceFirst(' ', 'T'));
  } on FormatException {
    return null;
  }
}

int _dateTimeToDosTimestamp(DateTime value) {
  return ((value.year - 1980) << 25) |
      (value.month << 21) |
      (value.day << 16) |
      (value.hour << 11) |
      (value.minute << 5) |
      (value.second ~/ 2);
}

class _SevenZipListedEntry {
  const _SevenZipListedEntry({
    required this.path,
    required this.isDirectory,
    this.modified,
  });

  final String path;
  final bool isDirectory;
  final DateTime? modified;
}
