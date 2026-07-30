import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test('bytecode preserves button table literals with function fields', () async {
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
local buttons = {
  {text = "PLAY", action = function() end, y = 320},
  {text = "CONTROLS", action = function() end, y = 380},
  {text = "QUIT", action = function() end, y = 440},
}
testbed = {
  count = #buttons,
  y1 = buttons[1].y,
  y2 = buttons[2].y,
  y3 = buttons[3].y,
  t1 = buttons[1].text,
}
''', scriptPath: '=[table literal function field test]');
    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    // ignore: avoid_print
    print(snapshot);
    expect(snapshot['count'], 3);
    expect(snapshot['y1'], 320);
    expect(snapshot['y2'], 380);
    expect(snapshot['y3'], 440);
  });
}
