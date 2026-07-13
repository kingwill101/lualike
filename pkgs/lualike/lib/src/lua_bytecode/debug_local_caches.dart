/// Debug-local caches and register inference for Lua bytecode prototypes.
///
/// Official Lua 5.x chunks store locals as `(name, startPc, endPc)` only.
/// This VM needs a stack **register** for each local so
/// `debug.getlocal` / `debug.setlocal` can read frame slots.
///
/// After [LuaBytecodeReader.readChunk] parses a chunk, call
/// [prototypeWithInferredLocalRegisters] (done automatically in the reader)
/// so reloaded pipeline/`--fold` chunks keep working.
///
/// See also: `doc/decisions.md` ("Official bytecode omits local registers").
library;

import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart';

/// Active debug local window at a given PC.
///
/// [locals] are named entries live at that PC; [registers] is the set of
/// stack slots they occupy (used to hide those slots from temporary listing).
typedef LuaBytecodeDebugLocalWindow = ({
  List<LuaBytecodeLocalVariableDebugInfo> locals,
  Set<int> registers,
});

const emptyLuaBytecodeDebugLocalWindow = (
  locals: <LuaBytecodeLocalVariableDebugInfo>[],
  registers: <int>{},
);

final Expando<List<({int start, int? end})?>>
prototypeWrittenRegisterRangesByPc = Expando<List<({int start, int? end})?>>(
  'luaBytecodePrototypeWrittenRegisterRangesByPc',
);

List<({int start, int? end})?> writtenRegisterRangesByPcFor(
  LuaBytecodePrototype prototype,
) {
  final cached = prototypeWrittenRegisterRangesByPc[prototype];
  if (cached != null) {
    return cached;
  }

  final ranges = List<({int start, int? end})?>.generate(
    prototype.code.length,
    (pc) {
      final word = prototype.code[pc];
      return switch (word.opcode) {
        Opcode.move ||
        Opcode.loadI ||
        Opcode.loadF ||
        Opcode.loadK ||
        Opcode.loadKx ||
        Opcode.loadFalse ||
        Opcode.lFalseSkip ||
        Opcode.loadTrue ||
        Opcode.getUpval ||
        Opcode.getTabUp ||
        Opcode.getTable ||
        Opcode.getI ||
        Opcode.getField ||
        Opcode.newTable ||
        Opcode.self ||
        Opcode.closure ||
        Opcode.varArgPrep ||
        Opcode.varArg => (start: word.a, end: word.a),
        Opcode.loadNil => (start: word.a, end: word.a + word.b),
        Opcode.call || Opcode.tailCall => (
          start: word.a,
          end: word.c == 0 ? null : word.a + word.c - 2,
        ),
        _ => null,
      };
    },
    growable: false,
  );
  prototypeWrittenRegisterRangesByPc[prototype] = ranges;
  return ranges;
}

final Expando<List<Map<int, String>>> prototypeActiveNamedLocalsByPc =
    Expando<List<Map<int, String>>>(
      'luaBytecodePrototypeActiveNamedLocalsByPc',
    );

List<Map<int, String>> activeNamedLocalsByPcFor(
  LuaBytecodePrototype prototype,
) {
  final cached = prototypeActiveNamedLocalsByPc[prototype];
  if (cached != null) {
    return cached;
  }

  final codeLength = prototype.code.length;
  final startsByPc = List<List<LuaBytecodeLocalVariableDebugInfo>>.generate(
    codeLength,
    (_) => <LuaBytecodeLocalVariableDebugInfo>[],
    growable: false,
  );
  final endsByPc = List<List<LuaBytecodeLocalVariableDebugInfo>>.generate(
    codeLength,
    (_) => <LuaBytecodeLocalVariableDebugInfo>[],
    growable: false,
  );
  for (final local in prototype.localVariables) {
    if (local.register == null || local.endPc <= local.startPc) {
      continue;
    }
    final startPc = local.startPc;
    if (startPc >= 0 && startPc < codeLength) {
      startsByPc[startPc].add(local);
    }
    final endPc = local.endPc;
    if (endPc >= 0 && endPc < codeLength) {
      endsByPc[endPc].add(local);
    }
  }

  final activeLocalsByRegister =
      <int, List<LuaBytecodeLocalVariableDebugInfo>>{};
  var currentNamedLocals = const <int, String>{};
  final snapshots = List<Map<int, String>>.filled(
    codeLength,
    const <int, String>{},
    growable: false,
  );

  Map<int, String> snapshotNamedLocals() {
    if (activeLocalsByRegister.isEmpty) {
      return const <int, String>{};
    }
    final namedLocals = <int, String>{};
    for (final entry in activeLocalsByRegister.entries) {
      for (final local in entry.value.reversed) {
        final name = local.name;
        if (name == null || name.isEmpty || name.startsWith('(')) {
          continue;
        }
        namedLocals[entry.key] = name;
        break;
      }
    }
    return namedLocals.isEmpty ? const <int, String>{} : namedLocals;
  }

  for (var pc = 0; pc < codeLength; pc++) {
    var changed = false;
    for (final local in endsByPc[pc]) {
      final register = local.register!;
      final locals = activeLocalsByRegister[register];
      if (locals == null) {
        continue;
      }
      locals.remove(local);
      if (locals.isEmpty) {
        activeLocalsByRegister.remove(register);
      }
      changed = true;
    }
    for (final local in startsByPc[pc]) {
      final register = local.register!;
      activeLocalsByRegister
          .putIfAbsent(register, () => <LuaBytecodeLocalVariableDebugInfo>[])
          .add(local);
      changed = true;
    }
    if (changed) {
      currentNamedLocals = snapshotNamedLocals();
    }
    snapshots[pc] = currentNamedLocals;
  }

  prototypeActiveNamedLocalsByPc[prototype] = snapshots;
  return snapshots;
}

final Expando<List<LuaBytecodeDebugLocalWindow>>
prototypeActiveDebugLocalsByPc = Expando<List<LuaBytecodeDebugLocalWindow>>(
  'luaBytecodePrototypeActiveDebugLocalsByPc',
);

final Expando<List<Map<int, String>>> prototypeVisibleNamedLocalsByPc =
    Expando<List<Map<int, String>>>(
      'luaBytecodePrototypeVisibleNamedLocalsByPc',
    );

List<LuaBytecodeDebugLocalWindow> activeDebugLocalsByPcFor(
  LuaBytecodePrototype prototype,
) {
  final cached = prototypeActiveDebugLocalsByPc[prototype];
  if (cached != null) {
    return cached;
  }

  final sortedLocals = sortedDebugLocalsFor(prototype);
  final windows = List<LuaBytecodeDebugLocalWindow>.generate(
    prototype.code.length,
    (pc) => debugLocalWindowForPc(sortedLocals, pc),
    growable: false,
  );
  prototypeActiveDebugLocalsByPc[prototype] = windows;
  return windows;
}

List<Map<int, String>> visibleNamedLocalsByPcFor(
  LuaBytecodePrototype prototype,
) {
  // Precompute the visible-local snapshots once per prototype; the frame
  // constructor and debug hooks query these repeatedly.
  final cached = prototypeVisibleNamedLocalsByPc[prototype];
  if (cached != null) {
    return cached;
  }

  final codeLength = prototype.code.length;
  final startsByPc = List<List<LuaBytecodeLocalVariableDebugInfo>>.generate(
    codeLength,
    (_) => <LuaBytecodeLocalVariableDebugInfo>[],
    growable: false,
  );
  final endsByPc = List<List<LuaBytecodeLocalVariableDebugInfo>>.generate(
    codeLength,
    (_) => <LuaBytecodeLocalVariableDebugInfo>[],
    growable: false,
  );
  for (final local in prototype.localVariables) {
    if (local.register == null) {
      continue;
    }
    final startPc = local.startPc;
    if (startPc >= 0 && startPc < codeLength) {
      startsByPc[startPc].add(local);
    }
    final endPc = local.endPc;
    if (endPc >= 0 && endPc < codeLength) {
      endsByPc[endPc].add(local);
    }
  }

  final activeLocalsByRegister =
      <int, List<LuaBytecodeLocalVariableDebugInfo>>{};
  var currentVisibleLocals = const <int, String>{};
  final snapshots = List<Map<int, String>>.filled(
    codeLength,
    const <int, String>{},
    growable: false,
  );

  Map<int, String> snapshotVisibleLocals() {
    if (activeLocalsByRegister.isEmpty) {
      return const <int, String>{};
    }
    final visibleLocals = <int, String>{};
    for (final entry in activeLocalsByRegister.entries) {
      for (final local in entry.value) {
        final name = local.name;
        if (name == null || name.isEmpty || name.startsWith('(')) {
          continue;
        }
        visibleLocals[entry.key] = name;
        break;
      }
    }
    return visibleLocals.isEmpty ? const <int, String>{} : visibleLocals;
  }

  for (var pc = 0; pc < codeLength; pc++) {
    var changed = false;
    for (final local in endsByPc[pc]) {
      final register = local.register!;
      final locals = activeLocalsByRegister[register];
      if (locals == null) {
        continue;
      }
      locals.remove(local);
      if (locals.isEmpty) {
        activeLocalsByRegister.remove(register);
      }
      changed = true;
    }
    for (final local in startsByPc[pc]) {
      final register = local.register!;
      activeLocalsByRegister
          .putIfAbsent(register, () => <LuaBytecodeLocalVariableDebugInfo>[])
          .add(local);
      changed = true;
    }
    if (changed) {
      currentVisibleLocals = snapshotVisibleLocals();
    }
    snapshots[pc] = currentVisibleLocals;
  }

  prototypeVisibleNamedLocalsByPc[prototype] = snapshots;
  return snapshots;
}

LuaBytecodeDebugLocalWindow debugLocalWindowForPc(
  List<LuaBytecodeLocalVariableDebugInfo> sortedLocals,
  int pc,
) {
  final locals = <LuaBytecodeLocalVariableDebugInfo>[];
  final registers = <int>{};
  for (final local in sortedLocals) {
    final register = local.register;
    if (register == null || local.startPc > pc || pc >= local.endPc) {
      continue;
    }
    locals.add(local);
    registers.add(register);
  }
  if (locals.isEmpty) {
    return emptyLuaBytecodeDebugLocalWindow;
  }
  return (
    locals: List<LuaBytecodeLocalVariableDebugInfo>.unmodifiable(locals),
    registers: Set<int>.unmodifiable(registers),
  );
}

final Expando<List<LuaBytecodeLocalVariableDebugInfo>>
prototypeSortedDebugLocals = Expando<List<LuaBytecodeLocalVariableDebugInfo>>(
  'luaBytecodePrototypeSortedDebugLocals',
);

List<LuaBytecodeLocalVariableDebugInfo> sortedDebugLocalsFor(
  LuaBytecodePrototype prototype,
) {
  // Sorting locals is pure prototype metadata, so cache it instead of paying
  // the cost on every frame setup.
  final cached = prototypeSortedDebugLocals[prototype];
  if (cached != null) {
    return cached;
  }

  final sorted = List<LuaBytecodeLocalVariableDebugInfo>.of(
    prototype.localVariables,
    growable: false,
  )..sort(compareDebugLocals);
  prototypeSortedDebugLocals[prototype] = sorted;
  return sorted;
}

int compareDebugLocals(
  LuaBytecodeLocalVariableDebugInfo left,
  LuaBytecodeLocalVariableDebugInfo right,
) {
  final startOrder = left.startPc.compareTo(right.startPc);
  if (startOrder != 0) {
    return startOrder;
  }
  final leftRegister = left.register ?? -1;
  final rightRegister = right.register ?? -1;
  final registerOrder = leftRegister.compareTo(rightRegister);
  if (registerOrder != 0) {
    return registerOrder;
  }
  return (left.name ?? '').compareTo(right.name ?? '');
}

final Expando<List<Set<int>>> prototypeEnvironmentRegistersByPc =
    Expando<List<Set<int>>>('luaBytecodePrototypeEnvironmentRegistersByPc');

List<Set<int>> environmentRegistersByPcFor(LuaBytecodePrototype prototype) {
  final cached = prototypeEnvironmentRegistersByPc[prototype];
  if (cached != null) {
    return cached;
  }

  final codeLength = prototype.code.length;
  final startsByPc = List<List<LuaBytecodeLocalVariableDebugInfo>>.generate(
    codeLength,
    (_) => <LuaBytecodeLocalVariableDebugInfo>[],
    growable: false,
  );
  final endsByPc = List<List<LuaBytecodeLocalVariableDebugInfo>>.generate(
    codeLength,
    (_) => <LuaBytecodeLocalVariableDebugInfo>[],
    growable: false,
  );
  for (final local in prototype.localVariables) {
    if (local.register == null || local.endPc <= local.startPc) {
      continue;
    }
    final startPc = local.startPc;
    if (startPc >= 0 && startPc < codeLength) {
      startsByPc[startPc].add(local);
    }
    final endPc = local.endPc;
    if (endPc >= 0 && endPc < codeLength) {
      endsByPc[endPc].add(local);
    }
  }

  final activeLocalsByRegister =
      <int, List<LuaBytecodeLocalVariableDebugInfo>>{};
  var currentEnvironmentRegisters = const <int>{};
  final snapshots = List<Set<int>>.filled(
    codeLength,
    const <int>{},
    growable: false,
  );

  Set<int> snapshotEnvironmentRegisters() {
    if (activeLocalsByRegister.isEmpty) {
      return const <int>{};
    }
    final envRegisters = <int>{};
    for (final entry in activeLocalsByRegister.entries) {
      if (entry.value.any((local) => local.name == '_ENV')) {
        envRegisters.add(entry.key);
      }
    }
    return envRegisters.isEmpty ? const <int>{} : envRegisters;
  }

  for (var pc = 0; pc < codeLength; pc++) {
    var changed = false;
    for (final local in endsByPc[pc]) {
      final register = local.register!;
      final locals = activeLocalsByRegister[register];
      if (locals == null) {
        continue;
      }
      locals.remove(local);
      if (locals.isEmpty) {
        activeLocalsByRegister.remove(register);
      }
      changed = true;
    }
    for (final local in startsByPc[pc]) {
      final register = local.register!;
      activeLocalsByRegister
          .putIfAbsent(register, () => <LuaBytecodeLocalVariableDebugInfo>[])
          .add(local);
      changed = true;
    }
    if (changed) {
      currentEnvironmentRegisters = snapshotEnvironmentRegisters();
    }
    snapshots[pc] = currentEnvironmentRegisters;
  }

  prototypeEnvironmentRegistersByPc[prototype] = snapshots;
  return snapshots;
}

/// Recovers per-local stack registers missing from official Lua debug sections.
///
/// Official chunks only store `(name, startPc, endPc)`. Lua locals form a
/// **stack** of active slots (PUC-Rio `actvar`): the n-th active local at any
/// PC lives in register `n - 1`. This simulates that stack at each local's
/// birth so [LuaBytecodeLocalVariableDebugInfo.register] is filled.
///
/// **Why this exists:** serialize → parse strips registers (not in the binary
/// format). Without inference, `debug_local_caches` skips `register == null`
/// entries and `debug.getlocal` returns nothing after `--fold` / pipeline load.
///
/// **Invariant assumed:** lifetimes nest like a stack (block-scoped locals).
/// That matches both the direct emitter and the IR compiler's local allocator.
/// If a future pass assigns non-stack local registers, prefer emitting an
/// explicit register extension on serialize instead of relying only on this.
///
/// Locals that already have [LuaBytecodeLocalVariableDebugInfo.register] set
/// are left unchanged; only `null` slots are filled.
List<LuaBytecodeLocalVariableDebugInfo> inferLocalRegisters(
  List<LuaBytecodeLocalVariableDebugInfo> locals,
) {
  if (locals.isEmpty) {
    return locals;
  }
  if (locals.every((local) => local.register != null)) {
    return locals;
  }

  // Process births in startPc order (stable by original index on ties).
  final order = List<int>.generate(locals.length, (index) => index)
    ..sort((left, right) {
      final startOrder = locals[left].startPc.compareTo(locals[right].startPc);
      if (startOrder != 0) {
        return startOrder;
      }
      return left.compareTo(right);
    });

  final registers = <int?>[for (final local in locals) local.register];
  // Indices of currently live locals; only the top of the stack dies first.
  final active = <int>[];

  for (final index in order) {
    final local = locals[index];
    // endPc is the first PC where the local is dead (Lua LocVar convention).
    while (active.isNotEmpty && locals[active.last].endPc <= local.startPc) {
      active.removeLast();
    }

    if (registers[index] == null) {
      // Depth on the actvar stack == register index under stack discipline.
      registers[index] = active.length;
    }
    active.add(index);
  }

  return <LuaBytecodeLocalVariableDebugInfo>[
    for (var index = 0; index < locals.length; index++)
      LuaBytecodeLocalVariableDebugInfo(
        name: locals[index].name,
        startPc: locals[index].startPc,
        endPc: locals[index].endPc,
        register: registers[index],
      ),
  ];
}

/// Returns [prototype] with [inferLocalRegisters] applied recursively.
///
/// Prefer calling this once at chunk-load time (see [LuaBytecodeReader.readChunk])
/// rather than ad hoc in the VM, so all debug caches see consistent registers.
LuaBytecodePrototype prototypeWithInferredLocalRegisters(
  LuaBytecodePrototype prototype,
) {
  final localVariables = inferLocalRegisters(prototype.localVariables);
  final children = <LuaBytecodePrototype>[
    for (final child in prototype.prototypes)
      prototypeWithInferredLocalRegisters(child),
  ];

  final localsUnchanged =
      identical(localVariables, prototype.localVariables) ||
      _localListsEqual(localVariables, prototype.localVariables);
  var childrenUnchanged = children.length == prototype.prototypes.length;
  if (childrenUnchanged) {
    for (var index = 0; index < children.length; index++) {
      if (!identical(children[index], prototype.prototypes[index])) {
        childrenUnchanged = false;
        break;
      }
    }
  }

  if (localsUnchanged && childrenUnchanged) {
    return prototype;
  }

  return LuaBytecodePrototype(
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    parameterCount: prototype.parameterCount,
    flags: prototype.flags,
    maxStackSize: prototype.maxStackSize,
    code: prototype.code,
    constants: prototype.constants,
    upvalues: prototype.upvalues,
    prototypes: List<LuaBytecodePrototype>.unmodifiable(children),
    source: prototype.source,
    lineInfo: prototype.lineInfo,
    absoluteLineInfo: prototype.absoluteLineInfo,
    localVariables: List<LuaBytecodeLocalVariableDebugInfo>.unmodifiable(
      localVariables,
    ),
    upvalueNames: prototype.upvalueNames,
  );
}

bool _localListsEqual(
  List<LuaBytecodeLocalVariableDebugInfo> left,
  List<LuaBytecodeLocalVariableDebugInfo> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    final a = left[index];
    final b = right[index];
    if (a.name != b.name ||
        a.startPc != b.startPc ||
        a.endPc != b.endPc ||
        a.register != b.register) {
      return false;
    }
  }
  return true;
}
