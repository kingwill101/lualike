/// Runs build_runner to generate table schema docs, then renders the output.
///
/// Usage:
///   dart run tool/generate.dart
library;

import 'dart:io';

Future<void> main(List<String> args) async {
  // 1. Generate .table_schema.g.dart from annotated classes
  final build = await Process.run(
    'dart',
    ['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
    runInShell: true,
  );

  if (build.exitCode != 0) {
    stderr.writeln('build_runner failed:\n${build.stderr}');
    exitCode = build.exitCode;
    return;
  }

  // 2. Render the docs using the generated constants
  final render = await Process.run(
    'dart',
    ['run', 'bin/render.dart'],
    runInShell: true,
  );

  stdout.write(render.stdout);
  if (render.exitCode != 0) {
    stderr.writeln('render failed:\n${render.stderr}');
  }
  exitCode = render.exitCode;
}
