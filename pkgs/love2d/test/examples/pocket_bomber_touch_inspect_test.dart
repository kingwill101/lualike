import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('inspect pocket bomber touch module', () async {
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
''', scriptPath: '=[pocket bomber touch inspect bootstrap]');
    await runtime.callLoadIfDefined();
    await runtime.callUpdateIfDefined(1 / 60);
    await runtime.execute('''
testbed = {}
local touchControls = require("src.touch_controls")
testbed.initial_type = type(touchControls.joystick)
testbed.initial_value_type = type(touchControls.joystick)
''', scriptPath: '=[pocket bomber touch inspect]');
    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    expect(snapshot['initial_type'], anyOf('table', 'function', 'nil'));
  });
}
