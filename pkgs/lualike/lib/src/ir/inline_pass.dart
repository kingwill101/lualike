/// Function inlining pass for the lualike IR.
///
/// Replaces CALL to a known small function with the function body
/// expanded inline, eliminating frame creation and call overhead.
///
/// ## Approach
///
/// 1. Scan for CLOSURE + CALL pairs where the callee's prototype is small
/// 2. Clone the callee's instruction list
/// 3. Remap registers: callee params → caller arg regs, callee locals → fresh temps
/// 4. Replace RETURN in callee with MOVE to caller's target register
/// 5. Replace CLOSURE + CALL with the inlined body
library;

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';

/// Max instructions in a function body for inlining to be profitable.
const int _maxInlineInstructions = 10;

/// Run function inlining on an IR prototype.
LualikeIrPrototype inlineFunctions(LualikeIrPrototype prototype) {
  var current = prototype;
  for (var iter = 0; iter < 5; iter++) {
    final result = _runOnce(current);
    if (result == null) return current;
    current = result;
  }
  return current;
}

/// Try inlining once. Returns null if no change.
LualikeIrPrototype? _runOnce(LualikeIrPrototype prototype) {
  final instructions = prototype.instructions;
  final subProtos = prototype.prototypes;
  if (instructions.isEmpty || subProtos.isEmpty) return null;

  // Build a map of register → protoIndex for CLOSURE instructions
  final closureMap = <int, int>{};
  for (var pc = 0; pc < instructions.length; pc++) {
    final inst = instructions[pc];
    if (inst is ABxInstruction && inst.opcode == LualikeIrOpcode.closure) {
      closureMap[inst.a] = inst.bx;
    }
  }

  if (closureMap.isEmpty) return null;

  var changed = false;
  final newInstructions = <LualikeIrInstruction>[];

  for (var pc = 0; pc < instructions.length; pc++) {
    final inst = instructions[pc];
    if (inst is ABCInstruction &&
        inst.opcode == LualikeIrOpcode.call &&
        closureMap.containsKey(inst.a)) {
      final protoIdx = closureMap[inst.a]!;
      if (protoIdx < subProtos.length) {
        final callee = subProtos[protoIdx];
        if (_shouldInline(callee, inst)) {
          _inlineCall(newInstructions, callee, inst, inst.a);
          changed = true;
          continue;
        }
      }
    }
    newInstructions.add(inst);
  }

  if (!changed) return null;

  return LualikeIrPrototype(
    instructions: newInstructions,
    constants: prototype.constants,
    registerCount: prototype.registerCount,
    paramCount: prototype.paramCount,
    isVararg: prototype.isVararg,
    upvalueDescriptors: prototype.upvalueDescriptors,
    prototypes: subProtos,
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    debugInfo: prototype.debugInfo,
    registerConstFlags: prototype.registerConstFlags,
    constSealPoints: prototype.constSealPoints,
  );
}

bool _shouldInline(LualikeIrPrototype callee, ABCInstruction call) {
  if (callee.instructions.length > _maxInlineInstructions) return false;
  if (callee.upvalueDescriptors.isNotEmpty) return false;
  if (callee.isVararg) return false;
  // Check for constant-referencing instructions that can't be inlined
  // without merging constant tables between prototypes
  for (final inst in callee.instructions) {
    final op = inst.opcode;
    if (op == LualikeIrOpcode.loadK ||
        op == LualikeIrOpcode.loadKx ||
        op == LualikeIrOpcode.addK ||
        op == LualikeIrOpcode.subK ||
        op == LualikeIrOpcode.mulK ||
        op == LualikeIrOpcode.modK ||
        op == LualikeIrOpcode.powK ||
        op == LualikeIrOpcode.divK ||
        op == LualikeIrOpcode.idivK ||
        op == LualikeIrOpcode.bandK ||
        op == LualikeIrOpcode.borK ||
        op == LualikeIrOpcode.bxorK ||
        op == LualikeIrOpcode.eqK) {
      return false;
    }
  }
  return true;
}

void _inlineCall(
  List<LualikeIrInstruction> out,
  LualikeIrPrototype callee,
  ABCInstruction call,
  int closureReg,
) {
  final args = <int>[];
  final argCount = call.b;
  // args start from closureReg + 1...closureReg + argCount
  for (var i = 1; i < argCount; i++) {
    args.add(closureReg + i);
  }

  // Register remap: param k → arg[k] (if available), else new temps
  final regMap = <int, int>{};
  var nextReg = closureReg + argCount;

  for (var i = 0; i < callee.paramCount; i++) {
    regMap[i] = i < args.length ? args[i] : nextReg++;
  }

  // Clone instructions with remapped registers
  for (final inst in callee.instructions) {
    if (inst.opcode == LualikeIrOpcode.return0) {
      // RETURN0 → no-op (inlined function returns void)
      continue;
    }
    if (inst.opcode == LualikeIrOpcode.return1) {
      // RETURN1 r → MOVE call.a, r (result to caller's target)
      final srcReg = (inst as ABCInstruction).a;
      final dstReg = call.a;
      final mappedSrc = regMap[srcReg] ?? srcReg;
      out.add(
        ABCInstruction(
          opcode: LualikeIrOpcode.move,
          a: dstReg,
          b: mappedSrc,
          c: 0,
        ),
      );
      continue;
    }
    if (inst.opcode == LualikeIrOpcode.ret) {
      // Multi-value return → just move the first result
      if (inst is ABCInstruction) {
        final srcReg = inst.a;
        final dstReg = call.a;
        final mappedSrc = regMap[srcReg] ?? srcReg;
        out.add(
          ABCInstruction(
            opcode: LualikeIrOpcode.move,
            a: dstReg,
            b: mappedSrc,
            c: 0,
          ),
        );
      }
      continue;
    }
    // Remap registers in all other instructions
    out.add(_remapRegisters(inst, regMap));
  }
}

LualikeIrInstruction _remapRegisters(
  LualikeIrInstruction inst,
  Map<int, int> regMap,
) {
  int map(int r) => regMap[r] ?? r;
  return inst.when(
    abc: (i) {
      var a = map(i.a);
      var b = map(i.b);
      var c = map(i.c);
      if (a == i.a && b == i.b && c == i.c) return inst;
      return ABCInstruction(opcode: i.opcode, a: a, b: b, c: c, k: i.k);
    },
    abx: (i) {
      var a = map(i.a);
      if (a == i.a) return inst;
      return ABxInstruction(opcode: i.opcode, a: a, bx: i.bx);
    },
    asbx: (i) {
      var a = map(i.a);
      if (a == i.a) return inst;
      return AsBxInstruction(opcode: i.opcode, a: a, sBx: i.sBx);
    },
    ax: (_) => inst,
    asj: (_) => inst,
    avbc: (i) {
      var a = map(i.a);
      if (a == i.a) return inst;
      return AvBCInstruction(
        opcode: i.opcode,
        a: a,
        vB: i.vB,
        vC: i.vC,
        k: i.k,
      );
    },
  );
}
