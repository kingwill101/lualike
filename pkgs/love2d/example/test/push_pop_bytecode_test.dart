import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

void main() {
  test('graphics push/pop under bytecode', () async {
    for (final mode in [EngineMode.ast, EngineMode.luaBytecode]) {
      final runtime = LoveScriptRuntime(
        engineMode: mode,
        host: LoveHeadlessHost(),
      );
      await runtime.execute('''
local cam = {}
cam.scaleX = 2
cam.scaleY = 3
function cam.apply()
  love.graphics.push()
  love.graphics.scale(cam.scaleX, cam.scaleY)
end
function cam.remove()
  love.graphics.pop()
end
function love.draw()
  cam.apply()
  love.graphics.rectangle("fill", 0, 0, 10, 10)
  cam.remove()
end
''');
      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();
      expect(runtime.context.graphics.stackDepth, 0, reason: '$mode');
      print('$mode OK');
    }
  });

  test('pocket bomber first draw bytecode', () async {
    final runtime = LoveScriptRuntime(
      engineMode: EngineMode.luaBytecode,
      host: LoveHeadlessHost(),
      filesystemAdapter: LoveLualikeFilesystemAdapter(),
    );
    final fs = LoveFilesystemState.of(runtime.runtime);
    expect(fs.setSource('assets/pocket_bomber/main.lua'), isTrue);
    await runtime.loadConfIfPresent();
    await runtime.execute(
      'assert(love.filesystem.load("main.lua"))()',
      scriptPath: '=[pb]',
    );
    await runtime.callLoadIfDefined();
    // wrap draw to see where it fails
    await runtime.execute(r'''
local old = love.draw
love.draw = function()
  local ok, err = pcall(old)
  if not ok then
    error("draw failed: " .. tostring(err) .. " stackApprox")
  end
end
''');
    runtime.context.beginDrawFrame();
    runtime.context.graphics.origin();
    await runtime.callDrawIfDefined();
  });
}
