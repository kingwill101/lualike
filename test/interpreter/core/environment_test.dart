@Tags(['core'])
import 'package:lualike/testing.dart';

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

    test('returns Value(null) for undefined variable', () {
      expect(env.get('c'), equals(null));
    });
  });
}
