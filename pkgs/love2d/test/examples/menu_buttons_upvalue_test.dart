import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('menu buttons upvalue values under bytecode', () async {
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
''', scriptPath: '=[menu buttons upvalue bootstrap]');
    await runtime.callLoadIfDefined();
    await runtime.execute('''
local menu = require("src.states.menu")
local _, buttons = debug.getupvalue(menu.touchpressed, 2)
testbed = { count = #buttons }
for i, btn in ipairs(buttons) do
  testbed['y' .. i] = btn.y
  testbed['text' .. i] = btn.text
end
''', scriptPath: '=[menu buttons upvalue inspect]');
    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    // ignore: avoid_print
    print(snapshot);
    expect(snapshot['count'], 3);
    expect(snapshot['y1'], isNotNull);
    expect(snapshot['y2'], isNotNull);
    expect(snapshot['y3'], isNotNull);
  });
}
