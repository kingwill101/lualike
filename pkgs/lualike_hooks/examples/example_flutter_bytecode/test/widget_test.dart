import 'package:flutter_test/flutter_test.dart';

import 'package:example_flutter_bytecode/main.dart';

void main() {
  testWidgets('renders the bytecode example app', (WidgetTester tester) async {
    await tester.pumpWidget(const App(autoRun: false));
    await tester.pumpAndSettle();

    expect(find.text('Bytecode Mode'), findsOneWidget);
  });
}
