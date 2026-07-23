import 'dart:io';

import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  test('loads legacy build/lua bytecode files', () async {
    final tempDir = await Directory.systemTemp.createTemp('lualike_asset_');
    addTearDown(() => tempDir.delete(recursive: true));

    final buildDir = tempDir.uri.resolve('build/lua/');
    await Directory.fromUri(buildDir).create(recursive: true);
    await File.fromUri(buildDir.resolve('hello.lua')).writeAsBytes([1, 2, 3]);

    final loader = LuaAssetLoader(buildDir: buildDir);
    expect(await loader.loadBytecode('hello.lua'), [1, 2, 3]);
  });

  test('loads bundled data assets from the executable assets directory',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('lualike_asset_');
    addTearDown(() => tempDir.delete(recursive: true));

    final buildDir = tempDir.uri.resolve('build/lua/');
    final bundleDir = tempDir.uri.resolve('bundle/bin/');
    final assetDir = bundleDir.resolve('assets/');
    await Directory.fromUri(assetDir).create(recursive: true);
    await File.fromUri(assetDir.resolve('hello.lua')).writeAsBytes([4, 5, 6]);

    final loader = LuaAssetLoader(buildDir: buildDir, bundleDir: bundleDir);

    expect(await loader.loadBytecode('hello.lua'), [4, 5, 6]);
  });
}
