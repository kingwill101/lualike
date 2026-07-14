/// Conservative function inlining for finalized lualike IR.
///
/// This pass intentionally accepts only direct, single-use, fixed-arity,
/// straight-line closures. A rejected candidate remains a normal `CLOSURE` +
/// `CALL`; correctness takes priority over recovering every possible call.
library;

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';
import 'register_budget.dart';

/// Maximum number of callee instructions considered for inlining.
const int _maxInlineInstructions = 10;

/// Inlines supported calls in [prototype] and its child prototypes.
///
/// When [preserveDebug] is true, callees with observable debug metadata are
/// not inlined because removing their frame would change debug behavior. A
/// bytecode pipeline that will strip debug data may pass false.
///
/// Each candidate is checked independently against the bytecode register
/// budget. A candidate that would exceed the budget is skipped without
/// preventing smaller candidates in the same prototype from being inlined.
LualikeIrPrototype inlineFunctions(
  LualikeIrPrototype prototype, {
  bool preserveDebug = true,
}) {
  final children = prototype.prototypes
      .map((child) => inlineFunctions(child, preserveDebug: preserveDebug))
      .toList(growable: false);
  var current = _withChildren(prototype, children);
  for (var iteration = 0; iteration < 5; iteration++) {
    final result = _runOnce(current, preserveDebug: preserveDebug);
    if (result == null) {
      return current;
    }
    current = result;
  }
  return current;
}

LualikeIrPrototype? _runOnce(
  LualikeIrPrototype prototype, {
  required bool preserveDebug,
}) {
  final instructions = prototype.instructions;
  if (instructions.isEmpty || prototype.prototypes.isEmpty) {
    return null;
  }

  // PC remapping for arbitrary caller control flow is deliberately deferred.
  // Straight-line callers still get exact debug and const-seal remapping.
  if (instructions.any(_isControlFlowInstruction)) {
    return null;
  }

  final candidates = <int, _InlineCandidate>{};
  final removedClosurePcs = <int>{};
  var nextRegister = prototype.registerCount;

  for (var closurePc = 0; closurePc < instructions.length; closurePc++) {
    final closure = instructions[closurePc];
    if (closure is! ABxInstruction ||
        closure.opcode != LualikeIrOpcode.closure ||
        closure.bx < 0 ||
        closure.bx >= prototype.prototypes.length) {
      continue;
    }

    final callPc = _findDirectCall(instructions, closurePc, closure.a);
    if (callPc == null || candidates.containsKey(callPc)) {
      continue;
    }
    final call = instructions[callPc] as ABCInstruction;
    final callee = prototype.prototypes[closure.bx];
    final freshRegisters = _freshRegistersRequired(callee);
    if (!_canInline(callee, call, preserveDebug: preserveDebug) ||
        (preserveDebug &&
            _callerDebugObservesClosure(
              prototype.debugInfo,
              closure.a,
              closurePc,
              callPc,
            )) ||
        nextRegister + freshRegisters >
            IrBytecodeRegisterBudget.maxRegisterCount) {
      continue;
    }

    final registerBase = nextRegister;
    nextRegister += freshRegisters;
    candidates[callPc] = _InlineCandidate(
      callee: callee,
      call: call,
      registerBase: registerBase,
    );
    removedClosurePcs.add(closurePc);
  }

  if (candidates.isEmpty) {
    return null;
  }

  final output = <LualikeIrInstruction>[];
  final pcMap = List<int>.filled(instructions.length + 1, 0, growable: false);
  final outputLines = <int>[];
  final oldLines = prototype.debugInfo?.lineInfo;

  for (var pc = 0; pc < instructions.length; pc++) {
    pcMap[pc] = output.length;
    if (removedClosurePcs.contains(pc)) {
      continue;
    }

    final candidate = candidates[pc];
    final start = output.length;
    if (candidate != null) {
      output.addAll(_inlineCandidate(candidate));
    } else {
      output.add(instructions[pc]);
    }
    final line = oldLines != null && pc < oldLines.length ? oldLines[pc] : 0;
    outputLines.addAll(List<int>.filled(output.length - start, line));
  }
  pcMap[instructions.length] = output.length;

  return LualikeIrPrototype(
    instructions: List<LualikeIrInstruction>.unmodifiable(output),
    constants: prototype.constants,
    registerCount: nextRegister,
    paramCount: prototype.paramCount,
    isVararg: prototype.isVararg,
    namedVarargRegister: prototype.namedVarargRegister,
    upvalueDescriptors: prototype.upvalueDescriptors,
    prototypes: prototype.prototypes,
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    debugInfo: _remapDebugInfo(prototype.debugInfo, outputLines, pcMap),
    registerConstFlags: List<bool>.unmodifiable(<bool>[
      ...prototype.registerConstFlags,
      ...List<bool>.filled(nextRegister - prototype.registerCount, false),
    ]),
    constSealPoints: _remapConstSealPoints(prototype.constSealPoints, pcMap),
  );
}

int? _findDirectCall(
  List<LualikeIrInstruction> instructions,
  int closurePc,
  int closureRegister,
) {
  for (var pc = closurePc + 1; pc < instructions.length; pc++) {
    final instruction = instructions[pc];
    if (instruction case ABCInstruction(
      opcode: LualikeIrOpcode.call,
      a: final callRegister,
    ) when callRegister == closureRegister) {
      return pc;
    }
    if (_conservativelyTouchesRegister(instruction, closureRegister)) {
      return null;
    }
  }
  return null;
}

bool _canInline(
  LualikeIrPrototype callee,
  ABCInstruction call, {
  required bool preserveDebug,
}) {
  if (callee.instructions.isEmpty ||
      callee.instructions.length > _maxInlineInstructions ||
      callee.registerCount < callee.paramCount ||
      callee.upvalueDescriptors.isNotEmpty ||
      callee.prototypes.isNotEmpty ||
      callee.isVararg ||
      callee.namedVarargRegister != null ||
      callee.constSealPoints.isNotEmpty ||
      callee.registerConstFlags.any((isConst) => isConst) ||
      call.b <= 0 ||
      call.b - 1 != callee.paramCount ||
      (call.c != 1 && call.c != 2) ||
      (preserveDebug && _hasObservableDebugMetadata(callee.debugInfo))) {
    return false;
  }

  final last = callee.instructions.last;
  if (last.opcode != LualikeIrOpcode.return0 &&
      last.opcode != LualikeIrOpcode.return1) {
    return false;
  }
  if (call.c == 2 && last.opcode != LualikeIrOpcode.return1) {
    return false;
  }

  for (var pc = 0; pc < callee.instructions.length - 1; pc++) {
    if (!_isSupportedBodyInstruction(callee.instructions[pc])) {
      return false;
    }
  }
  return true;
}

bool _callerDebugObservesClosure(
  LualikeIrDebugInfo? debugInfo,
  int register,
  int closurePc,
  int callPc,
) {
  if (debugInfo == null) {
    return false;
  }
  return debugInfo.localNames.any(
    (local) =>
        local.register == register &&
        local.startPc <= callPc &&
        local.endPc > closurePc,
  );
}

bool _hasObservableDebugMetadata(LualikeIrDebugInfo? debugInfo) {
  if (debugInfo == null) {
    return false;
  }
  return debugInfo.lineInfo.any((line) => line != 0) ||
      debugInfo.localNames.isNotEmpty ||
      debugInfo.upvalueNames.isNotEmpty ||
      debugInfo.toBeClosedNamesByPc.isNotEmpty ||
      debugInfo.preferredName != null ||
      debugInfo.preferredNameWhat.isNotEmpty;
}

int _freshRegistersRequired(LualikeIrPrototype callee) =>
    callee.registerCount - callee.paramCount;

List<LualikeIrInstruction> _inlineCandidate(_InlineCandidate candidate) {
  final callee = candidate.callee;
  final call = candidate.call;
  final registerMap = <int, int>{};
  for (var register = 0; register < callee.paramCount; register++) {
    registerMap[register] = call.a + 1 + register;
  }
  for (
    var register = callee.paramCount;
    register < callee.registerCount;
    register++
  ) {
    registerMap[register] =
        candidate.registerBase + register - callee.paramCount;
  }

  final output = <LualikeIrInstruction>[];
  for (var pc = 0; pc < callee.instructions.length - 1; pc++) {
    output.add(_remapBodyInstruction(callee.instructions[pc], registerMap));
  }

  final returnInstruction = callee.instructions.last;
  if (call.c == 2 && returnInstruction is ABCInstruction) {
    final source = registerMap[returnInstruction.a]!;
    if (source != call.a) {
      output.add(
        ABCInstruction(
          opcode: LualikeIrOpcode.move,
          a: call.a,
          b: source,
          c: 0,
        ),
      );
    }
  }
  return output;
}

bool _isSupportedBodyInstruction(LualikeIrInstruction instruction) {
  return switch (instruction.opcode) {
    LualikeIrOpcode.move ||
    LualikeIrOpcode.loadI ||
    LualikeIrOpcode.loadF ||
    LualikeIrOpcode.loadFalse ||
    LualikeIrOpcode.loadTrue ||
    LualikeIrOpcode.loadNil ||
    LualikeIrOpcode.addI ||
    LualikeIrOpcode.subI ||
    LualikeIrOpcode.shlI ||
    LualikeIrOpcode.shrI ||
    LualikeIrOpcode.add ||
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
    LualikeIrOpcode.mmBin ||
    LualikeIrOpcode.mmBinI ||
    LualikeIrOpcode.unm ||
    LualikeIrOpcode.bnot ||
    LualikeIrOpcode.notOp ||
    LualikeIrOpcode.len =>
      instruction is! ABCInstruction ||
          instruction.opcode != LualikeIrOpcode.loadNil ||
          instruction.b == 0,
    _ => false,
  };
}

LualikeIrInstruction _remapBodyInstruction(
  LualikeIrInstruction instruction,
  Map<int, int> registerMap,
) {
  int register(int value) => registerMap[value]!;

  return switch (instruction) {
    ABCInstruction(:final opcode, :final a, :final b, :final c, :final k)
        when opcode == LualikeIrOpcode.move =>
      ABCInstruction(
        opcode: opcode,
        a: register(a),
        b: register(b),
        c: c,
        k: k,
      ),
    AsBxInstruction(:final opcode, :final a, :final sBx)
        when opcode == LualikeIrOpcode.loadI ||
            opcode == LualikeIrOpcode.loadF =>
      AsBxInstruction(opcode: opcode, a: register(a), sBx: sBx),
    ABCInstruction(:final opcode, :final a, :final b, :final c, :final k)
        when opcode == LualikeIrOpcode.loadFalse ||
            opcode == LualikeIrOpcode.loadTrue ||
            opcode == LualikeIrOpcode.loadNil =>
      ABCInstruction(opcode: opcode, a: register(a), b: b, c: c, k: k),
    ABCInstruction(:final opcode, :final a, :final b, :final c, :final k)
        when opcode == LualikeIrOpcode.addI ||
            opcode == LualikeIrOpcode.subI ||
            opcode == LualikeIrOpcode.shlI ||
            opcode == LualikeIrOpcode.shrI =>
      ABCInstruction(
        opcode: opcode,
        a: register(a),
        b: register(b),
        c: c,
        k: k,
      ),
    ABCInstruction(:final opcode, :final a, :final b, :final c, :final k)
        when opcode == LualikeIrOpcode.add ||
            opcode == LualikeIrOpcode.sub ||
            opcode == LualikeIrOpcode.mul ||
            opcode == LualikeIrOpcode.mod ||
            opcode == LualikeIrOpcode.pow ||
            opcode == LualikeIrOpcode.div ||
            opcode == LualikeIrOpcode.idiv ||
            opcode == LualikeIrOpcode.band ||
            opcode == LualikeIrOpcode.bor ||
            opcode == LualikeIrOpcode.bxor ||
            opcode == LualikeIrOpcode.shl ||
            opcode == LualikeIrOpcode.shr =>
      ABCInstruction(
        opcode: opcode,
        a: register(a),
        b: register(b),
        c: register(c),
        k: k,
      ),
    ABCInstruction(:final opcode, :final a, :final b, :final c, :final k)
        when opcode == LualikeIrOpcode.mmBin =>
      ABCInstruction(
        opcode: opcode,
        a: register(a),
        b: register(b),
        c: c,
        k: k,
      ),
    ABCInstruction(:final opcode, :final a, :final b, :final c, :final k)
        when opcode == LualikeIrOpcode.mmBinI =>
      ABCInstruction(opcode: opcode, a: register(a), b: b, c: c, k: k),
    ABCInstruction(:final opcode, :final a, :final b, :final c, :final k)
        when opcode == LualikeIrOpcode.unm ||
            opcode == LualikeIrOpcode.bnot ||
            opcode == LualikeIrOpcode.notOp ||
            opcode == LualikeIrOpcode.len =>
      ABCInstruction(
        opcode: opcode,
        a: register(a),
        b: register(b),
        c: c,
        k: k,
      ),
    _ => throw StateError(
      'unsupported instruction reached inliner: ${instruction.opcode.name}',
    ),
  };
}

bool _isControlFlowInstruction(LualikeIrInstruction instruction) {
  return switch (instruction.opcode) {
    LualikeIrOpcode.lFalseSkip ||
    LualikeIrOpcode.jmp ||
    LualikeIrOpcode.eq ||
    LualikeIrOpcode.lt ||
    LualikeIrOpcode.le ||
    LualikeIrOpcode.eqK ||
    LualikeIrOpcode.eqI ||
    LualikeIrOpcode.ltI ||
    LualikeIrOpcode.leI ||
    LualikeIrOpcode.gtI ||
    LualikeIrOpcode.geI ||
    LualikeIrOpcode.test ||
    LualikeIrOpcode.testSet ||
    LualikeIrOpcode.forLoop ||
    LualikeIrOpcode.forPrep ||
    LualikeIrOpcode.tForPrep ||
    LualikeIrOpcode.tForCall ||
    LualikeIrOpcode.tForLoop => true,
    _ => false,
  };
}

bool _conservativelyTouchesRegister(
  LualikeIrInstruction instruction,
  int register,
) {
  return switch (instruction) {
    ABCInstruction(:final a, :final b, :final c) =>
      a == register || b == register || c == register,
    ABxInstruction(:final a) ||
    AsBxInstruction(:final a) ||
    AvBCInstruction(:final a) => a == register,
    AxInstruction() || AsJInstruction() => true,
  };
}

LualikeIrDebugInfo? _remapDebugInfo(
  LualikeIrDebugInfo? debugInfo,
  List<int> lineInfo,
  List<int> pcMap,
) {
  if (debugInfo == null) {
    return null;
  }
  return LualikeIrDebugInfo(
    lineInfo: List<int>.unmodifiable(lineInfo),
    absoluteSourcePath: debugInfo.absoluteSourcePath,
    localNames: List<LocalDebugEntry>.unmodifiable(
      debugInfo.localNames.map(
        (entry) => LocalDebugEntry(
          name: entry.name,
          startPc: _remapPc(entry.startPc, pcMap),
          endPc: _remapPc(entry.endPc, pcMap),
          register: entry.register,
        ),
      ),
    ),
    upvalueNames: debugInfo.upvalueNames,
    toBeClosedNamesByPc: Map<int, String>.unmodifiable(
      debugInfo.toBeClosedNamesByPc.map(
        (pc, name) => MapEntry(_remapPc(pc, pcMap), name),
      ),
    ),
    preferredName: debugInfo.preferredName,
    preferredNameWhat: debugInfo.preferredNameWhat,
  );
}

Map<int, List<int>> _remapConstSealPoints(
  Map<int, List<int>> constSealPoints,
  List<int> pcMap,
) {
  return Map<int, List<int>>.unmodifiable(
    constSealPoints.map(
      (pc, registers) =>
          MapEntry(_remapPc(pc, pcMap), List<int>.unmodifiable(registers)),
    ),
  );
}

int _remapPc(int pc, List<int> pcMap) {
  if (pc <= 0) {
    return 0;
  }
  if (pc >= pcMap.length) {
    return pcMap.last;
  }
  return pcMap[pc];
}

LualikeIrPrototype _withChildren(
  LualikeIrPrototype prototype,
  List<LualikeIrPrototype> children,
) {
  if (_sameChildren(prototype.prototypes, children)) {
    return prototype;
  }
  return LualikeIrPrototype(
    instructions: prototype.instructions,
    constants: prototype.constants,
    registerCount: prototype.registerCount,
    paramCount: prototype.paramCount,
    isVararg: prototype.isVararg,
    namedVarargRegister: prototype.namedVarargRegister,
    upvalueDescriptors: prototype.upvalueDescriptors,
    prototypes: children,
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    debugInfo: prototype.debugInfo,
    registerConstFlags: prototype.registerConstFlags,
    constSealPoints: prototype.constSealPoints,
  );
}

bool _sameChildren(
  List<LualikeIrPrototype> before,
  List<LualikeIrPrototype> after,
) {
  if (before.length != after.length) {
    return false;
  }
  for (var index = 0; index < before.length; index++) {
    if (!identical(before[index], after[index])) {
      return false;
    }
  }
  return true;
}

final class _InlineCandidate {
  const _InlineCandidate({
    required this.callee,
    required this.call,
    required this.registerBase,
  });

  final LualikeIrPrototype callee;
  final ABCInstruction call;
  final int registerBase;
}
