@Tags(['core'])
library;

import 'package:lualike_test/test.dart';

void main() {
  late Environment env;
  setUpAll(() {
    env = Interpreter().globals;
  });

  group('Environment', () {
    test('defines and retrieves variable correctly', () {
      env.define('a', 5);
      expect(env.get('a'), equals(5));
    });

    test('assigns variable correctly', () {
      env.define('b', 10);
      env.define('b', 15);
      expect(env.get('b'), equals(15));
    });

    test('resolves dotted table paths', () {
      env.define(
        'love',
        Value({
          'graphics': Value({
            'setColor': 42,
          }),
        }),
      );

      final child = Environment(parent: env);
      expect(child.get('love.graphics.setColor'), equals(42));
      expect(child.contains('love.graphics.setColor'), isTrue);
      expect(child.get('love.graphics.missing'), equals(null));
      expect(child.contains('love.graphics.missing'), isFalse);
    });

    test('returns Value(null) for undefined variable', () {
      expect(env.get('c'), equals(null));
    });
  });
}
