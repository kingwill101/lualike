import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d_test_bed/game_center/game_center.dart';

class _FakeLauncher extends StatelessWidget {
  const _FakeLauncher({required this.entry, required this.onBack});

  final GameEntry entry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF060816),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Launching ${entry.title}'),
            Text(entry.entryAsset),
            const SizedBox(height: 12),
            TextButton(onPressed: onBack, child: const Text('Back')),
          ],
        ),
      ),
    );
  }
}

Future<void> _pumpTicks(
  WidgetTester tester, {
  int count = 2,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(step);
  }
}

void main() {
  test('game center exposes all vendored demos', () {
    final titles = kDemoEntries.map((entry) => entry.title).toList();

    expect(titles, hasLength(5));
    expect(
      titles,
      containsAll(<String>[
        'Modern Pong',
        'LOVE Example Browser',
        'Pocket Bomber',
        'Shader Explorer',
        'Relic Breach',
      ]),
    );
    expect(
      kDemoEntries
          .singleWhere((entry) => entry.title == 'LOVE Example Browser')
          .entryAsset,
      loveExampleBrowserEntryAsset,
    );
    expect(
      kDemoEntries
          .singleWhere((entry) => entry.title == 'Relic Breach')
          .automaticGc,
      isTrue,
    );
  });

  testWidgets('game center menu renders on narrow screens', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(const GameCenterApp());
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('LOVE Game Center'), findsOneWidget);
    expect(find.text('Modern Pong'), findsOneWidget);
    expect(find.text('LOVE Example Browser'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('game center selects and returns from every demo', (
    tester,
  ) async {
    await tester.pumpWidget(
      GameCenterApp(
        launcherBuilder: (context, entry, onBack) {
          return _FakeLauncher(entry: entry, onBack: onBack);
        },
      ),
    );
    await _pumpTicks(tester);

    for (final entry in kDemoEntries) {
      await tester.ensureVisible(find.text(entry.title));
      await tester.tap(find.text(entry.title));
      await _pumpTicks(tester);

      expect(find.text('Launching ${entry.title}'), findsOneWidget);
      expect(find.text(entry.entryAsset), findsOneWidget);

      await tester.tap(find.text('Back'));
      await _pumpTicks(tester);

      expect(find.text('LOVE Game Center'), findsOneWidget);
    }

    expect(tester.takeException(), isNull);
  });
}
