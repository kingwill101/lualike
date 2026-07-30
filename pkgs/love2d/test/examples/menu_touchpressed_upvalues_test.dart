import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('menu touchpressed upvalues under bytecode', () async {
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
''', scriptPath: '=[menu touchpressed upvalues bootstrap]');
    await runtime.callLoadIfDefined();
    await runtime.execute('''
local menu = require("src.states.menu")
testbed = {}
for i = 1, 5 do
  local name, value = debug.getupvalue(menu.touchpressed, i)
  if not name then break end
  testbed['name' .. i] = name
  testbed['type' .. i] = type(value)
  if name == 'buttons' and type(value) == 'table' then
    testbed.buttonsCount = #value
    for j, btn in ipairs(value) do
      testbed['btn' .. j .. 'y'] = btn.y
      testbed['btn' .. j .. 'text'] = btn.text
    end
  end
end
''', scriptPath: '=[menu touchpressed upvalues inspect]');
    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    // ignore: avoid_print
    print(snapshot);
    expect(snapshot['name1'], isA<String>());
  });
}
