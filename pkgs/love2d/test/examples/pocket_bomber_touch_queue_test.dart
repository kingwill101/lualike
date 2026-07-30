import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('pocket bomber touch queue path under bytecode', () async {
    final host = LoveHeadlessHost();
    final runtime = LoveScriptRuntime(
      engineMode: EngineMode.luaBytecode,
      host: host,
      filesystemAdapter: LoveLualikeFilesystemAdapter(),
    );
    final filesystem = LoveFilesystemState.of(runtime.runtime);
    expect(filesystem.setSource(_pocketBomberEntry), isTrue);
    await runtime.loadConfIfPresent();
    await runtime.execute('''
local loaded = assert(love.filesystem.load("main.lua"))
loaded()
''', scriptPath: '=[pocket bomber touch queue bootstrap]');
    await runtime.callLoadIfDefined();
    await runtime.callUpdateIfDefined(1 / 60);
    await runtime.queueTouchPressed(100, 480, 320, 0, 0, 1.0);
    await runtime.processMainLoopEvents();
    await runtime.execute('''
testbed = testbed or {}
local touchControls = require("src.touch_controls")
testbed.after_queue_pressed = type(touchControls.joystick)
local _, touchValue = debug.getupvalue(love.touchreleased, 2)
testbed.callback_touch_type = type(touchValue)
''', scriptPath: '=[pocket bomber queue inspect after press]');
    await runtime.callUpdateIfDefined(1 / 60);
    await runtime.execute('''
local _, touchValue = debug.getupvalue(love.touchreleased, 2)
testbed.after_update_touch_type = type(touchValue)
local StateMachine = require("src.state_machine")
local Touch = require("src.touch_controls")
local okState, errState = pcall(function()
  StateMachine.touchreleased(100, 480, 320)
end)
testbed.okStateReleased = okState
testbed.errStateReleased = tostring(errState)
local okTouch, errTouch = pcall(function()
  Touch.touchreleased(100, 480, 320)
end)
testbed.okTouchReleased = okTouch
testbed.errTouchReleased = tostring(errTouch)
''', scriptPath: '=[pocket bomber queue inspect after update]');
    // ignore: avoid_print
    print(runtime.unwrapGlobalTable('testbed'));
    return;
  });
}
