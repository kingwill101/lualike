/// Rebuild an IR instruction list after deleting PCs, fixing relative jumps.
///
/// SSA DCE / coalesce remove instructions. JMP `sJ` and FORPREP/FORLOOP `sBx`
/// are relative to the instruction stream; leaving them unchanged after
/// deletions makes lowering's pcMap look past the end of the list
/// (`RangeError` in `_lowerInstructions`) or sends control to the wrong
/// successor (e.g. skipping a `GETTABUP` after an empty if-end jump).
///
/// Always use [compactIrInstructions] (and [remapDebugInfoAfterCompact])
/// when dropping PCs from a prototype's code list.
library;

import 'package:lualike/src/ir/instruction.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/ir/prototype.dart';

/// Returns [instructions] with [removePcs] dropped and jump offsets rewritten.
///
/// [removePcs] are indices into the original [instructions] list.
List<LualikeIrInstruction> compactIrInstructions(
  List<LualikeIrInstruction> instructions,
  Set<int> removePcs,
) {
  if (removePcs.isEmpty) {
    return instructions;
  }

  // oldPc → newPc for kept instructions; also map[length] = new length.
  final map = List<int>.filled(instructions.length + 1, 0, growable: false);
  var newPc = 0;
  for (var oldPc = 0; oldPc < instructions.length; oldPc++) {
    map[oldPc] = newPc;
    if (!removePcs.contains(oldPc)) {
      newPc++;
    }
  }
  map[instructions.length] = newPc;

  final result = <LualikeIrInstruction>[];
  for (var oldPc = 0; oldPc < instructions.length; oldPc++) {
    if (removePcs.contains(oldPc)) {
      continue;
    }
    result.add(_remapRelativeControlFlow(instructions[oldPc], oldPc, map));
  }
  return result;
}

LualikeIrInstruction _remapRelativeControlFlow(
  LualikeIrInstruction inst,
  int oldPc,
  List<int> oldToNewPc,
) {
  final newPc = oldToNewPc[oldPc];
  switch (inst) {
    case AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: final sJ):
      final targetOld = oldPc + 1 + sJ;
      final targetNew = _mapTarget(targetOld, oldToNewPc);
      return AsJInstruction(
        opcode: LualikeIrOpcode.jmp,
        sJ: targetNew - newPc - 1,
      );
    case AsBxInstruction(opcode: final opcode, a: final a, sBx: final sBx)
        when opcode == LualikeIrOpcode.forPrep ||
            opcode == LualikeIrOpcode.forLoop ||
            opcode == LualikeIrOpcode.tForPrep ||
            opcode == LualikeIrOpcode.tForLoop:
      final targetOld = oldPc + 1 + sBx;
      final targetNew = _mapTarget(targetOld, oldToNewPc);
      return AsBxInstruction(opcode: opcode, a: a, sBx: targetNew - newPc - 1);
    default:
      return inst;
  }
}

int _mapTarget(int targetOldPc, List<int> oldToNewPc) {
  if (targetOldPc < 0) {
    return 0;
  }
  if (targetOldPc >= oldToNewPc.length) {
    // Past-end target → end of compacted list.
    return oldToNewPc[oldToNewPc.length - 1];
  }
  return oldToNewPc[targetOldPc];
}

/// Remaps debug local PC ranges after [compactIrInstructions].
LualikeIrDebugInfo? remapDebugInfoAfterCompact(
  LualikeIrDebugInfo? debugInfo,
  int oldLength,
  Set<int> removePcs,
) {
  if (debugInfo == null || removePcs.isEmpty) {
    return debugInfo;
  }
  final map = List<int>.filled(oldLength + 1, 0, growable: false);
  var newPc = 0;
  for (var oldPc = 0; oldPc < oldLength; oldPc++) {
    map[oldPc] = newPc;
    if (!removePcs.contains(oldPc)) {
      newPc++;
    }
  }
  map[oldLength] = newPc;

  int mapPc(int pc) {
    if (pc < 0) {
      return 0;
    }
    if (pc >= map.length) {
      return map[map.length - 1];
    }
    return map[pc];
  }

  final locals = debugInfo.localNames;
  final remappedLocals = <LocalDebugEntry>[
    for (final local in locals)
      LocalDebugEntry(
        name: local.name,
        startPc: mapPc(local.startPc),
        endPc: mapPc(local.endPc),
        register: local.register,
      ),
  ];

  final lineInfo = debugInfo.lineInfo;
  final remappedLines = <int>[
    for (var oldPc = 0; oldPc < lineInfo.length; oldPc++)
      if (!removePcs.contains(oldPc)) lineInfo[oldPc],
  ];

  final tbc = <int, String>{
    for (final entry in debugInfo.toBeClosedNamesByPc.entries)
      mapPc(entry.key): entry.value,
  };

  return LualikeIrDebugInfo(
    absoluteSourcePath: debugInfo.absoluteSourcePath,
    lineInfo: remappedLines,
    localNames: remappedLocals,
    upvalueNames: debugInfo.upvalueNames,
    toBeClosedNamesByPc: tbc,
    preferredName: debugInfo.preferredName,
    preferredNameWhat: debugInfo.preferredNameWhat,
  );
}
