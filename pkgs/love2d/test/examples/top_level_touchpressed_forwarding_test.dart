import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('top level touchpressed callback forwards args under bytecode', () async {
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
local StateMachine = {
  touchpressed = function(id, x, y)
    received.pressed = { id = id, x = x, y = y }
  end,
}
function love.touchpressed(id, x, y, dx, dy, pressure)
  x, y = camera.toGame(x, y)
  StateMachine.touchpressed(id, x, y)
end
love.touchpressed(100, 480, 320, 0, 0, 1.0)
testbed = received
''', scriptPath: '=[top level touchpressed forwarding test]');
    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    // ignore: avoid_print
    print(snapshot);
    expect(snapshot['pressed'], isNotNull);
  });
}
