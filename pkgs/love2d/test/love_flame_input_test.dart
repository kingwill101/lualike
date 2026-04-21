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
  local poll = love.event.poll()
  local name, queuedKey, queuedScancode, queuedRepeat = poll()
  testbed.keypressed = string.format("%s|%s|%s|%s|%s|%s|%s", name, queuedKey, tostring(queuedScancode), tostring(queuedRepeat), key, tostring(scancode), tostring(isrepeat))
end

function love.keyreleased(key, scancode)
  local poll = love.event.poll()
  local name, queuedKey, queuedScancode = poll()
  testbed.keyreleased = string.format("%s|%s|%s|%s|%s", name, queuedKey, tostring(queuedScancode), key, tostring(scancode))
end

function love.textinput(text)
  local poll = love.event.poll()
  local name, queuedText = poll()
  testbed.textinput = string.format("%s|%s|%s", name, queuedText, text)
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
      await adapter.flush();

      expect(host.keyboard.isDown(const <String>['a']), isTrue);
      expect(
        runtime.unwrapGlobalTable('testbed')!['keypressed'],
        'keypressed|a|a|false|a|a|false',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['textinput'],
        'textinput|a|a',
      );

      host.keyboard.keyRepeat = true;
      adapter.handleKeyEvent(
        const KeyRepeatEvent(
          physicalKey: PhysicalKeyboardKey.digit1,
          logicalKey: LogicalKeyboardKey.digit1,
          character: '!',
          timeStamp: Duration.zero,
        ),
      );
      await adapter.flush();

      expect(
        runtime.unwrapGlobalTable('testbed')!['keypressed'],
        'keypressed|!|1|true|!|1|true',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['textinput'],
        'textinput|!|!',
      );

      adapter.handleKeyEvent(
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
        ),
      );
      await adapter.flush();

      expect(host.keyboard.isDown(const <String>['a']), isFalse);
      expect(
        runtime.unwrapGlobalTable('testbed')!['keyreleased'],
        'keyreleased|a|a|a|a',
      );

      host.keyboard.setTextInput(false);
      adapter.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyB,
          logicalKey: LogicalKeyboardKey.keyB,
          character: 'b',
          timeStamp: Duration.zero,
        ),
      );
      await adapter.flush();

      expect(
        runtime.unwrapGlobalTable('testbed')!['keypressed'],
        'keypressed|b|b|false|b|b|false',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['textinput'],
        'textinput|!|!',
      );
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
  local poll = love.event.poll()
  local name, queuedFocused = poll()
  testbed.focus = string.format("%s|%s|%s", name, tostring(queuedFocused), tostring(focused))
end

function love.mousefocus(focused)
  local poll = love.event.poll()
  local name, queuedFocused = poll()
  testbed.mousefocus = string.format("%s|%s|%s", name, tostring(queuedFocused), tostring(focused))
end

function love.mousemoved(x, y, dx, dy, istouch)
  local poll = love.event.poll()
  local name, queuedX, queuedY, queuedDx, queuedDy, queuedTouch = poll()
  testbed.mousemoved = string.format("%s|%.0f,%.0f,%.0f,%.0f,%s|%.0f,%.0f,%.0f,%.0f,%s", name, queuedX, queuedY, queuedDx, queuedDy, tostring(queuedTouch), x, y, dx, dy, tostring(istouch))
end

function love.mousepressed(x, y, button, istouch, presses)
  local poll = love.event.poll()
  local name, queuedX, queuedY, queuedButton, queuedTouch, queuedPresses = poll()
  testbed.mousepressed = string.format("%s|%.0f,%.0f,%d,%s,%d|%.0f,%.0f,%d,%s,%d", name, queuedX, queuedY, queuedButton, tostring(queuedTouch), queuedPresses, x, y, button, tostring(istouch), presses)
end

function love.mousereleased(x, y, button, istouch, presses)
  local poll = love.event.poll()
  local name, queuedX, queuedY, queuedButton, queuedTouch, queuedPresses = poll()
  testbed.mousereleased = string.format("%s|%.0f,%.0f,%d,%s,%d|%.0f,%.0f,%d,%s,%d", name, queuedX, queuedY, queuedButton, tostring(queuedTouch), queuedPresses, x, y, button, tostring(istouch), presses)
end

function love.wheelmoved(x, y)
  local poll = love.event.poll()
  local name, queuedX, queuedY = poll()
  testbed.wheelmoved = string.format("%s|%.0f,%.0f|%.0f,%.0f", name, queuedX, queuedY, x, y)
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  local poll = love.event.poll()
  local name, queuedId, queuedX, queuedY, queuedDx, queuedDy, queuedPressure = poll()
  testbed.touchpressed = string.format("%s|%d,%.0f,%.0f,%.0f,%.0f,%.1f|%d,%.0f,%.0f,%.0f,%.0f,%.1f", name, queuedId, queuedX, queuedY, queuedDx, queuedDy, queuedPressure, id, x, y, dx, dy, pressure)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
  local poll = love.event.poll()
  local name, queuedId, queuedX, queuedY, queuedDx, queuedDy, queuedPressure = poll()
  testbed.touchmoved = string.format("%s|%d,%.0f,%.0f,%.0f,%.0f,%.1f|%d,%.0f,%.0f,%.0f,%.0f,%.1f", name, queuedId, queuedX, queuedY, queuedDx, queuedDy, queuedPressure, id, x, y, dx, dy, pressure)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
  local poll = love.event.poll()
  local name, queuedId, queuedX, queuedY, queuedDx, queuedDy, queuedPressure = poll()
  testbed.touchreleased = string.format("%s|%d,%.0f,%.0f,%.0f,%.0f,%.1f|%d,%.0f,%.0f,%.0f,%.0f,%.1f", name, queuedId, queuedX, queuedY, queuedDx, queuedDy, queuedPressure, id, x, y, dx, dy, pressure)
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
      await adapter.flush();

      expect(runtime.unwrapGlobalTable('testbed')!['focus'], 'focus|true|true');
      expect(
        runtime.unwrapGlobalTable('testbed')!['mousefocus'],
        'mousefocus|false|false',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['mousemoved'],
        'mousemoved|7,11,4,7,false|7,11,4,7,false',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['mousepressed'],
        'mousepressed|10,20,1,false,1|10,20,1,false,1',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['mousereleased'],
        'mousereleased|10,20,1,false,1|10,20,1,false,1',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['wheelmoved'],
        'wheelmoved|1,1|1,1',
      );
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
      await adapter.flush();

      expect(
        runtime.unwrapGlobalTable('testbed')!['touchpressed'],
        'touchpressed|17,4,5,0,0,0.6|17,4,5,0,0,0.6',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['touchmoved'],
        'touchmoved|17,9,11,5,6,0.8|17,9,11,5,6,0.8',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['touchreleased'],
        'touchreleased|17,9,11,0,0,0.4|17,9,11,0,0,0.4',
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
      await adapter.flush();

      expect(host.windowHasFocus, isTrue);
      expect(host.windowHasMouseFocus, isTrue);
      expect(host.keyboard.isDown(const <String>['a']), isTrue);
      expect(host.mouse.isDown(const <int>[1]), isTrue);
      expect(host.touch.getTouches(), <int>[17]);

      await runtime.execute('love.event.clear()');
      adapter.handleVisibilityChanged(false);
      await adapter.flush();

      expect(host.windowHasFocus, isFalse);
      expect(host.windowHasMouseFocus, isFalse);
      expect(host.keyboard.isDown(const <String>['a']), isFalse);
      expect(host.mouse.isDown(const <int>[1]), isFalse);
      expect(host.touch.getTouches(), isEmpty);
      expect(
        runtime.unwrapGlobalTable('testbed')!['focus'],
        'focus|false|false',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['mousefocus'],
        'mousefocus|false|false',
      );

      adapter.handleFocusChanged(true);
      adapter.handlePointerEnter(
        const PointerEnterEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(2, 3),
        ),
      );
      await adapter.flush();

      expect(host.windowHasFocus, isTrue);
      expect(host.windowHasMouseFocus, isTrue);
      expect(runtime.unwrapGlobalTable('testbed')!['focus'], 'focus|true|true');
      expect(
        runtime.unwrapGlobalTable('testbed')!['mousefocus'],
        'mousefocus|true|true',
      );
    });
  });
}
