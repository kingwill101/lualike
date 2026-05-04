import 'dart:io';

import 'package:path/path.dart' as p;

final String packageRootPath = _findPackageRoot();

String packagePath(String relativePath) {
  return p.joinAll(<String>[packageRootPath, ...p.posix.split(relativePath)]);
}

String luaPathLiteral(String path) {
  final normalized = path.replaceAll(r'\', '/').replaceAll("'", r"\'");
  return "'$normalized'";
}

bool _hasPackageFiles(String dir) =>
    File(p.join(dir, 'pubspec.yaml')).existsSync() &&
    File(p.join(dir, 'bin', 'main.dart')).existsSync() &&
    Directory(p.join(dir, 'luascripts')).existsSync();

String _findPackageRoot() {
  // Walk up from cwd first.
  var current = Directory.current.absolute;
  while (true) {
    if (_hasPackageFiles(current.path)) {
      return current.path;
    }

    // Also probe well-known monorepo sub-path so tests run from the
    // workspace root (e.g. `dart test pkgs/lualike`) still resolve.
    final candidate = p.join(current.path, 'pkgs', 'lualike');
    if (_hasPackageFiles(candidate)) {
      return candidate;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError(
        'Could not find pkgs/lualike package root from '
        '${Directory.current.path}',
      );
    }
    current = parent;
  }
}
