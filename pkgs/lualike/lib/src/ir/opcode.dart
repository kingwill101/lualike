import 'package:meta/meta.dart';

/// Enumeration of the lualike IR instructions supported by the lualike VM.
///
/// The ordering and naming mirrors the Lua 5.4 instruction set (lopcodes.h)
/// so that documentation and upstream tooling remain applicable. Not every
/// opcode will be implemented in the first iteration, but the enum provides
/// a stable surface for the emitter and VM.
@immutable
class LualikeIrOpcode {
  const LualikeIrOpcode._(this.name);

  final String name;

  @override
  String toString() => name;

  static const LualikeIrOpcode move = LualikeIrOpcode._('MOVE');
  static const LualikeIrOpcode loadI = LualikeIrOpcode._('LOADI');
  static const LualikeIrOpcode loadF = LualikeIrOpcode._('LOADF');
  static const LualikeIrOpcode loadK = LualikeIrOpcode._('LOADK');
  static const LualikeIrOpcode loadKx = LualikeIrOpcode._('LOADKX');
  static const LualikeIrOpcode loadFalse = LualikeIrOpcode._('LOADFALSE');
  static const LualikeIrOpcode lFalseSkip = LualikeIrOpcode._('LFALSESKIP');
  static const LualikeIrOpcode loadTrue = LualikeIrOpcode._('LOADTRUE');
  static const LualikeIrOpcode loadNil = LualikeIrOpcode._('LOADNIL');
  static const LualikeIrOpcode getUpval = LualikeIrOpcode._('GETUPVAL');
  static const LualikeIrOpcode setUpval = LualikeIrOpcode._('SETUPVAL');
  static const LualikeIrOpcode getTabUp = LualikeIrOpcode._('GETTABUP');
  static const LualikeIrOpcode getTable = LualikeIrOpcode._('GETTABLE');
  static const LualikeIrOpcode getI = LualikeIrOpcode._('GETI');
  static const LualikeIrOpcode getField = LualikeIrOpcode._('GETFIELD');
  static const LualikeIrOpcode setTabUp = LualikeIrOpcode._('SETTABUP');
  static const LualikeIrOpcode checkGlobal = LualikeIrOpcode._('CHECKGLOBAL');
  static const LualikeIrOpcode setTable = LualikeIrOpcode._('SETTABLE');
  static const LualikeIrOpcode setI = LualikeIrOpcode._('SETI');
  static const LualikeIrOpcode setField = LualikeIrOpcode._('SETFIELD');
  static const LualikeIrOpcode newTable = LualikeIrOpcode._('NEWTABLE');
  static const LualikeIrOpcode selfOp = LualikeIrOpcode._('SELF');
  static const LualikeIrOpcode addI = LualikeIrOpcode._('ADDI');
  static const LualikeIrOpcode addK = LualikeIrOpcode._('ADDK');
  static const LualikeIrOpcode subK = LualikeIrOpcode._('SUBK');
  static const LualikeIrOpcode mulK = LualikeIrOpcode._('MULK');
  static const LualikeIrOpcode modK = LualikeIrOpcode._('MODK');
  static const LualikeIrOpcode powK = LualikeIrOpcode._('POWK');
  static const LualikeIrOpcode divK = LualikeIrOpcode._('DIVK');
  static const LualikeIrOpcode idivK = LualikeIrOpcode._('IDIVK');
  static const LualikeIrOpcode bandK = LualikeIrOpcode._('BANDK');
  static const LualikeIrOpcode borK = LualikeIrOpcode._('BORK');
  static const LualikeIrOpcode bxorK = LualikeIrOpcode._('BXORK');
  static const LualikeIrOpcode shlI = LualikeIrOpcode._('SHLI');
  static const LualikeIrOpcode shrI = LualikeIrOpcode._('SHRI');
  static const LualikeIrOpcode add = LualikeIrOpcode._('ADD');
  static const LualikeIrOpcode sub = LualikeIrOpcode._('SUB');
  static const LualikeIrOpcode mul = LualikeIrOpcode._('MUL');
  static const LualikeIrOpcode mod = LualikeIrOpcode._('MOD');
  static const LualikeIrOpcode pow = LualikeIrOpcode._('POW');
  static const LualikeIrOpcode div = LualikeIrOpcode._('DIV');
  static const LualikeIrOpcode idiv = LualikeIrOpcode._('IDIV');
  static const LualikeIrOpcode band = LualikeIrOpcode._('BAND');
  static const LualikeIrOpcode bor = LualikeIrOpcode._('BOR');
  static const LualikeIrOpcode bxor = LualikeIrOpcode._('BXOR');
  static const LualikeIrOpcode shl = LualikeIrOpcode._('SHL');
  static const LualikeIrOpcode shr = LualikeIrOpcode._('SHR');
  static const LualikeIrOpcode mmBin = LualikeIrOpcode._('MMBIN');
  static const LualikeIrOpcode mmBinI = LualikeIrOpcode._('MMBINI');
  static const LualikeIrOpcode mmBinK = LualikeIrOpcode._('MMBINK');
  static const LualikeIrOpcode unm = LualikeIrOpcode._('UNM');
  static const LualikeIrOpcode bnot = LualikeIrOpcode._('BNOT');
  static const LualikeIrOpcode notOp = LualikeIrOpcode._('NOT');
  static const LualikeIrOpcode len = LualikeIrOpcode._('LEN');
  static const LualikeIrOpcode concat = LualikeIrOpcode._('CONCAT');
  static const LualikeIrOpcode close = LualikeIrOpcode._('CLOSE');
  static const LualikeIrOpcode tbc = LualikeIrOpcode._('TBC');
  static const LualikeIrOpcode jmp = LualikeIrOpcode._('JMP');
  static const LualikeIrOpcode eq = LualikeIrOpcode._('EQ');
  static const LualikeIrOpcode lt = LualikeIrOpcode._('LT');
  static const LualikeIrOpcode le = LualikeIrOpcode._('LE');
  static const LualikeIrOpcode eqK = LualikeIrOpcode._('EQK');
  static const LualikeIrOpcode eqI = LualikeIrOpcode._('EQI');
  static const LualikeIrOpcode ltI = LualikeIrOpcode._('LTI');
  static const LualikeIrOpcode leI = LualikeIrOpcode._('LEI');
  static const LualikeIrOpcode gtI = LualikeIrOpcode._('GTI');
  static const LualikeIrOpcode geI = LualikeIrOpcode._('GEI');
  static const LualikeIrOpcode test = LualikeIrOpcode._('TEST');
  static const LualikeIrOpcode testSet = LualikeIrOpcode._('TESTSET');
  static const LualikeIrOpcode call = LualikeIrOpcode._('CALL');
  static const LualikeIrOpcode tailCall = LualikeIrOpcode._('TAILCALL');
  static const LualikeIrOpcode ret = LualikeIrOpcode._('RETURN');
  static const LualikeIrOpcode return0 = LualikeIrOpcode._('RETURN0');
  static const LualikeIrOpcode return1 = LualikeIrOpcode._('RETURN1');
  static const LualikeIrOpcode forLoop = LualikeIrOpcode._('FORLOOP');
  static const LualikeIrOpcode forPrep = LualikeIrOpcode._('FORPREP');
  static const LualikeIrOpcode tForPrep = LualikeIrOpcode._('TFORPREP');
  static const LualikeIrOpcode tForCall = LualikeIrOpcode._('TFORCALL');
  static const LualikeIrOpcode tForLoop = LualikeIrOpcode._('TFORLOOP');
  static const LualikeIrOpcode setList = LualikeIrOpcode._('SETLIST');
  static const LualikeIrOpcode closure = LualikeIrOpcode._('CLOSURE');
  static const LualikeIrOpcode varArg = LualikeIrOpcode._('VARARG');
  static const LualikeIrOpcode getVarArg = LualikeIrOpcode._('GETVARG');
  static const LualikeIrOpcode varArgPrep = LualikeIrOpcode._('VARARGPREP');
  static const LualikeIrOpcode extraArg = LualikeIrOpcode._('EXTRAARG');

  static const List<LualikeIrOpcode> values = <LualikeIrOpcode>[
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
    checkGlobal,
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

  static final Map<String, LualikeIrOpcode> _byName =
      Map<String, LualikeIrOpcode>.fromEntries(
        values.map((opcode) => MapEntry(opcode.name, opcode)),
      );

  static LualikeIrOpcode? tryByName(String name) => _byName[name];

  static LualikeIrOpcode byName(String name) {
    final opcode = tryByName(name);
    if (opcode == null) {
      throw ArgumentError.value(name, 'name', 'Unknown lualike_ir opcode');
    }
    return opcode;
  }
}
