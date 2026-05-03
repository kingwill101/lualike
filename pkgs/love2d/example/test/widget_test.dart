import 'package:flutter_test/flutter_test.dart';
import 'package:love2d_test_bed/game_center/game_center.dart';

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
}
