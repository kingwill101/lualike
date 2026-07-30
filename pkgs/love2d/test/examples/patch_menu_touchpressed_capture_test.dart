import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('patched menu.touchpressed captures forwarded args', () async {
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
''', scriptPath: '=[patch menu touchpressed bootstrap]');
    await runtime.callLoadIfDefined();
    await runtime.execute('''
local menu = require("src.states.menu")
local received = {}
menu.touchpressed = function(id, x, y)
  received.pressed = { id = id, x = x, y = y }
end
love.touchpressed(100, 480, 320, 0, 0, 1.0)
testbed = received
''', scriptPath: '=[patch menu touchpressed inspect]');
    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    // ignore: avoid_print
    print(snapshot);
    expect(snapshot['pressed'], isNotNull);
  });
}
