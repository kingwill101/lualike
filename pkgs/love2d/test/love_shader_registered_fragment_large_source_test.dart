import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test(
    'newShader accepts the shader explorer water fragment source',
    () async {
      final shaderPath =
          '/run/media/kingwill101/disk2/code/code/dart_packages/lualike/'
          'pkgs/love2d/example/assets/shader_explorer/shaders/water.frag';
      final rawSource = await File(shaderPath).readAsString();

      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());
      await runtime.execute('''
local shader = love.graphics._newRegisteredFragmentShader(
  "assets/shader_explorer/shaders/water.frag",
  [==[
$rawSource
]==]
)
assert(shader ~= nil)
''');
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );
}
