import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'LoveFlameHarness advances love.timer state from the external frame loop',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(() async {
        await binding.setSurfaceSize(null);
      });
      await binding.setSurfaceSize(const Size(320, 240));

      const script = '''
local saw_positive_delta = false
local saw_positive_fps = false

function love.update(dt)
  local timer_delta = love.timer.getDelta()
  if dt <= 0 then
    error("expected positive dt from harness, got " .. tostring(dt))
  end
  if timer_delta ~= dt then
    error(
      "expected love.timer.getDelta() to match update dt, got "
        .. tostring(timer_delta)
        .. " and "
        .. tostring(dt)
    )
  end

  saw_positive_delta = saw_positive_delta or timer_delta > 0
  saw_positive_fps = saw_positive_fps or love.timer.getFPS() > 0

  if saw_positive_delta and saw_positive_fps then
    love.event.quit()
  end
end
''';

      await tester.pumpWidget(
        MaterialApp(
          home: LoveFlameHarness(
            entryAsset: 'assets/game/main.lua',
            filesystemAdapter: _scriptAdapter(script),
            onQuitRequested: () async {},
          ),
        ),
      );
      await _pumpUntilStatus(tester, 'Running');
      await _pumpUntilStatus(
        tester,
        'Quit',
        step: const Duration(milliseconds: 500),
        maxPumps: 4,
      );
    },
  );
}

LoveAssetBundleFilesystemAdapter _scriptAdapter(String script) {
  return LoveAssetBundleFilesystemAdapter(
    bundle: _MapAssetBundle(<String, List<int>>{
      'assets/game/main.lua': script.codeUnits,
    }),
    assetKeys: const <String>['assets/game/main.lua'],
  );
}

Future<void> _pumpUntilStatus(
  WidgetTester tester,
  String status, {
  Duration step = const Duration(milliseconds: 16),
  int maxPumps = 120,
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
  _MapAssetBundle(this.assets);

  final Map<String, List<int>> assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = assets[key];
    if (bytes == null) {
      throw FlutterError('Missing asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
