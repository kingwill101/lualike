import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('inspect love.touchreleased upvalues in bytecode', () async {
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
''', scriptPath: '=[pocket bomber touch upvalue bootstrap]');
    await runtime.callLoadIfDefined();
    await runtime.execute('''
testbed = {}
local name1, value1 = debug.getupvalue(love.touchreleased, 1)
testbed.name1 = name1
testbed.type1 = type(value1)
local name2, value2 = debug.getupvalue(love.touchreleased, 2)
testbed.name2 = name2
testbed.type2 = type(value2)
''', scriptPath: '=[pocket bomber touch upvalue inspect]');
    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    // ignore: avoid_print
    print(snapshot);
    fail('inspect');
  });
}
