import 'dart:collection';

import 'control_flow.dart';
import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';

/// A placeholder SSA shape built on top of the existing IR control-flow graph.
///
/// Lualike already compiles `AST -> IR -> BYTECODE`. This model keeps the IR
/// pipeline intact while adding the graph/phi vocabulary needed for future SSA
/// work. The current factory derives blocks, dominance data, phi placement, and
/// a first-pass SSA renaming of register versions.
final class LualikeIrSsaFunction {
  const LualikeIrSsaFunction({
    required this.cfg,
    required this.blocks,
    required this.immediateDominatorByBlock,
    required this.dominanceFrontierByBlock,
  });

  final LualikeIrControlFlowGraph cfg;
  final List<LualikeIrSsaBlock> blocks;
  final Map<int, int?> immediateDominatorByBlock;
  final Map<int, List<int>> dominanceFrontierByBlock;

  factory LualikeIrSsaFunction.fromPrototype(LualikeIrPrototype prototype) {
    final cfg = LualikeIrControlFlowGraph.fromPrototype(prototype);
    final phiBuildersByBlock = _placePhiNodes(cfg, prototype.registerCount);
    final renameData = _renameValues(
      cfg,
      phiBuildersByBlock,
      prototype.registerCount,
    );
    final phisByBlock = _materializePhis(phiBuildersByBlock);

    final blocks = cfg.blocks
        .map(
          (block) => LualikeIrSsaBlock(
            block: block,
            phis: phisByBlock[block.index] ?? const <LualikeIrPhi>[],
            entryValues:
                renameData[block.index]?.entryValues ??
                const <int, LualikeIrSsaValue>{},
            exitValues:
                renameData[block.index]?.exitValues ??
                const <int, LualikeIrSsaValue>{},
            definedValues:
                renameData[block.index]?.definedValues ??
                const <LualikeIrSsaValue>[],
          ),
        )
        .toList(growable: false);

    final function = LualikeIrSsaFunction(
      cfg: cfg,
      blocks: blocks,
      immediateDominatorByBlock: cfg.immediateDominatorByBlock,
      dominanceFrontierByBlock: cfg.dominanceFrontierByBlock,
    );
    _rebuildSsaUses(function);
    return function;
  }

  int? immediateDominatorOf(int blockIndex) =>
      immediateDominatorByBlock[blockIndex];

  List<int> dominanceFrontierOf(int blockIndex) =>
      dominanceFrontierByBlock[blockIndex] ?? const <int>[];

  /// Values defined in this function that are never used.
  Iterable<LualikeIrSsaValue> get unusedDefinitions =>
      blocks.expand((block) => block.unusedDefinitions);

  /// Whether the function contains any unused SSA values.
  bool get hasUnusedDefinitions => unusedDefinitions.isNotEmpty;

  LualikeIrSsaFunction simplifyTrivialPhis() {
    // Run to a fixed point: removing one trivial phi can make another phi
    // trivial once its incoming values are rewritten.
    var currentBlocks = blocks;
    while (true) {
      final replacementByValue = <LualikeIrSsaValue, LualikeIrSsaValue>{};
      var changed = false;
      final rewrittenBlocks = <LualikeIrSsaBlock>[];

      for (final block in currentBlocks) {
        final remainingPhis = <LualikeIrPhi>[];
        for (final phi in block.phis) {
          final incoming = _resolvedTrivialIncomingValue(
            phi,
            replacementByValue,
          );
          if (incoming != null) {
            replacementByValue[phi.value] = incoming;
            changed = true;
            continue;
          }
          remainingPhis.add(phi);
        }

        rewrittenBlocks.add(
          _rewriteSsaBlock(
            block,
            replacements: replacementByValue,
            phis: remainingPhis,
          ),
        );
      }

      if (!changed) {
        final simplified = LualikeIrSsaFunction(
          cfg: cfg,
          blocks: List<LualikeIrSsaBlock>.unmodifiable(rewrittenBlocks),
          immediateDominatorByBlock: immediateDominatorByBlock,
          dominanceFrontierByBlock: dominanceFrontierByBlock,
        );
        _rebuildSsaUses(simplified);
        return simplified;
      }

      currentBlocks = rewrittenBlocks;
    }
  }

  @override
  String toString() => formatLualikeIrSsaFunction(this);
}

/// A single SSA value for one register version.
final class LualikeIrSsaValue {
  LualikeIrSsaValue({
    required this.register,
    required this.version,
    required this.definingBlock,
    this.definingPc,
    this.isPhi = false,
    List<LualikeIrSsaUse>? uses,
  }) : uses = uses ?? <LualikeIrSsaUse>[];

  final int register;
  final int version;
  final int definingBlock;
  final int? definingPc;
  final bool isPhi;

  /// Recorded uses of this SSA value.
  ///
  /// The list is rebuilt after SSA rewrites so the def-use metadata stays in
  /// sync with the current block/value graph.
  final List<LualikeIrSsaUse> uses;

  String get label => 'r$register#$version';

  /// Number of recorded uses.
  int get useCount => uses.length;

  /// Whether this value has no recorded uses.
  bool get isUnused => uses.isEmpty;

  /// Records one additional use of this SSA value.
  void addUse(LualikeIrSsaUse use) {
    uses.add(use);
  }

  @override
  String toString() => label;
}

/// A use of an SSA value at a particular control-flow location.
///
/// The `kind` field is a lightweight tag (`instruction` or `phi`) so the SSA
/// dump can tell whether the use came from an instruction operand or a phi
/// input edge.
final class LualikeIrSsaUse {
  const LualikeIrSsaUse({
    required this.blockIndex,
    required this.kind,
    this.pc,
    this.operandRegister,
  });

  final int blockIndex;
  final int? pc;
  final String kind;
  final int? operandRegister;

  @override
  String toString() {
    final parts = <String>['b$blockIndex'];
    if (pc != null) {
      parts.add('pc=$pc');
    }
    if (operandRegister != null) {
      parts.add('r$operandRegister');
    }
    parts.add(kind);
    return 'Use(${parts.join(', ')})';
  }
}

/// An SSA phi node describing a value selected from predecessor blocks.
final class LualikeIrPhi {
  const LualikeIrPhi({
    required this.targetRegister,
    required this.value,
    required this.incomingByPredecessor,
  });

  final int targetRegister;
  final LualikeIrSsaValue value;
  final Map<int, LualikeIrSsaValue> incomingByPredecessor;

  /// Returns the incoming value contributed by [predecessorBlock], if any.
  LualikeIrSsaValue? incomingForBlock(int predecessorBlock) {
    return incomingByPredecessor[predecessorBlock];
  }

  /// Returns the shared incoming value when every predecessor contributes the
  /// exact same SSA object.
  LualikeIrSsaValue? get trivialIncomingValue {
    if (incomingByPredecessor.isEmpty) {
      return null;
    }

    final iterator = incomingByPredecessor.values.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    final first = iterator.current;
    while (iterator.moveNext()) {
      if (!identical(iterator.current, first)) {
        return null;
      }
    }
    return first;
  }

  /// Whether this phi can be collapsed to a single incoming value.
  bool get isTrivial => trivialIncomingValue != null;

  @override
  String toString() =>
      'Phi(target=r$targetRegister, incoming=${_formatPhiIncoming(incomingByPredecessor)})';
}

String formatLualikeIrSsaFunction(LualikeIrSsaFunction function) {
  final buffer = StringBuffer();
  buffer.writeln('ssa {');
  for (final block in function.blocks) {
    _writeSsaBlock(buffer, block, indent: 1);
  }
  buffer.writeln('}');
  return buffer.toString();
}

void _writeSsaBlock(
  StringBuffer buffer,
  LualikeIrSsaBlock block, {
  required int indent,
}) {
  final prefix = '  ' * indent;
  buffer.writeln(
    '$prefix block ${block.block.index} '
    'pcs=${block.block.instructionPcs} '
    'pred=${block.block.predecessors} '
    'succ=${block.block.successors}',
  );

  if (block.entryValues.isNotEmpty) {
    buffer.writeln('$prefix   entry ${_formatSsaValueMap(block.entryValues)}');
  }
  if (block.phis.isNotEmpty) {
    for (final phi in block.phis) {
      buffer.writeln('$prefix   phi ${phi.value.label}');
      buffer.writeln(
        '$prefix     target=r${phi.targetRegister} '
        'incoming=${_formatPhiIncoming(phi.incomingByPredecessor)}',
      );
    }
  }
  if (block.definedValues.isNotEmpty) {
    buffer.writeln(
      '$prefix   defs ${block.definedValues.map((value) => value.label).toList()}',
    );
  }
  if (block.exitValues.isNotEmpty) {
    buffer.writeln('$prefix   exit ${_formatSsaValueMap(block.exitValues)}');
  }
}

String _formatSsaValueMap(Map<int, LualikeIrSsaValue> values) {
  final entries = values.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return '{${entries.map((entry) => 'r${entry.key}=${entry.value.label}(${entry.value.useCount})').join(', ')}}';
}

String _formatPhiIncoming(Map<int, LualikeIrSsaValue> incoming) {
  final entries = incoming.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return '[${entries.map((entry) => 'b${entry.key}:${entry.value.label}(${entry.value.useCount})').join(', ')}]';
}

/// A CFG block with an SSA overlay.
final class LualikeIrSsaBlock {
  const LualikeIrSsaBlock({
    required this.block,
    this.phis = const <LualikeIrPhi>[],
    this.entryValues = const <int, LualikeIrSsaValue>{},
    this.exitValues = const <int, LualikeIrSsaValue>{},
    this.definedValues = const <LualikeIrSsaValue>[],
  });

  final LualikeIrBasicBlock block;
  final List<LualikeIrPhi> phis;
  final Map<int, LualikeIrSsaValue> entryValues;
  final Map<int, LualikeIrSsaValue> exitValues;
  final List<LualikeIrSsaValue> definedValues;

  bool get hasPhis => phis.isNotEmpty;

  Iterable<LualikeIrSsaValue> get unusedDefinitions =>
      definedValues.where((value) => value.isUnused);

  bool get hasUnusedDefinitions => unusedDefinitions.isNotEmpty;

  @override
  String toString() => 'SsaBlock(block=${block.index}, phis=${phis.length})';
}

final class _PhiBuilder {
  _PhiBuilder({required this.targetRegister})
    : incomingByPredecessor = <int, LualikeIrSsaValue>{};

  final int targetRegister;
  final Map<int, LualikeIrSsaValue> incomingByPredecessor;
  LualikeIrSsaValue? value;

  LualikeIrPhi build() {
    return LualikeIrPhi(
      targetRegister: targetRegister,
      value: value!,
      incomingByPredecessor: Map<int, LualikeIrSsaValue>.unmodifiable(
        incomingByPredecessor,
      ),
    );
  }
}

final class _BlockRenameData {
  const _BlockRenameData({
    required this.entryValues,
    required this.exitValues,
    required this.definedValues,
  });

  final Map<int, LualikeIrSsaValue> entryValues;
  final Map<int, LualikeIrSsaValue> exitValues;
  final List<LualikeIrSsaValue> definedValues;
}

final class _RenameState {
  const _RenameState({
    required this.valuesByRegister,
    required this.nextVersionByRegister,
  });

  final Map<int, LualikeIrSsaValue> valuesByRegister;
  final List<int> nextVersionByRegister;

  _RenameState fork() {
    return _RenameState(
      valuesByRegister: Map<int, LualikeIrSsaValue>.from(valuesByRegister),
      nextVersionByRegister: nextVersionByRegister,
    );
  }
}

Map<int, List<_PhiBuilder>> _placePhiNodes(
  LualikeIrControlFlowGraph cfg,
  int registerCount,
) {
  if (registerCount == 0) {
    return const <int, List<_PhiBuilder>>{};
  }

  final defsByRegister = List<Set<int>>.generate(
    registerCount,
    (_) => <int>{},
    growable: false,
  );
  for (final block in cfg.blocks) {
    for (final register in _definedRegistersInBlock(block, cfg.prototype)) {
      if (register >= 0 && register < registerCount) {
        defsByRegister[register].add(block.index);
      }
    }
  }

  final buildersByBlock = <int, List<_PhiBuilder>>{};
  for (var register = 0; register < registerCount; register++) {
    final worklist = Queue<int>()..addAll(defsByRegister[register]);
    final placed = <int>{};

    while (worklist.isNotEmpty) {
      final blockIndex = worklist.removeFirst();
      for (final frontierIndex in cfg.dominanceFrontierOf(blockIndex)) {
        if (!placed.add(frontierIndex)) {
          continue;
        }

        final predecessorBlocks = cfg.blocks[frontierIndex].predecessors;
        if (predecessorBlocks.isEmpty) {
          continue;
        }

        buildersByBlock
            .putIfAbsent(frontierIndex, () => <_PhiBuilder>[])
            .add(_PhiBuilder(targetRegister: register));
        if (!defsByRegister[register].contains(frontierIndex)) {
          worklist.add(frontierIndex);
        }
      }
    }
  }

  for (final entry in buildersByBlock.entries) {
    entry.value.sort(
      (left, right) => left.targetRegister.compareTo(right.targetRegister),
    );
  }

  return Map<int, List<_PhiBuilder>>.unmodifiable(
    buildersByBlock.map(
      (key, value) => MapEntry(key, List<_PhiBuilder>.unmodifiable(value)),
    ),
  );
}

Map<int, List<LualikeIrPhi>> _materializePhis(
  Map<int, List<_PhiBuilder>> phiBuildersByBlock,
) {
  final result = <int, List<LualikeIrPhi>>{};
  for (final entry in phiBuildersByBlock.entries) {
    // Skip phi builders whose value was never assigned during renaming.
    // This can happen for unreachable blocks that appear in dominance
    // frontiers but are never visited by the rename traversal.
    final phis = <LualikeIrPhi>[];
    for (final builder in entry.value) {
      if (builder.value == null) continue;
      phis.add(builder.build());
    }
    if (phis.isNotEmpty) {
      result[entry.key] = List<LualikeIrPhi>.unmodifiable(phis);
    }
  }
  return Map<int, List<LualikeIrPhi>>.unmodifiable(result);
}

Map<int, _BlockRenameData> _renameValues(
  LualikeIrControlFlowGraph cfg,
  Map<int, List<_PhiBuilder>> phiBuildersByBlock,
  int registerCount,
) {
  final childrenByBlock = _childrenByDominator(cfg);
  final nextVersionByRegister = List<int>.filled(registerCount, 1);
  final initialValues = <int, LualikeIrSsaValue>{
    for (var register = 0; register < registerCount; register++)
      register: LualikeIrSsaValue(
        register: register,
        version: 0,
        definingBlock: -1,
        definingPc: null,
      ),
  };

  final results = <int, _BlockRenameData>{};

  void renameBlock(int blockIndex, _RenameState state) {
    final block = cfg.blocks[blockIndex];
    final localState = state.fork();
    final phiBuilders = phiBuildersByBlock[blockIndex] ?? const <_PhiBuilder>[];

    for (final builder in phiBuilders) {
      final value = _newValue(
        register: builder.targetRegister,
        blockIndex: blockIndex,
        pc: block.startPc,
        nextVersionByRegister: localState.nextVersionByRegister,
        isPhi: true,
      );
      builder.value = value;
      localState.valuesByRegister[builder.targetRegister] = value;
    }

    final entryValues = Map<int, LualikeIrSsaValue>.unmodifiable(
      localState.valuesByRegister,
    );

    final definedValues = <LualikeIrSsaValue>[];
    for (final pc in block.instructionPcs) {
      final instruction = cfg.prototype.instructions[pc];
      for (final register in _usedRegistersForInstruction(
        instruction,
        registerCount,
      )) {
        final value = localState.valuesByRegister[register];
        if (value != null) {
          value.addUse(
            LualikeIrSsaUse(
              blockIndex: blockIndex,
              pc: pc,
              kind: 'instruction',
              operandRegister: register,
            ),
          );
        }
      }

      for (final register in _definedRegistersForInstruction(
        instruction,
        registerCount,
      )) {
        if (register < 0 || register >= registerCount) {
          continue;
        }
        final value = _newValue(
          register: register,
          blockIndex: blockIndex,
          pc: pc,
          nextVersionByRegister: localState.nextVersionByRegister,
        );
        localState.valuesByRegister[register] = value;
        definedValues.add(value);
      }
    }

    final exitValues = Map<int, LualikeIrSsaValue>.unmodifiable(
      localState.valuesByRegister,
    );
    results[blockIndex] = _BlockRenameData(
      entryValues: entryValues,
      exitValues: exitValues,
      definedValues: List<LualikeIrSsaValue>.unmodifiable(definedValues),
    );

    for (final successor in block.successors) {
      final successorPhiBuilders = phiBuildersByBlock[successor];
      if (successorPhiBuilders == null) {
        continue;
      }
      for (final builder in successorPhiBuilders) {
        final incomingValue =
            localState.valuesByRegister[builder.targetRegister];
        if (incomingValue != null) {
          incomingValue.addUse(
            LualikeIrSsaUse(
              blockIndex: successor,
              pc: cfg.blocks[successor].startPc,
              kind: 'phi',
              operandRegister: builder.targetRegister,
            ),
          );
          builder.incomingByPredecessor[blockIndex] = incomingValue;
        }
      }
    }

    for (final child in childrenByBlock[blockIndex] ?? const <int>[]) {
      renameBlock(child, localState);
    }
  }

  if (cfg.blocks.isNotEmpty) {
    renameBlock(
      cfg.entryBlock.index,
      _RenameState(
        valuesByRegister: initialValues,
        nextVersionByRegister: nextVersionByRegister,
      ),
    );
  }

  return results;
}

Map<int, List<int>> _childrenByDominator(LualikeIrControlFlowGraph cfg) {
  final children = <int, List<int>>{
    for (final block in cfg.blocks) block.index: <int>[],
  };
  for (final entry in cfg.immediateDominatorByBlock.entries) {
    final blockIndex = entry.key;
    final idom = entry.value;
    if (idom != null) {
      children[idom]!.add(blockIndex);
    }
  }
  for (final entry in children.entries) {
    entry.value.sort();
  }
  return Map<int, List<int>>.unmodifiable(
    children.map((key, value) => MapEntry(key, List<int>.unmodifiable(value))),
  );
}

LualikeIrSsaValue? _resolvedTrivialIncomingValue(
  LualikeIrPhi phi,
  Map<LualikeIrSsaValue, LualikeIrSsaValue> replacements,
) {
  if (phi.incomingByPredecessor.isEmpty) {
    return null;
  }

  LualikeIrSsaValue? first;
  for (final incoming in phi.incomingByPredecessor.values) {
    final resolved = _resolveReplacementValue(incoming, replacements);
    if (first == null) {
      first = resolved;
      continue;
    }
    if (!identical(first, resolved)) {
      return null;
    }
  }
  return first;
}

// Follow replacement chains so downstream blocks see the final value, not an
// intermediate phi that has already been eliminated.
LualikeIrSsaValue _resolveReplacementValue(
  LualikeIrSsaValue value,
  Map<LualikeIrSsaValue, LualikeIrSsaValue> replacements,
) {
  var current = value;
  final seen = <LualikeIrSsaValue>{};
  while (true) {
    final replacement = replacements[current];
    if (replacement == null || identical(replacement, current)) {
      return current;
    }
    if (!seen.add(current)) {
      return current;
    }
    current = replacement;
  }
}

LualikeIrSsaBlock _rewriteSsaBlock(
  LualikeIrSsaBlock block, {
  required Map<LualikeIrSsaValue, LualikeIrSsaValue> replacements,
  required List<LualikeIrPhi> phis,
}) {
  Map<int, LualikeIrSsaValue> rewriteValues(
    Map<int, LualikeIrSsaValue> values,
  ) {
    return Map<int, LualikeIrSsaValue>.unmodifiable({
      for (final entry in values.entries)
        entry.key: _resolveReplacementValue(entry.value, replacements),
    });
  }

  final definedValues = <LualikeIrSsaValue>[
    for (final value in block.definedValues)
      if (identical(_resolveReplacementValue(value, replacements), value))
        value,
  ];
  final rewrittenPhis = List<LualikeIrPhi>.unmodifiable(
    phis.map(
      (phi) => LualikeIrPhi(
        targetRegister: phi.targetRegister,
        value: phi.value,
        incomingByPredecessor: Map<int, LualikeIrSsaValue>.unmodifiable({
          for (final entry in phi.incomingByPredecessor.entries)
            entry.key: _resolveReplacementValue(entry.value, replacements),
        }),
      ),
    ),
  );

  return LualikeIrSsaBlock(
    block: block.block,
    phis: rewrittenPhis,
    entryValues: rewriteValues(block.entryValues),
    exitValues: rewriteValues(block.exitValues),
    definedValues: definedValues,
  );
}

// Uses are derived from the final SSA graph, so we rebuild them wholesale
// after any structural rewrite instead of trying to patch counts in place.
void _rebuildSsaUses(LualikeIrSsaFunction function) {
  final registerCount = function.cfg.prototype.registerCount;
  final uniqueValues = <LualikeIrSsaValue>{};
  for (final block in function.blocks) {
    uniqueValues.addAll(block.entryValues.values);
    uniqueValues.addAll(block.exitValues.values);
    uniqueValues.addAll(block.definedValues);
    for (final phi in block.phis) {
      uniqueValues.add(phi.value);
      uniqueValues.addAll(phi.incomingByPredecessor.values);
    }
  }

  for (final value in uniqueValues) {
    value.uses.clear();
  }

  for (final block in function.blocks) {
    final valuesByRegister = Map<int, LualikeIrSsaValue>.from(
      block.entryValues,
    );
    var definedValueIndex = 0;

    for (final pc in block.block.instructionPcs) {
      final instruction = function.cfg.prototype.instructions[pc];
      for (final register in _usedRegistersForInstruction(
        instruction,
        registerCount,
      )) {
        final value = valuesByRegister[register];
        if (value != null) {
          value.addUse(
            LualikeIrSsaUse(
              blockIndex: block.block.index,
              pc: pc,
              kind: 'instruction',
              operandRegister: register,
            ),
          );
        }
      }

      for (final register in _definedRegistersForInstruction(
        instruction,
        registerCount,
      )) {
        if (definedValueIndex >= block.definedValues.length) {
          break;
        }
        valuesByRegister[register] = block.definedValues[definedValueIndex++];
      }
    }

    for (final successorIndex in block.block.successors) {
      final successorBlock = function.blocks[successorIndex];
      for (final phi in successorBlock.phis) {
        final incoming = phi.incomingByPredecessor[block.block.index];
        if (incoming != null) {
          incoming.addUse(
            LualikeIrSsaUse(
              blockIndex: successorBlock.block.index,
              pc: successorBlock.block.startPc,
              kind: 'phi',
              operandRegister: phi.targetRegister,
            ),
          );
        }
      }
    }
  }
}

LualikeIrSsaValue _newValue({
  required int register,
  required int blockIndex,
  required int? pc,
  required List<int> nextVersionByRegister,
  bool isPhi = false,
}) {
  final version = nextVersionByRegister[register];
  nextVersionByRegister[register] = version + 1;
  return LualikeIrSsaValue(
    register: register,
    version: version,
    definingBlock: blockIndex,
    definingPc: pc,
    isPhi: isPhi,
  );
}

Set<int> _definedRegistersInBlock(
  LualikeIrBasicBlock block,
  LualikeIrPrototype prototype,
) {
  final registers = <int>{};
  for (final pc in block.instructionPcs) {
    registers.addAll(
      _definedRegistersForInstruction(
        prototype.instructions[pc],
        prototype.registerCount,
      ),
    );
  }
  return registers;
}

Set<int> _usedRegistersForInstruction(
  LualikeIrInstruction instruction,
  int registerCount,
) {
  Set<int> single(int register) => <int>{
    if (register >= 0 && register < registerCount) register,
  };

  Set<int> range(int start, int count) {
    final registers = <int>{};
    for (var offset = 0; offset < count; offset++) {
      final register = start + offset;
      if (register >= 0 && register < registerCount) {
        registers.add(register);
      }
    }
    return registers;
  }

  return switch (instruction) {
    ABCInstruction(opcode: LualikeIrOpcode.move, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.getUpval) => const <int>{},
    ABCInstruction(opcode: LualikeIrOpcode.getTabUp) => const <int>{},
    ABCInstruction(opcode: LualikeIrOpcode.getTable, b: final b, c: final c) =>
      {...single(b), ...single(c)},
    ABCInstruction(opcode: LualikeIrOpcode.getI, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.getField, b: final b) => single(b),
    // Stores *read* the table (and often key/value regs). Missing A here
    // makes DCE drop GETTABUP/MOVE that only feed SETFIELD table slots —
    // e.g. `package.path = "x"` lost the load of `package` (nil index).
    ABCInstruction(opcode: LualikeIrOpcode.setUpval, c: final c) => single(c),
    ABCInstruction(opcode: LualikeIrOpcode.setTabUp, c: final c) => single(c),
    ABCInstruction(
      opcode: LualikeIrOpcode.setTable,
      a: final a,
      b: final b,
      c: final c,
    ) =>
      {...single(a), ...single(b), ...single(c)},
    ABCInstruction(opcode: LualikeIrOpcode.setI, a: final a, c: final c) => {
      ...single(a),
      ...single(c),
    },
    ABCInstruction(opcode: LualikeIrOpcode.setField, a: final a, c: final c) =>
      {...single(a), ...single(c)},
    // SETLIST reads R(A) (table) and R(A+1)..R(A+B) (or open to top when B==0).
    // Missing this lets DCE drop LOADI/MOVE into the SETLIST window — array
    // constructors become empty tables (`{10,9}` → nils).
    ABCInstruction(opcode: LualikeIrOpcode.setList, a: final a, b: final b) =>
      b == 0
          ? {...single(a), ...range(a + 1, registerCount - (a + 1))}
          : {...single(a), ...range(a + 1, b)},
    ABCInstruction(opcode: LualikeIrOpcode.selfOp, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.addI, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.subI, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.addK, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.subK, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.mulK, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.modK, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.powK, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.divK, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.idivK, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.bandK, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.borK, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.bxorK, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.add, b: final b, c: final c) => {
      ...single(b),
      ...single(c),
    },
    ABCInstruction(opcode: LualikeIrOpcode.sub, b: final b, c: final c) => {
      ...single(b),
      ...single(c),
    },
    ABCInstruction(opcode: LualikeIrOpcode.mul, b: final b, c: final c) => {
      ...single(b),
      ...single(c),
    },
    ABCInstruction(opcode: LualikeIrOpcode.mod, b: final b, c: final c) => {
      ...single(b),
      ...single(c),
    },
    ABCInstruction(opcode: LualikeIrOpcode.pow, b: final b, c: final c) => {
      ...single(b),
      ...single(c),
    },
    ABCInstruction(opcode: LualikeIrOpcode.div, b: final b, c: final c) => {
      ...single(b),
      ...single(c),
    },
    ABCInstruction(opcode: LualikeIrOpcode.idiv, b: final b, c: final c) => {
      ...single(b),
      ...single(c),
    },
    ABCInstruction(opcode: LualikeIrOpcode.band, b: final b, c: final c) => {
      ...single(b),
      ...single(c),
    },
    ABCInstruction(opcode: LualikeIrOpcode.bor, b: final b, c: final c) => {
      ...single(b),
      ...single(c),
    },
    ABCInstruction(opcode: LualikeIrOpcode.bxor, b: final b, c: final c) => {
      ...single(b),
      ...single(c),
    },
    ABCInstruction(opcode: LualikeIrOpcode.shlI, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.shrI, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.shl, b: final b, c: final c) => {
      ...single(b),
      ...single(c),
    },
    ABCInstruction(opcode: LualikeIrOpcode.shr, b: final b, c: final c) => {
      ...single(b),
      ...single(c),
    },
    ABCInstruction(opcode: LualikeIrOpcode.unm, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.bnot, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.notOp, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.len, b: final b) => single(b),
    ABCInstruction(opcode: LualikeIrOpcode.concat, b: final b, c: final c) =>
      range(b, c - b + 1),
    ABCInstruction(opcode: LualikeIrOpcode.call, a: final a, b: final b) =>
      b == 0 ? range(a, registerCount - a) : range(a, b),
    ABCInstruction(opcode: LualikeIrOpcode.tailCall, a: final a, b: final b) =>
      b == 0 ? range(a, registerCount - a) : range(a, b),
    ABCInstruction(opcode: LualikeIrOpcode.ret, a: final a, b: final b) =>
      b == 0 ? range(a, registerCount - a) : range(a, b - 1),
    ABCInstruction(opcode: LualikeIrOpcode.return1, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.test, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.testSet, b: final b) => single(b),
    // IR compares: A=result (def), B/C = operand registers / imm.
    ABCInstruction(
      opcode: LualikeIrOpcode.eq || LualikeIrOpcode.lt || LualikeIrOpcode.le,
      b: final b,
      c: final c,
    ) =>
      {...single(b), ...single(c)},
    ABCInstruction(
      opcode: LualikeIrOpcode.eqI ||
          LualikeIrOpcode.ltI ||
          LualikeIrOpcode.leI ||
          LualikeIrOpcode.gtI ||
          LualikeIrOpcode.geI ||
          LualikeIrOpcode.eqK,
      b: final b,
    ) =>
      single(b),
    ABCInstruction(opcode: LualikeIrOpcode.varArg, b: final b, a: final a) =>
      b == 0 ? const <int>{} : range(a, b - 1),
    ABCInstruction(opcode: LualikeIrOpcode.getVarArg) => const <int>{},
    ABCInstruction(opcode: LualikeIrOpcode.tForCall, a: final a, c: final c) =>
      {
        ...single(a),
        ...single(a + 1),
        ...single(a + 3),
        if (c > 0) ...range(a + 4, c),
      },
    AsBxInstruction(opcode: LualikeIrOpcode.forPrep, a: final a) => range(a, 3),
    AsBxInstruction(opcode: LualikeIrOpcode.forLoop, a: final a) => range(a, 3),
    AsBxInstruction(opcode: LualikeIrOpcode.tForPrep, a: final a) => {
      ...single(a + 2),
      ...single(a + 3),
    },
    AsBxInstruction(opcode: LualikeIrOpcode.tForLoop, a: final a) => single(
      a + 3,
    ),
    _ => const <int>{},
  };
}

Set<int> _definedRegistersForInstruction(
  LualikeIrInstruction instruction,
  int registerCount,
) {
  Set<int> single(int register) => <int>{
    if (register >= 0 && register < registerCount) register,
  };

  Set<int> range(int start, int count) {
    final registers = <int>{};
    for (var offset = 0; offset < count; offset++) {
      final register = start + offset;
      if (register >= 0 && register < registerCount) {
        registers.add(register);
      }
    }
    return registers;
  }

  return switch (instruction) {
    ABCInstruction(opcode: LualikeIrOpcode.move, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.loadI, a: final a) => single(a),
    AsBxInstruction(opcode: LualikeIrOpcode.loadI, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.loadF, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.loadFalse, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.lFalseSkip, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.loadTrue, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.loadNil, a: final a, b: final b) =>
      range(a, b + 1),
    ABxInstruction(opcode: LualikeIrOpcode.loadK, a: final a, bx: _) ||
    ABxInstruction(
      opcode: LualikeIrOpcode.loadKx,
      a: final a,
      bx: _,
    ) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.getUpval, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.getTabUp, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.getTable, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.getI, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.getField, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.newTable, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.selfOp, a: final a) => range(a, 2),
    ABCInstruction(
      opcode: LualikeIrOpcode.addI ||
          LualikeIrOpcode.subI ||
          LualikeIrOpcode.addK ||
          LualikeIrOpcode.subK ||
          LualikeIrOpcode.mulK ||
          LualikeIrOpcode.modK ||
          LualikeIrOpcode.powK ||
          LualikeIrOpcode.divK ||
          LualikeIrOpcode.idivK ||
          LualikeIrOpcode.bandK ||
          LualikeIrOpcode.borK ||
          LualikeIrOpcode.bxorK ||
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
          LualikeIrOpcode.shlI ||
          LualikeIrOpcode.shrI ||
          LualikeIrOpcode.shl ||
          LualikeIrOpcode.shr ||
          LualikeIrOpcode.unm ||
          LualikeIrOpcode.bnot ||
          LualikeIrOpcode.notOp ||
          LualikeIrOpcode.len ||
          LualikeIrOpcode.concat,
      a: final a,
    ) =>
      single(a),
    ABCInstruction(opcode: LualikeIrOpcode.closure, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.getVarArg, a: final a) => single(a),
    ABCInstruction(opcode: LualikeIrOpcode.varArg, a: final a, b: final b) =>
      (b == 0 ? range(a, registerCount - a) : range(a, b - 1)),
    ABCInstruction(opcode: LualikeIrOpcode.call, a: final a, c: final c) =>
      (c == 0 ? range(a, registerCount - a) : range(a, c - 1)),
    ABCInstruction(opcode: LualikeIrOpcode.testSet, a: final a) => single(a),
    // Compare ops write the result register A (materialized bool / IR result).
    ABCInstruction(
      opcode: LualikeIrOpcode.eq ||
          LualikeIrOpcode.lt ||
          LualikeIrOpcode.le ||
          LualikeIrOpcode.eqI ||
          LualikeIrOpcode.ltI ||
          LualikeIrOpcode.leI ||
          LualikeIrOpcode.gtI ||
          LualikeIrOpcode.geI ||
          LualikeIrOpcode.eqK,
      a: final a,
    ) =>
      single(a),
    ABCInstruction(opcode: LualikeIrOpcode.forLoop, a: final a) => range(a, 4),
    AsBxInstruction(opcode: LualikeIrOpcode.forPrep, a: final a) => range(a, 4),
    ABCInstruction(opcode: LualikeIrOpcode.tForCall, a: final a, c: final c) =>
      range(a + 3, c + 1),
    AsBxInstruction(opcode: LualikeIrOpcode.tForPrep, a: final a) => range(
      a + 2,
      2,
    ),
    AsBxInstruction(opcode: LualikeIrOpcode.tForLoop, a: final _) =>
      const <int>{},
    _ => <int>{},
  };
}
