import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeVm literals', () {
    test('executes numeric return', () async {
      final chunk = BytecodeCompiler().compile(parse('return 123'));
      final result = await BytecodeVm().execute(chunk);
      expect(result, equals(123));
    });

    test('executes boolean return', () async {
      final chunk = BytecodeCompiler().compile(parse('return false'));
      final result = await BytecodeVm().execute(chunk);
      expect(result, isFalse);
    });

    test('executes nil return', () async {
      final chunk = BytecodeCompiler().compile(parse('return nil'));
      final result = await BytecodeVm().execute(chunk);
      expect(result, isNull);
    });

    test('implicit return yields null', () async {
      final chunk = BytecodeCompiler().compile(parse(''));
      final result = await BytecodeVm().execute(chunk);
      expect(result, isNull);
    });
  });
}
