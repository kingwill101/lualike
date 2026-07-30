import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

void main() {
  test('flame touch adapter passes coordinates to love callbacks', () async {
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

    await runtime.execute('''
testbed = {}
function love.touchreleased(id, x, y, dx, dy, pressure)
  testbed = {
    id = id,
    x = x,
    y = y,
    dx = dx,
    dy = dy,
    pressure = pressure,
  }
end
''', scriptPath: '=[flame touch arg test]');

    adapter.handlePointerDown(
      const PointerDownEvent(
        kind: PointerDeviceKind.touch,
        pointer: 100,
        position: Offset(480, 320),
        pressure: 1.0,
      ),
    );
    await adapter.flush();
    await runtime.processMainLoopEvents();
    adapter.handlePointerUp(
      const PointerUpEvent(
        kind: PointerDeviceKind.touch,
        pointer: 100,
        position: Offset(480, 320),
        pressure: 0.0,
      ),
    );
    await adapter.flush();
    await runtime.processMainLoopEvents();

    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    expect(snapshot['x'], isNotNull);
    expect(snapshot['y'], isNotNull);
  });
}
