@Tags(['ir'])
library;

import 'package:lualike/lualike.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart';
import 'package:test/test.dart';

const _rootEnv = <LualikeIrUpvalueDescriptor>[
  LualikeIrUpvalueDescriptor(inStack: 1, index: 0),
];

LualikeIrPrototype _prototype({
  required List<LualikeIrInstruction> instructions,
  int registerCount = 1,
  List<LualikeIrConstant> constants = const <LualikeIrConstant>[],
}) {
  return LualikeIrPrototype(
    registerCount: registerCount,
    paramCount: 0,
    isVararg: false,
    upvalueDescriptors: _rootEnv,
    instructions: instructions,
    constants: constants,
    prototypes: const <LualikeIrPrototype>[],
    lineDefined: 0,
    lastLineDefined: 0,
    debugInfo: const LualikeIrDebugInfo(
      lineInfo: <int>[],
      upvalueNames: <String>['_ENV'],
      absoluteSourcePath: '=(lowering-audit)',
    ),
    registerConstFlags: List<bool>.filled(registerCount, false),
    constSealPoints: const <int, List<int>>{},
  );
}

LuaBytecodePrototype _lower(LualikeIrPrototype prototype) {
  return lowerIrChunkToLuaBytecodeChunk(
    LualikeIrChunk(
      flags: const LualikeIrChunkFlags(),
      mainPrototype: prototype,
    ),
  ).mainPrototype;
}

void main() {
  group('IR bytecode lowering contract', () {
    test('compiler records root _ENV before lowering', () {
      final ir = LualikeIrCompiler().compile(parse('return 1'));

      expect(ir.mainPrototype.upvalueDescriptors, hasLength(1));
      expect(ir.mainPrototype.upvalueDescriptors.single.inStack, equals(1));
      expect(ir.mainPrototype.upvalueDescriptors.single.index, equals(0));
      expect(ir.mainPrototype.debugInfo?.upvalueNames, equals(['_ENV']));
    });

    test('lowering rejects a main prototype without root _ENV', () {
      final prototype = LualikeIrPrototype(
        registerCount: 0,
        paramCount: 0,
        isVararg: false,
        upvalueDescriptors: const <LualikeIrUpvalueDescriptor>[],
        instructions: const <LualikeIrInstruction>[],
        constants: const <LualikeIrConstant>[],
        prototypes: const <LualikeIrPrototype>[],
        lineDefined: 0,
        lastLineDefined: 0,
        registerConstFlags: const <bool>[],
        constSealPoints: const <int, List<int>>{},
      );

      expect(
        () => _lower(prototype),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('must declare _ENV'),
          ),
        ),
      );
    });

    test('lowering rejects malformed root _ENV metadata', () {
      final prototype = LualikeIrPrototype(
        registerCount: 0,
        paramCount: 0,
        isVararg: false,
        upvalueDescriptors: const <LualikeIrUpvalueDescriptor>[
          LualikeIrUpvalueDescriptor(inStack: 0, index: 1),
        ],
        instructions: const <LualikeIrInstruction>[],
        constants: const <LualikeIrConstant>[],
        prototypes: const <LualikeIrPrototype>[],
        lineDefined: 0,
        lastLineDefined: 0,
        debugInfo: const LualikeIrDebugInfo(
          lineInfo: <int>[],
          upvalueNames: <String>['not_env'],
          absoluteSourcePath: '=(malformed-env)',
        ),
        registerConstFlags: const <bool>[],
        constSealPoints: const <int, List<int>>{},
      );

      expect(
        () => _lower(prototype),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('upvalue 0 must be _ENV'),
          ),
        ),
      );
    });

    test('reserves only scratch slots used by expansions', () {
      final direct = _lower(
        _prototype(
          registerCount: 3,
          instructions: const <LualikeIrInstruction>[
            ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
          ],
        ),
      );
      final oneScratch = _lower(
        _prototype(
          registerCount: 3,
          instructions: const <LualikeIrInstruction>[
            ABCInstruction(opcode: LualikeIrOpcode.shlI, a: 0, b: 0, c: 3),
          ],
        ),
      );
      final twoScratch = _lower(
        _prototype(
          registerCount: 3,
          constants: List<LualikeIrConstant>.generate(
            257,
            (index) => IntegerConstant(index),
          ),
          instructions: const <LualikeIrInstruction>[
            ABCInstruction(
              opcode: LualikeIrOpcode.setTabUp,
              a: 0,
              b: 256,
              c: 0,
            ),
          ],
        ),
      );

      expect(direct.maxStackSize, equals(3));
      expect(oneScratch.maxStackSize, equals(4));
      expect(twoScratch.maxStackSize, equals(5));
    });

    test('high constant table writes preserve constant-value k bit', () {
      final constants = List<LualikeIrConstant>.generate(
        257,
        (index) => IntegerConstant(index),
      );
      final setField = _lower(
        _prototype(
          constants: constants,
          instructions: const <LualikeIrInstruction>[
            ABCInstruction(
              opcode: LualikeIrOpcode.setField,
              a: 0,
              b: 256,
              c: 0,
              k: true,
            ),
          ],
        ),
      );
      final setTabUp = _lower(
        _prototype(
          constants: constants,
          instructions: const <LualikeIrInstruction>[
            ABCInstruction(
              opcode: LualikeIrOpcode.setTabUp,
              a: 0,
              b: 256,
              c: 0,
              k: true,
            ),
          ],
        ),
      );

      expect(
        setField.code
            .singleWhere((word) => word.opcode == Opcode.setTable)
            .kFlag,
        isTrue,
      );
      expect(
        setTabUp.code
            .singleWhere((word) => word.opcode == Opcode.setTable)
            .kFlag,
        isTrue,
      );
    });

    test('left-shift immediate remains a semantic value', () {
      final lowered = _lower(
        _prototype(
          instructions: const <LualikeIrInstruction>[
            ABCInstruction(opcode: LualikeIrOpcode.shlI, a: 0, b: 0, c: 511),
          ],
        ),
      );

      expect(lowered.code.first.opcode, Opcode.loadI);
      expect(lowered.code.first.sBx, equals(511));
    });

    test('signed C boundary 128 lowers without a scratch register', () {
      final lowered = _lower(
        _prototype(
          registerCount: 2,
          instructions: const <LualikeIrInstruction>[
            ABCInstruction(opcode: LualikeIrOpcode.eqI, a: 0, b: 1, c: 128),
          ],
        ),
      );

      expect(lowered.maxStackSize, equals(2));
      expect(lowered.code.first.opcode, Opcode.eqI);
      expect(lowered.code.first.signedB, equals(128));
    });

    test('empty code safely ignores otherwise populated debug lines', () {
      final lowered = _lower(
        LualikeIrPrototype(
          registerCount: 0,
          paramCount: 0,
          isVararg: false,
          upvalueDescriptors: _rootEnv,
          instructions: const <LualikeIrInstruction>[],
          constants: const <LualikeIrConstant>[],
          prototypes: const <LualikeIrPrototype>[],
          lineDefined: 0,
          lastLineDefined: 0,
          debugInfo: const LualikeIrDebugInfo(
            lineInfo: <int>[1],
            upvalueNames: <String>['_ENV'],
            absoluteSourcePath: '=(empty-debug)',
          ),
          registerConstFlags: const <bool>[],
          constSealPoints: const <int, List<int>>{},
        ),
      );

      expect(lowered.code, isEmpty);
      expect(lowered.lineInfo, isEmpty);
      expect(lowered.absoluteLineInfo, isEmpty);
    });

    test('rejects jumps outside the finalized IR instruction stream', () {
      expect(
        () => _lower(
          _prototype(
            instructions: const <LualikeIrInstruction>[
              AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: 1),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('invalid JMP target'),
          ),
        ),
      );
    });

    test('rejects malformed finalized table and concat shapes', () {
      final malformed = <LualikeIrInstruction>[
        const ABCInstruction(
          opcode: LualikeIrOpcode.newTable,
          a: 0,
          b: -1,
          c: 0,
        ),
        const ABCInstruction(opcode: LualikeIrOpcode.setList, a: 0, b: 0, c: 0),
        const ABCInstruction(opcode: LualikeIrOpcode.concat, a: 0, b: 2, c: 1),
      ];

      for (final instruction in malformed) {
        expect(
          () => _lower(_prototype(instructions: [instruction])),
          throwsA(isA<StateError>()),
          reason: '${instruction.opcode.name} must not be normalized',
        );
      }
    });
  });
}
