import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('LoveFlameInputAdapter gamepad bridge', () {
    late LoveHeadlessHost host;
    late LoveScriptRuntime runtime;
    late LoveJoystickInputAdapter joystickInput;
    late LoveFlameInputAdapter adapter;

    setUp(() async {
      host = LoveHeadlessHost();
      runtime = LoveScriptRuntime(host: host);
      joystickInput = LoveJoystickInputAdapter(
        host: host,
        runtimeProvider: () => runtime,
      );
      adapter = LoveFlameInputAdapter(
        host: host,
        runtimeProvider: () => runtime,
        joystickInput: joystickInput,
      );

      await runtime.execute('''
testbed = {}

function love.keypressed(key)
  testbed.keypressed = key
end

function love.textinput(text)
  testbed.textinput = text
end

function love.joystickadded(j)
  testbed.joystickadded = string.format(
    "%s|%d",
    j:getName(),
    love.joystick.getJoystickCount()
  )
end

function love.joystickpressed(j, button)
  testbed.joystickpressed = string.format(
    "%d|%s",
    button,
    tostring(j:isDown(button))
  )
end

function love.joystickreleased(j, button)
  testbed.joystickreleased = string.format(
    "%d|%s",
    button,
    tostring(j:isDown(button))
  )
end

function love.gamepadpressed(j, button)
  testbed.gamepadpressed = string.format(
    "%s|%s",
    button,
    tostring(j:isGamepadDown(button))
  )
end

function love.gamepadreleased(j, button)
  testbed.gamepadreleased = string.format(
    "%s|%s",
    button,
    tostring(j:isGamepadDown(button))
  )
end

function love.gamepadaxis(j, axis, value)
  testbed.gamepadaxis = string.format("%s|%.1f", axis, value)
end
''');
    });

    test(
      'routes gamepad button and trigger keys through love.joystick',
      () async {
        expect(
          adapter.handleKeyEvent(
            const KeyDownEvent(
              physicalKey: PhysicalKeyboardKey.gameButtonA,
              logicalKey: LogicalKeyboardKey.gameButtonA,
              deviceType: ui.KeyEventDeviceType.gamepad,
              timeStamp: Duration.zero,
            ),
          ),
          KeyEventResult.handled,
        );
        await _flushQueuedGamepadInput(adapter, runtime);

        final joystick = host.joysticks.devices.single;
        expect(host.keyboard.isDown(const <String>['a']), isFalse);
        expect(runtime.unwrapGlobalTable('testbed')!['keypressed'], isNull);
        expect(runtime.unwrapGlobalTable('testbed')!['textinput'], isNull);
        expect(
          runtime.unwrapGlobalTable('testbed')!['joystickadded'],
          'Flutter Virtual Gamepad|1',
        );
        expect(
          runtime.unwrapGlobalTable('testbed')!['gamepadpressed'],
          'a|true',
        );
        expect(joystick.isGamepadDown(const <String>['a']), isTrue);

        adapter.handleKeyEvent(
          const KeyRepeatEvent(
            physicalKey: PhysicalKeyboardKey.gameButtonA,
            logicalKey: LogicalKeyboardKey.gameButtonA,
            deviceType: ui.KeyEventDeviceType.gamepad,
            timeStamp: Duration.zero,
          ),
        );
        await _flushQueuedGamepadInput(adapter, runtime);

        expect(
          runtime.unwrapGlobalTable('testbed')!['gamepadpressed'],
          'a|true',
        );

        adapter.handleKeyEvent(
          const KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.gameButtonA,
            logicalKey: LogicalKeyboardKey.gameButtonA,
            deviceType: ui.KeyEventDeviceType.gamepad,
            timeStamp: Duration.zero,
          ),
        );
        await _flushQueuedGamepadInput(adapter, runtime);

        expect(
          runtime.unwrapGlobalTable('testbed')!['gamepadreleased'],
          'a|false',
        );
        expect(joystick.isGamepadDown(const <String>['a']), isFalse);

        adapter.handleKeyEvent(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.gameButtonLeft2,
            logicalKey: LogicalKeyboardKey.gameButtonLeft2,
            deviceType: ui.KeyEventDeviceType.gamepad,
            timeStamp: Duration.zero,
          ),
        );
        await _flushQueuedGamepadInput(adapter, runtime);

        expect(
          runtime.unwrapGlobalTable('testbed')!['gamepadaxis'],
          'triggerleft|1.0',
        );
        expect(joystick.getGamepadAxis('triggerleft'), 1.0);

        adapter.handleKeyEvent(
          const KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.gameButtonLeft2,
            logicalKey: LogicalKeyboardKey.gameButtonLeft2,
            deviceType: ui.KeyEventDeviceType.gamepad,
            timeStamp: Duration.zero,
          ),
        );
        await _flushQueuedGamepadInput(adapter, runtime);

        expect(
          runtime.unwrapGlobalTable('testbed')!['gamepadaxis'],
          'triggerleft|0.0',
        );
        expect(joystick.getGamepadAxis('triggerleft'), 0.0);
      },
    );

    test('maps joystick dpad arrow keys to LOVE gamepad buttons', () async {
      adapter.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowUp,
          logicalKey: LogicalKeyboardKey.arrowUp,
          deviceType: ui.KeyEventDeviceType.joystick,
          timeStamp: Duration.zero,
        ),
      );
      await _flushQueuedGamepadInput(adapter, runtime);

      final joystick = host.joysticks.devices.single;
      expect(
        runtime.unwrapGlobalTable('testbed')!['gamepadpressed'],
        'dpup|true',
      );
      expect(joystick.isGamepadDown(const <String>['dpup']), isTrue);

      adapter.handleKeyEvent(
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.arrowUp,
          logicalKey: LogicalKeyboardKey.arrowUp,
          deviceType: ui.KeyEventDeviceType.joystick,
          timeStamp: Duration.zero,
        ),
      );
      await _flushQueuedGamepadInput(adapter, runtime);

      expect(
        runtime.unwrapGlobalTable('testbed')!['gamepadreleased'],
        'dpup|false',
      );
      expect(joystick.isGamepadDown(const <String>['dpup']), isFalse);
    });

    test(
      'routes generic game button keys through joystick button callbacks',
      () async {
        adapter.handleKeyEvent(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.gameButton3,
            logicalKey: LogicalKeyboardKey.gameButton3,
            deviceType: ui.KeyEventDeviceType.joystick,
            timeStamp: Duration.zero,
          ),
        );
        await _flushQueuedGamepadInput(adapter, runtime);

        final joystick = host.joysticks.devices.single;
        expect(
          runtime.unwrapGlobalTable('testbed')!['joystickpressed'],
          '3|true',
        );
        expect(joystick.isDown(const <int>[3]), isTrue);

        adapter.handleKeyEvent(
          const KeyRepeatEvent(
            physicalKey: PhysicalKeyboardKey.gameButton3,
            logicalKey: LogicalKeyboardKey.gameButton3,
            deviceType: ui.KeyEventDeviceType.joystick,
            timeStamp: Duration.zero,
          ),
        );
        await _flushQueuedGamepadInput(adapter, runtime);

        expect(
          runtime.unwrapGlobalTable('testbed')!['joystickpressed'],
          '3|true',
        );

        adapter.handleKeyEvent(
          const KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.gameButton3,
            logicalKey: LogicalKeyboardKey.gameButton3,
            deviceType: ui.KeyEventDeviceType.joystick,
            timeStamp: Duration.zero,
          ),
        );
        await _flushQueuedGamepadInput(adapter, runtime);

        expect(
          runtime.unwrapGlobalTable('testbed')!['joystickreleased'],
          '3|false',
        );
        expect(joystick.isDown(const <int>[3]), isFalse);
      },
    );
  });

  test(
    'love.event receives gamepad input queue entries when callbacks are undefined',
    () async {
      final host = LoveHeadlessHost();
      final runtime = LoveScriptRuntime(host: host);
      final adapter = LoveFlameInputAdapter(
        host: host,
        runtimeProvider: () => runtime,
      );

      adapter.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.gameButtonStart,
          logicalKey: LogicalKeyboardKey.gameButtonStart,
          deviceType: ui.KeyEventDeviceType.gamepad,
          timeStamp: Duration.zero,
        ),
      );
      adapter.handleKeyEvent(
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.gameButtonStart,
          logicalKey: LogicalKeyboardKey.gameButtonStart,
          deviceType: ui.KeyEventDeviceType.gamepad,
          timeStamp: Duration.zero,
        ),
      );
      await adapter.flush();

      final poll = await luaCall(runtime, const ['love', 'event', 'poll']);
      expect(poll, isA<BuiltinFunction>());
      final iterator = poll! as BuiltinFunction;

      final added = await luaCallCallable(iterator);
      expect(added, isA<List<Object?>>());
      expect((added! as List<Object?>)[0], 'joystickadded');

      final pressed = await luaCallCallable(iterator);
      expect(pressed, isA<List<Object?>>());
      final pressedArgs = pressed! as List<Object?>;
      expect(pressedArgs[0], 'gamepadpressed');
      expect(pressedArgs[1], isA<Map>());
      expect(
        (pressedArgs[1]! as Map)['__love2d_joystick__'],
        same(host.joysticks.devices.single),
      );
      expect(pressedArgs[2], 'start');

      final released = await luaCallCallable(iterator);
      expect(released, isA<List<Object?>>());
      final releasedArgs = released! as List<Object?>;
      expect(releasedArgs[0], 'gamepadreleased');
      expect(releasedArgs[1], isA<Map>());
      expect(
        (releasedArgs[1]! as Map)['__love2d_joystick__'],
        same(host.joysticks.devices.single),
      );
      expect(releasedArgs[2], 'start');

      expect(await luaCallCallable(iterator), isNull);
    },
  );

  test(
    'love.event receives joystick button queue entries for generic controller keys',
    () async {
      final host = LoveHeadlessHost();
      final runtime = LoveScriptRuntime(host: host);
      final adapter = LoveFlameInputAdapter(
        host: host,
        runtimeProvider: () => runtime,
      );

      adapter.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.gameButton5,
          logicalKey: LogicalKeyboardKey.gameButton5,
          deviceType: ui.KeyEventDeviceType.gamepad,
          timeStamp: Duration.zero,
        ),
      );
      adapter.handleKeyEvent(
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.gameButton5,
          logicalKey: LogicalKeyboardKey.gameButton5,
          deviceType: ui.KeyEventDeviceType.gamepad,
          timeStamp: Duration.zero,
        ),
      );
      await adapter.flush();

      final poll = await luaCall(runtime, const ['love', 'event', 'poll']);
      expect(poll, isA<BuiltinFunction>());
      final iterator = poll! as BuiltinFunction;

      final added = await luaCallCallable(iterator);
      expect(added, isA<List<Object?>>());
      expect((added! as List<Object?>)[0], 'joystickadded');

      final pressed = await luaCallCallable(iterator);
      expect(pressed, isA<List<Object?>>());
      final pressedArgs = pressed! as List<Object?>;
      expect(pressedArgs[0], 'joystickpressed');
      expect(pressedArgs[1], isA<Map>());
      expect(
        (pressedArgs[1]! as Map)['__love2d_joystick__'],
        same(host.joysticks.devices.single),
      );
      expect(pressedArgs[2], 5);

      final released = await luaCallCallable(iterator);
      expect(released, isA<List<Object?>>());
      final releasedArgs = released! as List<Object?>;
      expect(releasedArgs[0], 'joystickreleased');
      expect(releasedArgs[1], isA<Map>());
      expect(
        (releasedArgs[1]! as Map)['__love2d_joystick__'],
        same(host.joysticks.devices.single),
      );
      expect(releasedArgs[2], 5);

      expect(await luaCallCallable(iterator), isNull);
    },
  );

  test(
    'visibility loss clears synthesized gamepad state without release callbacks',
    () async {
      final host = LoveHeadlessHost();
      final runtime = LoveScriptRuntime(host: host);
      final adapter = LoveFlameInputAdapter(
        host: host,
        runtimeProvider: () => runtime,
      );

      await runtime.execute('''
testbed = {}

function love.gamepadreleased(j, button)
  testbed.gamepadreleased = button
end
''');

      adapter.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.gameButtonA,
          logicalKey: LogicalKeyboardKey.gameButtonA,
          deviceType: ui.KeyEventDeviceType.gamepad,
          timeStamp: Duration.zero,
        ),
      );
      await adapter.flush();

      final joystick = host.joysticks.devices.single;
      expect(joystick.isGamepadDown(const <String>['a']), isTrue);

      adapter.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.gameButton4,
          logicalKey: LogicalKeyboardKey.gameButton4,
          deviceType: ui.KeyEventDeviceType.gamepad,
          timeStamp: Duration.zero,
        ),
      );
      await adapter.flush();

      expect(joystick.isDown(const <int>[4]), isTrue);

      await runtime.execute('love.event.clear()');
      adapter.handleVisibilityChanged(false);
      await adapter.flush();

      expect(joystick.isGamepadDown(const <String>['a']), isFalse);
      expect(joystick.isDown(const <int>[4]), isFalse);
      expect(runtime.unwrapGlobalTable('testbed')!['gamepadreleased'], isNull);

      final poll = await luaCall(runtime, const ['love', 'event', 'poll']);
      final iterator = poll! as BuiltinFunction;
      expect(await luaCallCallable(iterator), isNull);
    },
  );
}

Future<void> _flushQueuedGamepadInput(
  LoveFlameInputAdapter adapter,
  LoveScriptRuntime runtime,
) async {
  await adapter.flush();
  await runtime.processMainLoopEvents();
}
