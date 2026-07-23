import 'package:flutter_test/flutter_test.dart';

import 'package:example_flutter_dart_source/main.dart';

void main() {
  testWidgets('renders the dart source example app', (WidgetTester tester) async {
    await tester.pumpWidget(const App(autoRun: false));
    await tester.pumpAndSettle();

    expect(find.text('Dart Source Mode'), findsOneWidget);
  });
}
