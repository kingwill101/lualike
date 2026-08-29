import 'package:lualike_test/test.dart';

final class _InlineFrameProbe extends BuiltinFunction {
  _InlineFrameProbe(this.vm) : super(vm);

  final Interpreter vm;
  int? observedDepth;
  List<Object?>? observedArgs;
  int fastCalls = 0;

  @override
  bool get canBytecodeInlineWithoutManagedFrame => true;

  @override
  Object? fastCall0() {
    fastCalls++;
    observedDepth = vm.callStack.depth;
    observedArgs = const <Object?>[];
    return 42;
  }

  @override
  Object? call(List<Object?> args) {
    observedDepth = vm.callStack.depth;
    observedArgs = List<Object?>.of(args);
    return vm.constantPrimitiveValue(42);
  }
}

void main() {
  group('AST inline builtin frame', () {
    test('skips the managed call frame for an eligible leaf builtin', () async {
      final vm = Interpreter();
      final probe = _InlineFrameProbe(vm);
      vm.globals.define('probe', probe);

      final result = await FunctionCall(Identifier('probe'), []).accept(vm);

      expect(result, 42);
      expect(probe.observedDepth, 0);
      expect(vm.callStack.depth, 0);
      expect(probe.fastCalls, 1);
    });

    test('falls back to wrapped-argument call at unsupported arity', () async {
      final vm = Interpreter();
      final probe = _InlineFrameProbe(vm);
      vm.globals.define('probe', probe);

      await FunctionCall(Identifier('probe'), [
        BinaryExpression(NumberLiteral(1), '+', NumberLiteral(2)),
        NumberLiteral(4),
      ]).accept(vm);

      expect(probe.fastCalls, 0);
      expect(probe.observedArgs, hasLength(2));
      expect(probe.observedArgs, everyElement(isA<Value>()));
      expect(probe.observedArgs!.map((arg) => (arg as Value).unwrap()), [3, 4]);
    });

    test('keeps the managed frame while a debug hook is installed', () async {
      final vm = Interpreter();
      final probe = _InlineFrameProbe(vm);
      vm.globals.define('probe', probe);
      vm.debugHookFunction = Value((List<Object?> args) => null);

      final result = await FunctionCall(Identifier('probe'), []).accept(vm);

      expect((result as Value).unwrap(), 42);
      expect(probe.observedDepth, 1);
      expect(vm.callStack.depth, 0);
      expect(probe.fastCalls, 0);
    });
  });
}
