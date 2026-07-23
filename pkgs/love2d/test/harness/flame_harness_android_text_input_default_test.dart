import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'LoveFlameHarness does not attach Flutter text input by default on Android',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;

        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        binding.testTextInput.log.clear();

        const script = '''
function love.load()
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
        expect(binding.testTextInput.hasAnyClients, isFalse);
        expect(binding.testTextInput.isVisible, isFalse);
        expect(find.byKey(const Key('error-message')), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
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
