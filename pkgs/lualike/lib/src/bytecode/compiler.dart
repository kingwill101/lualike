import 'package:lualike/src/ast.dart';

import 'chunk_builder.dart';
import 'emitter.dart';
import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';

/// Compiles AST programs into bytecode chunks understood by the upcoming VM.
///
/// The initial implementation focuses on a restricted subset (literal
/// expressions, expression statements, and basic return statements) to validate
/// the bytecode infrastructure. Coverage will expand incrementally as we port
/// additional interpreter features.
class BytecodeCompiler {
  BytecodeChunk compile(Program program) {
    final chunkBuilder = BytecodeChunkBuilder();
    final prototypeBuilder = chunkBuilder.mainPrototypeBuilder..isVararg = true;
    final context = _PrototypeContext(prototypeBuilder);

    for (final statement in program.statements) {
      context.emitStatement(statement);
      if (context.hasExplicitReturn) {
        break;
      }
    }

    context.finalize();
    return chunkBuilder.build();
  }
}

class _PrototypeContext {
  _PrototypeContext(this.builder) : emitter = BytecodeEmitter(builder);

  final BytecodePrototypeBuilder builder;
  final BytecodeEmitter emitter;

  bool hasExplicitReturn = false;

  int _nextRegister = 0;
  int _maxRegister = 0;
  final List<Map<String, int>> _localScopes = <Map<String, int>>[<String, int>{}];

  void _pushLocalScope() {
    _localScopes.add(<String, int>{});
  }

  void _popLocalScope() {
    assert(_localScopes.length > 1, 'Cannot pop the root scope');
    _localScopes.removeLast();
  }

  void _declareLocal(String name, int register) {
    _localScopes.last[name] = register;
  }

  int? _lookupLocal(String name) {
    for (var i = _localScopes.length - 1; i >= 0; i--) {
      final reg = _localScopes[i][name];
      if (reg != null) {
        return reg;
      }
    }
    return null;
  }

  void emitStatement(AstNode node) {
    if (hasExplicitReturn) {
      return;
    }

    switch (node) {
      case ReturnStatement():
        _emitReturn(node);
        return;
      case Assignment():
        _emitAssignment(node);
        return;
      case IfStatement():
        _emitIfStatement(node);
        return;
      case WhileStatement():
        _emitWhileStatement(node);
        return;
      case ForLoop():
        _emitForLoop(node);
        return;
      case ForInLoop():
        _emitForInLoop(node);
        return;
      case ExpressionStatement(:final expr):
        if (expr is FunctionCall) {
          _emitFunctionCall(expr, discardResult: true);
        } else {
          final reg = _emitExpression(expr);
          _releaseRegister(reg);
        }
        return;
      case AssignmentIndexAccessExpr():
        _emitAssignmentIndexAccessExpr(node);
        return;
      default:
        throw UnsupportedError(
          'Bytecode compiler does not yet support statement type: '
          '${node.runtimeType}',
        );
    }
  }

  void _emitReturn(ReturnStatement node) {
    hasExplicitReturn = true;

    if (node.expr.isEmpty) {
      emitter.emitABC(opcode: BytecodeOpcode.return0, a: 0, b: 0, c: 0);
      return;
    }

    if (node.expr.length != 1) {
      throw UnsupportedError(
        'Multiple return values are not yet supported by the bytecode '
        'compiler.',
      );
    }

    final expression = node.expr.first;
    if (expression is FunctionCall) {
      _emitFunctionCall(expression, discardResult: false, asTailCall: true);
      return;
    }

    final reg = _emitExpression(expression, target: 0);
    emitter.emitABC(opcode: BytecodeOpcode.return1, a: reg, b: 0, c: 0);
  }

  int _emitExpression(AstNode node, {int? target}) {
    switch (node) {
      case NumberLiteral(:final value):
        final reg = _materializeRegister(target);
        final constant = value is int
            ? IntegerConstant(value)
            : NumberConstant(value.toDouble());
        final index = builder.addConstant(constant);
        emitter.emitABx(opcode: BytecodeOpcode.loadK, a: reg, bx: index);
        return reg;
      case BooleanLiteral(:final value):
        final reg = _materializeRegister(target);
        emitter.emitABC(
          opcode: value ? BytecodeOpcode.loadTrue : BytecodeOpcode.loadFalse,
          a: reg,
          b: 0,
          c: 0,
        );
        return reg;
      case NilValue():
        final reg = _materializeRegister(target);
        emitter.emitABC(opcode: BytecodeOpcode.loadNil, a: reg, b: 0, c: 0);
        return reg;
      case StringLiteral(:final bytes):
        final reg = _materializeRegister(target);
        final text = String.fromCharCodes(bytes);
        final constant = text.length <= 40
            ? ShortStringConstant(text)
            : LongStringConstant(text);
        final index = builder.addConstant(constant);
        emitter.emitABx(opcode: BytecodeOpcode.loadK, a: reg, bx: index);
        return reg;
      case Identifier(:final name):
        final localReg = _lookupLocal(name);
        if (localReg != null) {
          if (target != null) {
            final dest = _materializeRegister(target);
            if (dest != localReg) {
              emitter.emitABC(
                opcode: BytecodeOpcode.move,
                a: dest,
                b: localReg,
                c: 0,
              );
            }
            return dest;
          }
          final temp = _allocateRegister();
          emitter.emitABC(
            opcode: BytecodeOpcode.move,
            a: temp,
            b: localReg,
            c: 0,
          );
          return temp;
        }
        final reg = _materializeRegister(target);
        final constant = name.length <= 40
            ? ShortStringConstant(name)
            : LongStringConstant(name);
        final index = builder.addConstant(constant);
        emitter.emitABC(
          opcode: BytecodeOpcode.getTabUp,
          a: reg,
          b: 0,
          c: index,
        );
        return reg;
      case BinaryExpression():
        return _emitBinaryExpression(node, target: target);
      case UnaryExpression():
        return _emitUnaryExpression(node, target: target);
      case GroupedExpression(:final expr):
        return _emitExpression(expr, target: target);
      case TableFieldAccess():
        return _emitTableFieldAccess(node, target: target);
      case TableIndexAccess():
        return _emitTableIndexAccess(node.table, node.index, target: target);
      case FunctionCall():
        return _emitFunctionCall(node, target: target);
      case TableAccessExpr():
        final index = node.index;
        if (index is Identifier) {
          return _emitTableFieldAccess(
            TableFieldAccess(node.table, index),
            target: target,
          );
        }
        return _emitTableIndexAccess(node.table, index, target: target);
      default:
        throw UnsupportedError(
          'Bytecode compiler does not yet support expression type: '
          '${node.runtimeType}',
        );
    }
  }

  void _emitAssignment(Assignment node) {
    if (node.targets.length != 1 || node.exprs.length != 1) {
      throw UnsupportedError(
        'Bytecode compiler does not yet support multi-target assignments.',
      );
    }
    _emitTableAssignment(node.targets.single, node.exprs.single);
  }

  void _emitAssignmentIndexAccessExpr(AssignmentIndexAccessExpr node) {
    _emitTableIndexAssignment(node.target, node.index, node.value);
  }

  void _emitTableAssignment(AstNode target, AstNode valueNode) {
    switch (target) {
      case TableFieldAccess():
        _emitTableFieldAssignment(target, valueNode);
        return;
      case TableIndexAccess():
        _emitTableIndexAssignment(target.table, target.index, valueNode);
        return;
      case TableAccessExpr():
        final index = target.index;
        if (index is Identifier) {
          _emitTableFieldAssignment(
            TableFieldAccess(target.table, index),
            valueNode,
          );
          return;
        }
        _emitTableIndexAssignment(target.table, index, valueNode);
        return;
      case AssignmentIndexAccessExpr():
        _emitTableIndexAssignment(target.target, target.index, valueNode);
        return;
      default:
        throw UnsupportedError(
          'Bytecode compiler does not yet support assignment target type: '
          '${target.runtimeType}',
        );
    }
  }

  void _emitTableFieldAssignment(TableFieldAccess target, AstNode valueNode) {
    final tableReg = _emitExpression(target.table);
    final fieldIndex = _ensureConstantIndex(target.fieldName.name);
    final valueReg = _emitExpression(valueNode);
    emitter.emitABC(
      opcode: BytecodeOpcode.setField,
      a: tableReg,
      b: fieldIndex,
      c: valueReg,
    );
    _releaseRegister(valueReg);
    _releaseRegister(tableReg);
  }

  void _emitTableIndexAssignment(
    AstNode tableNode,
    AstNode indexNode,
    AstNode valueNode,
  ) {
    final tableReg = _emitExpression(tableNode);
    final numericIndex = _numericLiteralValue(indexNode);
    if (numericIndex is int) {
      final valueReg = _emitExpression(valueNode);
      emitter.emitABC(
        opcode: BytecodeOpcode.setI,
        a: tableReg,
        b: numericIndex,
        c: valueReg,
      );
      _releaseRegister(valueReg);
      _releaseRegister(tableReg);
      return;
    }

    final indexReg = _emitExpression(indexNode);
    final valueReg = _emitExpression(valueNode);
    emitter.emitABC(
      opcode: BytecodeOpcode.setTable,
      a: tableReg,
      b: indexReg,
      c: valueReg,
    );
    _releaseRegister(valueReg);
    _releaseRegister(indexReg);
    _releaseRegister(tableReg);
  }

  void _emitIfStatement(IfStatement node) {
    final exitJumps = <int>[];
    final falseJump = _emitConditionJump(node.cond, jumpWhenTrue: false);
    _emitBlock(node.thenBlock);
    exitJumps.add(_emitJumpPlaceholder());
    _patchJump(falseJump, _currentInstructionIndex);

    for (final clause in node.elseIfs) {
      final clauseFalseJump = _emitConditionJump(
        clause.cond,
        jumpWhenTrue: false,
      );
      _emitBlock(clause.thenBlock);
      exitJumps.add(_emitJumpPlaceholder());
      _patchJump(clauseFalseJump, _currentInstructionIndex);
    }

    if (node.elseBlock.isNotEmpty) {
      _emitBlock(node.elseBlock);
    }

    final endIndex = _currentInstructionIndex;
    for (final jump in exitJumps) {
      _patchJump(jump, endIndex);
    }
  }

  void _emitWhileStatement(WhileStatement node) {
    final loopStart = _currentInstructionIndex;
    final exitJump = _emitConditionJump(node.cond, jumpWhenTrue: false);
    _emitBlock(node.body);

    final backJumpIndex = emitter.emitAsJ(opcode: BytecodeOpcode.jmp, sJ: 0);
    _patchJump(backJumpIndex, loopStart);
    _patchJump(exitJump, _currentInstructionIndex);
  }

  void _emitForLoop(ForLoop node) {
    final base = _allocateRegister();
    final limitReg = _allocateRegister();
    final stepReg = _allocateRegister();
    final controlReg = _allocateRegister();

    _emitExpression(node.start, target: base);
    _emitExpression(node.endExpr, target: limitReg);

    if (node.stepExpr != null) {
      _emitExpression(node.stepExpr!, target: stepReg);
    } else {
      _loadNumberIntoRegister(stepReg, 1);
    }

    emitter.emitABC(
      opcode: BytecodeOpcode.move,
      a: controlReg,
      b: base,
      c: 0,
    );

    final forPrepIndex = emitter.emitAsBx(
      opcode: BytecodeOpcode.forPrep,
      a: base,
      sBx: 0,
    );

    final bodyStart = _currentInstructionIndex;

    _pushLocalScope();
    _declareLocal(node.varName.name, controlReg);
    _emitBlock(node.body);
    _popLocalScope();

    final forLoopIndex = emitter.emitAsBx(
      opcode: BytecodeOpcode.forLoop,
      a: base,
      sBx: 0,
    );

    final patchedForPrep = AsBxInstruction(
      opcode: BytecodeOpcode.forPrep,
      a: base,
      sBx: forLoopIndex - forPrepIndex - 1,
    );
    builder.replaceInstruction(forPrepIndex, patchedForPrep);

    final forLoopOffset = bodyStart - (forLoopIndex + 1);
    final patchedForLoop = AsBxInstruction(
      opcode: BytecodeOpcode.forLoop,
      a: base,
      sBx: forLoopOffset,
    );
    builder.replaceInstruction(forLoopIndex, patchedForLoop);

    _releaseRegister(controlReg);
    _releaseRegister(stepReg);
    _releaseRegister(limitReg);
    _releaseRegister(base);
  }

  void _emitForInLoop(ForInLoop node) {
    if (node.iterators.isEmpty || node.names.isEmpty) {
      throw UnsupportedError('Generic for loop requires iterators and names');
    }

    final iteratorCount = node.iterators.length;
    if (iteratorCount > 3) {
      throw UnsupportedError(
        'Bytecode compiler supports up to three iterator expressions',
      );
    }

    final base = _allocateRegister();
    final stateReg = _allocateRegister();
    final controlReg = _allocateRegister();
    final loopVarRegs = <int>[];
    for (var i = 0; i < node.names.length; i++) {
      loopVarRegs.add(_allocateRegister());
    }

    for (var i = 0; i < iteratorCount; i++) {
      _emitExpression(node.iterators[i], target: base + i);
    }
    for (var i = iteratorCount; i < 3; i++) {
      emitter.emitABC(opcode: BytecodeOpcode.loadNil, a: base + i, b: 0, c: 0);
    }

    final tforPrepIndex = emitter.emitAsBx(
      opcode: BytecodeOpcode.tForPrep,
      a: base,
      sBx: 0,
    );

    final tforCallIndex = emitter.emitABC(
      opcode: BytecodeOpcode.tForCall,
      a: base,
      b: 0,
      c: node.names.length,
    );

    final tforLoopIndex = emitter.emitAsBx(
      opcode: BytecodeOpcode.tForLoop,
      a: base,
      sBx: 0,
    );

    final bodyStart = _currentInstructionIndex;

    _pushLocalScope();
    for (var i = 0; i < node.names.length; i++) {
      _declareLocal(node.names[i].name, loopVarRegs[i]);
    }
    _emitBlock(node.body);
    _popLocalScope();

    final loopJumpIndex = _emitJumpPlaceholder();
    final exitIndex = _currentInstructionIndex;

    final patchedTforPrep = AsBxInstruction(
      opcode: BytecodeOpcode.tForPrep,
      a: base,
      sBx: tforCallIndex - (tforPrepIndex + 1),
    );
    builder.replaceInstruction(tforPrepIndex, patchedTforPrep);

    final patchedTforLoop = AsBxInstruction(
      opcode: BytecodeOpcode.tForLoop,
      a: base,
      sBx: exitIndex - (tforLoopIndex + 1),
    );
    builder.replaceInstruction(tforLoopIndex, patchedTforLoop);

    _patchJump(loopJumpIndex, tforCallIndex);

    for (var i = loopVarRegs.length - 1; i >= 0; i--) {
      _releaseRegister(loopVarRegs[i]);
    }
    _releaseRegister(controlReg);
    _releaseRegister(stateReg);
    _releaseRegister(base);
  }

  int _emitConditionJump(AstNode cond, {required bool jumpWhenTrue}) {
    final condReg = _emitExpression(cond);
    emitter.emitABC(
      opcode: BytecodeOpcode.test,
      a: condReg,
      b: 0,
      c: 0,
      k: jumpWhenTrue,
    );
    final jumpIndex = _emitJumpPlaceholder();
    _releaseRegister(condReg);
    return jumpIndex;
  }

  int _emitJumpPlaceholder() {
    return emitter.emitAsJ(opcode: BytecodeOpcode.jmp, sJ: 0);
  }

  void _emitBlock(List<AstNode> statements) {
    for (final statement in statements) {
      emitStatement(statement);
      if (hasExplicitReturn) {
        break;
      }
    }
  }

  int _emitLogicalBinaryExpression(BinaryExpression node, {int? target}) {
    final isAnd = node.op == 'and';
    final resultReg = _emitExpression(node.left, target: target);
    emitter.emitABC(
      opcode: BytecodeOpcode.test,
      a: resultReg,
      b: 0,
      c: 0,
      k: !isAnd,
    );
    final jumpIndex = _emitJumpPlaceholder();
    _emitExpression(node.right, target: resultReg);
    _patchJump(jumpIndex, _currentInstructionIndex);
    return resultReg;
  }

  int get _currentInstructionIndex => builder.instructions.length;

  void _patchJump(int jumpIndex, int targetIndex) {
    final instruction = builder.instructions[jumpIndex] as AsJInstruction;
    final offset = targetIndex - jumpIndex - 1;
    builder.replaceInstruction(
      jumpIndex,
      AsJInstruction(opcode: instruction.opcode, sJ: offset),
    );
  }

  int _emitFunctionCall(
    FunctionCall node, {
    int? target,
    bool discardResult = false,
    bool asTailCall = false,
  }) {
    final base = _allocateRegister();
    _emitExpression(node.name, target: base);

    final argRegs = <int>[];
    for (final argument in node.args) {
      final reg = _allocateRegister();
      argRegs.add(reg);
      _emitExpression(argument, target: reg);
    }

    final b = argRegs.length + 1;
    final opcode = asTailCall ? BytecodeOpcode.tailCall : BytecodeOpcode.call;
    final c = asTailCall
        ? 0
        : discardResult
            ? 1
            : 2;

    emitter.emitABC(opcode: opcode, a: base, b: b, c: c);

    for (var i = argRegs.length - 1; i >= 0; i--) {
      _releaseRegister(argRegs[i]);
    }

    if (asTailCall) {
      _releaseRegister(base);
      return base;
    }

    if (discardResult) {
      _releaseRegister(base);
      return base;
    }

    if (target != null) {
      final dest = _materializeRegister(target);
      if (dest != base) {
        emitter.emitABC(opcode: BytecodeOpcode.move, a: dest, b: base, c: 0);
      }
      _releaseRegister(base);
      return dest;
    }

    return base;
  }

  int _emitBinaryExpression(BinaryExpression node, {int? target}) {
    if (node.op == 'and' || node.op == 'or') {
      return _emitLogicalBinaryExpression(node, target: target);
    }

    final literalValue = _literalValue(node.right);
    final leftReg = _emitExpression(node.left, target: target);

    if (literalValue is num) {
      final opcode = _opcodeForBinaryConstant(node.op);
      if (opcode != null) {
        final constantIndex = _ensureConstantIndex(literalValue);
        emitter.emitABC(
          opcode: opcode,
          a: leftReg,
          b: leftReg,
          c: constantIndex,
          k: true,
        );
        return leftReg;
      }
    }

    if (literalValue case final Object? value) {
      final handled = switch (node.op) {
        '==' => _emitEqualityWithLiteral(leftReg, value, negate: false),
        '~=' || '!=' => _emitEqualityWithLiteral(leftReg, value, negate: true),
        '<' => _emitRelationalWithLiteral(leftReg, value, BytecodeOpcode.ltI),
        '<=' => _emitRelationalWithLiteral(leftReg, value, BytecodeOpcode.leI),
        '>' => _emitRelationalWithLiteral(leftReg, value, BytecodeOpcode.gtI),
        '>=' => _emitRelationalWithLiteral(leftReg, value, BytecodeOpcode.geI),
        _ => false,
      };
      if (handled) {
        return leftReg;
      }
    }

    final rightReg = _emitExpression(node.right);

    switch (node.op) {
      case '==':
        emitter.emitABC(
          opcode: BytecodeOpcode.eq,
          a: leftReg,
          b: leftReg,
          c: rightReg,
        );
        break;
      case '~=':
      case '!=':
        emitter.emitABC(
          opcode: BytecodeOpcode.eq,
          a: leftReg,
          b: leftReg,
          c: rightReg,
        );
        emitter.emitABC(
          opcode: BytecodeOpcode.notOp,
          a: leftReg,
          b: leftReg,
          c: 0,
        );
        break;
      case '<':
        emitter.emitABC(
          opcode: BytecodeOpcode.lt,
          a: leftReg,
          b: leftReg,
          c: rightReg,
        );
        break;
      case '>':
        emitter.emitABC(
          opcode: BytecodeOpcode.lt,
          a: leftReg,
          b: rightReg,
          c: leftReg,
        );
        break;
      case '<=':
        emitter.emitABC(
          opcode: BytecodeOpcode.le,
          a: leftReg,
          b: leftReg,
          c: rightReg,
        );
        break;
      case '>=':
        emitter.emitABC(
          opcode: BytecodeOpcode.le,
          a: leftReg,
          b: rightReg,
          c: leftReg,
        );
        break;
      default:
        final opcode = _opcodeForBinary(node.op);
        if (opcode == null) {
          _releaseRegister(rightReg);
          throw UnsupportedError(
            'Operator ${node.op} is not supported by bytecode compiler',
          );
        }
        emitter.emitABC(opcode: opcode, a: leftReg, b: leftReg, c: rightReg);
    }

    _releaseRegister(rightReg);
    return leftReg;
  }

  BytecodeOpcode? _opcodeForBinary(String operatorToken) {
    return switch (operatorToken) {
      '+' => BytecodeOpcode.add,
      '-' => BytecodeOpcode.sub,
      '*' => BytecodeOpcode.mul,
      '/' => BytecodeOpcode.div,
      '%' => BytecodeOpcode.mod,
      '^' => BytecodeOpcode.pow,
      '//' => BytecodeOpcode.idiv,
      '&' => BytecodeOpcode.band,
      '|' => BytecodeOpcode.bor,
      '~' => BytecodeOpcode.bxor,
      '<<' => BytecodeOpcode.shl,
      '>>' => BytecodeOpcode.shr,
      _ => null,
    };
  }

  BytecodeOpcode? _opcodeForBinaryConstant(String operatorToken) {
    return switch (operatorToken) {
      '+' => BytecodeOpcode.addK,
      '-' => BytecodeOpcode.subK,
      '*' => BytecodeOpcode.mulK,
      '/' => BytecodeOpcode.divK,
      '%' => BytecodeOpcode.modK,
      '^' => BytecodeOpcode.powK,
      '//' => BytecodeOpcode.idivK,
      _ => null,
    };
  }

  int? _numericConstantIndex(AstNode node) {
    final numericValue = _numericLiteralValue(node);
    if (numericValue == null) {
      return null;
    }
    if (numericValue is int) {
      return builder.addConstant(IntegerConstant(numericValue));
    }
    if (numericValue is double) {
      return builder.addConstant(NumberConstant(numericValue));
    }
    return null;
  }

  num? _numericLiteralValue(AstNode node) {
    switch (node) {
      case NumberLiteral(value: final value):
        if (value is int) {
          return value;
        }
        if (value is double) {
          return value;
        }
        if (value is BigInt && value.bitLength <= 63) {
          return value.toInt();
        }
        return null;
      case UnaryExpression(op: '-', expr: final expr):
        final inner = _numericLiteralValue(expr);
        return inner == null ? null : -inner;
      default:
        return null;
    }
  }

  Object? _literalValue(AstNode node) {
    switch (node) {
      case NilValue():
        return null;
      case BooleanLiteral(value: final value):
        return value;
      case StringLiteral(:final bytes):
        return String.fromCharCodes(bytes);
      case NumberLiteral():
      case UnaryExpression():
        return _numericLiteralValue(node);
      default:
        return null;
    }
  }

  bool _emitEqualityWithLiteral(
    int leftReg,
    Object? value, {
    required bool negate,
  }) {
    if (value is int) {
      emitter.emitABC(
        opcode: BytecodeOpcode.eqI,
        a: leftReg,
        b: leftReg,
        c: value,
      );
    } else {
      final constantIndex = _ensureConstantIndex(value);
      emitter.emitABC(
        opcode: BytecodeOpcode.eqK,
        a: leftReg,
        b: leftReg,
        c: constantIndex,
      );
    }

    if (negate) {
      emitter.emitABC(
        opcode: BytecodeOpcode.notOp,
        a: leftReg,
        b: leftReg,
        c: 0,
      );
    }

    return true;
  }

  bool _emitRelationalWithLiteral(
    int leftReg,
    Object? value,
    BytecodeOpcode opcode,
  ) {
    if (value is! int) {
      return false;
    }
    emitter.emitABC(opcode: opcode, a: leftReg, b: leftReg, c: value);
    return true;
  }

  void _loadNumberIntoRegister(int register, num value) {
    final index = builder.addConstant(
      value is int ? IntegerConstant(value) : NumberConstant(value.toDouble()),
    );
    emitter.emitABx(opcode: BytecodeOpcode.loadK, a: register, bx: index);
  }

  int _ensureConstantIndex(Object? value) {
    final constant = switch (value) {
      null => const NilConstant(),
      bool boolValue => BooleanConstant(boolValue),
      int intValue => IntegerConstant(intValue),
      num numValue => NumberConstant(numValue.toDouble()),
      String stringValue when stringValue.length <= 40 => ShortStringConstant(
        stringValue,
      ),
      String stringValue => LongStringConstant(stringValue),
      _ => throw UnsupportedError(
        'Unsupported literal constant type: ${value.runtimeType}',
      ),
    };
    return builder.addConstant(constant);
  }

  int _emitTableFieldAccess(TableFieldAccess node, {int? target}) {
    final tableReg = _emitExpression(node.table, target: target);
    final fieldIndex = _ensureConstantIndex(node.fieldName.name);
    emitter.emitABC(
      opcode: BytecodeOpcode.getField,
      a: tableReg,
      b: tableReg,
      c: fieldIndex,
    );
    return tableReg;
  }

  int _emitTableIndexAccess(
    AstNode tableNode,
    AstNode indexNode, {
    int? target,
  }) {
    final tableReg = _emitExpression(tableNode, target: target);
    final numericIndex = _numericLiteralValue(indexNode);
    if (numericIndex is int) {
      emitter.emitABC(
        opcode: BytecodeOpcode.getI,
        a: tableReg,
        b: tableReg,
        c: numericIndex,
      );
      return tableReg;
    }

    final indexReg = _emitExpression(indexNode);
    emitter.emitABC(
      opcode: BytecodeOpcode.getTable,
      a: tableReg,
      b: tableReg,
      c: indexReg,
    );
    _releaseRegister(indexReg);
    return tableReg;
  }

  int _emitUnaryExpression(UnaryExpression node, {int? target}) {
    final reg = _emitExpression(node.expr, target: target);
    final opcode = switch (node.op) {
      'not' => BytecodeOpcode.notOp,
      '-' => BytecodeOpcode.unm,
      '~' => BytecodeOpcode.bnot,
      '#' => BytecodeOpcode.len,
      _ => throw UnsupportedError(
        'Unary operator ${node.op} is not supported by bytecode compiler',
      ),
    };

    emitter.emitABC(opcode: opcode, a: reg, b: reg, c: 0);
    return reg;
  }

  void finalize() {
    if (!hasExplicitReturn) {
      emitter.emitABC(opcode: BytecodeOpcode.return0, a: 0, b: 0, c: 0);
    }

    final registers = _maxRegister == 0 ? 1 : _maxRegister;
    builder.registerCount = registers;
  }

  int _materializeRegister(int? target) {
    if (target != null) {
      return _ensureRegister(target);
    }
    return _allocateRegister();
  }

  int _allocateRegister() {
    final reg = _nextRegister;
    _nextRegister += 1;
    if (_nextRegister > _maxRegister) {
      _maxRegister = _nextRegister;
    }
    return reg;
  }

  int _ensureRegister(int reg) {
    if (_nextRegister <= reg) {
      _nextRegister = reg + 1;
    }
    if (_nextRegister > _maxRegister) {
      _maxRegister = _nextRegister;
    }
    return reg;
  }

  void _releaseRegister(int reg) {
    if (_nextRegister == 0) {
      return;
    }
    assert(
      reg == _nextRegister - 1,
      'Registers must be released in LIFO order',
    );
    _nextRegister -= 1;
  }
}
