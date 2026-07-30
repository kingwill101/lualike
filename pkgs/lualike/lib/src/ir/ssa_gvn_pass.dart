/// Global Value Numbering (GVN) pass for the lualike IR.
///
/// Eliminates redundant pure computations: when two instructions compute the
/// same operation on the same operand values, the later one becomes
/// `MOVE dest, earlierResult`.
///
/// ## Critical safety rules (do not regress)
///
/// ### Register clobber
///
/// Value numbers are keyed by pure expression shape and map to a **source
/// register**. After `CALL` (or any def) clobbers that register, the map entry
/// is stale. Without invalidation, a second `GETTABUP _ENV,"debug"` was
/// rewritten to reuse a register that now held a getlocal *result string*,
/// producing `attempt to call field 'getlocal' (a nil value)`.
///
/// Always drop value-number map entries whose source register is redefined
/// before reusing a value number.
///
/// ### Not every opcode is a pure value producer
///
/// * `TEST` / `TESTSET` affect control flow; `TEST` does **not** write A.
///   Treating them as pure and replacing later `TEST`s with `MOVE` destroys
///   branches (snake `if willGrow then` / `and`/`or` conditions).
/// * Loads (`GETUPVAL`, `GETTABLE`, `GETFIELD`, …) read mutable state; without
///   memory SSA they must not be CSE'd across stores.
/// * `NEWTABLE` / `CLOSURE` allocate distinct objects — never CSE by shape.
/// * Operand fields are not always registers: upvalue/Kst/int immediates must
///   key as immediates, not as SSA labels of register indices.
///
/// Only pure opcodes in the pure-opcode set are considered.
library;

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';
import 'ssa.dart';

/// Opcodes safe for value-number CSE (no control-flow, no memory, no alloc).
const _gvnPureOpcodes = <LualikeIrOpcode>{
  LualikeIrOpcode.move,
  LualikeIrOpcode.loadI,
  // `loadF` has caused stale-register rewrites in optimized bytecode when the
  // loaded value later flows into table constructors; keep it out of GVN until
  // the value-tracking is proven safe under that shape.
  LualikeIrOpcode.loadK,
  LualikeIrOpcode.loadKx,
  LualikeIrOpcode.loadFalse,
  LualikeIrOpcode.loadTrue,
  LualikeIrOpcode.loadNil,
  // Arithmetic / bitwise (register + immediate forms).
  LualikeIrOpcode.addI,
  LualikeIrOpcode.subI,
  LualikeIrOpcode.addK,
  LualikeIrOpcode.subK,
  LualikeIrOpcode.mulK,
  LualikeIrOpcode.modK,
  LualikeIrOpcode.powK,
  LualikeIrOpcode.divK,
  LualikeIrOpcode.idivK,
  LualikeIrOpcode.bandK,
  LualikeIrOpcode.borK,
  LualikeIrOpcode.bxorK,
  LualikeIrOpcode.shlI,
  LualikeIrOpcode.shrI,
  LualikeIrOpcode.add,
  LualikeIrOpcode.sub,
  LualikeIrOpcode.mul,
  LualikeIrOpcode.mod,
  LualikeIrOpcode.pow,
  LualikeIrOpcode.div,
  LualikeIrOpcode.idiv,
  LualikeIrOpcode.band,
  LualikeIrOpcode.bor,
  LualikeIrOpcode.bxor,
  LualikeIrOpcode.shl,
  LualikeIrOpcode.shr,
  LualikeIrOpcode.unm,
  LualikeIrOpcode.bnot,
  LualikeIrOpcode.notOp,
  // Comparisons that *store* a boolean into A (IR dialect, not Lua skip-form).
  LualikeIrOpcode.eq,
  LualikeIrOpcode.lt,
  LualikeIrOpcode.le,
  LualikeIrOpcode.eqK,
  LualikeIrOpcode.eqI,
  LualikeIrOpcode.ltI,
  LualikeIrOpcode.leI,
  LualikeIrOpcode.gtI,
  LualikeIrOpcode.geI,
};

/// Find which register an instruction writes to (-1 if none / not a value def).
int _resultReg(LualikeIrInstruction inst, int registerCount) {
  final r = inst.when(
    abc: (i) {
      switch (i.opcode) {
        case LualikeIrOpcode.jmp ||
            LualikeIrOpcode.close ||
            LualikeIrOpcode.tbc ||
            LualikeIrOpcode.ret ||
            LualikeIrOpcode.return0 ||
            LualikeIrOpcode.return1 ||
            LualikeIrOpcode.tailCall ||
            LualikeIrOpcode.call ||
            // Control-flow predicates: do not produce R(A).
            LualikeIrOpcode.test ||
            LualikeIrOpcode.lFalseSkip ||
            // Stores.
            LualikeIrOpcode.setTabUp ||
            LualikeIrOpcode.setTable ||
            LualikeIrOpcode.setI ||
            LualikeIrOpcode.setField ||
            LualikeIrOpcode.setList ||
            LualikeIrOpcode.setUpval:
          return -1;
        default:
          return i.a;
      }
    },
    abx: (i) => i.a,
    asbx: (i) {
      if (i.opcode == LualikeIrOpcode.forPrep ||
          i.opcode == LualikeIrOpcode.forLoop ||
          i.opcode == LualikeIrOpcode.tForPrep ||
          i.opcode == LualikeIrOpcode.tForLoop) {
        return -1;
      }
      return i.a;
    },
    ax: (_) => -1,
    asj: (_) => -1,
    avbc: (i) => i.a,
  );
  return (r >= 0 && r < registerCount) ? r : -1;
}

String _regKey(int reg, Map<int, String> ssaLabels) =>
    ssaLabels[reg] ?? 'r$reg';

/// Build a canonical string key for (opcode, operand SSA labels / immediates).
String _computeKey(LualikeIrInstruction inst, Map<int, String> ssaLabels) {
  final opName = inst.opcode.name;
  final buf = StringBuffer(opName);
  inst.when(
    abc: (i) {
      final op = i.opcode;
      // Operand roles differ by opcode — never treat Kst/upval/int as SSA regs.
      switch (op) {
        case LualikeIrOpcode.move ||
            LualikeIrOpcode.unm ||
            LualikeIrOpcode.bnot ||
            LualikeIrOpcode.notOp:
          buf.write('|b=${_regKey(i.b, ssaLabels)}');
        case LualikeIrOpcode.addI ||
            LualikeIrOpcode.subI ||
            LualikeIrOpcode.shlI ||
            LualikeIrOpcode.shrI:
          buf.write('|b=${_regKey(i.b, ssaLabels)}|imm=${i.c}');
        case LualikeIrOpcode.addK ||
            LualikeIrOpcode.subK ||
            LualikeIrOpcode.mulK ||
            LualikeIrOpcode.modK ||
            LualikeIrOpcode.powK ||
            LualikeIrOpcode.divK ||
            LualikeIrOpcode.idivK ||
            LualikeIrOpcode.bandK ||
            LualikeIrOpcode.borK ||
            LualikeIrOpcode.bxorK ||
            LualikeIrOpcode.eqK:
          buf.write('|b=${_regKey(i.b, ssaLabels)}|k=${i.c}');
        case LualikeIrOpcode.eqI ||
            LualikeIrOpcode.ltI ||
            LualikeIrOpcode.leI ||
            LualikeIrOpcode.gtI ||
            LualikeIrOpcode.geI:
          buf.write('|b=${_regKey(i.b, ssaLabels)}|imm=${i.c}');
          if (i.k) buf.write('|k=1');
        case LualikeIrOpcode.add ||
            LualikeIrOpcode.sub ||
            LualikeIrOpcode.mul ||
            LualikeIrOpcode.mod ||
            LualikeIrOpcode.pow ||
            LualikeIrOpcode.div ||
            LualikeIrOpcode.idiv ||
            LualikeIrOpcode.band ||
            LualikeIrOpcode.bor ||
            LualikeIrOpcode.bxor ||
            LualikeIrOpcode.shl ||
            LualikeIrOpcode.shr ||
            LualikeIrOpcode.eq ||
            LualikeIrOpcode.lt ||
            LualikeIrOpcode.le:
          buf.write('|b=${_regKey(i.b, ssaLabels)}');
          buf.write('|c=${_regKey(i.c, ssaLabels)}');
          if (i.k) buf.write('|k=1');
        case LualikeIrOpcode.loadNil:
          buf.write('|n=${i.b}');
        case LualikeIrOpcode.loadFalse ||
            LualikeIrOpcode.loadTrue:
          break;
        default:
          // Conservative: include raw fields so unknown shapes never collide.
          buf.write('|b=${i.b}|c=${i.c}');
          if (i.k) buf.write('|k=1');
      }
    },
    abx: (i) => buf.write('|bx=${i.bx}'),
    asbx: (i) => buf.write('|sBx=${i.sBx}'),
    ax: (i) => buf.write('|ax=${i.ax}'),
    asj: (i) => buf.write('|sJ=${i.sJ}'),
    avbc: (i) {
      buf.write('|vB=${i.vB}|vC=${i.vC}');
      if (i.k) buf.write('|k=1');
    },
  );
  return buf.toString();
}

/// Runs Global Value Numbering on an IR prototype.
///
/// Returns a new prototype with redundant computations eliminated, or the
/// same prototype if no changes were made.
LualikeIrPrototype eliminateRedundantComputations(
  LualikeIrPrototype prototype,
) {
  // First recurse into sub-prototypes
  final processedSubs = <LualikeIrPrototype>[
    for (final sub in prototype.prototypes) eliminateRedundantComputations(sub),
  ];

  var current = LualikeIrPrototype(
    instructions: prototype.instructions,
    constants: prototype.constants,
    registerCount: prototype.registerCount,
    paramCount: prototype.paramCount,
    isVararg: prototype.isVararg,
    namedVarargRegister: prototype.namedVarargRegister,
    upvalueDescriptors: prototype.upvalueDescriptors,
    prototypes: processedSubs,
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    debugInfo: prototype.debugInfo,
    registerConstFlags: prototype.registerConstFlags,
    constSealPoints: prototype.constSealPoints,
  );

  for (var iter = 0; iter < 10; iter++) {
    final result = _runOnce(current);
    if (result == null) return current;
    current = result;
  }
  return current;
}

/// Single GVN iteration. Returns null if no change.
LualikeIrPrototype? _runOnce(LualikeIrPrototype prototype) {
  final instructions = prototype.instructions;
  if (instructions.isEmpty) return null;
  final registerCount = prototype.registerCount;

  // Build SSA form to get value labels
  final ssa = LualikeIrSsaFunction.fromPrototype(prototype);

  // Pure-expression key → register currently holding that value.
  // Must be invalidated when any of those registers is redefined.
  final valueToSourceReg = <String, int>{};

  // Walk PCs in order, tracking SSA labels per register.
  final ssaLabels = <int, String>{}; // register -> label
  for (final block in ssa.blocks) {
    if (block.block.index == 0) {
      for (final entry in block.entryValues.entries) {
        ssaLabels[entry.key] = entry.value.label;
      }
    }
  }

  // Replacement map: pc -> source register to MOVE from.
  final replacements = <int, int>{};

  for (final block in ssa.blocks) {
    for (final entry in block.entryValues.entries) {
      ssaLabels[entry.key] = entry.value.label;
    }

    for (final pc in block.block.instructionPcs) {
      final inst = instructions[pc];

      if (_gvnPureOpcodes.contains(inst.opcode)) {
        final key = _computeKey(inst, ssaLabels);
        final existingReg = valueToSourceReg[key];

        if (existingReg != null) {
          final targetReg = _resultReg(inst, registerCount);
          // Reuse only while the source register still holds that value.
          final existingLabel = ssaLabels[existingReg];
          if (targetReg >= 0 &&
              existingLabel != null &&
              valueToSourceReg[key] == existingReg) {
            replacements[pc] = existingReg;
            ssaLabels[targetReg] = existingLabel;
            continue;
          }
        }

        final targetReg = _resultReg(inst, registerCount);
        if (targetReg >= 0) {
          valueToSourceReg[key] = targetReg;
        }
      }

      // Apply defs for this PC: new SSA labels + kill stale value numbers.
      // Example failure without kill: GETTABUP debug → CALL overwrites R4 →
      // later GETTABUP debug reuses R4 which now holds the string "a".
      final instLabels = <int, String>{};
      final definedRegs = <int>{};
      for (final value in block.definedValues) {
        if (value.definingPc == pc) {
          instLabels[value.register] = value.label;
          definedRegs.add(value.register);
        }
      }
      if (definedRegs.isNotEmpty) {
        valueToSourceReg.removeWhere(
          (key, sourceReg) => definedRegs.contains(sourceReg),
        );
      }
      for (final entry in instLabels.entries) {
        ssaLabels[entry.key] = entry.value;
      }
    }
  }

  if (replacements.isEmpty) return null;

  // Build new instruction list with replacements applied
  final newInstructions = <LualikeIrInstruction>[];
  for (var pc = 0; pc < instructions.length; pc++) {
    final replacementReg = replacements[pc];
    if (replacementReg != null) {
      final inst = instructions[pc];
      final targetReg = _resultReg(inst, registerCount);
      newInstructions.add(
        ABCInstruction(
          opcode: LualikeIrOpcode.move,
          a: targetReg,
          b: replacementReg,
          c: 0,
        ),
      );
    } else {
      newInstructions.add(instructions[pc]);
    }
  }

  return LualikeIrPrototype(
    instructions: newInstructions,
    constants: prototype.constants,
    registerCount: prototype.registerCount,
    paramCount: prototype.paramCount,
    isVararg: prototype.isVararg,
    namedVarargRegister: prototype.namedVarargRegister,
    upvalueDescriptors: prototype.upvalueDescriptors,
    prototypes: prototype.prototypes,
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    debugInfo: prototype.debugInfo,
    registerConstFlags: prototype.registerConstFlags,
    constSealPoints: prototype.constSealPoints,
  );
}
