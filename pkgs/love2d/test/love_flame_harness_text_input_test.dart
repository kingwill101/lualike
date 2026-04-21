import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'LoveFlameHarness routes Flutter text input updates into LOVE textedited and textinput callbacks',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      binding.testTextInput.log.clear();

      const script = '''
local firstEdited = nil
local lastEdited = nil

function love.load()
  love.keyboard.setTextInput(true, 12, 20, 160, 48)
end

function love.textedited(text, start, length)
  local poll = love.event.poll()
  while true do
    local name, queuedText, queuedStart, queuedLength = poll()
    if name == nil then
      return
    end
    if name == "textedited"
        and queuedText == text
        and queuedStart == start
        and queuedLength == length then
      local formatted = string.format("%s|%s|%d|%d|%s|%d|%d", name, queuedText, queuedStart, queuedLength, text, start, length)
      if firstEdited == nil then
        firstEdited = formatted
      end
      lastEdited = formatted
      return
    end
  end
end

function love.textinput(text)
  local poll = love.event.poll()
  while true do
    local name, queuedText = poll()
    if name == nil then
      return
    end
    if name == "textinput" and queuedText == text then
      assert(firstEdited == "textedited|he|1|1|he|1|1", "expected candidate text callback")
      assert(lastEdited == "textedited||0|0||0|0", "expected cleared composition callback")
      assert(string.format("%s|%s|%s", name, queuedText, text) == "textinput|he|he", "expected committed text callback")
      assert(love.keyboard.hasTextInput(), "expected text input to be enabled before disabling it in the callback")
      love.keyboard.setTextInput(false)
      love.event.quit()
      return
    end
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

      expect(binding.testTextInput.hasAnyClients, isTrue);
      expect(binding.testTextInput.isVisible, isTrue);

      final markedTextCall = binding.testTextInput.log.lastWhere(
        (call) =>
            call.method == 'TextInput.setMarkedTextRect' &&
            (call.arguments as Map<String, dynamic>)['x'] == 12.0 &&
            (call.arguments as Map<String, dynamic>)['y'] == 20.0 &&
            (call.arguments as Map<String, dynamic>)['width'] == 160.0 &&
            (call.arguments as Map<String, dynamic>)['height'] == 48.0,
      );
      expect(markedTextCall.method, 'TextInput.setMarkedTextRect');

      binding.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'he',
          selection: TextSelection(baseOffset: 1, extentOffset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();

      binding.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'he',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await _pumpUntilStatus(tester, 'Quit');
      await tester.pump();
      await tester.pump();

      expect(binding.testTextInput.hasAnyClients, isFalse);
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
