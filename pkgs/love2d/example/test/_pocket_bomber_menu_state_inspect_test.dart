import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _entry = 'example/assets/pocket_bomber/main.lua';

Future<Map<String, Object?>> _inspect() async {
  final runtime = LoveScriptRuntime(
    engineMode: EngineMode.luaBytecode,
    host: LoveHeadlessHost(),
    filesystemAdapter: LoveLualikeFilesystemAdapter(),
  );
  final filesystem = LoveFilesystemState.of(runtime.runtime);
  expect(filesystem.setSource(_entry), isTrue);
  await runtime.loadConfIfPresent();
  await runtime.execute('''
local loaded = assert(love.filesystem.load("main.lua"))
loaded()
''', scriptPath: '=[pocket bomber inspect bootstrap]');
  await runtime.callLoadIfDefined();
  await runtime.execute('''
local StateMachine = require("src.state_machine")
local menu = require("src.states.menu")
local current = StateMachine.getCurrent()
local _, buttons = debug.getupvalue(menu.touchpressed, 2)
testbed = {
  currentType = type(current),
  currentIsMenu = current == menu,
  menuButtonsFieldType = type(menu.buttons),
  menuButtonsFieldLen = menu.buttons and #menu.buttons or -1,
  buttonsUpvalueType = type(buttons),
  buttonsUpvalueLen = buttons and #buttons or -1,
}
''', scriptPath: '=[pocket bomber inspect state]');
  return runtime.unwrapGlobalTable('testbed')!.cast<String, Object?>();
}

void main() {
  test('pocket bomber menu state inspect', () async {
    final bc = await _inspect();
    // ignore: avoid_print
    print(bc);
    expect(bc['currentType'], 'table');
  });
}
