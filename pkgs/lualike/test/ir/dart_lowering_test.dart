import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/dart_lowering.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

String _dart(String source) {
  final program = parse('local x = $source; return x');
  final chunk = LualikeIrCompiler().compile(program);
  return LualikeIrToDart(chunk: chunk).generateModule();
}

void main() {
  group('Dart lowering', () {
    test('add', () {
      final d = _dart('1 + 2');
      expect(d, contains('Value(1)'));
      expect(d, contains('+ Value(2)'));
      expect(d, contains('return r['));
    });

    test('sub', () {
      final d = _dart('5 - 3');
      expect(d, contains('Value(5)'));
    });

    test('not', () {
      final d = _dart('not false');
      expect(d, contains('isTruthy'));
    });

    test('state machine', () {
      final d = _dart('1 + 2');
      expect(d, contains('switch (pc)'));
      expect(d, contains('break;'));
    });
  });
}
