import 'dart:io';

import 'package:lualike/docs.dart'
    show DocPageOptions, documentedLibrariesForRuntime, renderDocsPage;
import 'package:lualike/lualike.dart';

import 'package:love2d/src/generated/love_api_reference.g.dart'
    show LoveLibrary;

void main() {
  final lua = LuaLike();
  final registry = lua.vm.libraryRegistry;

  registry.register(LoveLibrary());
  final libraries = documentedLibrariesForRuntime(lua.vm);

  final html = renderDocsPage(
    libraries,
    options: const DocPageOptions(
      title: 'LuaLike + LOVE 2D API Reference',
      brandName: 'LuaLike + LOVE 2D',
      homeHref: 'index.html',
      homeLabel: 'REPL',
    ),
  );

  final outFile = File('love2d_docs.html');
  outFile.writeAsStringSync(html);
  stdout.writeln('Wrote ${outFile.path} (${html.length} bytes)');
  stdout.writeln(
    'Libraries with docs: '
    '${libraries.where((l) => l.getDocs().isNotEmpty).length}/'
    '${libraries.length}',
  );
  for (final lib in libraries) {
    final docs = lib.getDocs();
    if (docs.isEmpty) continue;
    stdout.writeln(
      '  ${lib.name.isEmpty ? "(base)" : lib.name}: ${docs.length} functions',
    );
  }
}
