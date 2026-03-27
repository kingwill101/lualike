import 'dart:math';

import 'package:lualike/src/ast.dart';
import 'chunk_builder.dart';
import 'emitter.dart';
import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';

/// Attempts to compile a numeric `for` loop into lualike IR.
///
/// The compiler currently supports a restricted subset of Lua:
/// - Numeric for loops with numeric (already evaluated) start/end/step values.
/// - Loop bodies containing simple assignments to identifiers.
/// - Assignment expressions composed of identifiers, numeric literals,
///   and binary arithmetic operators (+, -, *, /, %).
///
/// If the loop body contains unsupported constructs the compiler returns null
/// and the interpreter should fall back to the AST implementation.
class LoopIrCompiler {
  LoopIrCompiler({
    required this.loopVarName,
    required this.startValue,
    required this.endValue,
    required this.stepValue,
  });

  final String loopVarName;
  final num startValue;
  final num endValue;
  final num stepValue;

  static const int _loopBaseRegister = 0;

  LualikeIrChunk? compile(List<AstNode> body) {
    if (!_bodySupported(body)) {
      return null;
    }

    final chunkBuilder = LualikeIrChunkBuilder();
    final protoBuilder = chunkBuilder.mainPrototypeBuilder;
    final emitter = LualikeIrEmitter(protoBuilder);
    final registerAllocator = _RegisterAllocator(base: _loopBaseRegister + 4);

    // Reserve _ENV upvalue.
    protoBuilder.upvalueDescriptors.add(
      const LualikeIrUpvalueDescriptor(inStack: 0, index: 0),
    );

    // Load start/end/step constants into registers R0..R2, set R3 = start.
    final startConst = _makeNumberConstant(startValue);
    final endConst = _makeNumberConstant(endValue);
    final stepConst = _makeNumberConstant(stepValue);

    final startConstIndex = protoBuilder.addConstant(startConst);
    final endConstIndex = protoBuilder.addConstant(endConst);
    final stepConstIndex = protoBuilder.addConstant(stepConst);

    emitter.emitABx(
      opcode: LualikeIrOpcode.loadK,
      a: _loopBaseRegister,
      bx: startConstIndex,
    );
    emitter.emitABx(
      opcode: LualikeIrOpcode.loadK,
      a: _loopBaseRegister + 1,
      bx: endConstIndex,
    );
    emitter.emitABx(
      opcode: LualikeIrOpcode.loadK,
      a: _loopBaseRegister + 2,
      bx: stepConstIndex,
    );
    emitter.emitABC(
      opcode: LualikeIrOpcode.move,
      a: _loopBaseRegister + 3,
      b: _loopBaseRegister,
      c: 0,
    );

    final forPrepIndex = emitter.emitAsBx(
      opcode: LualikeIrOpcode.forPrep,
      a: _loopBaseRegister,
      sBx: 0, // placeholder
    );

    final bodyStartIndex = protoBuilder.instructions.length;

    for (final statement in body) {
      final compiled = _compileStatement(
        statement,
        emitter,
        protoBuilder,
        registerAllocator,
      );
      if (!compiled) {
        return null;
      }
    }

    final forLoopIndex = emitter.emitAsBx(
      opcode: LualikeIrOpcode.forLoop,
      a: _loopBaseRegister,
      sBx: 0, // placeholder
    );

    emitter.emitABC(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0);

    // Patch FORPREP / FORLOOP offsets.
    final patchedForPrep = AsBxInstruction(
      opcode: LualikeIrOpcode.forPrep,
      a: _loopBaseRegister,
      sBx: (forLoopIndex - forPrepIndex - 1),
    );
    protoBuilder.replaceInstruction(forPrepIndex, patchedForPrep);

    final bodyStart = bodyStartIndex;
    final forLoopOffset = bodyStart - (forLoopIndex + 1);
    final patchedForLoop = AsBxInstruction(
      opcode: LualikeIrOpcode.forLoop,
      a: _loopBaseRegister,
      sBx: forLoopOffset,
    );
    protoBuilder.replaceInstruction(forLoopIndex, patchedForLoop);

    protoBuilder.registerCount = max(
      protoBuilder.registerCount,
      registerAllocator.maxAllocated,
    );

    return chunkBuilder.build();
  }

  bool _bodySupported(List<AstNode> body) {
    if (body.isEmpty) {
      return false;
    }
    for (final node in body) {
      if (node is Assignment) {
        if (node.targets.length != node.exprs.length ||
            node.targets.length != 1) {
          return false;
        }
        final target = node.targets.first;
        if (target is Identifier) {
          if (!_expressionSupported(node.exprs.first)) {
            return false;
          }
        } else if (target is TableAccessExpr) {
          if (!_tableAccessSupported(target)) {
            return false;
          }
          if (!_expressionSupported(node.exprs.first)) {
            return false;
          }
        } else {
          return false;
        }
      } else {
        return false;
      }
    }
    return true;
  }

  bool _tableAccessSupported(TableAccessExpr target) {
    if (target.table is! Identifier) {
      return false;
    }
    return _expressionSupported(target.index);
  }

  bool _expressionSupported(AstNode node) {
    if (node is NumberLiteral || node is Identifier) {
      return true;
    }
    if (node is BinaryExpression) {
      const supportedOps = {'+', '-', '*', '/', '%'};
      if (!supportedOps.contains(node.op)) {
        return false;
      }
      return _expressionSupported(node.left) &&
          _expressionSupported(node.right);
    }
    if (node is GroupedExpression) {
      return _expressionSupported(node.expr);
    }
    return false;
  }

  bool _compileStatement(
    AstNode statement,
    LualikeIrEmitter emitter,
    LualikeIrPrototypeBuilder protoBuilder,
    _RegisterAllocator allocator,
  ) {
    if (statement is! Assignment) {
      return false;
    }
    final AstNode target = statement.targets.first;
    final expressionRegister = _compileExpression(
      statement.exprs.first,
      emitter,
      protoBuilder,
      allocator,
    );
    if (expressionRegister == null) {
      return false;
    }

    if (target is Identifier) {
      final int targetRegister = _resolveIdentifierRegister(target.name);
      if (targetRegister >= 0) {
        emitter.emitABC(
          opcode: LualikeIrOpcode.move,
          a: targetRegister,
          b: expressionRegister,
          c: 0,
        );
      } else {
        final constIndex = protoBuilder.addConstant(
          ShortStringConstant(target.name),
        );
        emitter.emitABC(
          opcode: LualikeIrOpcode.setTabUp,
          a: 0,
          b: constIndex,
          c: expressionRegister,
          k: false,
        );
      }
    } else if (target is TableAccessExpr) {
      final tableReg = _compileExpression(
        target.table,
        emitter,
        protoBuilder,
        allocator,
      );
      if (tableReg == null) {
        return false;
      }

      final indexReg = _compileIndexRegister(
        target.index,
        emitter,
        protoBuilder,
        allocator,
      );
      if (indexReg == null) {
        return false;
      }

      emitter.emitABC(
        opcode: LualikeIrOpcode.setTable,
        a: tableReg,
        b: indexReg,
        c: expressionRegister,
      );
    } else {
      return false;
    }

    allocator.resetTemps();
    return true;
  }

  int? _compileExpression(
    AstNode node,
    LualikeIrEmitter emitter,
    LualikeIrPrototypeBuilder protoBuilder,
    _RegisterAllocator allocator,
  ) {
    if (node is NumberLiteral) {
      final reg = allocator.allocateTemp();
      final num value = node.value;
      final constant = _makeNumberConstant(value);
      final idx = protoBuilder.addConstant(constant);
      emitter.emitABx(opcode: LualikeIrOpcode.loadK, a: reg, bx: idx);
      return reg;
    }

    if (node is Identifier) {
      final reg = _resolveIdentifierRegister(node.name);
      if (reg >= 0) {
        return reg;
      }

      final dest = allocator.allocateTemp();
      final constIndex = protoBuilder.addConstant(
        ShortStringConstant(node.name),
      );
      emitter.emitABC(
        opcode: LualikeIrOpcode.getTabUp,
        a: dest,
        b: 0,
        c: constIndex,
        k: true,
      );
      return dest;
    }

    if (node is GroupedExpression) {
      return _compileExpression(node.expr, emitter, protoBuilder, allocator);
    }

    if (node is BinaryExpression) {
      final leftReg = _compileExpression(
        node.left,
        emitter,
        protoBuilder,
        allocator,
      );
      final rightReg = _compileExpression(
        node.right,
        emitter,
        protoBuilder,
        allocator,
      );
      if (leftReg == null || rightReg == null) {
        return null;
      }
      final dest = allocator.allocateTemp();
      final opcode = switch (node.op) {
        '+' => LualikeIrOpcode.add,
        '-' => LualikeIrOpcode.sub,
        '*' => LualikeIrOpcode.mul,
        '/' => LualikeIrOpcode.div,
        '%' => LualikeIrOpcode.mod,
        _ => null,
      };
      if (opcode == null) {
        return null;
      }
      emitter.emitABC(opcode: opcode, a: dest, b: leftReg, c: rightReg);
      return dest;
    }

    return null;
  }

  int? _compileIndexRegister(
    AstNode node,
    LualikeIrEmitter emitter,
    LualikeIrPrototypeBuilder protoBuilder,
    _RegisterAllocator allocator,
  ) {
    if (node is Identifier) {
      final reg = _resolveIdentifierRegister(node.name);
      if (reg >= 0) {
        return reg;
      }
    }

    if (node is NumberLiteral) {
      final reg = allocator.allocateTemp();
      final constant = _makeNumberConstant(node.value);
      final constIndex = protoBuilder.addConstant(constant);
      emitter.emitABx(opcode: LualikeIrOpcode.loadK, a: reg, bx: constIndex);
      return reg;
    }

    final reg = _compileExpression(node, emitter, protoBuilder, allocator);
    return reg;
  }

  int _resolveIdentifierRegister(String name) {
    if (name == loopVarName) {
      return _loopBaseRegister + 3;
    }
    return -1;
  }

  LualikeIrConstant _makeNumberConstant(num value) {
    if (value is int) {
      return IntegerConstant(value);
    }
    return NumberConstant(value.toDouble());
  }
}

class _RegisterAllocator {
  _RegisterAllocator({required this.base});

  final int base;
  int _next = 0;
  int _max = 0;

  int allocateTemp() {
    final reg = base + _next;
    _next += 1;
    _max = max(_max, base + _next);
    return reg;
  }

  void resetTemps() {
    _next = 0;
  }

  int get maxAllocated => max(_max, base + _next);
}
