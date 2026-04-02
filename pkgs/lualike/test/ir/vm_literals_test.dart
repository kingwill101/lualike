@Tags(['ir'])
library;

import 'package:lualike/src/config.dart';
import 'package:lualike/src/executor.dart';
import 'package:test/test.dart';

void main() {
  group('Lualike IR lowered literals', () {
    test('executes numeric return', () async {
      final result = await executeCode('return 123', mode: EngineMode.ir);
      expect(result, equals(123));
    });

    test('executes boolean return', () async {
      final result = await executeCode('return false', mode: EngineMode.ir);
      expect(result, isFalse);
    });

    test('executes nil return', () async {
      final result = await executeCode('return nil', mode: EngineMode.ir);
      expect(result, isNull);
    });

    test('implicit return yields null', () async {
      final result = await executeCode('', mode: EngineMode.ir);
      expect(result, isNull);
    });
  });
}
