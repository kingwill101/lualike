import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('state machine forwards touch args under bytecode', () async {
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
''', scriptPath: '=[state machine touch dispatch bootstrap]');
    await runtime.callLoadIfDefined();
    await runtime.execute('''
local StateMachine = require("src.state_machine")
local received = {}
StateMachine.register("probe", {
  touchpressed = function(id, x, y)
    received.pressed = { id = id, x = x, y = y }
  end,
  touchreleased = function(id, x, y)
    received.released = { id = id, x = x, y = y }
  end,
})
StateMachine.switch("probe")
StateMachine.touchpressed(7, 11, 13)
StateMachine.touchreleased(7, 11, 13)
testbed = received
''', scriptPath: '=[state machine touch dispatch inspect]');
    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    // ignore: avoid_print
    print(snapshot);
    expect(snapshot['pressed'], isNotNull);
    expect(snapshot['released'], isNotNull);
  });
}
