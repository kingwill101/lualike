import 'dart:io';

import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:lualike_hooks/lualike_hooks.dart';
import 'package:test/test.dart';

void main() {
  test('emits a data asset for bytecode mode when enabled', () async {
    final temp = await Directory.systemTemp.createTemp('lualike_hooks_');
    addTearDown(() => temp.delete(recursive: true));

    final packageRoot = temp.uri;
    final luaDir = packageRoot.resolve('lua/');
    await Directory.fromUri(luaDir).create(recursive: true);
    await File.fromUri(luaDir.resolve('hello.lua')).writeAsString(
      'return function() return 42 end',
    );

    final inputBuilder = BuildInputBuilder()
      ..setupShared(
        packageRoot: packageRoot,
        packageName: 'example_app',
        outputDirectoryShared: packageRoot.resolve('.dart_tool/hooks_runner/'),
        outputFile: packageRoot.resolve('.dart_tool/hooks_runner/output.json'),
      )
      ..config.setupBuild(linkingEnabled: false)
      ..setupBuildInput();
    DataAssetsExtension().setupBuildInput(inputBuilder);

    final outputBuilder = BuildOutputBuilder();
    final builder = LuaBuilder(sources: ['lua/']);
    await builder.run(
      input: inputBuilder.build(),
      output: outputBuilder,
      logger: null,
    );

    final output = outputBuilder.build();
    expect(output.assets.data, hasLength(1));
    final asset = output.assets.data.single;
    expect(asset.package, 'example_app');
    expect(asset.name, 'lua/hello.lua');
    expect(File.fromUri(asset.file).existsSync(), isTrue);
  });
}
