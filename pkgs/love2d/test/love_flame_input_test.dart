import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:love2d/love2d.dart';

void main() {
  group('LoveFlameInputAdapter keyboard bridge', () {
    late LoveHeadlessHost host;
    late LoveScriptRuntime runtime;
    late LoveFlameInputAdapter adapter;

    setUp(() async {
      host = LoveHeadlessHost();
      runtime = LoveScriptRuntime(host: host);
      adapter = LoveFlameInputAdapter(
        host: host,
        runtimeProvider: () => runtime,
      );

      await runtime.execute('''
testbed = {}

function love.keypressed(key, scancode, isrepeat)
  testbed.keypressed = string.format(
    "%s|%s|%s",
    key,
    tostring(scancode),
    tostring(isrepeat)
  )
end

function love.keyreleased(key, scancode)
  testbed.keyreleased = string.format("%s|%s", key, tostring(scancode))
end

function love.textinput(text)
  testbed.textinput = text
end
''');
    });

    test('dispatches key press, repeat, release, and text callbacks', () async {
      expect(
        adapter.handleKeyEvent(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.keyA,
            logicalKey: LogicalKeyboardKey.keyA,
            character: 'a',
            timeStamp: Duration.zero,
          ),
        ),
        KeyEventResult.handled,
      );
      await _flushQueuedInput(adapter, runtime);

      expect(host.keyboard.isDown(const <String>['a']), isTrue);
      expect(runtime.unwrapGlobalTable('testbed')!['keypressed'], 'a|a|false');
      expect(runtime.unwrapGlobalTable('testbed')!['textinput'], 'a');

      host.keyboard.keyRepeat = true;
      adapter.handleKeyEvent(
        const KeyRepeatEvent(
          physicalKey: PhysicalKeyboardKey.digit1,
          logicalKey: LogicalKeyboardKey.digit1,
          character: '!',
          timeStamp: Duration.zero,
        ),
      );
      await _flushQueuedInput(adapter, runtime);

      expect(runtime.unwrapGlobalTable('testbed')!['keypressed'], '!|1|true');
      expect(runtime.unwrapGlobalTable('testbed')!['textinput'], '!');

      adapter.handleKeyEvent(
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
        ),
      );
      await _flushQueuedInput(adapter, runtime);

      expect(host.keyboard.isDown(const <String>['a']), isFalse);
      expect(runtime.unwrapGlobalTable('testbed')!['keyreleased'], 'a|a');

      host.keyboard.setTextInput(false);
      adapter.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyB,
          logicalKey: LogicalKeyboardKey.keyB,
          character: 'b',
          timeStamp: Duration.zero,
        ),
      );
      await _flushQueuedInput(adapter, runtime);

      expect(runtime.unwrapGlobalTable('testbed')!['keypressed'], 'b|b|false');
      expect(runtime.unwrapGlobalTable('testbed')!['textinput'], '!');
    });
  });

  group('LoveFlameInputAdapter pointer bridge', () {
    late LoveHeadlessHost host;
    late LoveScriptRuntime runtime;
    late LoveFlameInputAdapter adapter;

    setUp(() async {
      host = LoveHeadlessHost();
      runtime = LoveScriptRuntime(host: host);
      adapter = LoveFlameInputAdapter(
        host: host,
        runtimeProvider: () => runtime,
      );

      await runtime.execute('''
testbed = {}

function love.focus(focused)
  testbed.focus = tostring(focused)
end

function love.mousefocus(focused)
  testbed.mousefocus = tostring(focused)
end

function love.mousemoved(x, y, dx, dy, istouch)
  testbed.mousemoved = string.format(
    "%.0f,%.0f,%.0f,%.0f,%s",
    x,
    y,
    dx,
    dy,
    tostring(istouch)
  )
end

function love.mousepressed(x, y, button, istouch, presses)
  testbed.mousepressed = string.format(
    "%.0f,%.0f,%d,%s,%d",
    x,
    y,
    button,
    tostring(istouch),
    presses
  )
end

function love.mousereleased(x, y, button, istouch, presses)
  testbed.mousereleased = string.format(
    "%.0f,%.0f,%d,%s,%d",
    x,
    y,
    button,
    tostring(istouch),
    presses
  )
end

function love.wheelmoved(x, y)
  testbed.wheelmoved = string.format("%.0f,%.0f", x, y)
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  testbed.touchpressed = string.format(
    "%d,%.0f,%.0f,%.0f,%.0f,%.1f",
    id,
    x,
    y,
    dx,
    dy,
    pressure
  )
end

function love.touchmoved(id, x, y, dx, dy, pressure)
  testbed.touchmoved = string.format(
    "%d,%.0f,%.0f,%.0f,%.0f,%.1f",
    id,
    x,
    y,
    dx,
    dy,
    pressure
  )
end

function love.touchreleased(id, x, y, dx, dy, pressure)
  testbed.touchreleased = string.format(
    "%d,%.0f,%.0f,%.0f,%.0f,%.1f",
    id,
    x,
    y,
    dx,
    dy,
    pressure
  )
end
''');
    });

    test('dispatches focus, motion, button, and wheel callbacks', () async {
      adapter.handleFocusChanged(true);
      adapter.handlePointerEnter(
        const PointerEnterEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(3, 4),
        ),
      );
      adapter.handlePointerHover(
        const PointerHoverEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(7, 11),
          delta: Offset(4, 7),
        ),
      );
      adapter.handlePointerDown(
        const PointerDownEvent(
          kind: PointerDeviceKind.mouse,
          pointer: 21,
          position: Offset(10.9, 20.1),
          buttons: kPrimaryMouseButton,
        ),
      );
      adapter.handlePointerUp(
        const PointerUpEvent(
          kind: PointerDeviceKind.mouse,
          pointer: 21,
          position: Offset(10.9, 20.1),
        ),
      );
      adapter.handlePointerSignal(
        const PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(10.9, 20.1),
          scrollDelta: Offset(30, -30),
        ),
      );
      adapter.handlePointerExit(
        const PointerExitEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(10.9, 20.1),
        ),
      );
      await _flushQueuedInput(adapter, runtime);

      expect(runtime.unwrapGlobalTable('testbed')!['focus'], 'true');
      expect(runtime.unwrapGlobalTable('testbed')!['mousefocus'], 'false');
      expect(
        runtime.unwrapGlobalTable('testbed')!['mousemoved'],
        '7,11,4,7,false',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['mousepressed'],
        '10,20,1,false,1',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['mousereleased'],
        '10,20,1,false,1',
      );
      expect(runtime.unwrapGlobalTable('testbed')!['wheelmoved'], '1,1');
      expect(host.mouse.x, 10);
      expect(host.mouse.y, 20);
      expect(host.mouse.isDown(const <int>[1]), isFalse);
    });

    test('dispatches touch callbacks and tracks touch state', () async {
      adapter.handlePointerDown(
        const PointerDownEvent(
          kind: PointerDeviceKind.touch,
          pointer: 17,
          position: Offset(4, 5),
          pressure: 0.6,
        ),
      );
      adapter.handlePointerMove(
        const PointerMoveEvent(
          kind: PointerDeviceKind.touch,
          pointer: 17,
          position: Offset(9, 11),
          delta: Offset(5, 6),
          pressure: 0.8,
        ),
      );
      adapter.handlePointerUp(
        const PointerUpEvent(
          kind: PointerDeviceKind.touch,
          pointer: 17,
          position: Offset(9, 11),
          pressure: 0.4,
        ),
      );
      await _flushQueuedInput(adapter, runtime);

      expect(
        runtime.unwrapGlobalTable('testbed')!['touchpressed'],
        '17,4,5,0,0,0.6',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['touchmoved'],
        '17,9,11,5,6,0.8',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['touchreleased'],
        '17,9,11,0,0,0.4',
      );
      expect(host.touch.getTouches(), isEmpty);
    });

    test('visibility loss clears focus and active input state', () async {
      adapter.handleFocusChanged(true);
      adapter.handlePointerEnter(
        const PointerEnterEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(2, 3),
        ),
      );
      adapter.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          character: 'a',
          timeStamp: Duration.zero,
        ),
      );
      adapter.handlePointerDown(
        const PointerDownEvent(
          kind: PointerDeviceKind.mouse,
          pointer: 99,
          position: Offset(10, 20),
          buttons: kPrimaryMouseButton,
        ),
      );
      adapter.handlePointerDown(
        const PointerDownEvent(
          kind: PointerDeviceKind.touch,
          pointer: 17,
          position: Offset(4, 5),
          pressure: 0.6,
        ),
      );
      await _flushQueuedInput(adapter, runtime);

      expect(host.windowHasFocus, isTrue);
      expect(host.windowHasMouseFocus, isTrue);
      expect(host.keyboard.isDown(const <String>['a']), isTrue);
      expect(host.mouse.isDown(const <int>[1]), isTrue);
      expect(host.touch.getTouches(), <int>[17]);

      await runtime.execute('love.event.clear()');
      adapter.handleVisibilityChanged(false);
      await _flushQueuedInput(adapter, runtime);

      expect(host.windowHasFocus, isFalse);
      expect(host.windowHasMouseFocus, isFalse);
      expect(host.keyboard.isDown(const <String>['a']), isFalse);
      expect(host.mouse.isDown(const <int>[1]), isFalse);
      expect(host.touch.getTouches(), isEmpty);
      expect(runtime.unwrapGlobalTable('testbed')!['focus'], 'false');
      expect(runtime.unwrapGlobalTable('testbed')!['mousefocus'], 'false');

      adapter.handleFocusChanged(true);
      adapter.handlePointerEnter(
        const PointerEnterEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(2, 3),
        ),
      );
      await _flushQueuedInput(adapter, runtime);

      expect(host.windowHasFocus, isTrue);
      expect(host.windowHasMouseFocus, isTrue);
      expect(runtime.unwrapGlobalTable('testbed')!['focus'], 'true');
      expect(runtime.unwrapGlobalTable('testbed')!['mousefocus'], 'true');
    });
  });
}

Future<void> _flushQueuedInput(
  LoveFlameInputAdapter adapter,
  LoveScriptRuntime runtime,
) async {
  await adapter.flush();
  await runtime.processMainLoopEvents();
}
