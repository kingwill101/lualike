import 'instruction_mode.dart';

/// Lua bytecode opcode enum.
///
/// The enum values mirror Lua's opcode names and numeric codes. A thin
/// compatibility wrapper ([LuaBytecodeOpcodes]) remains for callers that still
/// expect the legacy lookup API.
enum Opcode {
  move(0, 'MOVE', LuaBytecodeInstructionMode.iabc),
  loadI(1, 'LOADI', LuaBytecodeInstructionMode.iasbx),
  loadF(2, 'LOADF', LuaBytecodeInstructionMode.iasbx),
  loadK(3, 'LOADK', LuaBytecodeInstructionMode.iabx),
  loadKx(4, 'LOADKX', LuaBytecodeInstructionMode.iabx),
  loadFalse(5, 'LOADFALSE', LuaBytecodeInstructionMode.iabc),
  lFalseSkip(6, 'LFALSESKIP', LuaBytecodeInstructionMode.iabc),
  loadTrue(7, 'LOADTRUE', LuaBytecodeInstructionMode.iabc),
  loadNil(8, 'LOADNIL', LuaBytecodeInstructionMode.iabc),
  getUpval(9, 'GETUPVAL', LuaBytecodeInstructionMode.iabc),
  setUpval(10, 'SETUPVAL', LuaBytecodeInstructionMode.iabc),
  getTabUp(11, 'GETTABUP', LuaBytecodeInstructionMode.iabc),
  getTable(12, 'GETTABLE', LuaBytecodeInstructionMode.iabc),
  getI(13, 'GETI', LuaBytecodeInstructionMode.iabc),
  getField(14, 'GETFIELD', LuaBytecodeInstructionMode.iabc),
  setTabUp(15, 'SETTABUP', LuaBytecodeInstructionMode.iabc),
  setTable(16, 'SETTABLE', LuaBytecodeInstructionMode.iabc),
  setI(17, 'SETI', LuaBytecodeInstructionMode.iabc),
  setField(18, 'SETFIELD', LuaBytecodeInstructionMode.iabc),
  newTable(19, 'NEWTABLE', LuaBytecodeInstructionMode.ivabc),
  self(20, 'SELF', LuaBytecodeInstructionMode.iabc),
  addI(21, 'ADDI', LuaBytecodeInstructionMode.iabc),
  addK(22, 'ADDK', LuaBytecodeInstructionMode.iabc),
  subK(23, 'SUBK', LuaBytecodeInstructionMode.iabc),
  mulK(24, 'MULK', LuaBytecodeInstructionMode.iabc),
  modK(25, 'MODK', LuaBytecodeInstructionMode.iabc),
  powK(26, 'POWK', LuaBytecodeInstructionMode.iabc),
  divK(27, 'DIVK', LuaBytecodeInstructionMode.iabc),
  idivK(28, 'IDIVK', LuaBytecodeInstructionMode.iabc),
  bandK(29, 'BANDK', LuaBytecodeInstructionMode.iabc),
  borK(30, 'BORK', LuaBytecodeInstructionMode.iabc),
  bxorK(31, 'BXORK', LuaBytecodeInstructionMode.iabc),
  shlI(32, 'SHLI', LuaBytecodeInstructionMode.iabc),
  shrI(33, 'SHRI', LuaBytecodeInstructionMode.iabc),
  add(34, 'ADD', LuaBytecodeInstructionMode.iabc),
  sub(35, 'SUB', LuaBytecodeInstructionMode.iabc),
  mul(36, 'MUL', LuaBytecodeInstructionMode.iabc),
  mod(37, 'MOD', LuaBytecodeInstructionMode.iabc),
  pow(38, 'POW', LuaBytecodeInstructionMode.iabc),
  div(39, 'DIV', LuaBytecodeInstructionMode.iabc),
  idiv(40, 'IDIV', LuaBytecodeInstructionMode.iabc),
  band(41, 'BAND', LuaBytecodeInstructionMode.iabc),
  bor(42, 'BOR', LuaBytecodeInstructionMode.iabc),
  bxor(43, 'BXOR', LuaBytecodeInstructionMode.iabc),
  shl(44, 'SHL', LuaBytecodeInstructionMode.iabc),
  shr(45, 'SHR', LuaBytecodeInstructionMode.iabc),
  mmBin(46, 'MMBIN', LuaBytecodeInstructionMode.iabc),
  mmBinI(47, 'MMBINI', LuaBytecodeInstructionMode.iabc),
  mmBinK(48, 'MMBINK', LuaBytecodeInstructionMode.iabc),
  unm(49, 'UNM', LuaBytecodeInstructionMode.iabc),
  bnot(50, 'BNOT', LuaBytecodeInstructionMode.iabc),
  notOp(51, 'NOT', LuaBytecodeInstructionMode.iabc),
  len(52, 'LEN', LuaBytecodeInstructionMode.iabc),
  concat(53, 'CONCAT', LuaBytecodeInstructionMode.iabc),
  close(54, 'CLOSE', LuaBytecodeInstructionMode.iabc),
  tbc(55, 'TBC', LuaBytecodeInstructionMode.iabc),
  jmp(56, 'JMP', LuaBytecodeInstructionMode.isj),
  eq(57, 'EQ', LuaBytecodeInstructionMode.iabc),
  lt(58, 'LT', LuaBytecodeInstructionMode.iabc),
  le(59, 'LE', LuaBytecodeInstructionMode.iabc),
  eqK(60, 'EQK', LuaBytecodeInstructionMode.iabc),
  eqI(61, 'EQI', LuaBytecodeInstructionMode.iabc),
  ltI(62, 'LTI', LuaBytecodeInstructionMode.iabc),
  leI(63, 'LEI', LuaBytecodeInstructionMode.iabc),
  gtI(64, 'GTI', LuaBytecodeInstructionMode.iabc),
  geI(65, 'GEI', LuaBytecodeInstructionMode.iabc),
  test(66, 'TEST', LuaBytecodeInstructionMode.iabc),
  testSet(67, 'TESTSET', LuaBytecodeInstructionMode.iabc),
  call(68, 'CALL', LuaBytecodeInstructionMode.iabc),
  tailCall(69, 'TAILCALL', LuaBytecodeInstructionMode.iabc),
  return_(70, 'RETURN', LuaBytecodeInstructionMode.iabc),
  return0(71, 'RETURN0', LuaBytecodeInstructionMode.iabc),
  return1(72, 'RETURN1', LuaBytecodeInstructionMode.iabc),
  forLoop(73, 'FORLOOP', LuaBytecodeInstructionMode.iabx),
  forPrep(74, 'FORPREP', LuaBytecodeInstructionMode.iabx),
  tForPrep(75, 'TFORPREP', LuaBytecodeInstructionMode.iabx),
  tForCall(76, 'TFORCALL', LuaBytecodeInstructionMode.iabc),
  tForLoop(77, 'TFORLOOP', LuaBytecodeInstructionMode.iabx),
  setList(78, 'SETLIST', LuaBytecodeInstructionMode.ivabc),
  closure(79, 'CLOSURE', LuaBytecodeInstructionMode.iabx),
  varArg(80, 'VARARG', LuaBytecodeInstructionMode.iabc),
  getVarArg(81, 'GETVARG', LuaBytecodeInstructionMode.iabc),
  errNNil(82, 'ERRNNIL', LuaBytecodeInstructionMode.iabx),
  varArgPrep(83, 'VARARGPREP', LuaBytecodeInstructionMode.iabc),
  extraArg(84, 'EXTRAARG', LuaBytecodeInstructionMode.iax),
  checkGlobal(85, 'CHECKGLOBAL', LuaBytecodeInstructionMode.iabx);

  const Opcode(this.code, this.luaName, this.mode);

  final int code;
  final String luaName;
  final LuaBytecodeInstructionMode mode;

  @pragma('vm:prefer-inline')
  static Opcode fromCode(int code) {
    final table = values;
    if (code < 0 || code >= table.length) {
      throw RangeError.range(code, 0, table.length - 1, 'code');
    }
    return table[code];
  }

  static Opcode fromName(String name) => switch (name) {
    'MOVE' => move,
    'LOADI' => loadI,
    'LOADF' => loadF,
    'LOADK' => loadK,
    'LOADKX' => loadKx,
    'LOADFALSE' => loadFalse,
    'LFALSESKIP' => lFalseSkip,
    'LOADTRUE' => loadTrue,
    'LOADNIL' => loadNil,
    'GETUPVAL' => getUpval,
    'SETUPVAL' => setUpval,
    'GETTABUP' => getTabUp,
    'GETTABLE' => getTable,
    'GETI' => getI,
    'GETFIELD' => getField,
    'SETTABUP' => setTabUp,
    'SETTABLE' => setTable,
    'SETI' => setI,
    'SETFIELD' => setField,
    'NEWTABLE' => newTable,
    'SELF' => self,
    'ADDI' => addI,
    'ADDK' => addK,
    'SUBK' => subK,
    'MULK' => mulK,
    'MODK' => modK,
    'POWK' => powK,
    'DIVK' => divK,
    'IDIVK' => idivK,
    'BANDK' => bandK,
    'BORK' => borK,
    'BXORK' => bxorK,
    'SHLI' => shlI,
    'SHRI' => shrI,
    'ADD' => add,
    'SUB' => sub,
    'MUL' => mul,
    'MOD' => mod,
    'POW' => pow,
    'DIV' => div,
    'IDIV' => idiv,
    'BAND' => band,
    'BOR' => bor,
    'BXOR' => bxor,
    'SHL' => shl,
    'SHR' => shr,
    'MMBIN' => mmBin,
    'MMBINI' => mmBinI,
    'MMBINK' => mmBinK,
    'UNM' => unm,
    'BNOT' => bnot,
    'NOT' => notOp,
    'LEN' => len,
    'CONCAT' => concat,
    'CLOSE' => close,
    'TBC' => tbc,
    'JMP' => jmp,
    'EQ' => eq,
    'LT' => lt,
    'LE' => le,
    'EQK' => eqK,
    'EQI' => eqI,
    'LTI' => ltI,
    'LEI' => leI,
    'GTI' => gtI,
    'GEI' => geI,
    'TEST' => test,
    'TESTSET' => testSet,
    'CALL' => call,
    'TAILCALL' => tailCall,
    'RETURN' => return_,
    'RETURN0' => return0,
    'RETURN1' => return1,
    'FORLOOP' => forLoop,
    'FORPREP' => forPrep,
    'TFORPREP' => tForPrep,
    'TFORCALL' => tForCall,
    'TFORLOOP' => tForLoop,
    'SETLIST' => setList,
    'CLOSURE' => closure,
    'VARARG' => varArg,
    'GETVARG' => getVarArg,
    'ERRNNIL' => errNNil,
    'VARARGPREP' => varArgPrep,
    'EXTRAARG' => extraArg,
    'CHECKGLOBAL' => checkGlobal,
    _ => throw ArgumentError.value(name, 'name', 'Unknown lua bytecode opcode'),
  };
}

@Deprecated('Use Opcode directly')
final class LuaBytecodeOpcodeInfo {
  const LuaBytecodeOpcodeInfo(this.opcode);

  final Opcode opcode;

  int get code => opcode.code;
  String get name => opcode.luaName;
  LuaBytecodeInstructionMode get mode => opcode.mode;
}

abstract final class LuaBytecodeOpcodes {
  static const List<Opcode> table = Opcode.values;

  static LuaBytecodeOpcodeInfo byCode(int code) =>
      LuaBytecodeOpcodeInfo(Opcode.fromCode(code));

  static LuaBytecodeOpcodeInfo byName(String name) =>
      LuaBytecodeOpcodeInfo(Opcode.fromName(name));
}
