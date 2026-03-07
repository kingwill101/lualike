@Tags(['lua_bytecode'])
library;

import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/instruction.dart';
import 'package:lualike/src/lua_bytecode/parser.dart';
import 'package:lualike/src/lua_bytecode/serializer.dart';
import 'package:test/test.dart';

void main() {
  group('lua_bytecode chunk model', () {
    test('official header matches vendored upstream sentinels', () {
      const header = LuaBytecodeChunkHeader.official();

      expect(header.signature, equals(<int>[0x1b, 0x4c, 0x75, 0x61]));
      expect(header.version, equals(0x55));
      expect(header.format, isZero);
      expect(
        header.luacData,
        equals(<int>[0x19, 0x93, 0x0d, 0x0a, 0x1a, 0x0a]),
      );
      expect(header.intSize, equals(4));
      expect(header.instructionSize, equals(4));
      expect(header.luaIntegerSize, equals(8));
      expect(header.luaNumberSize, equals(8));
      expect(header.luacInt, equals(-0x5678));
      expect(header.luacInstruction, equals(0x12345678));
      expect(header.luacNumber, equals(-370.5));
      expect(header.matchesOfficial, isTrue);
    });

    test('constant tags match Lua binary chunk tags', () {
      const constants = <LuaBytecodeConstant>[
        LuaBytecodeNilConstant(),
        LuaBytecodeBooleanConstant(false),
        LuaBytecodeBooleanConstant(true),
        LuaBytecodeIntegerConstant(42),
        LuaBytecodeFloatConstant(3.5),
        LuaBytecodeStringConstant('short', isLong: false),
        LuaBytecodeStringConstant('long', isLong: true),
      ];

      final tags = constants.map((constant) => constant.tag.value).toList();
      expect(tags, equals(<int>[0x00, 0x01, 0x11, 0x03, 0x13, 0x04, 0x14]));
    });

    test('prototype preserves flags and upvalue metadata', () {
      const prototype = LuaBytecodePrototype(
        lineDefined: 10,
        lastLineDefined: 20,
        parameterCount: 2,
        flags:
            LuaBytecodePrototypeFlags.hasHiddenVarargs |
            LuaBytecodePrototypeFlags.hasVarargTable,
        maxStackSize: 5,
        upvalues: <LuaBytecodeUpvalueDescriptor>[
          LuaBytecodeUpvalueDescriptor(
            inStack: true,
            index: 0,
            kind: LuaBytecodeUpvalueKind.toBeClosed,
            name: '_ENV',
          ),
        ],
      );

      expect(prototype.isVararg, isTrue);
      expect(prototype.hasHiddenVarargs, isTrue);
      expect(prototype.needsVarargTable, isTrue);
      expect(
        prototype.upvalues.single.kind,
        equals(LuaBytecodeUpvalueKind.toBeClosed),
      );
      expect(prototype.upvalues.single.name, equals('_ENV'));
    });

    test('serializer round-trips mininteger constants', () {
      final chunk = LuaBytecodeBinaryChunk(
        header: const LuaBytecodeChunkHeader.official(),
        rootUpvalueCount: 1,
        mainPrototype: const LuaBytecodePrototype(
          lineDefined: 0,
          lastLineDefined: 0,
          parameterCount: 0,
          flags: 0,
          maxStackSize: 2,
          constants: <LuaBytecodeConstant>[
            LuaBytecodeIntegerConstant(-9223372036854775808),
          ],
        ),
      );

      final bytes = serializeLuaBytecodeChunk(chunk);
      final parsed = const LuaBytecodeParser().parse(bytes);

      final parsedConstant =
          parsed.mainPrototype.constants.single as LuaBytecodeIntegerConstant;
      expect(
        parsedConstant.value,
        equals(-9223372036854775808),
      );
    });

    test('line mapping follows absolute checkpoints and deltas', () {
      final prototype = LuaBytecodePrototype(
        lineDefined: 10,
        lastLineDefined: 14,
        parameterCount: 0,
        flags: 0,
        maxStackSize: 2,
        code: <LuaBytecodeInstructionWord>[
          LuaBytecodeInstructionWord.abc(opcode: 0, a: 0, b: 0, c: 0),
          LuaBytecodeInstructionWord.abc(opcode: 0, a: 0, b: 0, c: 0),
          LuaBytecodeInstructionWord.abc(opcode: 0, a: 0, b: 0, c: 0),
          LuaBytecodeInstructionWord.abc(opcode: 0, a: 0, b: 0, c: 0),
        ],
        lineInfo: <int>[0, 1, 0, -1],
        absoluteLineInfo: <LuaBytecodeAbsLineInfo>[
          LuaBytecodeAbsLineInfo(pc: 0, line: 10),
        ],
      );

      expect(prototype.lineForPc(0), equals(10));
      expect(prototype.lineForPc(1), equals(11));
      expect(prototype.lineForPc(2), equals(11));
      expect(prototype.lineForPc(3), equals(10));
    });
  });

  group('lua_bytecode instruction packing', () {
    test('decodes iABC fields', () {
      final instruction = LuaBytecodeInstructionWord.abc(
        opcode: 0x35,
        a: 0x12,
        b: 0x34,
        c: 0x56,
        k: true,
      );

      expect(instruction.opcodeValue, equals(0x35));
      expect(instruction.abc, equals((a: 0x12, b: 0x34, c: 0x56, k: true)));
    });

    test('decodes ivABC fields', () {
      final instruction = LuaBytecodeInstructionWord.vabc(
        opcode: 0x13,
        a: 0x12,
        b: 0x21,
        c: 0x155,
      );

      expect(instruction.opcodeValue, equals(0x13));
      expect(instruction.vabc, equals((a: 0x12, b: 0x21, c: 0x155, k: false)));
    });

    test('decodes iABx and iAsBx fields', () {
      final abx = LuaBytecodeInstructionWord.abx(
        opcode: 0x02,
        a: 0x20,
        bx: 0x10101,
      );
      final asbx = LuaBytecodeInstructionWord.asBx(
        opcode: 0x03,
        a: 0x21,
        sBx: -345,
      );

      expect(abx.abx, equals((a: 0x20, bx: 0x10101)));
      expect(asbx.asBx, equals((a: 0x21, sBx: -345)));
    });

    test('decodes iAx and isJ fields', () {
      final ax = LuaBytecodeInstructionWord.ax(opcode: 0x11, ax: 0x1abcdef);
      final sj = LuaBytecodeInstructionWord.sj(opcode: 0x2a, sJ: -1234);

      expect(ax.axFields, equals((ax: 0x1abcdef)));
      expect(sj.sj, equals((sJ: -1234)));
    });
  });
}
