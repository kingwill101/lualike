@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/vm.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrVm literals', () {
    test('executes numeric return', () async {
      final chunk = LualikeIrCompiler().compile(parse('return 123'));
      final result = await LualikeIrVm().execute(chunk);
      expect(result, equals(123));
    });

    test('executes boolean return', () async {
      final chunk = LualikeIrCompiler().compile(parse('return false'));
      final result = await LualikeIrVm().execute(chunk);
      expect(result, isFalse);
    });

    test('executes nil return', () async {
      final chunk = LualikeIrCompiler().compile(parse('return nil'));
      final result = await LualikeIrVm().execute(chunk);
      expect(result, isNull);
    });

    test('implicit return yields null', () async {
      final chunk = LualikeIrCompiler().compile(parse(''));
      final result = await LualikeIrVm().execute(chunk);
      expect(result, isNull);
    });
  });
}
