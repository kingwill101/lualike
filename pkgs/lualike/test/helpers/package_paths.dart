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

String _findPackageRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final hasPackageFiles =
        File(p.join(current.path, 'pubspec.yaml')).existsSync() &&
        File(p.join(current.path, 'bin', 'main.dart')).existsSync() &&
        Directory(p.join(current.path, 'luascripts')).existsSync();
    if (hasPackageFiles) {
      return current.path;
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
