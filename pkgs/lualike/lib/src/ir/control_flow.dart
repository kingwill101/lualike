import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';

/// A basic block in the existing lualike IR.
///
/// The current compiler already lowers AST into IR before bytecode emission.
/// This graph is a migration scaffold: it lets later SSA work reason about the
/// existing IR without replacing the current AST -> IR -> bytecode pipeline.
final class LualikeIrBasicBlock {
  const LualikeIrBasicBlock({
    required this.index,
    required this.startPc,
    required this.endPc,
    required this.instructionPcs,
    required this.successors,
    required this.predecessors,
  });

  final int index;
  final int startPc;
  final int endPc;
  final List<int> instructionPcs;
  final List<int> successors;
  final List<int> predecessors;

  int get length => endPc - startPc;

  bool get isEntry => index == 0;

  bool get isEmpty => instructionPcs.isEmpty;

  @override
  String toString() {
    return 'BasicBlock(index: $index, startPc: $startPc, endPc: $endPc, '
        'successors: $successors, predecessors: $predecessors)';
  }
}

/// A control-flow graph derived from a lualike IR prototype.
final class LualikeIrControlFlowGraph {
  LualikeIrControlFlowGraph._({
    required this.prototype,
    required this.blocks,
    required this.blockIndexByPc,
    required this.immediateDominatorByBlock,
    required this.dominanceFrontierByBlock,
  });

  final LualikeIrPrototype prototype;
  final List<LualikeIrBasicBlock> blocks;
  final Map<int, int> blockIndexByPc;
  final Map<int, int?> immediateDominatorByBlock;
  final Map<int, List<int>> dominanceFrontierByBlock;

  factory LualikeIrControlFlowGraph.fromPrototype(
    LualikeIrPrototype prototype,
  ) {
    final instructions = prototype.instructions;
    if (instructions.isEmpty) {
      const emptyBlock = LualikeIrBasicBlock(
        index: 0,
        startPc: 0,
        endPc: 0,
        instructionPcs: <int>[],
        successors: <int>[],
        predecessors: <int>[],
      );
      return LualikeIrControlFlowGraph._(
        prototype: prototype,
        blocks: const <LualikeIrBasicBlock>[emptyBlock],
        blockIndexByPc: const <int, int>{},
        immediateDominatorByBlock: const <int, int?>{},
        dominanceFrontierByBlock: const <int, List<int>>{},
      );
    }

    final leaders = <int>{0};
    for (var pc = 0; pc < instructions.length; pc++) {
      final inst = instructions[pc];
      final nextPc = pc + 1;

      if (_isTestPairStarter(inst) &&
          nextPc < instructions.length &&
          instructions[nextPc].opcode == LualikeIrOpcode.jmp) {
        leaders.add(nextPc + 1);
        final target = _jumpTarget(instructions[nextPc], nextPc);
        if (target >= 0 && target < instructions.length) {
          leaders.add(target);
        }
        continue;
      }

      if (_isUnconditionalBranch(inst)) {
        final target = _jumpTarget(inst, pc);
        if (target >= 0 && target < instructions.length) {
          leaders.add(target);
        }
        if (nextPc < instructions.length) {
          leaders.add(nextPc);
        }
        continue;
      }

      if (_isConditionalLoopBranch(inst)) {
        final target = _jumpTarget(inst, pc);
        if (target >= 0 && target < instructions.length) {
          leaders.add(target);
        }
        if (nextPc < instructions.length) {
          leaders.add(nextPc);
        }
        continue;
      }

      if (_isTerminator(inst.opcode) && nextPc < instructions.length) {
        leaders.add(nextPc);
      }
    }

    final leaderList = leaders.toList()..sort();
    final blockSpecs = <_BlockSpec>[];
    for (var i = 0; i < leaderList.length; i++) {
      final startPc = leaderList[i];
      final endPc = i + 1 < leaderList.length
          ? leaderList[i + 1]
          : instructions.length;
      if (startPc >= endPc) {
        continue;
      }
      blockSpecs.add(_BlockSpec(startPc: startPc, endPc: endPc));
    }

    if (blockSpecs.isEmpty) {
      const emptyBlock = LualikeIrBasicBlock(
        index: 0,
        startPc: 0,
        endPc: 0,
        instructionPcs: <int>[],
        successors: <int>[],
        predecessors: <int>[],
      );
      return LualikeIrControlFlowGraph._(
        prototype: prototype,
        blocks: const <LualikeIrBasicBlock>[emptyBlock],
        blockIndexByPc: const <int, int>{},
        immediateDominatorByBlock: const <int, int?>{},
        dominanceFrontierByBlock: const <int, List<int>>{},
      );
    }

    final blockIndexByPc = <int, int>{};
    final blocks = <LualikeIrBasicBlock>[];
    for (var index = 0; index < blockSpecs.length; index++) {
      final spec = blockSpecs[index];
      final instructionPcs = List<int>.generate(
        spec.endPc - spec.startPc,
        (offset) => spec.startPc + offset,
        growable: false,
      );
      final block = LualikeIrBasicBlock(
        index: index,
        startPc: spec.startPc,
        endPc: spec.endPc,
        instructionPcs: List<int>.unmodifiable(instructionPcs),
        successors: const <int>[],
        predecessors: const <int>[],
      );
      blocks.add(block);
      for (final pc in instructionPcs) {
        blockIndexByPc[pc] = index;
      }
    }

    final successorLists = List<List<int>>.generate(
      blocks.length,
      (_) => <int>[],
      growable: false,
    );
    final predecessorLists = List<List<int>>.generate(
      blocks.length,
      (_) => <int>[],
      growable: false,
    );

    for (final block in blocks) {
      final successors = _successorsForBlock(
        block,
        instructions,
        blockIndexByPc,
      );
      successorLists[block.index].addAll(successors);
      for (final successor in successors) {
        predecessorLists[successor].add(block.index);
      }
    }

    final finalizedBlocks = <LualikeIrBasicBlock>[];
    for (final block in blocks) {
      finalizedBlocks.add(
        LualikeIrBasicBlock(
          index: block.index,
          startPc: block.startPc,
          endPc: block.endPc,
          instructionPcs: block.instructionPcs,
          successors: List<int>.unmodifiable(successorLists[block.index]),
          predecessors: List<int>.unmodifiable(predecessorLists[block.index]),
        ),
      );
    }

    final dominance = _computeDominanceAnalysis(finalizedBlocks);

    return LualikeIrControlFlowGraph._(
      prototype: prototype,
      blocks: List<LualikeIrBasicBlock>.unmodifiable(finalizedBlocks),
      blockIndexByPc: Map<int, int>.unmodifiable(blockIndexByPc),
      immediateDominatorByBlock: dominance.immediateDominators,
      dominanceFrontierByBlock: dominance.dominanceFrontiers,
    );
  }

  LualikeIrBasicBlock blockForPc(int pc) {
    final blockIndex = blockIndexByPc[pc];
    if (blockIndex == null) {
      throw RangeError.index(pc, prototype.instructions, 'pc');
    }
    return blocks[blockIndex];
  }

  LualikeIrBasicBlock get entryBlock => blocks.first;

  List<LualikeIrBasicBlock> get exitBlocks =>
      blocks.where((block) => block.successors.isEmpty).toList(growable: false);

  int? immediateDominatorOf(int blockIndex) =>
      immediateDominatorByBlock[blockIndex];

  List<int> dominanceFrontierOf(int blockIndex) =>
      dominanceFrontierByBlock[blockIndex] ?? const <int>[];

  bool dominates(int dominatorIndex, int dominatedIndex) {
    if (dominatorIndex == dominatedIndex) {
      return true;
    }

    var current = immediateDominatorByBlock[dominatedIndex];
    while (current != null) {
      if (current == dominatorIndex) {
        return true;
      }
      current = immediateDominatorByBlock[current];
    }

    return false;
  }

  static List<int> _successorsForBlock(
    LualikeIrBasicBlock block,
    List<LualikeIrInstruction> instructions,
    Map<int, int> blockIndexByPc,
  ) {
    if (block.isEmpty) {
      return const <int>[];
    }

    final lastPc = block.endPc - 1;
    final lastInst = instructions[lastPc];

    if (lastInst is AsJInstruction &&
        lastInst.opcode == LualikeIrOpcode.jmp &&
        block.length >= 2) {
      final previousInst = instructions[lastPc - 1];
      if (previousInst.opcode == LualikeIrOpcode.test ||
          previousInst.opcode == LualikeIrOpcode.testSet) {
        final target = _jumpTarget(lastInst, lastPc);
        final successors = <int>[];
        final targetBlock = blockIndexByPc[target];
        if (targetBlock != null) {
          successors.add(targetBlock);
        }
        final fallthroughPc = lastPc + 1;
        final fallthroughBlock = blockIndexByPc[fallthroughPc];
        if (fallthroughBlock != null) {
          successors.add(fallthroughBlock);
        }
        return successors;
      }
    }

    if (lastInst is AsJInstruction && lastInst.opcode == LualikeIrOpcode.jmp) {
      return _blockSuccessorsFromTarget(
        _jumpTarget(lastInst, lastPc),
        instructions.length,
        blockIndexByPc,
      );
    }

    if (lastInst is AsBxInstruction &&
        (lastInst.opcode == LualikeIrOpcode.forLoop ||
            lastInst.opcode == LualikeIrOpcode.tForLoop)) {
      final target = _jumpTarget(lastInst, lastPc);
      final successors = <int>[];
      final targetBlock = blockIndexByPc[target];
      if (targetBlock != null) {
        successors.add(targetBlock);
      }
      final fallthroughPc = block.endPc;
      final fallthroughBlock = blockIndexByPc[fallthroughPc];
      if (fallthroughBlock != null) {
        successors.add(fallthroughBlock);
      }
      return successors;
    }

    if (lastInst is AsBxInstruction &&
        (lastInst.opcode == LualikeIrOpcode.forPrep ||
            lastInst.opcode == LualikeIrOpcode.tForPrep)) {
      return _blockSuccessorsFromTarget(
        _jumpTarget(lastInst, lastPc),
        instructions.length,
        blockIndexByPc,
      );
    }

    if (lastInst.opcode == LualikeIrOpcode.test ||
        lastInst.opcode == LualikeIrOpcode.testSet) {
      final nextPc = lastPc + 1;
      if (nextPc < instructions.length &&
          instructions[nextPc] is AsJInstruction &&
          instructions[nextPc].opcode == LualikeIrOpcode.jmp) {
        final jmp = instructions[nextPc] as AsJInstruction;
        final target = _jumpTarget(jmp, nextPc);
        final successors = <int>[];
        final targetBlock = blockIndexByPc[target];
        if (targetBlock != null) {
          successors.add(targetBlock);
        }
        final fallthroughPc = nextPc + 1;
        final fallthroughBlock = blockIndexByPc[fallthroughPc];
        if (fallthroughBlock != null) {
          successors.add(fallthroughBlock);
        }
        return successors;
      }
    }

    if (_isTerminator(lastInst.opcode)) {
      return const <int>[];
    }

    final nextBlock = blockIndexByPc[block.endPc];
    if (nextBlock != null) {
      return <int>[nextBlock];
    }

    return const <int>[];
  }

  static List<int> _blockSuccessorsFromTarget(
    int targetPc,
    int instructionCount,
    Map<int, int> blockIndexByPc,
  ) {
    final successors = <int>[];
    final targetBlock = blockIndexByPc[targetPc];
    if (targetBlock != null) {
      successors.add(targetBlock);
    }

    if (targetPc < 0 || targetPc >= instructionCount) {
      return successors;
    }

    return successors;
  }

  static bool _isTestPairStarter(LualikeIrInstruction instruction) {
    return instruction.opcode == LualikeIrOpcode.test ||
        instruction.opcode == LualikeIrOpcode.testSet;
  }

  static bool _isUnconditionalBranch(LualikeIrInstruction instruction) {
    return instruction is AsJInstruction &&
        instruction.opcode == LualikeIrOpcode.jmp;
  }

  static bool _isConditionalLoopBranch(LualikeIrInstruction instruction) {
    return instruction is AsBxInstruction &&
        (instruction.opcode == LualikeIrOpcode.forLoop ||
            instruction.opcode == LualikeIrOpcode.tForLoop);
  }

  static bool _isTerminator(LualikeIrOpcode opcode) {
    return opcode == LualikeIrOpcode.ret ||
        opcode == LualikeIrOpcode.return0 ||
        opcode == LualikeIrOpcode.return1 ||
        opcode == LualikeIrOpcode.tailCall;
  }

  static int _jumpTarget(LualikeIrInstruction instruction, int pc) {
    if (instruction is AsJInstruction) {
      return pc + 1 + instruction.sJ;
    }
    if (instruction is AsBxInstruction) {
      return pc + 1 + instruction.sBx;
    }
    throw ArgumentError.value(
      instruction,
      'instruction',
      'Instruction does not encode a jump target',
    );
  }
}

final class _DominanceAnalysis {
  const _DominanceAnalysis({
    required this.immediateDominators,
    required this.dominanceFrontiers,
  });

  final Map<int, int?> immediateDominators;
  final Map<int, List<int>> dominanceFrontiers;
}

final class _BlockSpec {
  const _BlockSpec({required this.startPc, required this.endPc});

  final int startPc;
  final int endPc;
}

_DominanceAnalysis _computeDominanceAnalysis(List<LualikeIrBasicBlock> blocks) {
  if (blocks.isEmpty) {
    return const _DominanceAnalysis(
      immediateDominators: <int, int?>{},
      dominanceFrontiers: <int, List<int>>{},
    );
  }

  final blockCount = blocks.length;
  final allBlocks = <int>{for (var i = 0; i < blockCount; i++) i};
  final dominators = List<Set<int>>.generate(
    blockCount,
    (index) => index == 0 ? <int>{0} : Set<int>.from(allBlocks),
    growable: false,
  );

  var changed = true;
  while (changed) {
    changed = false;
    for (var blockIndex = 1; blockIndex < blockCount; blockIndex++) {
      final block = blocks[blockIndex];
      final newDominators = <int>{blockIndex};
      if (block.predecessors.isNotEmpty) {
        final intersection = Set<int>.from(allBlocks);
        for (final predecessor in block.predecessors) {
          intersection.retainAll(dominators[predecessor]);
        }
        newDominators.addAll(intersection);
      }
      if (!_setEquals(dominators[blockIndex], newDominators)) {
        dominators[blockIndex] = newDominators;
        changed = true;
      }
    }
  }

  final immediateDominators = <int, int?>{};
  for (var blockIndex = 0; blockIndex < blockCount; blockIndex++) {
    if (blockIndex == 0 || blocks[blockIndex].predecessors.isEmpty) {
      immediateDominators[blockIndex] = null;
      continue;
    }

    final strictDominators = dominators[blockIndex]
        .where((dominator) => dominator != blockIndex)
        .toList(growable: false);
    if (strictDominators.isEmpty) {
      immediateDominators[blockIndex] = null;
      continue;
    }

    var candidate = strictDominators.first;
    for (final dominator in strictDominators.skip(1)) {
      if (dominators[dominator].length > dominators[candidate].length) {
        candidate = dominator;
      }
    }
    immediateDominators[blockIndex] = candidate;
  }

  final frontierSets = List<Set<int>>.generate(
    blockCount,
    (_) => <int>{},
    growable: false,
  );
  for (final block in blocks) {
    if (block.predecessors.length < 2) {
      continue;
    }
    final blockIdom = immediateDominators[block.index];
    for (final predecessor in block.predecessors) {
      var runner = predecessor;
      while (runner != blockIdom) {
        frontierSets[runner].add(block.index);
        final nextRunner = immediateDominators[runner];
        if (nextRunner == null) {
          break;
        }
        runner = nextRunner;
      }
    }
  }

  final dominanceFrontiers = <int, List<int>>{};
  for (var blockIndex = 0; blockIndex < blockCount; blockIndex++) {
    final frontier = frontierSets[blockIndex].toList(growable: false)..sort();
    dominanceFrontiers[blockIndex] = List<int>.unmodifiable(frontier);
  }

  return _DominanceAnalysis(
    immediateDominators: Map<int, int?>.unmodifiable(immediateDominators),
    dominanceFrontiers: Map<int, List<int>>.unmodifiable(dominanceFrontiers),
  );
}

bool _setEquals<T>(Set<T> left, Set<T> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final value in left) {
    if (!right.contains(value)) {
      return false;
    }
  }
  return true;
}
