import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _pocketBomberEntry = 'example/assets/pocket_bomber/main.lua';

void main() {
  test(
    'pocket bomber touch id 100 does not corrupt keyboard polling during update',
    () async {
      final host = LoveHeadlessHost();
      final runtime = LoveScriptRuntime(
        engineMode: EngineMode.luaBytecode,
        host: host,
        filesystemAdapter: LoveLualikeFilesystemAdapter(),
      );
      final adapter = LoveFlameInputAdapter(
        host: host,
        runtimeProvider: () => runtime,
      );
      final filesystem = LoveFilesystemState.of(runtime.runtime);

      expect(filesystem.setSource(_pocketBomberEntry), isTrue);
      await runtime.loadConfIfPresent();
      await runtime.execute('''
local loaded = assert(love.filesystem.load("main.lua"))
loaded()
''', scriptPath: '=[pocket bomber touch smoke bootstrap]');
      await runtime.callLoadIfDefined();

      await runtime.callUpdateIfDefined(1 / 60);

      adapter.handlePointerDown(
        const PointerDownEvent(
          kind: PointerDeviceKind.touch,
          pointer: 100,
          position: Offset(480, 320),
          pressure: 1.0,
        ),
      );
      await _flushQueuedInput(adapter, runtime);
      await runtime.callUpdateIfDefined(1 / 60);

      adapter.handlePointerUp(
        const PointerUpEvent(
          kind: PointerDeviceKind.touch,
          pointer: 100,
          position: Offset(480, 320),
          pressure: 0.0,
        ),
      );
      await _flushQueuedInput(adapter, runtime);
      await runtime.callUpdateIfDefined(1 / 60);
    },
  );
}

Future<void> _flushQueuedInput(
  LoveFlameInputAdapter adapter,
  LoveScriptRuntime runtime,
) async {
  await adapter.flush();
  await runtime.processMainLoopEvents();
}
