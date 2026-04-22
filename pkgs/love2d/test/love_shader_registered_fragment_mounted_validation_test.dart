import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:love2d/src/runtime/flame/love_flame_harness_renderer.dart';

import 'test_support/memory_filesystem_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'newShader infers mounted Flutter fragment assets and validates them on Flutter hosts',
    () async {
      final rawSource = await _packageShaderSource(
        'test_assets/shaders/runtime_effect_solid_color.frag',
      );

      final runtime = LoveScriptRuntime(
        host: LoveFlameHarnessGame().host,
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: <String, List<int>>{
            'test_assets/shaders/runtime_effect_solid_color.frag':
                rawSource.codeUnits,
          },
        ),
      );
      final filesystem = LoveFilesystemState.attach(runtime.runtime);
      expect(filesystem.setSource('test_assets/shaders/main.lua'), isTrue);

      await runtime.execute('''
local shader = love.graphics.newShader("runtime_effect_solid_color.frag")
shader:sendColor("uColor", 1, 0.25, 0.5, 1)

function love.draw()
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
        'test_assets/shaders/runtime_effect_solid_color.frag',
      );
      expect(command.shader!.uniform('uColor'), <Object?>[1.0, 0.25, 0.5, 1.0]);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  test(
    'newShader rejects mounted Flutter fragment files whose inferred asset key is missing from the bundle',
    () async {
      final rawSource = await _packageShaderSource(
        'test_assets/shaders/runtime_effect_solid_color.frag',
      );

      final runtime = LoveScriptRuntime(
        host: LoveFlameHarnessGame().host,
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: <String, List<int>>{
            'test_assets/shaders/does_not_exist.frag': rawSource.codeUnits,
          },
        ),
      );
      final filesystem = LoveFilesystemState.attach(runtime.runtime);
      expect(filesystem.setSource('test_assets/shaders/main.lua'), isTrue);

      await expectLater(
        runtime.execute('''
local shader = love.graphics.newShader("does_not_exist.frag")
'''),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains(
              'Could not load Flutter fragment shader asset "test_assets/shaders/does_not_exist.frag"',
            ),
          ),
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  test(
    'validateShader returns false for mounted Flutter fragment files whose inferred asset key is missing from the bundle',
    () async {
      final rawSource = await _packageShaderSource(
        'test_assets/shaders/runtime_effect_solid_color.frag',
      );

      final runtime = LoveScriptRuntime(
        host: LoveFlameHarnessGame().host,
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: <String, List<int>>{
            'test_assets/shaders/does_not_exist.frag': rawSource.codeUnits,
          },
        ),
      );
      final filesystem = LoveFilesystemState.attach(runtime.runtime);
      expect(filesystem.setSource('test_assets/shaders/main.lua'), isTrue);

      await runtime.execute('''
local ok, err = love.graphics.validateShader(false, "does_not_exist.frag")
shader_ok = ok
shader_error = err
''');

      expect(runtime.unwrapGlobal('shader_ok'), isFalse);
      expect(
        runtime.unwrapGlobal('shader_error'),
        contains(
          'Could not load Flutter fragment shader asset "test_assets/shaders/does_not_exist.frag"',
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );
}

Future<String> _packageShaderSource(String relativePath) async {
  final shaderPath =
      '/run/media/kingwill101/disk2/code/code/dart_packages/lualike/'
      'pkgs/love2d/$relativePath';
  return File(shaderPath).readAsString();
}
