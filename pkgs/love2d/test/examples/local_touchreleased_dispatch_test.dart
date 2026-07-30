import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('local touchreleased dispatcher works under bytecode', () async {
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
local received = {}
local currentState = {
  touchreleased = function(id, x, y)
    received.released = { id = id, x = x, y = y }
  end,
}
local function touchreleased(id, x, y)
  if currentState and currentState.touchreleased then
    currentState.touchreleased(id, x, y)
  end
end
touchreleased(4, 5, 6)
testbed = received
''', scriptPath: '=[local touchreleased dispatch test]');
    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    // ignore: avoid_print
    print(snapshot);
    expect(snapshot['released'], isNotNull);
  });
}
