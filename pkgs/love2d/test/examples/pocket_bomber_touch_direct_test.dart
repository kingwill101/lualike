import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('direct pocket bomber touch controls under bytecode', () async {
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
local menu = require("src.states.menu")
local originalEnter = menu.enter
menu.enter = function(...)
  testbed = testbed or {}
  testbed.enterCalled = true
  local result = { originalEnter(...) }
  local _, enterButtons = debug.getupvalue(originalEnter, 2)
  local _, touchButtons = debug.getupvalue(menu.touchpressed, 2)
  print('ENTER-LEN', enterButtons and #enterButtons or -1)
  print('TOUCH-LEN', touchButtons and #touchButtons or -1)
  return table.unpack(result)
end
''', scriptPath: '=[pocket bomber touch direct bootstrap]');
    await runtime.callLoadIfDefined();
    await runtime.callUpdateIfDefined(1 / 60);

    await runtime.execute('''
local touchControls = require("src.touch_controls")
local StateMachine = require("src.state_machine")
local menu = require("src.states.menu")
local _, buttons = debug.getupvalue(menu.touchpressed, 2)
testbed = {
  before = type(touchControls.joystick),
  currentType = type(StateMachine.getCurrent()),
  currentIsMenu = StateMachine.getCurrent() == menu,
  buttonsType = type(buttons),
  buttonsLen = buttons and #buttons or -1,
  enterCalled = testbed and testbed.enterCalled or false,
}
local okPressed, errPressed = pcall(function()
  touchControls.touchpressed(100, 480, 320)
end)
testbed.okPressed = okPressed
testbed.errPressed = tostring(errPressed)
testbed.after_pressed = type(touchControls.joystick)
love.update(0.016)
testbed.after_update = type(touchControls.joystick)
local okReleased1, errReleased1 = pcall(function()
  touchControls.touchreleased(100, 480, 320)
end)
testbed.okReleased1 = okReleased1
testbed.errReleased1 = tostring(errReleased1)
testbed.after_released1 = type(touchControls.joystick)
local okReleased2, errReleased2 = pcall(function()
  touchControls.touchreleased(100, 480, 320)
end)
testbed.okReleased2 = okReleased2
testbed.errReleased2 = tostring(errReleased2)
testbed.after_released2 = type(touchControls.joystick)
''', scriptPath: '=[pocket bomber touch direct]');

    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    // ignore: avoid_print
    print(snapshot);
    fail('inspect');
  });
}
