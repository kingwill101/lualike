import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('bytecode preserves two-value assignment from camera.toGame', () async {
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
local function convert(x, y)
  x, y = camera.toGame(x, y)
  return x, y
end
local x, y = convert(480, 320)
testbed = { x = x, y = y, types = { type(x), type(y) } }
''', scriptPath: '=[multi return assignment test]');
    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    // ignore: avoid_print
    print(snapshot);
    expect(snapshot['x'], isNotNull);
    expect(snapshot['y'], isNotNull);
  });
}
