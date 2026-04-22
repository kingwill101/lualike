import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'LoveFlameHarness applies LOVE mouse cursor visibility and system cursor changes',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      const script = '''
local stage = 0

function love.load()
  love.mouse.setCursor(love.mouse.getSystemCursor("hand"))
end

function love.mousepressed(x, y, button, istouch, presses)
  if stage == 0 then
    stage = 1
    love.mouse.setVisible(false)
    return
  end

  if stage == 1 then
    stage = 2
    love.mouse.setVisible(true)
    love.mouse.setCursor(love.mouse.getSystemCursor("crosshair"))
    return
  end

  if stage == 2 then
    stage = 3
    love.mouse.setRelativeMode(true)
    return
  end

  love.event.quit()
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

      expect(_currentMouseCursor(tester), SystemMouseCursors.click);

      await tester.tapAt(tester.getCenter(find.byType(LoveFlameHarness)));
      await _pumpUntilCursor(tester, SystemMouseCursors.none);

      await tester.tapAt(tester.getCenter(find.byType(LoveFlameHarness)));
      await _pumpUntilCursor(tester, SystemMouseCursors.precise);

      await tester.tapAt(tester.getCenter(find.byType(LoveFlameHarness)));
      await _pumpUntilCursor(tester, SystemMouseCursors.none);

      await tester.tapAt(tester.getCenter(find.byType(LoveFlameHarness)));
      await _pumpUntilStatus(tester, 'Quit');

      expect(find.byKey(const Key('error-message')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('LoveFlameHarness renders LOVE image cursors as an overlay', (
    tester,
  ) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    const script = '''
function love.load()
  local cursor = love.mouse.newCursor(love.image.newImageData(8, 8), 2, 3)
  love.mouse.setCursor(cursor)
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

    final listenerBox = tester.renderObject<RenderBox>(
      find
          .descendant(
            of: find.byType(LoveFlameHarness),
            matching: find.byType(Listener),
          )
          .first,
    );
    const localTarget = Offset(123, 210);
    final globalTarget = listenerBox.localToGlobal(localTarget);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();
    await gesture.moveTo(globalTarget);
    await tester.pump(const Duration(milliseconds: 16));

    expect(_currentMouseCursor(tester), SystemMouseCursors.none);
    final cursorFinder = find.byKey(const Key('love-image-cursor'));
    expect(cursorFinder, findsOneWidget);
    expect(tester.getSize(cursorFinder), const Size(8, 8));
    final cursorTopLeft = tester.getTopLeft(cursorFinder);
    expect(cursorTopLeft.dx, closeTo(globalTarget.dx - 2, 0.01));
    expect(cursorTopLeft.dy, closeTo(globalTarget.dy - 3, 0.01));
    expect(find.byKey(const Key('error-message')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'LoveFlameHarness renders a synthetic system cursor after love.mouse.setPosition',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      const script = '''
function love.load()
  love.mouse.setPosition(120, 150)
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
      await tester.pump(const Duration(milliseconds: 16));

      expect(_currentMouseCursor(tester), SystemMouseCursors.none);
      final cursorFinder = find.byKey(const Key('love-system-cursor'));
      expect(cursorFinder, findsOneWidget);

      final listenerBox = tester.renderObject<RenderBox>(
        find
            .descendant(
              of: find.byType(LoveFlameHarness),
              matching: find.byType(Listener),
            )
            .first,
      );
      final expectedTopLeft = listenerBox.localToGlobal(const Offset(120, 150));
      final cursorTopLeft = tester.getTopLeft(cursorFinder);
      expect(cursorTopLeft.dx, closeTo(expectedTopLeft.dx, 0.01));
      expect(cursorTopLeft.dy, closeTo(expectedTopLeft.dy, 0.01));
      expect(find.byKey(const Key('error-message')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

MouseCursor _currentMouseCursor(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(LoveFlameHarness),
    matching: find.byType(MouseRegion),
  );
  return tester.widget<MouseRegion>(finder.first).cursor;
}

Future<void> _pumpUntilCursor(
  WidgetTester tester,
  MouseCursor cursor, {
  Duration step = const Duration(milliseconds: 16),
  int maxPumps = 80,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await tester.pump(step);
    if (_currentMouseCursor(tester) == cursor) {
      return;
    }
  }

  fail(
    'Expected cursor "$cursor". Current cursor: ${_currentMouseCursor(tester)}',
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
