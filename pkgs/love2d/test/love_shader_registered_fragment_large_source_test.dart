import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';

void main() {
  test(
    'newShader infers Flutter shader assets for mounted shader explorer files',
    () async {
      final shaderPath =
          '/run/media/kingwill101/disk2/code/code/dart_packages/lualike/'
          'pkgs/love2d/example/assets/shader_explorer/shaders/water.frag';
      final rawSource = await File(shaderPath).readAsString();

      final runtime = LoveScriptRuntime(
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: <String, List<int>>{
            'assets/shader_explorer/shaders/water.frag': rawSource.codeUnits,
          },
        ),
      );
      final filesystem = LoveFilesystemState.attach(runtime.runtime);
      expect(filesystem.setSource('assets/shader_explorer/main.lua'), isTrue);

      await runtime.execute('''
function love.draw()
  local shader = love.graphics.newShader("shaders/water.frag")
  love.graphics.setShader(shader)
  love.graphics.rectangle("fill", 0, 0, 1, 1)
  love.graphics.setShader()
end
''');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      final command =
          runtime.context.graphics.commands.single as LoveRectangleCommand;
      expect(command.shader, isNotNull);
      expect(
        command.shader!.flutterFragmentAssetKey,
        'assets/shader_explorer/shaders/water.frag',
      );
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  test(
    'validateShader accepts mounted shader explorer files through the public path',
    () async {
      final shaderPath =
          '/run/media/kingwill101/disk2/code/code/dart_packages/lualike/'
          'pkgs/love2d/example/assets/shader_explorer/shaders/water.frag';
      final rawSource = await File(shaderPath).readAsString();

      final runtime = LoveScriptRuntime(
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: <String, List<int>>{
            'assets/shader_explorer/shaders/water.frag': rawSource.codeUnits,
          },
        ),
      );
      final filesystem = LoveFilesystemState.attach(runtime.runtime);
      expect(filesystem.setSource('assets/shader_explorer/main.lua'), isTrue);

      await runtime.execute('''
local ok, err = love.graphics.validateShader(false, "shaders/water.frag")
shader_ok = ok
shader_error = err
''');

      expect(runtime.unwrapGlobal('shader_ok'), isTrue);
      expect(runtime.unwrapGlobal('shader_error'), isNull);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );
}
