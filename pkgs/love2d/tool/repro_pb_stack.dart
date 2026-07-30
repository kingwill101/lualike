import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

Future<void> main() async {
  final host = LoveHeadlessHost();
  for (final mode in [EngineMode.ast, EngineMode.luaBytecode]) {
    print('=== $mode ===');
    try {
      final runtime = LoveScriptRuntime(
        engineMode: mode,
        host: host,
        filesystemAdapter: LoveLualikeFilesystemAdapter(),
      );
      final fs = LoveFilesystemState.of(runtime.runtime);
      assert(fs.setSource('example/assets/pocket_bomber/main.lua'));
      await runtime.loadConfIfPresent();
      await runtime.execute('assert(love.filesystem.load("main.lua"))()', scriptPath: '=[pb]');
      await runtime.callLoadIfDefined();
      for (var i = 0; i < 5; i++) {
        await runtime.callUpdateIfDefined(1/60);
        print(' frame $i stackDepth before draw=${runtime.context.graphics.stackDepth}');
        runtime.context.beginDrawFrame();
        print('  after beginDraw stackDepth=${runtime.context.graphics.stackDepth}');
        runtime.context.graphics.origin();
        await runtime.callDrawIfDefined();
        print('  after draw stackDepth=${runtime.context.graphics.stackDepth}');
      }
      print('OK');
    } catch (e, st) {
      print('FAIL $e');
      print(st.toString().split('\n').take(6).join('\n'));
    }
  }
}
