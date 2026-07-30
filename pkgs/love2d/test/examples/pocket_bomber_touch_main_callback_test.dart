import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('pocket bomber main touch callbacks under bytecode', () async {
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
''', scriptPath: '=[pocket bomber main callback bootstrap]');
    await runtime.callLoadIfDefined();
    await runtime.execute('''
local okPress, errPress = pcall(function()
  love.touchpressed(100, 480, 320, 0, 0, 1.0)
end)
testbed = { okPress = okPress, errPress = tostring(errPress) }
local okRelease, errRelease = pcall(function()
  love.touchreleased(100, 480, 320, 0, 0, 0.0)
end)
testbed.okRelease = okRelease
testbed.errRelease = tostring(errRelease)
''', scriptPath: '=[pocket bomber main callback test]');
    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    // ignore: avoid_print
    print(snapshot);
    fail('inspect');
  });
}
