typedef LuaBytecodeAbcFields = ({int a, int b, int c, bool k});
typedef LuaBytecodeVAbcFields = ({int a, int b, int c, bool k});
typedef LuaBytecodeAbxFields = ({int a, int bx});
typedef LuaBytecodeAsBxFields = ({int a, int sBx});
typedef LuaBytecodeAxFields = ({int ax});
typedef LuaBytecodeSjFields = ({int sJ});

enum LuaBytecodeInstructionMode { iabc, ivabc, iabx, iasbx, iax, isj }

abstract final class LuaBytecodeInstructionLayout {
  static const int sizeOp = 7;
  static const int sizeA = 8;
  static const int sizeB = 8;
  static const int sizeC = 8;
  static const int sizeVB = 6;
  static const int sizeVC = 10;
  static const int sizeBx = sizeB + sizeC + 1;
  static const int sizeAx = sizeBx + sizeA;
  static const int sizeSJ = sizeBx + sizeA;

  static const int posOp = 0;
  static const int posA = posOp + sizeOp;
  static const int posK = posA + sizeA;
  static const int posB = posK + 1;
  static const int posVB = posK + 1;
  static const int posC = posB + sizeB;
  static const int posVC = posVB + sizeVB;
  static const int posBx = posK;
  static const int posAx = posA;
  static const int posSJ = posA;

  static const int maxOpcode = (1 << sizeOp) - 1;
  static const int maxArgA = (1 << sizeA) - 1;
  static const int maxArgB = (1 << sizeB) - 1;
  static const int maxArgC = (1 << sizeC) - 1;
  static const int maxArgVB = (1 << sizeVB) - 1;
  static const int maxArgVC = (1 << sizeVC) - 1;
  static const int maxArgBx = (1 << sizeBx) - 1;
  static const int maxArgAx = (1 << sizeAx) - 1;
  static const int maxArgSJ = (1 << sizeSJ) - 1;
  static const int offsetSBx = maxArgBx >> 1;
  static const int offsetSJ = maxArgSJ >> 1;
  static const int offsetSC = maxArgC >> 1;
  static const int offsetSB = maxArgB >> 1;
  static const int wordMask = 0xffffffff;
}

extension type const LuaBytecodeInstructionWord(int value) {
  factory LuaBytecodeInstructionWord.abc({
    required int opcode,
    required int a,
    required int b,
    required int c,
    bool k = false,
  }) {
    _checkUnsigned('opcode', opcode, LuaBytecodeInstructionLayout.maxOpcode);
    _checkUnsigned('a', a, LuaBytecodeInstructionLayout.maxArgA);
    _checkUnsigned('b', b, LuaBytecodeInstructionLayout.maxArgB);
    _checkUnsigned('c', c, LuaBytecodeInstructionLayout.maxArgC);

    var word = 0;
    word = _setBits(
      word,
      LuaBytecodeInstructionLayout.posOp,
      LuaBytecodeInstructionLayout.sizeOp,
      opcode,
    );
    word = _setBits(
      word,
      LuaBytecodeInstructionLayout.posA,
      LuaBytecodeInstructionLayout.sizeA,
      a,
    );
    word = _setBits(word, LuaBytecodeInstructionLayout.posK, 1, k ? 1 : 0);
    word = _setBits(
      word,
      LuaBytecodeInstructionLayout.posB,
      LuaBytecodeInstructionLayout.sizeB,
      b,
    );
    word = _setBits(
      word,
      LuaBytecodeInstructionLayout.posC,
      LuaBytecodeInstructionLayout.sizeC,
      c,
    );
    return LuaBytecodeInstructionWord(word);
  }

  factory LuaBytecodeInstructionWord.vabc({
    required int opcode,
    required int a,
    required int b,
    required int c,
    bool k = false,
  }) {
    _checkUnsigned('opcode', opcode, LuaBytecodeInstructionLayout.maxOpcode);
    _checkUnsigned('a', a, LuaBytecodeInstructionLayout.maxArgA);
    _checkUnsigned('b', b, LuaBytecodeInstructionLayout.maxArgVB);
    _checkUnsigned('c', c, LuaBytecodeInstructionLayout.maxArgVC);

    var word = 0;
    word = _setBits(
      word,
      LuaBytecodeInstructionLayout.posOp,
      LuaBytecodeInstructionLayout.sizeOp,
      opcode,
    );
    word = _setBits(
      word,
      LuaBytecodeInstructionLayout.posA,
      LuaBytecodeInstructionLayout.sizeA,
      a,
    );
    word = _setBits(word, LuaBytecodeInstructionLayout.posK, 1, k ? 1 : 0);
    word = _setBits(
      word,
      LuaBytecodeInstructionLayout.posVB,
      LuaBytecodeInstructionLayout.sizeVB,
      b,
    );
    word = _setBits(
      word,
      LuaBytecodeInstructionLayout.posVC,
      LuaBytecodeInstructionLayout.sizeVC,
      c,
    );
    return LuaBytecodeInstructionWord(word);
  }

  factory LuaBytecodeInstructionWord.abx({
    required int opcode,
    required int a,
    required int bx,
  }) {
    _checkUnsigned('opcode', opcode, LuaBytecodeInstructionLayout.maxOpcode);
    _checkUnsigned('a', a, LuaBytecodeInstructionLayout.maxArgA);
    _checkUnsigned('bx', bx, LuaBytecodeInstructionLayout.maxArgBx);

    var word = 0;
    word = _setBits(
      word,
      LuaBytecodeInstructionLayout.posOp,
      LuaBytecodeInstructionLayout.sizeOp,
      opcode,
    );
    word = _setBits(
      word,
      LuaBytecodeInstructionLayout.posA,
      LuaBytecodeInstructionLayout.sizeA,
      a,
    );
    word = _setBits(
      word,
      LuaBytecodeInstructionLayout.posBx,
      LuaBytecodeInstructionLayout.sizeBx,
      bx,
    );
    return LuaBytecodeInstructionWord(word);
  }

  factory LuaBytecodeInstructionWord.asBx({
    required int opcode,
    required int a,
    required int sBx,
  }) {
    _checkSigned('sBx', sBx, LuaBytecodeInstructionLayout.offsetSBx);
    return LuaBytecodeInstructionWord.abx(
      opcode: opcode,
      a: a,
      bx: sBx + LuaBytecodeInstructionLayout.offsetSBx,
    );
  }

  factory LuaBytecodeInstructionWord.ax({
    required int opcode,
    required int ax,
  }) {
    _checkUnsigned('opcode', opcode, LuaBytecodeInstructionLayout.maxOpcode);
    _checkUnsigned('ax', ax, LuaBytecodeInstructionLayout.maxArgAx);

    var word = 0;
    word = _setBits(
      word,
      LuaBytecodeInstructionLayout.posOp,
      LuaBytecodeInstructionLayout.sizeOp,
      opcode,
    );
    word = _setBits(
      word,
      LuaBytecodeInstructionLayout.posAx,
      LuaBytecodeInstructionLayout.sizeAx,
      ax,
    );
    return LuaBytecodeInstructionWord(word);
  }

  factory LuaBytecodeInstructionWord.sj({
    required int opcode,
    required int sJ,
  }) {
    _checkUnsigned('opcode', opcode, LuaBytecodeInstructionLayout.maxOpcode);
    _checkSigned('sJ', sJ, LuaBytecodeInstructionLayout.offsetSJ);

    var word = 0;
    word = _setBits(
      word,
      LuaBytecodeInstructionLayout.posOp,
      LuaBytecodeInstructionLayout.sizeOp,
      opcode,
    );
    word = _setBits(
      word,
      LuaBytecodeInstructionLayout.posSJ,
      LuaBytecodeInstructionLayout.sizeSJ,
      sJ + LuaBytecodeInstructionLayout.offsetSJ,
    );
    return LuaBytecodeInstructionWord(word);
  }

  int get rawValue => value & LuaBytecodeInstructionLayout.wordMask;
  int get opcodeValue => _getBits(
    rawValue,
    LuaBytecodeInstructionLayout.posOp,
    LuaBytecodeInstructionLayout.sizeOp,
  );
  int get a => _getBits(
    rawValue,
    LuaBytecodeInstructionLayout.posA,
    LuaBytecodeInstructionLayout.sizeA,
  );
  bool get kFlag =>
      _getBits(rawValue, LuaBytecodeInstructionLayout.posK, 1) == 1;
  int get b => _getBits(
    rawValue,
    LuaBytecodeInstructionLayout.posB,
    LuaBytecodeInstructionLayout.sizeB,
  );
  int get c => _getBits(
    rawValue,
    LuaBytecodeInstructionLayout.posC,
    LuaBytecodeInstructionLayout.sizeC,
  );
  int get vb => _getBits(
    rawValue,
    LuaBytecodeInstructionLayout.posVB,
    LuaBytecodeInstructionLayout.sizeVB,
  );
  int get vc => _getBits(
    rawValue,
    LuaBytecodeInstructionLayout.posVC,
    LuaBytecodeInstructionLayout.sizeVC,
  );
  int get bx => _getBits(
    rawValue,
    LuaBytecodeInstructionLayout.posBx,
    LuaBytecodeInstructionLayout.sizeBx,
  );
  int get sBx => bx - LuaBytecodeInstructionLayout.offsetSBx;
  int get ax => _getBits(
    rawValue,
    LuaBytecodeInstructionLayout.posAx,
    LuaBytecodeInstructionLayout.sizeAx,
  );
  int get sJ =>
      _getBits(
        rawValue,
        LuaBytecodeInstructionLayout.posSJ,
        LuaBytecodeInstructionLayout.sizeSJ,
      ) -
      LuaBytecodeInstructionLayout.offsetSJ;
  int get signedB => b - LuaBytecodeInstructionLayout.offsetSB;
  int get signedC => c - LuaBytecodeInstructionLayout.offsetSC;

  LuaBytecodeAbcFields get abc => (a: a, b: b, c: c, k: kFlag);
  LuaBytecodeVAbcFields get vabc => (a: a, b: vb, c: vc, k: kFlag);
  LuaBytecodeAbxFields get abx => (a: a, bx: bx);
  LuaBytecodeAsBxFields get asBx => (a: a, sBx: sBx);
  LuaBytecodeAxFields get axFields => (ax: ax);
  LuaBytecodeSjFields get sj => (sJ: sJ);
}

int _getBits(int value, int position, int size) =>
    (value >> position) & _mask(size);

int _setBits(int value, int position, int size, int fieldValue) {
  final mask = _mask(size) << position;
  return ((value & ~mask) | ((fieldValue & _mask(size)) << position)) &
      LuaBytecodeInstructionLayout.wordMask;
}

int _mask(int size) => (1 << size) - 1;

void _checkUnsigned(String name, int value, int max) {
  if (value < 0 || value > max) {
    throw RangeError.range(value, 0, max, name);
  }
}

void _checkSigned(String name, int value, int offset) {
  final min = -offset;
  final max = offset;
  if (value < min || value > max) {
    throw RangeError.range(value, min, max, name);
  }
}
