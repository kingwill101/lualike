import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

void main() {
  test('wrap push after updatePositions', () async {
    final runtime = LoveScriptRuntime(
      engineMode: EngineMode.luaBytecode,
      host: LoveHeadlessHost(),
      filesystemAdapter: LoveLualikeFilesystemAdapter(),
    );
    final fs = LoveFilesystemState.of(runtime.runtime);
    expect(fs.setSource('assets/pocket_bomber/main.lua'), isTrue);
    await runtime.loadConfIfPresent();
    await runtime.execute('assert(love.filesystem.load("main.lua"))()', scriptPath: '=[pb]');
    await runtime.callLoadIfDefined();

    await runtime.execute(r'''
_G.__log = {}
local function log(s)
  _G.__log[#_G.__log+1] = s
  print(s)
end
local rp, ro = love.graphics.push, love.graphics.pop
love.graphics.push = function(...)
  log("push")
  return rp(...)
end
love.graphics.pop = function(...)
  log("pop")
  return ro(...)
end
local Cam = require("src.camera")
local ra, rr = Cam.apply, Cam.remove
Cam.apply = function(...)
  log("apply")
  return ra(...)
end
Cam.remove = function(...)
  log("remove")
  return rr(...)
end
''');

    runtime.context.beginDrawFrame();
    await runtime.callDrawIfDefined();
    print('--- first draw done ---');

    await runtime.execute('require("src.touch_controls").updatePositions()');
    print('--- after updatePositions ---');

    runtime.context.beginDrawFrame();
    try {
      await runtime.callDrawIfDefined();
      print('--- second draw OK ---');
    } catch (e) {
      print('--- second draw FAIL $e ---');
      await runtime.execute(r'''
print("events:")
for i,s in ipairs(_G.__log) do print(i, s) end
''');
      rethrow;
    }
  });
}
