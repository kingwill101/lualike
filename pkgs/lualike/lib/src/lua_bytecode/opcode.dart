import 'instruction.dart';

final class LuaBytecodeOpcodeInfo {
  const LuaBytecodeOpcodeInfo({
    required this.code,
    required this.name,
    required this.mode,
  });

  final int code;
  final String name;
  final LuaBytecodeInstructionMode mode;
}

abstract final class LuaBytecodeOpcodes {
  static const List<LuaBytecodeOpcodeInfo> table = <LuaBytecodeOpcodeInfo>[
    LuaBytecodeOpcodeInfo(
      code: 0,
      name: 'MOVE',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 1,
      name: 'LOADI',
      mode: LuaBytecodeInstructionMode.iasbx,
    ),
    LuaBytecodeOpcodeInfo(
      code: 2,
      name: 'LOADF',
      mode: LuaBytecodeInstructionMode.iasbx,
    ),
    LuaBytecodeOpcodeInfo(
      code: 3,
      name: 'LOADK',
      mode: LuaBytecodeInstructionMode.iabx,
    ),
    LuaBytecodeOpcodeInfo(
      code: 4,
      name: 'LOADKX',
      mode: LuaBytecodeInstructionMode.iabx,
    ),
    LuaBytecodeOpcodeInfo(
      code: 5,
      name: 'LOADFALSE',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 6,
      name: 'LFALSESKIP',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 7,
      name: 'LOADTRUE',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 8,
      name: 'LOADNIL',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 9,
      name: 'GETUPVAL',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 10,
      name: 'SETUPVAL',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 11,
      name: 'GETTABUP',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 12,
      name: 'GETTABLE',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 13,
      name: 'GETI',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 14,
      name: 'GETFIELD',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 15,
      name: 'SETTABUP',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 16,
      name: 'SETTABLE',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 17,
      name: 'SETI',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 18,
      name: 'SETFIELD',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 19,
      name: 'NEWTABLE',
      mode: LuaBytecodeInstructionMode.ivabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 20,
      name: 'SELF',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 21,
      name: 'ADDI',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 22,
      name: 'ADDK',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 23,
      name: 'SUBK',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 24,
      name: 'MULK',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 25,
      name: 'MODK',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 26,
      name: 'POWK',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 27,
      name: 'DIVK',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 28,
      name: 'IDIVK',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 29,
      name: 'BANDK',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 30,
      name: 'BORK',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 31,
      name: 'BXORK',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 32,
      name: 'SHLI',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 33,
      name: 'SHRI',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 34,
      name: 'ADD',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 35,
      name: 'SUB',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 36,
      name: 'MUL',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 37,
      name: 'MOD',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 38,
      name: 'POW',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 39,
      name: 'DIV',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 40,
      name: 'IDIV',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 41,
      name: 'BAND',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 42,
      name: 'BOR',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 43,
      name: 'BXOR',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 44,
      name: 'SHL',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 45,
      name: 'SHR',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 46,
      name: 'MMBIN',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 47,
      name: 'MMBINI',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 48,
      name: 'MMBINK',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 49,
      name: 'UNM',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 50,
      name: 'BNOT',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 51,
      name: 'NOT',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 52,
      name: 'LEN',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 53,
      name: 'CONCAT',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 54,
      name: 'CLOSE',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 55,
      name: 'TBC',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 56,
      name: 'JMP',
      mode: LuaBytecodeInstructionMode.isj,
    ),
    LuaBytecodeOpcodeInfo(
      code: 57,
      name: 'EQ',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 58,
      name: 'LT',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 59,
      name: 'LE',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 60,
      name: 'EQK',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 61,
      name: 'EQI',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 62,
      name: 'LTI',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 63,
      name: 'LEI',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 64,
      name: 'GTI',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 65,
      name: 'GEI',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 66,
      name: 'TEST',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 67,
      name: 'TESTSET',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 68,
      name: 'CALL',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 69,
      name: 'TAILCALL',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 70,
      name: 'RETURN',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 71,
      name: 'RETURN0',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 72,
      name: 'RETURN1',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 73,
      name: 'FORLOOP',
      mode: LuaBytecodeInstructionMode.iabx,
    ),
    LuaBytecodeOpcodeInfo(
      code: 74,
      name: 'FORPREP',
      mode: LuaBytecodeInstructionMode.iabx,
    ),
    LuaBytecodeOpcodeInfo(
      code: 75,
      name: 'TFORPREP',
      mode: LuaBytecodeInstructionMode.iabx,
    ),
    LuaBytecodeOpcodeInfo(
      code: 76,
      name: 'TFORCALL',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 77,
      name: 'TFORLOOP',
      mode: LuaBytecodeInstructionMode.iabx,
    ),
    LuaBytecodeOpcodeInfo(
      code: 78,
      name: 'SETLIST',
      mode: LuaBytecodeInstructionMode.ivabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 79,
      name: 'CLOSURE',
      mode: LuaBytecodeInstructionMode.iabx,
    ),
    LuaBytecodeOpcodeInfo(
      code: 80,
      name: 'VARARG',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 81,
      name: 'GETVARG',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 82,
      name: 'ERRNNIL',
      mode: LuaBytecodeInstructionMode.iabx,
    ),
    LuaBytecodeOpcodeInfo(
      code: 83,
      name: 'VARARGPREP',
      mode: LuaBytecodeInstructionMode.iabc,
    ),
    LuaBytecodeOpcodeInfo(
      code: 84,
      name: 'EXTRAARG',
      mode: LuaBytecodeInstructionMode.iax,
    ),
    LuaBytecodeOpcodeInfo(
      code: 85,
      name: 'CHECKGLOBAL',
      mode: LuaBytecodeInstructionMode.iabx,
    ),
  ];

  static LuaBytecodeOpcodeInfo byCode(int code) {
    if (code < 0 || code >= table.length) {
      throw RangeError.range(code, 0, table.length - 1, 'code');
    }
    return table[code];
  }

  static LuaBytecodeOpcodeInfo byName(String name) {
    for (final opcode in table) {
      if (opcode.name == name) {
        return opcode;
      }
    }
    throw ArgumentError.value(name, 'name', 'Unknown lua bytecode opcode');
  }
}
