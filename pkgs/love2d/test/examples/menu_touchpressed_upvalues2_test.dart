import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('menu touchpressed upvalue names under bytecode', () async {
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
''', scriptPath: '=[menu touchpressed upvalues2 bootstrap]');
    await runtime.callLoadIfDefined();
    await runtime.execute('''
local menu = require("src.states.menu")
testbed = {}
for i = 1, 10 do
  local name, value = debug.getupvalue(menu.touchpressed, i)
  if not name then break end
  testbed[i] = tostring(name) .. ':' .. type(value)
end
''', scriptPath: '=[menu touchpressed upvalues2 inspect]');
    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    // ignore: avoid_print
    print(snapshot);
    expect(snapshot[1], isA<String>());
  });
}
