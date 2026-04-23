import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

String? findSevenZipExecutable() {
  for (final candidate in const <String>['7z', '7za', '7zr']) {
    try {
      final result = Process.runSync(
        candidate,
        const <String>['i'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode == 0) {
        return candidate;
      }
    } on ProcessException {
      continue;
    }
  }

  return null;
}

List<int> encode7zArchive({
  required List<SevenZipArchiveInputFile> files,
  List<String> methodArgs = const <String>[],
  String? sevenZipExecutable,
}) {
  final executable = sevenZipExecutable ?? findSevenZipExecutable();
  if (executable == null) {
    throw StateError('7z executable not available in PATH.');
  }

  final tempDirectory = Directory.systemTemp.createTempSync('love2d-test-7z-');
  try {
    final inputDirectory = Directory(p.join(tempDirectory.path, 'input'))
      ..createSync();
    for (final file in files) {
      final normalizedPath = p.posix.normalize(file.path);
      File(p.join(inputDirectory.path, normalizedPath))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(file.bytes);
    }

    final archivePath = p.join(tempDirectory.path, 'archive.7z');
    final roots =
        files
            .map((file) => p.posix.normalize(file.path).split('/').first)
            .toSet()
            .toList()
          ..sort();
    final result = Process.runSync(
      executable,
      <String>['a', '-spd', '-t7z', ...methodArgs, archivePath, '--', ...roots],
      workingDirectory: inputDirectory.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'Failed to create test 7z archive: ${result.stderr ?? result.stdout}',
      );
    }

    return File(archivePath).readAsBytesSync();
  } finally {
    tempDirectory.deleteSync(recursive: true);
  }
}

final class SevenZipArchiveInputFile {
  const SevenZipArchiveInputFile(this.path, this.bytes);

  final String path;
  final List<int> bytes;
}
