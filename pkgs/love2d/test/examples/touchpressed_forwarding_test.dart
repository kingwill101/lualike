import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('bytecode forwards converted touch args to a callback', () async {
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
local camera = require("src.camera")
local received = {}
local target = {
  touchpressed = function(id, x, y)
    received.pressed = { id = id, x = x, y = y }
  end,
}
local function touchpressed(id, x, y)
  x, y = camera.toGame(x, y)
  target.touchpressed(id, x, y)
end
touchpressed(100, 480, 320)
testbed = received
''', scriptPath: '=[touchpressed forwarding test]');
    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    // ignore: avoid_print
    print(snapshot);
    expect(snapshot['pressed'], isNotNull);
  });
}
