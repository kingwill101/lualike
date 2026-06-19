import 'dart:io';

import 'package:lualike/docs.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/docs/metadata_generator.dart' show generateMetadata;

import 'package:love2d/src/generated/love_api_reference.g.dart'
    show LoveLibrary;

Future<void> main() async {
  final lua = LuaLike();
  lua.vm.libraryRegistry.register(LoveLibrary());

  await generateMetadata(
    lua,
    outputDir: 'doc/api',
    formats: {MetadataFormat.html, MetadataFormat.json, MetadataFormat.luals},
    pageOptions: const DocPageOptions(
      title: 'LuaLike + LOVE 2D API Reference',
      brandName: 'LuaLike + LOVE 2D',
      homeHref: 'index.html',
      homeLabel: 'REPL',
    ),
  );

  stdout.writeln('Generated docs in doc/api/');

  // Also write the standalone HTML to the repo root for convenience.
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
  File('love2d_docs.html').writeAsStringSync(html);
  stdout.writeln('Wrote love2d_docs.html (${html.length} bytes)');
}
