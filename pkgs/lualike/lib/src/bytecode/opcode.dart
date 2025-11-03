import 'package:meta/meta.dart';

/// Enumeration of the bytecode instructions supported by the lualike VM.
///
/// The ordering and naming mirrors the Lua 5.4 instruction set (lopcodes.h)
/// so that documentation and upstream tooling remain applicable. Not every
/// opcode will be implemented in the first iteration, but the enum provides
/// a stable surface for the emitter and VM.
@immutable
class BytecodeOpcode {
  const BytecodeOpcode._(this.name);

  final String name;

  @override
  String toString() => name;

  static const BytecodeOpcode move = BytecodeOpcode._('MOVE');
  static const BytecodeOpcode loadI = BytecodeOpcode._('LOADI');
  static const BytecodeOpcode loadF = BytecodeOpcode._('LOADF');
  static const BytecodeOpcode loadK = BytecodeOpcode._('LOADK');
  static const BytecodeOpcode loadKx = BytecodeOpcode._('LOADKX');
  static const BytecodeOpcode loadFalse = BytecodeOpcode._('LOADFALSE');
  static const BytecodeOpcode lFalseSkip = BytecodeOpcode._('LFALSESKIP');
  static const BytecodeOpcode loadTrue = BytecodeOpcode._('LOADTRUE');
  static const BytecodeOpcode loadNil = BytecodeOpcode._('LOADNIL');
  static const BytecodeOpcode getUpval = BytecodeOpcode._('GETUPVAL');
  static const BytecodeOpcode setUpval = BytecodeOpcode._('SETUPVAL');
  static const BytecodeOpcode getTabUp = BytecodeOpcode._('GETTABUP');
  static const BytecodeOpcode getTable = BytecodeOpcode._('GETTABLE');
  static const BytecodeOpcode getI = BytecodeOpcode._('GETI');
  static const BytecodeOpcode getField = BytecodeOpcode._('GETFIELD');
  static const BytecodeOpcode setTabUp = BytecodeOpcode._('SETTABUP');
  static const BytecodeOpcode setTable = BytecodeOpcode._('SETTABLE');
  static const BytecodeOpcode setI = BytecodeOpcode._('SETI');
  static const BytecodeOpcode setField = BytecodeOpcode._('SETFIELD');
  static const BytecodeOpcode newTable = BytecodeOpcode._('NEWTABLE');
  static const BytecodeOpcode selfOp = BytecodeOpcode._('SELF');
  static const BytecodeOpcode addI = BytecodeOpcode._('ADDI');
  static const BytecodeOpcode addK = BytecodeOpcode._('ADDK');
  static const BytecodeOpcode subK = BytecodeOpcode._('SUBK');
  static const BytecodeOpcode mulK = BytecodeOpcode._('MULK');
  static const BytecodeOpcode modK = BytecodeOpcode._('MODK');
  static const BytecodeOpcode powK = BytecodeOpcode._('POWK');
  static const BytecodeOpcode divK = BytecodeOpcode._('DIVK');
  static const BytecodeOpcode idivK = BytecodeOpcode._('IDIVK');
  static const BytecodeOpcode bandK = BytecodeOpcode._('BANDK');
  static const BytecodeOpcode borK = BytecodeOpcode._('BORK');
  static const BytecodeOpcode bxorK = BytecodeOpcode._('BXORK');
  static const BytecodeOpcode shlI = BytecodeOpcode._('SHLI');
  static const BytecodeOpcode shrI = BytecodeOpcode._('SHRI');
  static const BytecodeOpcode add = BytecodeOpcode._('ADD');
  static const BytecodeOpcode sub = BytecodeOpcode._('SUB');
  static const BytecodeOpcode mul = BytecodeOpcode._('MUL');
  static const BytecodeOpcode mod = BytecodeOpcode._('MOD');
  static const BytecodeOpcode pow = BytecodeOpcode._('POW');
  static const BytecodeOpcode div = BytecodeOpcode._('DIV');
  static const BytecodeOpcode idiv = BytecodeOpcode._('IDIV');
  static const BytecodeOpcode band = BytecodeOpcode._('BAND');
  static const BytecodeOpcode bor = BytecodeOpcode._('BOR');
  static const BytecodeOpcode bxor = BytecodeOpcode._('BXOR');
  static const BytecodeOpcode shl = BytecodeOpcode._('SHL');
  static const BytecodeOpcode shr = BytecodeOpcode._('SHR');
  static const BytecodeOpcode mmBin = BytecodeOpcode._('MMBIN');
  static const BytecodeOpcode mmBinI = BytecodeOpcode._('MMBINI');
  static const BytecodeOpcode mmBinK = BytecodeOpcode._('MMBINK');
  static const BytecodeOpcode unm = BytecodeOpcode._('UNM');
  static const BytecodeOpcode bnot = BytecodeOpcode._('BNOT');
  static const BytecodeOpcode notOp = BytecodeOpcode._('NOT');
  static const BytecodeOpcode len = BytecodeOpcode._('LEN');
  static const BytecodeOpcode concat = BytecodeOpcode._('CONCAT');
  static const BytecodeOpcode close = BytecodeOpcode._('CLOSE');
  static const BytecodeOpcode tbc = BytecodeOpcode._('TBC');
  static const BytecodeOpcode jmp = BytecodeOpcode._('JMP');
  static const BytecodeOpcode eq = BytecodeOpcode._('EQ');
  static const BytecodeOpcode lt = BytecodeOpcode._('LT');
  static const BytecodeOpcode le = BytecodeOpcode._('LE');
  static const BytecodeOpcode eqK = BytecodeOpcode._('EQK');
  static const BytecodeOpcode eqI = BytecodeOpcode._('EQI');
  static const BytecodeOpcode ltI = BytecodeOpcode._('LTI');
  static const BytecodeOpcode leI = BytecodeOpcode._('LEI');
  static const BytecodeOpcode gtI = BytecodeOpcode._('GTI');
  static const BytecodeOpcode geI = BytecodeOpcode._('GEI');
  static const BytecodeOpcode test = BytecodeOpcode._('TEST');
  static const BytecodeOpcode testSet = BytecodeOpcode._('TESTSET');
  static const BytecodeOpcode call = BytecodeOpcode._('CALL');
  static const BytecodeOpcode tailCall = BytecodeOpcode._('TAILCALL');
  static const BytecodeOpcode ret = BytecodeOpcode._('RETURN');
  static const BytecodeOpcode return0 = BytecodeOpcode._('RETURN0');
  static const BytecodeOpcode return1 = BytecodeOpcode._('RETURN1');
  static const BytecodeOpcode forLoop = BytecodeOpcode._('FORLOOP');
  static const BytecodeOpcode forPrep = BytecodeOpcode._('FORPREP');
  static const BytecodeOpcode tForPrep = BytecodeOpcode._('TFORPREP');
  static const BytecodeOpcode tForCall = BytecodeOpcode._('TFORCALL');
  static const BytecodeOpcode tForLoop = BytecodeOpcode._('TFORLOOP');
  static const BytecodeOpcode setList = BytecodeOpcode._('SETLIST');
  static const BytecodeOpcode closure = BytecodeOpcode._('CLOSURE');
  static const BytecodeOpcode varArg = BytecodeOpcode._('VARARG');
  static const BytecodeOpcode getVarArg = BytecodeOpcode._('GETVARG');
  static const BytecodeOpcode varArgPrep = BytecodeOpcode._('VARARGPREP');
  static const BytecodeOpcode extraArg = BytecodeOpcode._('EXTRAARG');

  static const List<BytecodeOpcode> values = <BytecodeOpcode>[
    move,
    loadI,
    loadF,
    loadK,
    loadKx,
    loadFalse,
    lFalseSkip,
    loadTrue,
    loadNil,
    getUpval,
    setUpval,
    getTabUp,
    getTable,
    getI,
    getField,
    setTabUp,
    setTable,
    setI,
    setField,
    newTable,
    selfOp,
    addI,
    addK,
    subK,
    mulK,
    modK,
    powK,
    divK,
    idivK,
    bandK,
    borK,
    bxorK,
    shlI,
    shrI,
    add,
    sub,
    mul,
    mod,
    pow,
    div,
    idiv,
    band,
    bor,
    bxor,
    shl,
    shr,
    mmBin,
    mmBinI,
    mmBinK,
    unm,
    bnot,
    notOp,
    len,
    concat,
    close,
    tbc,
    jmp,
    eq,
    lt,
    le,
    eqK,
    eqI,
    ltI,
    leI,
    gtI,
    geI,
    test,
    testSet,
    call,
    tailCall,
    ret,
    return0,
    return1,
    forLoop,
    forPrep,
    tForPrep,
    tForCall,
    tForLoop,
    setList,
    closure,
    varArg,
    getVarArg,
    varArgPrep,
    extraArg,
  ];
}
