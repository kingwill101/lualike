import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

void main() {
  test('example browser list bar after load bytecode', () async {
    final runtime = LoveScriptRuntime(
      engineMode: EngineMode.luaBytecode,
      host: LoveHeadlessHost(),
      filesystemAdapter: LoveLualikeFilesystemAdapter(),
    );
    final fs = LoveFilesystemState.of(runtime.runtime);
    expect(fs.setSource('assets/love_example_browser/main.lua'), isTrue);
    await runtime.loadConfIfPresent();
    await runtime.execute(
      'assert(love.filesystem.load("main.lua"))()',
      scriptPath: '=[browser]',
    );
    await runtime.callLoadIfDefined();
    // inspect list bar
    await runtime.execute(r'''
local list = exf.list
testbed = {
  hasList = list ~= nil,
  barType = list and type(list.bar) or "nil",
  pos = list and list.bar and list.bar.pos,
  maxpos = list and list.bar and list.bar.maxpos,
  n = list and list.items and list.items.n,
}
''');
    final t = runtime.unwrapGlobalTable('testbed')!;
    // ignore: avoid_print
    print(t);
    expect(t['pos'], isNotNull);
    runtime.context.beginDrawFrame();
    await runtime.callDrawIfDefined();
  });
}
