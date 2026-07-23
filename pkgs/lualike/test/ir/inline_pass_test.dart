@Tags(['ir'])
library;

import 'package:lualike/lualike.dart';
import 'package:lualike/src/ir/inline_pass.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart';
import 'package:test/test.dart';

LualikeIrPrototype _prototype({
  required int registerCount,
  required int paramCount,
  required List<LualikeIrInstruction> instructions,
  List<LualikeIrPrototype> prototypes = const <LualikeIrPrototype>[],
  List<LualikeIrConstant> constants = const <LualikeIrConstant>[],
  List<LualikeIrUpvalueDescriptor> upvalues =
      const <LualikeIrUpvalueDescriptor>[],
  bool isVararg = false,
  LualikeIrDebugInfo? debugInfo,
  Map<int, List<int>> constSealPoints = const <int, List<int>>{},
}) {
  return LualikeIrPrototype(
    registerCount: registerCount,
    paramCount: paramCount,
    isVararg: isVararg,
    upvalueDescriptors: upvalues,
    instructions: instructions,
    constants: constants,
    prototypes: prototypes,
    lineDefined: 1,
    lastLineDefined: 1,
    debugInfo: debugInfo,
    registerConstFlags: List<bool>.filled(registerCount, false),
    constSealPoints: constSealPoints,
  );
}

LualikeIrPrototype _binaryCallee({LualikeIrDebugInfo? debugInfo}) {
  return _prototype(
    registerCount: 4,
    paramCount: 2,
    debugInfo: debugInfo,
    instructions: const <LualikeIrInstruction>[
      ABCInstruction(opcode: LualikeIrOpcode.add, a: 2, b: 0, c: 1),
      ABCInstruction(opcode: LualikeIrOpcode.mmBin, a: 0, b: 1, c: 6),
      ABCInstruction(opcode: LualikeIrOpcode.return1, a: 2, b: 0, c: 0),
    ],
  );
}

LualikeIrPrototype _caller(
  LualikeIrPrototype callee, {
  int registerCount = 3,
  LualikeIrDebugInfo? debugInfo,
  Map<int, List<int>> constSealPoints = const <int, List<int>>{},
}) {
  return _prototype(
    registerCount: registerCount,
    paramCount: 0,
    prototypes: <LualikeIrPrototype>[callee],
    debugInfo: debugInfo,
    constSealPoints: constSealPoints,
    instructions: const <LualikeIrInstruction>[
      ABxInstruction(opcode: LualikeIrOpcode.closure, a: 0, bx: 0),
      AsBxInstruction(opcode: LualikeIrOpcode.loadI, a: 1, sBx: 19),
      AsBxInstruction(opcode: LualikeIrOpcode.loadI, a: 2, sBx: 23),
      ABCInstruction(opcode: LualikeIrOpcode.call, a: 0, b: 3, c: 2),
      ABCInstruction(opcode: LualikeIrOpcode.move, a: 1, b: 0, c: 0),
      ABCInstruction(opcode: LualikeIrOpcode.return1, a: 1, b: 0, c: 0),
    ],
  );
}

void main() {
  group('IR function inlining hardening', () {
    test('uses fresh registers and preserves metamethod event operands', () {
      final result = inlineFunctions(_caller(_binaryCallee()));

      expect(result.registerCount, equals(5));
      expect(
        result.instructions.map((instruction) => instruction.opcode),
        isNot(contains(LualikeIrOpcode.closure)),
      );
      expect(
        result.instructions.map((instruction) => instruction.opcode),
        isNot(contains(LualikeIrOpcode.call)),
      );

      final add = result.instructions.whereType<ABCInstruction>().firstWhere(
        (instruction) => instruction.opcode == LualikeIrOpcode.add,
      );
      expect((add.a, add.b, add.c), equals((3, 1, 2)));

      final metamethod = result.instructions
          .whereType<ABCInstruction>()
          .firstWhere(
            (instruction) => instruction.opcode == LualikeIrOpcode.mmBin,
          );
      expect((metamethod.a, metamethod.b), equals((1, 2)));
      expect(
        metamethod.c,
        equals(6),
        reason: 'C is the __add event, not a reg',
      );
    });

    test(
      'preserves immediate fields instead of treating them as registers',
      () {
        final callee = _prototype(
          registerCount: 2,
          paramCount: 1,
          instructions: const <LualikeIrInstruction>[
            ABCInstruction(opcode: LualikeIrOpcode.addI, a: 1, b: 0, c: -1),
            ABCInstruction(opcode: LualikeIrOpcode.mmBinI, a: 0, b: -1, c: 7),
            ABCInstruction(opcode: LualikeIrOpcode.return1, a: 1, b: 0, c: 0),
          ],
        );
        final caller = _prototype(
          registerCount: 2,
          paramCount: 0,
          prototypes: <LualikeIrPrototype>[callee],
          instructions: const <LualikeIrInstruction>[
            ABxInstruction(opcode: LualikeIrOpcode.closure, a: 0, bx: 0),
            AsBxInstruction(opcode: LualikeIrOpcode.loadI, a: 1, sBx: 4),
            ABCInstruction(opcode: LualikeIrOpcode.call, a: 0, b: 2, c: 2),
            ABCInstruction(opcode: LualikeIrOpcode.return1, a: 0, b: 0, c: 0),
          ],
        );

        final result = inlineFunctions(caller);
        final add = result.instructions.whereType<ABCInstruction>().firstWhere(
          (instruction) => instruction.opcode == LualikeIrOpcode.addI,
        );
        final metamethod = result.instructions
            .whereType<ABCInstruction>()
            .firstWhere(
              (instruction) => instruction.opcode == LualikeIrOpcode.mmBinI,
            );
        expect(add.c, equals(-1));
        expect(metamethod.b, equals(-1));
        expect(metamethod.c, equals(7));
      },
    );

    test('remaps caller line, local, and const-seal PCs', () {
      final caller = _caller(
        _binaryCallee(),
        debugInfo: const LualikeIrDebugInfo(
          lineInfo: <int>[1, 2, 3, 4, 5, 6],
          localNames: <LocalDebugEntry>[
            LocalDebugEntry(name: 'result', startPc: 4, endPc: 6, register: 0),
          ],
          absoluteSourcePath: '=(inline-metadata)',
        ),
        constSealPoints: const <int, List<int>>{
          4: <int>[0],
        },
      );

      final result = inlineFunctions(caller);
      expect(result.instructions, hasLength(7));
      expect(result.debugInfo?.lineInfo, hasLength(7));
      expect(result.debugInfo?.localNames.single.startPc, equals(5));
      expect(result.debugInfo?.localNames.single.endPc, equals(7));
      expect(result.constSealPoints, containsPair(5, <int>[0]));
    });

    test('keeps debug-observable callees unless debug will be stripped', () {
      final callee = _binaryCallee(
        debugInfo: const LualikeIrDebugInfo(
          lineInfo: <int>[1, 1, 1],
          localNames: <LocalDebugEntry>[
            LocalDebugEntry(name: 'a', startPc: 0, endPc: 3, register: 0),
          ],
          absoluteSourcePath: '=(debug-callee)',
        ),
      );
      final caller = _caller(callee);

      expect(inlineFunctions(caller).instructions, same(caller.instructions));
      expect(
        inlineFunctions(
          caller,
          preserveDebug: false,
        ).instructions.map((instruction) => instruction.opcode),
        isNot(contains(LualikeIrOpcode.call)),
      );
    });

    test('keeps closures observed as caller debug locals', () {
      final caller = _caller(
        _binaryCallee(),
        debugInfo: const LualikeIrDebugInfo(
          lineInfo: <int>[1, 1, 1, 1, 1, 1],
          localNames: <LocalDebugEntry>[
            LocalDebugEntry(
              name: 'callable',
              startPc: 0,
              endPc: 4,
              register: 0,
            ),
          ],
          absoluteSourcePath: '=(debug-caller)',
        ),
      );

      expect(inlineFunctions(caller).instructions, same(caller.instructions));
      expect(
        inlineFunctions(
          caller,
          preserveDebug: false,
        ).instructions.map((instruction) => instruction.opcode),
        isNot(contains(LualikeIrOpcode.call)),
      );
    });

    test('skips candidates that exceed the bytecode register budget', () {
      final caller = _caller(_binaryCallee(), registerCount: 253);

      final result = inlineFunctions(caller);

      expect(result.registerCount, equals(253));
      expect(result.instructions, same(caller.instructions));
    });

    test('applies register budgets independently per candidate', () {
      final callee = _prototype(
        registerCount: 2,
        paramCount: 1,
        instructions: const <LualikeIrInstruction>[
          ABCInstruction(opcode: LualikeIrOpcode.addI, a: 1, b: 0, c: 1),
          ABCInstruction(opcode: LualikeIrOpcode.return1, a: 1, b: 0, c: 0),
        ],
      );
      final caller = _prototype(
        registerCount: 252,
        paramCount: 0,
        prototypes: <LualikeIrPrototype>[callee, callee],
        instructions: const <LualikeIrInstruction>[
          ABxInstruction(opcode: LualikeIrOpcode.closure, a: 0, bx: 0),
          AsBxInstruction(opcode: LualikeIrOpcode.loadI, a: 1, sBx: 1),
          ABCInstruction(opcode: LualikeIrOpcode.call, a: 0, b: 2, c: 2),
          ABxInstruction(opcode: LualikeIrOpcode.closure, a: 2, bx: 1),
          AsBxInstruction(opcode: LualikeIrOpcode.loadI, a: 3, sBx: 2),
          ABCInstruction(opcode: LualikeIrOpcode.call, a: 2, b: 2, c: 2),
          ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
        ],
      );

      final result = inlineFunctions(caller);

      expect(result.registerCount, equals(253));
      expect(
        result.instructions.where(
          (instruction) => instruction.opcode == LualikeIrOpcode.call,
        ),
        hasLength(1),
      );
      expect(
        result.instructions.where(
          (instruction) => instruction.opcode == LualikeIrOpcode.closure,
        ),
        hasLength(1),
      );
    });

    test('rejects constants, captures, and control flow conservatively', () {
      final constantCallee = _prototype(
        registerCount: 1,
        paramCount: 0,
        constants: const <LualikeIrConstant>[IntegerConstant(42)],
        instructions: const <LualikeIrInstruction>[
          ABxInstruction(opcode: LualikeIrOpcode.loadK, a: 0, bx: 0),
          ABCInstruction(opcode: LualikeIrOpcode.return1, a: 0, b: 0, c: 0),
        ],
      );
      final capturedCallee = _prototype(
        registerCount: 1,
        paramCount: 0,
        upvalues: const <LualikeIrUpvalueDescriptor>[
          LualikeIrUpvalueDescriptor(inStack: 0, index: 0),
        ],
        instructions: const <LualikeIrInstruction>[
          ABCInstruction(opcode: LualikeIrOpcode.getUpval, a: 0, b: 0, c: 0),
          ABCInstruction(opcode: LualikeIrOpcode.return1, a: 0, b: 0, c: 0),
        ],
      );

      for (final callee in <LualikeIrPrototype>[
        constantCallee,
        capturedCallee,
      ]) {
        final caller = _prototype(
          registerCount: 1,
          paramCount: 0,
          prototypes: <LualikeIrPrototype>[callee],
          instructions: const <LualikeIrInstruction>[
            ABxInstruction(opcode: LualikeIrOpcode.closure, a: 0, bx: 0),
            ABCInstruction(opcode: LualikeIrOpcode.call, a: 0, b: 1, c: 2),
            ABCInstruction(opcode: LualikeIrOpcode.return1, a: 0, b: 0, c: 0),
          ],
        );
        expect(inlineFunctions(caller).instructions, same(caller.instructions));
      }

      final branchingCaller = _caller(_binaryCallee());
      final withJump = _prototype(
        registerCount: branchingCaller.registerCount,
        paramCount: 0,
        prototypes: branchingCaller.prototypes,
        instructions: <LualikeIrInstruction>[
          ...branchingCaller.instructions,
          const AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: 0),
        ],
      );
      expect(
        inlineFunctions(withJump).instructions,
        same(withJump.instructions),
      );
    });

    test('rejects varargs, multi-results, close state, and wrong arity', () {
      final varargCallee = _prototype(
        registerCount: 1,
        paramCount: 0,
        isVararg: true,
        instructions: const <LualikeIrInstruction>[
          ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
        ],
      );
      final multiResultCallee = _prototype(
        registerCount: 2,
        paramCount: 0,
        instructions: const <LualikeIrInstruction>[
          ABCInstruction(opcode: LualikeIrOpcode.ret, a: 0, b: 3, c: 0),
        ],
      );
      final closeCallee = _prototype(
        registerCount: 1,
        paramCount: 0,
        instructions: const <LualikeIrInstruction>[
          ABCInstruction(opcode: LualikeIrOpcode.tbc, a: 0, b: 0, c: 0),
          ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
        ],
      );

      for (final callee in <LualikeIrPrototype>[
        varargCallee,
        multiResultCallee,
        closeCallee,
      ]) {
        final caller = _prototype(
          registerCount: 1,
          paramCount: 0,
          prototypes: <LualikeIrPrototype>[callee],
          instructions: const <LualikeIrInstruction>[
            ABxInstruction(opcode: LualikeIrOpcode.closure, a: 0, bx: 0),
            ABCInstruction(opcode: LualikeIrOpcode.call, a: 0, b: 1, c: 1),
            ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
          ],
        );
        expect(
          inlineFunctions(caller, preserveDebug: false).instructions,
          same(caller.instructions),
        );
      }

      final wrongArity = _caller(_binaryCallee());
      final instructions = <LualikeIrInstruction>[...wrongArity.instructions];
      instructions[3] = const ABCInstruction(
        opcode: LualikeIrOpcode.call,
        a: 0,
        b: 2,
        c: 2,
      );
      final malformedCall = _prototype(
        registerCount: wrongArity.registerCount,
        paramCount: 0,
        prototypes: wrongArity.prototypes,
        instructions: instructions,
      );
      expect(
        inlineFunctions(malformedCall).instructions,
        same(malformedCall.instructions),
      );
    });

    test(
      'strip-debug pipeline executes an inlined anonymous function',
      () async {
        final artifact =
            CompilePipeline(
                  config: const CompilePipelineConfig(
                    stripDebug: true,
                    enableFunctionInlining: true,
                    target: CompileBackend.luaBytecode,
                  ),
                ).compileSource('''
local result = (function(a, b) return a + b end)(19, 23)
return result
''')
                as LuaBytecodeArtifact;

        expect(
          artifact.chunk.mainPrototype.code.map((word) => word.opcode),
          isNot(contains(Opcode.closure)),
        );
        expect(
          artifact.chunk.mainPrototype.code.map((word) => word.opcode),
          isNot(contains(Opcode.call)),
        );

        final runtime = LuaBytecodeRuntime();
        final chunk = await runtime.loadBytecode(
          artifact.serializedBytes,
          moduleName: 'inline-execution.lua',
        );
        final result = await runtime.callFunction(chunk, const <Object?>[]);
        expect((result as Value).raw, equals(42));
      },
    );
  });
}
