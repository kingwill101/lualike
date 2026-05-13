import 'dart:io';

import 'package:path/path.dart' as p;

Future<Directory> love2dPackageRoot() async {
  const nestedSegments = <String>['pkgs', 'love2d'];

  var current = Directory.current.absolute;
  while (true) {
    final directCandidate = File(p.join(current.path, 'pubspec.yaml'));
    if (directCandidate.existsSync()) {
      final pubspec = directCandidate.readAsStringSync();
      if (pubspec.contains('name: love2d')) {
        return current;
      }
    }

    final nestedCandidate = Directory(
      p.joinAll(<String>[current.path, ...nestedSegments]),
    );
    final nestedPubspec = File(p.join(nestedCandidate.path, 'pubspec.yaml'));
    if (nestedPubspec.existsSync()) {
      final pubspec = nestedPubspec.readAsStringSync();
      if (pubspec.contains('name: love2d')) {
        return nestedCandidate;
      }
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }

  throw StateError(
    'Unable to locate package:love2d root from ${Directory.current.path}.',
  );
}

Future<File> love2dPackageFile(List<String> relativeSegments) async {
  final root = await love2dPackageRoot();
  return File(p.joinAll(<String>[root.path, ...relativeSegments]));
}

Future<Directory> love2dPackageDirectory(List<String> relativeSegments) async {
  final root = await love2dPackageRoot();
  return Directory(p.joinAll(<String>[root.path, ...relativeSegments]));
}
