import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'LoveFlameHarness routes callback failures through love.errorhandler loops',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(() async {
        await binding.setSurfaceSize(null);
      });
      await binding.setSurfaceSize(const Size(320, 240));

      const script = '''
local function explode()
  error("handled boom")
end

function love.update(dt)
  explode()
end

function love.errorhandler(msg)
  return function()
    love.graphics.print("handled:" .. msg, 16, 24)
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
      await _pumpUntilStatus(tester, 'Error');
      await tester.pump(const Duration(milliseconds: 16));

      final gameFinder = find.byWidgetPredicate(
        (widget) => widget is GameWidget,
      );
      final gameWidget = tester.widget<GameWidget>(gameFinder);
      final game = gameWidget.game as dynamic;
      final text = game.host.graphics.commands.single as LoveTextCommand;
      expect(text.text, contains('handled:'));
      expect(text.text, contains('handled boom'));
      expect(text.text, contains('stack traceback:'));
      expect(text.text, contains("function 'explode'"));
      expect(find.byKey(const Key('error-message')), findsNothing);
    },
  );

  testWidgets(
    'LoveFlameHarness passes the formatted Lua traceback to the default error loop',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(() async {
        await binding.setSurfaceSize(null);
      });
      await binding.setSurfaceSize(const Size(320, 240));

      const script = '''
local function explode()
  error("default boom")
end

function love.update(dt)
  explode()
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
      await _pumpUntilStatus(tester, 'Error');
      await tester.pump(const Duration(milliseconds: 16));

      final gameFinder = find.byWidgetPredicate(
        (widget) => widget is GameWidget,
      );
      final gameWidget = tester.widget<GameWidget>(gameFinder);
      final game = gameWidget.game as dynamic;
      final text = game.host.graphics.commands.single as LoveTextCommand;
      expect(text.text, contains('default boom'));
      expect(text.text, contains('stack traceback:'));
      expect(text.text, contains("function 'explode'"));
      expect(text.text, contains("function 'love.update'"));
      expect(find.byKey(const Key('error-message')), findsNothing);
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
  final currentStatus = statusFinder.evaluate().isEmpty
      ? '<missing>'
      : (tester.widget<Text>(statusFinder).data ?? '<empty>');
  fail(
    'Timed out waiting for status "$status". Current status: $currentStatus',
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
