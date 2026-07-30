import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('bytecode can call touchreleased fields', () async {
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
testbed = {}
local t = {
  touchpressed = function(id, x, y)
    testbed.pressed = { id = id, x = x, y = y }
  end,
  touchreleased = function(id, x, y)
    testbed.released = { id = id, x = x, y = y }
  end,
}
if t and t.touchpressed then t.touchpressed(1, 2, 3) end
if t and t.touchreleased then t.touchreleased(4, 5, 6) end
''', scriptPath: '=[touchreleased field call test]');
    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    // ignore: avoid_print
    print(snapshot);
    expect(snapshot['pressed'], isNotNull);
    expect(snapshot['released'], isNotNull);
  });
}
