import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'LoveFlameHarness exposes input adapters before runtime init and reuses joystick input after startup',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      const script = '''
local ready = false
local sawStart = false

function love.load()
  local sticks = love.joystick.getJoysticks()
  assert(love.joystick.getJoystickCount() == 1, "expected preloaded joystick")
  assert(sticks[1] ~= nil, "expected preloaded joystick wrapper")
  assert(sticks[1]:getName() == "Harness Pad", "expected harness joystick name")
  ready = true
end

function love.gamepadpressed(j, button)
  assert(ready, "expected load to complete before gamepad callback")
  if button == "start" and j:isGamepadDown("start") then
    sawStart = true
  end
end

function love.update(dt)
  if sawStart then
    love.event.quit()
  end
end
''';

      final adapter = LoveAssetBundleFilesystemAdapter(
        bundle: _MapAssetBundle(<String, List<int>>{
          'assets/game/main.lua': Uint8List.fromList(script.codeUnits),
        }),
        assetKeys: const <String>['assets/game/main.lua'],
      );

      late LoveJoystickInputAdapter joystickInput;
      final joystick = LoveJoystickDevice(
        id: 11,
        name: 'Harness Pad',
        connected: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LoveFlameHarness(
            entryAsset: 'assets/game/main.lua',
            filesystemAdapter: adapter,
            onInputAdaptersReady: (_, joystickAdapter) async {
              joystickInput = joystickAdapter;
              joystickAdapter.handleDeviceAdded(joystick);
              await joystickAdapter.flush();
            },
            onQuitRequested: () async {},
          ),
        ),
      );

      await _pumpUntilStatus(tester, 'Running');

      joystickInput.handleGamepadButtonDown(joystick, 'start');
      await _pumpUntilStatus(tester, 'Quit');

      expect(find.byKey(const Key('error-message')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'LoveFlameHarness routes focused key events into LOVE gamepad and joystick callbacks',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      const script = '''
local sawGamepad = false
local sawJoystick = false

function love.load()
  assert(love.joystick.getJoystickCount() == 0, "expected no joysticks before focused input")
end

function love.gamepadpressed(j, button)
  if button == "start" and j:isGamepadDown("start") then
    sawGamepad = true
  end
end

function love.joystickpressed(j, button)
  if button == 5 and j:isDown(button) then
    sawJoystick = true
  end
end

function love.update(dt)
  if sawGamepad and sawJoystick then
    love.event.quit()
  end
end
''';

      final adapter = LoveAssetBundleFilesystemAdapter(
        bundle: _MapAssetBundle(<String, List<int>>{
          'assets/game/main.lua': Uint8List.fromList(script.codeUnits),
        }),
        assetKeys: const <String>['assets/game/main.lua'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LoveFlameHarness(
            entryAsset: 'assets/game/main.lua',
            filesystemAdapter: adapter,
            onQuitRequested: () async {},
          ),
        ),
      );

      await _pumpUntilStatus(tester, 'Running');
      await tester.tapAt(tester.getCenter(find.byType(LoveFlameHarness)));
      await tester.pump();

      _dispatchSyntheticKeyData(
        binding,
        physicalKey: PhysicalKeyboardKey.gameButtonStart,
        logicalKey: LogicalKeyboardKey.gameButtonStart,
        deviceType: ui.KeyEventDeviceType.gamepad,
        type: ui.KeyEventType.down,
      );
      await tester.pump();

      _dispatchSyntheticKeyData(
        binding,
        physicalKey: PhysicalKeyboardKey.gameButton5,
        logicalKey: LogicalKeyboardKey.gameButton5,
        deviceType: ui.KeyEventDeviceType.joystick,
        type: ui.KeyEventType.down,
      );
      await _pumpUntilStatus(tester, 'Quit');

      expect(find.byKey(const Key('error-message')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpUntilStatus(
  WidgetTester tester,
  String status, {
  Duration step = const Duration(milliseconds: 16),
  int maxPumps = 160,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await tester.pump(step);
    if (find.text(status).evaluate().isNotEmpty) {
      return;
    }
  }

  final statusFinder = find.byKey(const Key('status-label'));
  final errorFinder = find.byKey(const Key('error-message'));
  final currentStatus = statusFinder.evaluate().isEmpty
      ? null
      : tester.widget<Text>(statusFinder).data;
  final errorMessage = errorFinder.evaluate().isEmpty
      ? null
      : tester.widget<Text>(errorFinder).data;

  fail(
    'Expected status "$status". Current status: '
    '${currentStatus ?? '<missing>'}. '
    'Error: ${errorMessage ?? '<none>'}',
  );
}

class _MapAssetBundle extends CachingAssetBundle {
  _MapAssetBundle(this._assets);

  final Map<String, List<int>> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) {
      throw StateError('Missing asset: $key');
    }

    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

bool _dispatchSyntheticKeyData(
  TestWidgetsFlutterBinding binding, {
  required PhysicalKeyboardKey physicalKey,
  required LogicalKeyboardKey logicalKey,
  required ui.KeyEventDeviceType deviceType,
  required ui.KeyEventType type,
  String? character,
}) {
  final callback = binding.platformDispatcher.onKeyData;
  if (callback == null) {
    throw StateError('Expected platformDispatcher.onKeyData to be registered.');
  }

  return callback(
    ui.KeyData(
      timeStamp: Duration.zero,
      type: type,
      physical: physicalKey.usbHidUsage,
      logical: logicalKey.keyId,
      character: character,
      synthesized: true,
      deviceType: deviceType,
    ),
  );
}
