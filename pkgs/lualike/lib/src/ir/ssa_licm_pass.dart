/// Loop Invariant Code Motion (LICM) pass for the lualike IR.
///
/// Hoists loop-invariant computations out of loops so they execute once
/// before the loop instead of on every iteration.
///
/// ## Algorithm
///
/// 1. Find natural loops via back edges (A→B where B dominates A)
/// 2. For each loop, build the loop body (header + blocks reachable from it)
/// 3. Find the preheader (block outside the loop that jumps to header)
/// 4. Identify instructions whose operands are all defined outside the loop
/// 5. Hoist: insert a copy before the loop, replace original with MOVE
library;

import 'dart:collection';

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';
import 'ssa.dart';

const _licmPureOpcodes = <LualikeIrOpcode>{
  LualikeIrOpcode.move,
  LualikeIrOpcode.loadI,
  LualikeIrOpcode.loadF,
  LualikeIrOpcode.loadK,
  LualikeIrOpcode.loadKx,
  LualikeIrOpcode.loadFalse,
  LualikeIrOpcode.lFalseSkip,
  LualikeIrOpcode.loadTrue,
  LualikeIrOpcode.loadNil,
  LualikeIrOpcode.getUpval,
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
  LualikeIrOpcode.len,
  LualikeIrOpcode.concat,
  LualikeIrOpcode.closure,
};

int _resultReg(LualikeIrInstruction inst, int registerCount) {
  final r = inst.when(
    abc: (i) =>
        i.opcode == LualikeIrOpcode.jmp ||
            i.opcode == LualikeIrOpcode.close ||
            i.opcode == LualikeIrOpcode.tbc ||
            i.opcode == LualikeIrOpcode.ret ||
            i.opcode == LualikeIrOpcode.return0 ||
            i.opcode == LualikeIrOpcode.tailCall
        ? -1
        : i.a,
    abx: (i) => i.a,
    asbx: (i) => i.a,
    ax: (_) => -1,
    asj: (_) => -1,
    avbc: (i) => i.a,
  );
  return (r >= 0 && r < registerCount) ? r : -1;
}

/// Find all registers read by an instruction.
Set<int> _readRegs(LualikeIrInstruction inst, int registerCount) {
  final regs = <int>{};
  inst.when(
    abc: (i) {
      if (i.b >= 0 && i.b < registerCount) regs.add(i.b);
      if (i.c >= 0 && i.c < registerCount) regs.add(i.c);
    },
    abx: (_) {},
    asbx: (_) {},
    ax: (_) {},
    asj: (_) {},
    avbc: (_) {},
  );
  return regs;
}

/// Run LICM on an IR prototype.
LualikeIrPrototype hoistLoopInvariants(LualikeIrPrototype prototype) {
  var current = prototype;
  for (var iter = 0; iter < 5; iter++) {
    final result = _runLicmOnce(current);
    if (result == null) return current;
    current = result;
  }
  return current;
}

/// Collect all blocks in a natural loop with given [header] and [backEdgeFrom].
Set<int> _collectLoopBody(
  List<LualikeIrSsaBlock> ssaBlocks,
  int header,
  int backEdgeFrom,
) {
  final body = <int>{};
  final worklist = Queue<int>()..add(backEdgeFrom);
  while (worklist.isNotEmpty) {
    final bi = worklist.removeFirst();
    if (!body.add(bi)) continue;
    if (bi == header) continue;
    final block = ssaBlocks[bi];
    for (final pred in block.block.predecessors) {
      worklist.add(pred);
    }
  }
  body.add(header);
  return body;
}

LualikeIrPrototype? _runLicmOnce(LualikeIrPrototype prototype) {
  final instructions = prototype.instructions;
  if (instructions.isEmpty) return null;
  final registerCount = prototype.registerCount;

  final ssa = LualikeIrSsaFunction.fromPrototype(prototype);
  if (ssa.blocks.length < 2) return null;

  // 1. Find natural loops via back edges
  final loops =
      <({int header, int backEdgeFrom, Set<int> body, int preheader})>[];

  for (final block in ssa.blocks) {
    for (final succ in block.block.successors) {
      if (ssa.cfg.dominates(succ, block.block.index)) {
        // Back edge: block.index -> succ where succ dominates block.index
        final body = _collectLoopBody(ssa.blocks, succ, block.block.index);
        // Find preheader: the predecessor of the header that's NOT in the loop
        var preheader = -1;
        for (final pred in ssa.blocks[succ].block.predecessors) {
          if (!body.contains(pred)) {
            preheader = pred;
            break;
          }
        }
        if (preheader >= 0) {
          loops.add((
            header: succ,
            backEdgeFrom: block.block.index,
            body: body,
            preheader: preheader,
          ));
        }
        break; // one back edge per block
      }
    }
  }

  if (loops.isEmpty) return null;

  // 2. For each loop, find invariant instructions
  final hoistPcs = <int>{}; // PCs to hoist (insert clone before loop)

  for (final loop in loops) {
    // Track which registers are defined inside the loop
    final loopDefs = <int>{};
    for (final bi in loop.body) {
      for (final value in ssa.blocks[bi].definedValues) {
        loopDefs.add(value.register);
      }
    }

    // Find instructions whose read operands are NOT defined in the loop
    for (final bi in loop.body) {
      if (bi >= ssa.blocks.length) continue;
      for (final pc in ssa.blocks[bi].block.instructionPcs) {
        final inst = instructions[pc];
        if (!_licmPureOpcodes.contains(inst.opcode)) continue;
        final reads = _readRegs(inst, registerCount);
        if (reads.isEmpty) continue;
        final invariant = reads.every((r) => !loopDefs.contains(r));
        if (invariant) {
          hoistPcs.add(pc);
        }
      }
    }
  }

  if (hoistPcs.isEmpty) return null;

  // 3. Build new instruction list with hoisting
  // For each hoisted instruction, insert its clone before the loop header
  // and replace the original with a MOVE
  final newInstructions = <LualikeIrInstruction>[];
  final hoistMap = <int, int>{}; // pc -> new pc in hoisted section

  var hoistIndex = 0;
  for (var pc = 0; pc < instructions.length; pc++) {
    if (hoistPcs.contains(pc)) {
      hoistMap[pc] = hoistIndex++;
      // Insert clone now (will be inserted at the preheader position)
    }
  }

  // Insert preheader (before loop start) with hoisted instructions
  // Find the earliest PC among all loop headers
  final earliestHeader = loops
      .map((l) => ssa.blocks[l.header].block.startPc)
      .reduce((a, b) => a < b ? a : b);

  for (var pc = 0; pc < earliestHeader; pc++) {
    newInstructions.add(instructions[pc]);
  }

  // Insert hoisted clones
  final clonedResults = <int, int>{}; // original pc -> clone target reg
  for (final pc in hoistPcs.toList()..sort()) {
    final inst = instructions[pc];
    final targetReg = _resultReg(inst, registerCount);
    if (targetReg >= 0) {
      // Clone the instruction verbatim
      newInstructions.add(inst);
      clonedResults[pc] = targetReg;
    }
  }

  // Rest of instructions, replacing hoisted ones with MOVEs
  for (var pc = earliestHeader; pc < instructions.length; pc++) {
    if (hoistPcs.contains(pc)) {
      final targetReg = _resultReg(instructions[pc], registerCount);
      if (targetReg >= 0) {
        // Replace with MOVE from the clone (same register, same result)
        // Since the clone computes the same value into the same register,
        // the original is redundant. We just skip it entirely.
        // But if there's a MOVE from targetReg in the loop, it's fine.
        // The clone already defined targetReg, so the original's definition
        // is dead. Just skip it.
        continue;
      }
    }
    newInstructions.add(instructions[pc]);
  }

  if (newInstructions.length == instructions.length) return null;

  return LualikeIrPrototype(
    instructions: newInstructions,
    constants: prototype.constants,
    registerCount: prototype.registerCount,
    paramCount: prototype.paramCount,
    isVararg: prototype.isVararg,
    upvalueDescriptors: prototype.upvalueDescriptors,
    prototypes: _licmSubPrototypes(prototype.prototypes),
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    debugInfo: prototype.debugInfo,
    registerConstFlags: prototype.registerConstFlags,
    constSealPoints: prototype.constSealPoints,
  );
}

List<LualikeIrPrototype> _licmSubPrototypes(List<LualikeIrPrototype> protos) {
  return [for (final sub in protos) hoistLoopInvariants(sub)];
}
