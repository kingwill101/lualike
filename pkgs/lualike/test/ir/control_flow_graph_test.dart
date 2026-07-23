@Tags(['ir'])
library;

import 'package:lualike/src/ir/chunk_builder.dart';
import 'package:lualike/src/ir/control_flow.dart';
import 'package:lualike/src/ir/instruction.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/ir/ssa.dart';
import 'package:test/test.dart';

LualikeIrPrototype _prototype(
  List<LualikeIrInstruction> instructions, {
  int registerCount = 2,
}) {
  final builder = LualikeIrPrototypeBuilder(registerCount: registerCount);
  for (final instruction in instructions) {
    builder.addInstruction(instruction);
  }
  return builder.build();
}

void main() {
  group('Lualike IR control-flow graph', () {
    test('splits unconditional jumps into separate blocks', () {
      final prototype = _prototype([
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 0, b: 0, c: 0),
        const AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: 1),
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 1, b: 0, c: 0),
        const ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
      ]);

      final cfg = LualikeIrControlFlowGraph.fromPrototype(prototype);

      expect(cfg.blocks.length, equals(3));
      expect(cfg.blocks[0].instructionPcs, equals([0, 1]));
      expect(cfg.blocks[0].successors, equals([2]));
      expect(cfg.blocks[1].instructionPcs, equals([2]));
      expect(cfg.blocks[1].successors, equals([2]));
      expect(cfg.blocks[2].instructionPcs, equals([3]));
      expect(cfg.blocks[2].successors, isEmpty);
      expect(cfg.blockForPc(3).index, equals(2));
    });

    test('keeps test and jump together as one conditional block', () {
      final prototype = _prototype([
        const ABCInstruction(
          opcode: LualikeIrOpcode.test,
          a: 0,
          b: 0,
          c: 0,
          k: false,
        ),
        const AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: 1),
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 1, b: 0, c: 0),
        const ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
      ]);

      final cfg = LualikeIrControlFlowGraph.fromPrototype(prototype);

      expect(cfg.blocks.length, equals(3));
      expect(cfg.blocks[0].instructionPcs, equals([0, 1]));
      expect(cfg.blocks[0].successors, equals([2, 1]));
      expect(cfg.blocks[1].instructionPcs, equals([2]));
      expect(cfg.blocks[2].instructionPcs, equals([3]));
      expect(cfg.blocks[0].predecessors, isEmpty);
      expect(cfg.blocks[2].predecessors, equals([0, 1]));
    });

    test('computes immediate dominators and dominance frontiers', () {
      final prototype = _prototype([
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 0, b: 0, c: 0),
        const ABCInstruction(
          opcode: LualikeIrOpcode.test,
          a: 0,
          b: 0,
          c: 0,
          k: false,
        ),
        const AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: 2),
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 1, b: 1, c: 0),
        const AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: 1),
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 1, b: 2, c: 0),
        const ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
      ]);

      final cfg = LualikeIrControlFlowGraph.fromPrototype(prototype);

      expect(cfg.blocks.length, equals(4));
      expect(cfg.entryBlock.index, equals(0));
      expect(cfg.exitBlocks.map((block) => block.index), equals([3]));
      expect(cfg.immediateDominatorOf(0), isNull);
      expect(cfg.immediateDominatorOf(1), equals(0));
      expect(cfg.immediateDominatorOf(2), equals(0));
      expect(cfg.immediateDominatorOf(3), equals(0));
      expect(cfg.dominates(0, 3), isTrue);
      expect(cfg.dominates(1, 3), isFalse);
      expect(cfg.dominanceFrontierOf(0), isEmpty);
      expect(cfg.dominanceFrontierOf(1), equals([3]));
      expect(cfg.dominanceFrontierOf(2), equals([3]));
      expect(cfg.dominanceFrontierOf(3), isEmpty);
    });
  });

  group('Lualike IR SSA scaffold', () {
    test('places phi nodes on dominance frontiers', () {
      final prototype = _prototype([
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 0, b: 0, c: 0),
        const ABCInstruction(
          opcode: LualikeIrOpcode.test,
          a: 0,
          b: 0,
          c: 0,
          k: false,
        ),
        const AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: 2),
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 1, b: 1, c: 0),
        const AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: 1),
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 1, b: 2, c: 0),
        const ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
      ]);

      final ssa = LualikeIrSsaFunction.fromPrototype(prototype);

      expect(ssa.blocks.length, equals(4));
      expect(ssa.blocks[1].phis, isEmpty);
      expect(ssa.blocks[2].phis, isEmpty);
      expect(ssa.blocks[3].hasPhis, isTrue);
      expect(ssa.blocks[3].phis.length, equals(1));
      final phi = ssa.blocks[3].phis.single;
      expect(phi.targetRegister, equals(1));
      expect(phi.value.label, equals('r1#3'));
      expect(phi.incomingByPredecessor[1]?.label, equals('r1#1'));
      expect(phi.incomingByPredecessor[2]?.label, equals('r1#2'));
      expect(phi.incomingForBlock(1), same(ssa.blocks[1].exitValues[1]));
      expect(phi.incomingForBlock(2), same(ssa.blocks[2].exitValues[1]));
      expect(phi.isTrivial, isFalse);
      expect(ssa.blocks[0].exitValues[0]!.useCount, greaterThan(0));
      expect(ssa.blocks[1].exitValues[1]!.useCount, equals(1));
      expect(ssa.blocks[1].exitValues[1]!.uses.single.kind, equals('phi'));
      expect(ssa.blocks[1].exitValues[1]!.uses.single.blockIndex, equals(3));
      expect(ssa.blocks[2].exitValues[1]!.useCount, equals(1));
      expect(ssa.blocks[2].exitValues[1]!.uses.single.kind, equals('phi'));
      expect(ssa.blocks[2].exitValues[1]!.uses.single.blockIndex, equals(3));
      expect(ssa.blocks[3].entryValues[1]?.label, equals('r1#3'));
      expect(ssa.blocks[3].exitValues[1]?.label, equals('r1#3'));
    });

    test('wraps the CFG and starts with empty phi nodes', () {
      final prototype = _prototype([
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 0, b: 0, c: 0),
        const ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
      ]);

      final ssa = LualikeIrSsaFunction.fromPrototype(prototype);

      expect(ssa.cfg.blocks.length, equals(1));
      expect(ssa.blocks.length, equals(1));
      expect(ssa.immediateDominatorOf(0), isNull);
      expect(ssa.dominanceFrontierOf(0), isEmpty);
      expect(ssa.blocks.single.hasPhis, isFalse);
      expect(ssa.blocks.single.phis, isEmpty);
    });

    test('handles empty prototypes without SSA values', () {
      final prototype = _prototype(
        const <LualikeIrInstruction>[],
        registerCount: 0,
      );

      final ssa = LualikeIrSsaFunction.fromPrototype(prototype);

      expect(ssa.cfg.blocks.length, equals(1));
      expect(ssa.blocks.single.entryValues, isEmpty);
      expect(ssa.blocks.single.exitValues, isEmpty);
      expect(ssa.blocks.single.hasPhis, isFalse);
      expect(ssa.blocks.single.hasUnusedDefinitions, isFalse);
      expect(ssa.hasUnusedDefinitions, isFalse);
      expect(ssa.unusedDefinitions, isEmpty);
    });

    test('places phi nodes for loop backedges', () {
      final prototype = _prototype([
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 0, b: 0, c: 0),
        const ABCInstruction(
          opcode: LualikeIrOpcode.test,
          a: 0,
          b: 0,
          c: 0,
          k: false,
        ),
        const AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: 2),
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 0, b: 1, c: 0),
        const AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: -4),
        const ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
      ]);

      final ssa = LualikeIrSsaFunction.fromPrototype(prototype);

      expect(ssa.blocks.length, equals(4));
      final loopHeader = ssa.blocks[1];
      expect(loopHeader.phis.length, equals(1));
      final phi = loopHeader.phis.single;
      expect(phi.targetRegister, equals(0));
      expect(phi.value.label, equals('r0#2'));
      expect(phi.incomingForBlock(0)?.label, equals('r0#1'));
      expect(phi.incomingForBlock(2)?.label, equals('r0#3'));
      expect(phi.isTrivial, isFalse);
      expect(loopHeader.entryValues[0], same(phi.value));
      expect(loopHeader.exitValues[0], same(phi.value));
    });

    test('formats SSA blocks and phi data', () {
      final prototype = _prototype([
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 0, b: 0, c: 0),
        const ABCInstruction(
          opcode: LualikeIrOpcode.test,
          a: 0,
          b: 0,
          c: 0,
          k: false,
        ),
        const AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: 2),
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 1, b: 1, c: 0),
        const AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: 1),
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 1, b: 2, c: 0),
        const ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
      ]);

      final ssa = LualikeIrSsaFunction.fromPrototype(prototype);
      final text = formatLualikeIrSsaFunction(ssa);

      expect(text, contains('ssa {'));
      expect(ssa.toString(), equals(text));
      expect(text, contains('block 3'));
      expect(ssa.blocks[3].toString(), contains('SsaBlock(block=3'));
      expect(text, contains('phi r1#'));
      expect(ssa.blocks[3].phis.single.toString(), contains('target=r1'));
      expect(text, contains('incoming=[b1:'));
      expect(text, contains('exit {r0='));
    });

    test('simplifies trivial phis to shared incoming values', () {
      final prototype = _prototype([
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 0, b: 0, c: 0),
        const ABCInstruction(
          opcode: LualikeIrOpcode.test,
          a: 0,
          b: 0,
          c: 0,
          k: false,
        ),
        const AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: 2),
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 1, b: 1, c: 0),
        const AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: 1),
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 1, b: 2, c: 0),
        const ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
      ]);

      final ssa = LualikeIrSsaFunction.fromPrototype(prototype);
      final shared = ssa.blocks[1].exitValues[1]!;
      final trivialValue = LualikeIrSsaValue(
        register: 1,
        version: 99,
        definingBlock: 3,
        isPhi: true,
      );
      final customJoinBlock = LualikeIrSsaBlock(
        block: ssa.blocks[3].block,
        phis: [
          LualikeIrPhi(
            targetRegister: 1,
            value: trivialValue,
            incomingByPredecessor: {1: shared, 2: shared},
          ),
        ],
        entryValues: {...ssa.blocks[3].entryValues, 1: trivialValue},
        exitValues: {...ssa.blocks[3].exitValues, 1: trivialValue},
        definedValues: ssa.blocks[3].definedValues,
      );
      final custom = LualikeIrSsaFunction(
        cfg: ssa.cfg,
        blocks: [ssa.blocks[0], ssa.blocks[1], ssa.blocks[2], customJoinBlock],
        immediateDominatorByBlock: ssa.immediateDominatorByBlock,
        dominanceFrontierByBlock: ssa.dominanceFrontierByBlock,
      );

      final simplified = custom.simplifyTrivialPhis();
      final joinBlock = simplified.blocks[3];

      expect(joinBlock.phis, isEmpty);
      expect(joinBlock.entryValues[1], same(shared));
      expect(joinBlock.exitValues[1], same(shared));
    });

    test('simplifies chained trivial phis to a fixed point', () {
      final emptyCfg = LualikeIrControlFlowGraph.fromPrototype(
        _prototype(const <LualikeIrInstruction>[], registerCount: 0),
      );
      final shared = LualikeIrSsaValue(
        register: 0,
        version: 0,
        definingBlock: 0,
      );
      final firstPhiValue = LualikeIrSsaValue(
        register: 0,
        version: 1,
        definingBlock: 1,
        isPhi: true,
      );
      final secondPhiValue = LualikeIrSsaValue(
        register: 0,
        version: 2,
        definingBlock: 2,
        isPhi: true,
      );
      final block0 = LualikeIrSsaBlock(
        block: const LualikeIrBasicBlock(
          index: 0,
          startPc: 0,
          endPc: 0,
          instructionPcs: <int>[],
          successors: <int>[],
          predecessors: <int>[],
        ),
        entryValues: {0: shared},
        exitValues: {0: shared},
        definedValues: const <LualikeIrSsaValue>[],
      );
      final block1 = LualikeIrSsaBlock(
        block: const LualikeIrBasicBlock(
          index: 1,
          startPc: 0,
          endPc: 0,
          instructionPcs: <int>[],
          successors: <int>[],
          predecessors: <int>[],
        ),
        phis: [
          LualikeIrPhi(
            targetRegister: 0,
            value: firstPhiValue,
            incomingByPredecessor: {0: shared, 2: shared},
          ),
        ],
        entryValues: {0: firstPhiValue},
        exitValues: {0: firstPhiValue},
        definedValues: const <LualikeIrSsaValue>[],
      );
      final block2 = LualikeIrSsaBlock(
        block: const LualikeIrBasicBlock(
          index: 2,
          startPc: 0,
          endPc: 0,
          instructionPcs: <int>[],
          successors: <int>[],
          predecessors: <int>[],
        ),
        phis: [
          LualikeIrPhi(
            targetRegister: 0,
            value: secondPhiValue,
            incomingByPredecessor: {1: firstPhiValue, 0: shared},
          ),
        ],
        entryValues: {0: secondPhiValue},
        exitValues: {0: secondPhiValue},
        definedValues: const <LualikeIrSsaValue>[],
      );
      final custom = LualikeIrSsaFunction(
        cfg: emptyCfg,
        blocks: [block0, block1, block2],
        immediateDominatorByBlock: const <int, int?>{},
        dominanceFrontierByBlock: const <int, List<int>>{},
      );

      final simplified = custom.simplifyTrivialPhis();

      expect(simplified.blocks[1].phis, isEmpty);
      expect(simplified.blocks[2].phis, isEmpty);
      expect(simplified.blocks[1].entryValues[0], same(shared));
      expect(simplified.blocks[2].entryValues[0], same(shared));
      expect(simplified.blocks[2].exitValues[0], same(shared));
    });

    test('tracks unused SSA definitions', () {
      final prototype = _prototype([
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 0, b: 0, c: 0),
        const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 1, b: 1, c: 0),
        const ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
      ]);

      final ssa = LualikeIrSsaFunction.fromPrototype(prototype);

      expect(ssa.blocks.single.hasUnusedDefinitions, isTrue);
      expect(ssa.hasUnusedDefinitions, isTrue);
      expect(
        ssa.blocks.single.unusedDefinitions.map((value) => value.label),
        equals(['r0#1', 'r1#1']),
      );
      expect(
        ssa.unusedDefinitions.map((value) => value.label),
        equals(['r0#1', 'r1#1']),
      );
    });
  });
}
