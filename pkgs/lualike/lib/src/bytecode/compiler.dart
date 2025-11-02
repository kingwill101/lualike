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
    final prototypeBuilder = chunkBuilder.mainPrototypeBuilder;
    final context = _PrototypeContext(prototypeBuilder, isVararg: true);

    for (final statement in program.statements) {
      final completed = context.emitStatement(statement);
      if (completed) {
        break;
      }
    }

    context.finalize();
    return chunkBuilder.build();
  }
}

class _CallEmissionResult {
  const _CallEmissionResult({
    required this.base,
    required this.resultCount,
    this.capturesAll = false,
  });

  final int base;
  final int resultCount;
  final bool capturesAll;
}

class _ExpressionListResult {
  const _ExpressionListResult({
    required this.registers,
    required this.temporaries,
  });

  final List<int> registers;
  final List<int> temporaries;
}

class _PrototypeContext {
  _PrototypeContext(
    this.builder, {
    this.parent,
    List<String> parameterNames = const <String>[],
    this.isVararg = false,
  }) : emitter = BytecodeEmitter(builder),
       _localScopes = <Map<String, int>>[<String, int>{}],
       _toBeClosedScopes = <List<int>>[<int>[]],
       _nextRegister = parameterNames.length,
       _maxRegister = parameterNames.length {
    builder.paramCount = parameterNames.length;
    builder.isVararg = isVararg;

    for (var i = 0; i < parameterNames.length; i++) {
      _localScopes.last[parameterNames[i]] = i;
    }

    if (isVararg) {
      _emitVarargPrep(parameterNames.length);
    }
  }

  final BytecodePrototypeBuilder builder;
  final BytecodeEmitter emitter;
  final _PrototypeContext? parent;
  final bool isVararg;

  bool hasExplicitReturn = false;

  int _nextRegister;
  int _maxRegister;
  final List<Map<String, int>> _localScopes;
  final List<List<int>> _toBeClosedScopes;
  final Map<String, int> _upvalues = <String, int>{};

  void _pushLocalScope() {
    _localScopes.add(<String, int>{});
    _toBeClosedScopes.add(<int>[]);
  }

  void _popLocalScope() {
    assert(_localScopes.length > 1, 'Cannot pop the root scope');
    final closables = _toBeClosedScopes.removeLast();
    if (closables.isNotEmpty) {
      closables.sort();
      emitter.emitABC(
        opcode: BytecodeOpcode.close,
        a: closables.first,
        b: 0,
        c: 0,
      );
    }
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

  void _recordToBeClosed(int register) {
    _toBeClosedScopes.last.add(register);
  }

  int? _lowestActiveToBeClosedRegister() {
    int? minReg;
    for (final scope in _toBeClosedScopes) {
      for (final reg in scope) {
        if (minReg == null || reg < minReg) {
          minReg = reg;
        }
      }
    }
    return minReg;
  }

  bool _emitCloseForActiveToBeClosed({bool clear = false}) {
    final minReg = _lowestActiveToBeClosedRegister();
    if (minReg == null) {
      return false;
    }
    emitter.emitABC(opcode: BytecodeOpcode.close, a: minReg, b: 0, c: 0);
    if (clear) {
      for (final scope in _toBeClosedScopes) {
        scope.clear();
      }
    }
    return true;
  }

  void _emitVarargPrep(int fixedParamCount) {
    emitter.emitABC(
      opcode: BytecodeOpcode.varArgPrep,
      a: fixedParamCount,
      b: 0,
      c: 0,
    );
  }

  void _ensureVarargAvailable() {
    if (!isVararg) {
      throw UnsupportedError(
        'Varargs are not available in the current function context.',
      );
    }
  }

  int? _resolveUpvalueIndex(String name) {
    final existing = _upvalues[name];
    if (existing != null) {
      return existing;
    }
    final resolved = parent?._ensureUpvalueForChild(name);
    if (resolved == null) {
      return null;
    }
    final index = builder.upvalueDescriptors.length;
    builder.upvalueDescriptors.add(
      BytecodeUpvalueDescriptor(
        inStack: resolved.inStack ? 1 : 0,
        index: resolved.index,
      ),
    );
    _upvalues[name] = index;
    return index;
  }

  _UpvalueReference? _ensureUpvalueForChild(String name) {
    final localRegister = _lookupLocal(name);
    if (localRegister != null) {
      return _UpvalueReference(inStack: true, index: localRegister);
    }

    final existing = _upvalues[name];
    if (existing != null) {
      return _UpvalueReference(inStack: false, index: existing);
    }

    final ancestor = parent?._ensureUpvalueForChild(name);
    if (ancestor == null) {
      return null;
    }

    final index = builder.upvalueDescriptors.length;
    builder.upvalueDescriptors.add(
      BytecodeUpvalueDescriptor(
        inStack: ancestor.inStack ? 1 : 0,
        index: ancestor.index,
      ),
    );
    _upvalues[name] = index;
    return _UpvalueReference(inStack: false, index: index);
  }

  bool emitStatement(AstNode node) {
    switch (node) {
      case ReturnStatement():
        _emitReturn(node);
        return true;
      case Assignment():
        _emitAssignment(node);
        return false;
      case IfStatement():
        return _emitIfStatement(node);
      case WhileStatement():
        _emitWhileStatement(node);
        return false;
      case ForLoop():
        _emitForLoop(node);
        return false;
      case ForInLoop():
        _emitForInLoop(node);
        return false;
      case FunctionDef():
        _emitFunctionDef(node);
        return false;
      case LocalFunctionDef():
        _emitLocalFunctionDef(node);
        return false;
      case LocalDeclaration():
        _emitLocalDeclaration(node);
        return false;
      case ExpressionStatement(:final expr):
        if (expr is FunctionCall) {
          _emitFunctionCall(expr, discardResult: true);
        } else if (expr is MethodCall) {
          _emitMethodCall(expr, discardResult: true);
        } else {
          final reg = _emitExpression(expr);
          _releaseRegister(reg);
        }
        return false;
      case DoBlock():
        return _emitDoBlock(node);
      case AssignmentIndexAccessExpr():
        _emitAssignmentIndexAccessExpr(node);
        return false;
      default:
        throw UnsupportedError(
          'Bytecode compiler does not yet support statement type: '
          '${node.runtimeType}',
        );
    }
    return false;
  }

  void _emitReturn(ReturnStatement node) {
    hasExplicitReturn = true;
    _emitCloseForActiveToBeClosed(clear: true);

    if (node.expr.isEmpty) {
      emitter.emitABC(opcode: BytecodeOpcode.return0, a: 0, b: 0, c: 0);
      return;
    }

    if (node.expr.length == 1) {
      final expression = node.expr.first;
      if (expression is FunctionCall) {
        _emitFunctionCall(expression, discardResult: false, asTailCall: true);
        return;
      }

      if (expression is MethodCall) {
        _emitMethodCall(expression, discardResult: false, asTailCall: true);
        return;
      }

      if (expression is VarArg) {
        final reg = _emitVarArg(resultCount: 0);
        emitter.emitABC(opcode: BytecodeOpcode.ret, a: reg, b: 0, c: 0);
        return;
      }

      final reg = _emitExpression(expression, target: 0);
      emitter.emitABC(opcode: BytecodeOpcode.return1, a: reg, b: 0, c: 0);
      return;
    }

    final valueRegs = <int>[];
    var capturesAll = false;

    for (var i = 0; i < node.expr.length; i++) {
      final expr = node.expr[i];
      final isLast = i == node.expr.length - 1;

      if (!isLast) {
        final reg = _emitExpression(expr);
        valueRegs.add(reg);
        continue;
      }

      if (expr is FunctionCall) {
        final call = _emitFunctionCall(expr, captureAll: true);
        valueRegs.add(call.base);
        capturesAll = true;
        continue;
      }

      if (expr is MethodCall) {
        final call = _emitMethodCall(expr, captureAll: true);
        valueRegs.add(call.base);
        capturesAll = true;
        continue;
      }

      if (expr is VarArg) {
        final reg = _emitVarArg(resultCount: 0);
        valueRegs.add(reg);
        capturesAll = true;
        continue;
      }

      final reg = _emitExpression(expr);
      valueRegs.add(reg);
    }

    final returnBase = valueRegs.first;
    if (capturesAll) {
      final fixedCount = valueRegs.length - 1;
      emitter.emitABC(
        opcode: BytecodeOpcode.ret,
        a: returnBase,
        b: 0,
        c: fixedCount,
      );
      return;
    }

    final valueCount = valueRegs.length;
    emitter.emitABC(
      opcode: BytecodeOpcode.ret,
      a: returnBase,
      b: valueCount + 1,
      c: 0,
    );
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
        final upvalueIndex = _resolveUpvalueIndex(name);
        if (upvalueIndex != null) {
          final dest = _materializeRegister(target);
          emitter.emitABC(
            opcode: BytecodeOpcode.getUpval,
            a: dest,
            b: upvalueIndex,
            c: 0,
          );
          return dest;
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
      case TableConstructor():
        return _emitTableConstructor(node, target: target);
      case FunctionCall():
        return _useCallResult(_emitFunctionCall(node), target: target);
      case MethodCall():
        return _useCallResult(_emitMethodCall(node), target: target);
      case TableAccessExpr():
        final index = node.index;
        if (index is Identifier) {
          return _emitTableFieldAccess(
            TableFieldAccess(node.table, index),
            target: target,
          );
        }
        return _emitTableIndexAccess(node.table, index, target: target);
      case FunctionLiteral():
        return _emitFunctionLiteral(node, target: target);
      case VarArg():
        return _emitVarArg(target: target);
      default:
        throw UnsupportedError(
          'Bytecode compiler does not yet support expression type: '
          '${node.runtimeType}',
        );
    }
  }

  void _emitSingleAssignment(AstNode target, AstNode valueNode) {
    switch (target) {
      case Identifier(:final name):
        _emitIdentifierAssignment(name, valueNode);
        return;
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

  void _emitAssignment(Assignment node) {
    if (node.targets.length == 1 && node.exprs.length == 1) {
      _emitSingleAssignment(node.targets.single, node.exprs.single);
      return;
    }

    if (node.targets.any((target) => target is! Identifier)) {
      throw UnsupportedError(
        'Bytecode compiler does not yet support multi-target assignments with '
        'non-identifier targets.',
      );
    }

    final identifiers = node.targets.cast<Identifier>();
    final result = _emitAssignmentValues(node.exprs, identifiers.length);
    final protected = <int>{};

    for (var i = 0; i < identifiers.length; i++) {
      final identifier = identifiers[i];
      final valueReg = result.registers[i];
      final name = identifier.name;
      final localReg = _lookupLocal(name);
      if (localReg != null) {
        if (localReg != valueReg) {
          emitter.emitABC(
            opcode: BytecodeOpcode.move,
            a: localReg,
            b: valueReg,
            c: 0,
          );
        } else {
          protected.add(valueReg);
        }
        continue;
      }

      final upvalueIndex = _resolveUpvalueIndex(name);
      if (upvalueIndex != null) {
        emitter.emitABC(
          opcode: BytecodeOpcode.setUpval,
          a: 0,
          b: upvalueIndex,
          c: valueReg,
        );
        continue;
      }

      final constantIndex = _ensureConstantIndex(name);
      emitter.emitABC(
        opcode: BytecodeOpcode.setTabUp,
        a: 0,
        b: constantIndex,
        c: valueReg,
      );
    }

    for (var i = result.temporaries.length - 1; i >= 0; i--) {
      final reg = result.temporaries[i];
      if (protected.contains(reg)) {
        continue;
      }
      _releaseRegister(reg);
    }
  }

  void _emitLocalDeclaration(LocalDeclaration node) {
    final nameCount = node.names.length;
    if (nameCount == 0) {
      return;
    }

    final closableIndices = <int>[];
    for (var i = 0; i < node.attributes.length; i++) {
      final attribute = node.attributes[i];
      if (attribute.isEmpty) {
        continue;
      }
      if (attribute == 'close') {
        closableIndices.add(i);
        continue;
      }
      throw UnsupportedError(
        'Bytecode compiler does not yet support local declaration attribute '
        '<$attribute>.',
      );
    }

    if (closableIndices.length > 1) {
      throw UnsupportedError(
        'a list of variables can contain at most one to-be-closed variable',
      );
    }

    if (closableIndices.isNotEmpty && closableIndices.first != nameCount - 1) {
      throw UnsupportedError(
        'to-be-closed variable must be the last name in the declaration.',
      );
    }

    final targetRegs = <int>[];
    for (final identifier in node.names) {
      final register = _allocateRegister();
      _declareLocal(identifier.name, register);
      targetRegs.add(register);
    }

    final result = _emitAssignmentValues(node.exprs, nameCount);
    final protected = <int>{};

    for (var i = 0; i < nameCount; i++) {
      final targetReg = targetRegs[i];
      final valueReg = result.registers[i];
      if (targetReg != valueReg) {
        emitter.emitABC(
          opcode: BytecodeOpcode.move,
          a: targetReg,
          b: valueReg,
          c: 0,
        );
      } else {
        protected.add(valueReg);
      }
    }

    if (closableIndices.isNotEmpty) {
      final reg = targetRegs[closableIndices.first];
      emitter.emitABC(opcode: BytecodeOpcode.tbc, a: reg, b: 0, c: 0);
      _recordToBeClosed(reg);
    }

    for (var i = result.temporaries.length - 1; i >= 0; i--) {
      final reg = result.temporaries[i];
      if (protected.contains(reg)) {
        continue;
      }
      _releaseRegister(reg);
    }
  }

  bool _emitDoBlock(DoBlock node) {
    return _emitBlock(node.body);
  }

  void _emitAssignmentIndexAccessExpr(AssignmentIndexAccessExpr node) {
    _emitTableIndexAssignment(node.target, node.index, node.value);
  }

  int _emitTableConstructor(TableConstructor node, {int? target}) {
    final hints = _computeTableConstructorHints(node);
    final tableReg = _materializeRegister(target);
    final arrayHint = hints.arraySlots.clamp(0, 0xFF).toInt();
    final hashHint = hints.hashSlots.clamp(0, 0xFF).toInt();
    emitter.emitABC(
      opcode: BytecodeOpcode.newTable,
      a: tableReg,
      b: arrayHint,
      c: hashHint,
    );

    var arrayIndex = 1;
    var pendingCount = 0;
    var pendingStart = -1;

    void flushPending() {
      if (pendingCount == 0) {
        return;
      }
      emitter.emitABC(
        opcode: BytecodeOpcode.setList,
        a: tableReg,
        b: pendingCount,
        c: arrayIndex,
      );
      for (var i = pendingCount - 1; i >= 0; i--) {
        _releaseRegister(pendingStart + i);
      }
      arrayIndex += pendingCount;
      pendingCount = 0;
      pendingStart = -1;
    }

    bool isExpandableTail(TableEntry entry, int entryIndex) {
      if (entryIndex != node.entries.length - 1) {
        return false;
      }
      if (entry case TableEntryLiteral(expr: final expr)) {
        return expr is VarArg || expr is FunctionCall || expr is MethodCall;
      }
      return false;
    }

    void expandTail(TableEntryLiteral entry) {
      final expr = entry.expr;
      final baseRegister = tableReg + 1;
      if (expr is VarArg) {
        _emitVarArg(target: baseRegister, resultCount: 0);
      } else if (expr is FunctionCall) {
        _emitFunctionCall(expr, captureAll: true, baseRegister: baseRegister);
      } else if (expr is MethodCall) {
        _emitMethodCall(expr, captureAll: true, baseRegister: baseRegister);
      } else {
        throw UnsupportedError(
          'Unexpected expandable tail expression: ${expr.runtimeType}',
        );
      }

      emitter.emitABC(
        opcode: BytecodeOpcode.setList,
        a: tableReg,
        b: 0,
        c: arrayIndex,
      );

      while (_nextRegister > baseRegister) {
        _releaseRegister(_nextRegister - 1);
      }
    }

    for (var i = 0; i < node.entries.length; i++) {
      final entry = node.entries[i];
      if (entry is TableEntryLiteral) {
        if (isExpandableTail(entry, i)) {
          flushPending();
          expandTail(entry);
          arrayIndex = -1;
          break;
        }
        final targetReg = tableReg + 1 + pendingCount;
        _emitExpression(entry.expr, target: targetReg);
        if (pendingStart == -1) {
          pendingStart = targetReg;
        }
        pendingCount += 1;
        if (pendingCount == 50) {
          flushPending();
        }
        continue;
      }

      flushPending();

      switch (entry) {
        case KeyedTableEntry():
          final key = entry.key;
          int? fieldIndex;
          int? keyReg;
          if (key is Identifier) {
            fieldIndex = _ensureConstantIndex(key.name);
          } else {
            keyReg = _emitExpression(key);
          }
          final valueReg = _emitExpression(entry.value);
          if (fieldIndex != null) {
            emitter.emitABC(
              opcode: BytecodeOpcode.setField,
              a: tableReg,
              b: fieldIndex,
              c: valueReg,
            );
            _releaseRegister(valueReg);
          } else {
            emitter.emitABC(
              opcode: BytecodeOpcode.setTable,
              a: tableReg,
              b: keyReg!,
              c: valueReg,
            );
            _releaseRegister(valueReg);
            _releaseRegister(keyReg);
          }
          break;
        case IndexedTableEntry():
          final keyReg = _emitExpression(entry.key);
          final valueReg = _emitExpression(entry.value);
          emitter.emitABC(
            opcode: BytecodeOpcode.setTable,
            a: tableReg,
            b: keyReg,
            c: valueReg,
          );
          _releaseRegister(valueReg);
          _releaseRegister(keyReg);
          break;
        default:
          throw UnsupportedError(
            'Unsupported table entry type: ${entry.runtimeType}',
          );
      }
    }

    flushPending();
    return tableReg;
  }

  void _emitTableFieldAssignment(TableFieldAccess target, AstNode valueNode) {
    final fieldIndex = _ensureConstantIndex(target.fieldName.name);
    if (_isEnvIdentifier(target.table)) {
      final valueReg = _emitExpression(valueNode);
      emitter.emitABC(
        opcode: BytecodeOpcode.setTabUp,
        a: 0,
        b: fieldIndex,
        c: valueReg,
      );
      _releaseRegister(valueReg);
      return;
    }

    final tableReg = _emitExpression(target.table);
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

    if (_isEnvIdentifier(tableNode) && indexNode is StringLiteral) {
      final fieldName = String.fromCharCodes(indexNode.bytes);
      final fieldIndex = _ensureConstantIndex(fieldName);
      final valueReg = _emitExpression(valueNode);
      emitter.emitABC(
        opcode: BytecodeOpcode.setTabUp,
        a: 0,
        b: fieldIndex,
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

  void _emitIdentifierAssignment(String name, AstNode valueNode) {
    final localReg = _lookupLocal(name);
    if (localReg != null) {
      _emitExpression(valueNode, target: localReg);
      return;
    }

    final upvalueIndex = _resolveUpvalueIndex(name);
    if (upvalueIndex != null) {
      final valueReg = _emitExpression(valueNode);
      emitter.emitABC(
        opcode: BytecodeOpcode.setUpval,
        a: 0,
        b: upvalueIndex,
        c: valueReg,
      );
      _releaseRegister(valueReg);
      return;
    }

    final valueReg = _emitExpression(valueNode);
    final constantIndex = _ensureConstantIndex(name);
    emitter.emitABC(
      opcode: BytecodeOpcode.setTabUp,
      a: 0,
      b: constantIndex,
      c: valueReg,
    );
    _releaseRegister(valueReg);
  }

  bool _emitIfStatement(IfStatement node) {
    final exitJumps = <int>[];
    final falseJump = _emitConditionJump(node.cond, jumpWhenTrue: false);
    final thenReturns = _emitBlock(node.thenBlock);
    exitJumps.add(_emitJumpPlaceholder());
    _patchJump(falseJump, _currentInstructionIndex);

    var allBranchesReturn = thenReturns;

    for (final clause in node.elseIfs) {
      final clauseFalseJump = _emitConditionJump(
        clause.cond,
        jumpWhenTrue: false,
      );
      final clauseReturns = _emitBlock(clause.thenBlock);
      allBranchesReturn = allBranchesReturn && clauseReturns;
      exitJumps.add(_emitJumpPlaceholder());
      _patchJump(clauseFalseJump, _currentInstructionIndex);
    }

    if (node.elseBlock.isNotEmpty) {
      final elseReturns = _emitBlock(node.elseBlock);
      allBranchesReturn = allBranchesReturn && elseReturns;
    } else {
      allBranchesReturn = false;
    }

    final endIndex = _currentInstructionIndex;
    for (final jump in exitJumps) {
      _patchJump(jump, endIndex);
    }

    return allBranchesReturn;
  }

  void _emitWhileStatement(WhileStatement node) {
    final loopStart = _currentInstructionIndex;
    final exitJump = _emitConditionJump(node.cond, jumpWhenTrue: false);
    _emitBlock(node.body, useNewScope: true);

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

    _emitExpression(node.stepExpr, target: stepReg);

    emitter.emitABC(opcode: BytecodeOpcode.move, a: controlReg, b: base, c: 0);

    final forPrepIndex = emitter.emitAsBx(
      opcode: BytecodeOpcode.forPrep,
      a: base,
      sBx: 0,
    );

    final bodyStart = _currentInstructionIndex;

    _pushLocalScope();
    _declareLocal(node.varName.name, controlReg);
    _emitBlock(node.body, useNewScope: false);
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
    _emitBlock(node.body, useNewScope: false);
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

  void _emitFunctionDef(FunctionDef node) {
    final register = _allocateRegister();
    final prototypeIndex = _compileFunctionBody(node.body);
    emitter.emitABx(
      opcode: BytecodeOpcode.closure,
      a: register,
      bx: prototypeIndex,
    );

    final rest = node.name.rest;
    if (!node.implicitSelf && rest.isEmpty) {
      final constantIndex = _ensureConstantIndex(node.name.first.name);
      emitter.emitABC(
        opcode: BytecodeOpcode.setTabUp,
        a: 0,
        b: constantIndex,
        c: register,
      );
      _releaseRegister(register);
      return;
    }

    late final String fieldName;
    final tablePath = <Identifier>[];

    if (node.implicitSelf) {
      fieldName = node.name.method!.name;
      tablePath.add(node.name.first);
      tablePath.addAll(rest);
    } else {
      fieldName = rest.last.name;
      tablePath.add(node.name.first);
      tablePath.addAll(rest.take(rest.length - 1));
    }

    if (tablePath.isEmpty) {
      final constantIndex = _ensureConstantIndex(fieldName);
      emitter.emitABC(
        opcode: BytecodeOpcode.setTabUp,
        a: 0,
        b: constantIndex,
        c: register,
      );
      _releaseRegister(register);
      return;
    }

    final usesEnv = tablePath.length == 1 && tablePath.first.name == '_ENV';
    final fieldIndex = _ensureConstantIndex(fieldName);

    if (usesEnv) {
      emitter.emitABC(
        opcode: BytecodeOpcode.setTabUp,
        a: 0,
        b: fieldIndex,
        c: register,
      );
      _releaseRegister(register);
      return;
    }

    final tableExpr = _buildTableExpression(tablePath);
    final tableReg = _emitExpression(tableExpr);
    emitter.emitABC(
      opcode: BytecodeOpcode.setField,
      a: tableReg,
      b: fieldIndex,
      c: register,
    );
    _releaseRegister(tableReg);
    _releaseRegister(register);
  }

  void _emitLocalFunctionDef(LocalFunctionDef node) {
    final register = _allocateRegister();
    _declareLocal(node.name.name, register);
    final prototypeIndex = _compileFunctionBody(node.funcBody);
    emitter.emitABx(
      opcode: BytecodeOpcode.closure,
      a: register,
      bx: prototypeIndex,
    );
  }

  int _compileFunctionBody(FunctionBody body) {
    final positionalParams = <String>[
      for (final param in body.parameters ?? const <Identifier>[]) param.name,
    ];

    if (body.implicitSelf) {
      if (positionalParams.isEmpty || positionalParams.first != 'self') {
        positionalParams.insert(0, 'self');
      }
    }

    final childBuilder = builder.createChild();
    final childContext = _PrototypeContext(
      childBuilder.builder,
      parent: this,
      parameterNames: positionalParams,
      isVararg: body.isVararg,
    );

    for (final statement in body.body) {
      childContext.emitStatement(statement);
      if (childContext.hasExplicitReturn) {
        break;
      }
    }
    childContext.finalize();
    return childBuilder.index;
  }

  int _emitFunctionLiteral(FunctionLiteral node, {int? target}) {
    final register = _materializeRegister(target);
    final prototypeIndex = _compileFunctionBody(node.funcBody);
    emitter.emitABx(
      opcode: BytecodeOpcode.closure,
      a: register,
      bx: prototypeIndex,
    );
    return register;
  }

  int _emitVarArg({int? target, int resultCount = 1}) {
    _ensureVarargAvailable();
    final register = _materializeRegister(target);
    final bOperand = resultCount == 0 ? 0 : resultCount + 1;
    emitter.emitABC(
      opcode: BytecodeOpcode.varArg,
      a: register,
      b: bOperand,
      c: 0,
    );
    return register;
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

  bool _emitBlock(List<AstNode> statements, {bool useNewScope = true}) {
    var returned = false;
    if (useNewScope) {
      _pushLocalScope();
    }
    for (final statement in statements) {
      if (emitStatement(statement)) {
        returned = true;
        break;
      }
    }
    if (useNewScope) {
      _popLocalScope();
    }
    return returned;
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

  _CallEmissionResult _emitFunctionCall(
    FunctionCall node, {
    bool discardResult = false,
    bool asTailCall = false,
    int? resultCount,
    bool captureAll = false,
    int? baseRegister,
  }) {
    assert(
      !(captureAll && resultCount != null),
      'Cannot request a fixed result count when capturing all results.',
    );

    final base = baseRegister != null
        ? _ensureRegister(baseRegister)
        : _allocateRegister();
    _emitExpression(node.name, target: base);

    final argRegs = <int>[];
    var hasVariadicArgs = false;
    for (var i = 0; i < node.args.length; i++) {
      final argument = node.args[i];
      final reg = _allocateRegister();
      argRegs.add(reg);
      final isLastArg = i == node.args.length - 1;
      if (argument is VarArg) {
        final requested = isLastArg ? 0 : 1;
        _emitVarArg(target: reg, resultCount: requested);
        if (requested == 0) {
          hasVariadicArgs = true;
        }
      } else {
        _emitExpression(argument, target: reg);
      }
    }

    final bOperand = hasVariadicArgs ? 0 : argRegs.length + 1;
    final opcode = asTailCall ? BytecodeOpcode.tailCall : BytecodeOpcode.call;

    int producedResults = 0;
    final int cOperand;
    if (asTailCall) {
      cOperand = 0;
    } else if (discardResult) {
      cOperand = 1;
    } else if (captureAll) {
      cOperand = 0;
    } else {
      final requested = resultCount ?? 1;
      cOperand = requested + 1;
      producedResults = requested;
    }

    emitter.emitABC(opcode: opcode, a: base, b: bOperand, c: cOperand);

    for (var i = argRegs.length - 1; i >= 0; i--) {
      _releaseRegister(argRegs[i]);
    }

    if (hasVariadicArgs) {
      while (_nextRegister > base) {
        _releaseRegister(_nextRegister - 1);
      }
    }

    if (asTailCall || discardResult) {
      _releaseRegister(base);
    } else if (!captureAll) {
      final requested = resultCount ?? 1;
      if (requested > 1) {
        _ensureRegister(base + requested - 1);
      }
    }

    return _CallEmissionResult(
      base: base,
      resultCount: producedResults,
      capturesAll: captureAll || asTailCall,
    );
  }

  _CallEmissionResult _emitMethodCall(
    MethodCall node, {
    bool discardResult = false,
    bool asTailCall = false,
    int? resultCount,
    bool captureAll = false,
    int? baseRegister,
  }) {
    final objectReg = _emitExpression(node.prefix);
    if (node.methodName is! Identifier) {
      throw UnsupportedError(
        'Bytecode compiler requires identifier method names for method calls.',
      );
    }

    final methodIdentifier = node.methodName as Identifier;
    final funcReg = baseRegister != null
        ? _ensureRegister(baseRegister)
        : objectReg;
    final fieldIndex = _ensureConstantIndex(methodIdentifier.name);

    final argRegs = <int>[];
    var hasVariadicArgs = false;
    final selfReg = _allocateRegister();
    emitter.emitABC(
      opcode: BytecodeOpcode.move,
      a: selfReg,
      b: objectReg,
      c: 0,
    );
    argRegs.add(selfReg);

    emitter.emitABC(
      opcode: BytecodeOpcode.getField,
      a: funcReg,
      b: selfReg,
      c: fieldIndex,
    );

    for (var i = 0; i < node.args.length; i++) {
      final reg = _allocateRegister();
      argRegs.add(reg);
      final argument = node.args[i];
      final isLastArg = i == node.args.length - 1;
      if (argument is VarArg) {
        final requested = isLastArg ? 0 : 1;
        _emitVarArg(target: reg, resultCount: requested);
        if (requested == 0) {
          hasVariadicArgs = true;
        }
      } else {
        _emitExpression(argument, target: reg);
      }
    }

    final opcode = asTailCall ? BytecodeOpcode.tailCall : BytecodeOpcode.call;
    final bOperand = hasVariadicArgs ? 0 : argRegs.length + 1;

    int producedResults = 0;
    final int cOperand;
    if (asTailCall) {
      cOperand = 0;
    } else if (discardResult) {
      cOperand = 1;
    } else if (captureAll) {
      cOperand = 0;
    } else {
      final requested = resultCount ?? 1;
      cOperand = requested + 1;
      producedResults = requested;
    }

    emitter.emitABC(opcode: opcode, a: funcReg, b: bOperand, c: cOperand);

    for (var i = argRegs.length - 1; i >= 0; i--) {
      _releaseRegister(argRegs[i]);
    }

    if (hasVariadicArgs) {
      while (_nextRegister > funcReg) {
        _releaseRegister(_nextRegister - 1);
      }
    }

    if (asTailCall || discardResult) {
      _releaseRegister(funcReg);
    } else if (!captureAll) {
      final requested = resultCount ?? 1;
      if (requested > 1) {
        _ensureRegister(funcReg + requested - 1);
      }
    }

    if (funcReg != objectReg) {
      _releaseRegister(objectReg);
    }

    return _CallEmissionResult(
      base: funcReg,
      resultCount: producedResults,
      capturesAll: captureAll || asTailCall,
    );
  }

  int _useCallResult(_CallEmissionResult call, {int? target}) {
    final base = call.base;
    if (target != null) {
      final dest = _materializeRegister(target);
      if (dest != base) {
        emitter.emitABC(opcode: BytecodeOpcode.move, a: dest, b: base, c: 0);
        _releaseRegister(base);
      }
      return dest;
    }
    return base;
  }

  void _emitExpressionAndDiscard(AstNode expr) {
    switch (expr) {
      case FunctionCall():
        _emitFunctionCall(expr, discardResult: true);
        return;
      case MethodCall():
        _emitMethodCall(expr, discardResult: true);
        return;
      case VarArg():
        final reg = _emitVarArg();
        _releaseRegister(reg);
        return;
      default:
        final reg = _emitExpression(expr);
        _releaseRegister(reg);
    }
  }

  _ExpressionListResult _emitAssignmentValues(
    List<AstNode> exprs,
    int targetCount,
  ) {
    final registers = <int>[];
    final temporaries = <int>[];

    for (var i = 0; i < exprs.length; i++) {
      final expr = exprs[i];
      final isLast = i == exprs.length - 1;
      final needValue = registers.length < targetCount;
      final remainingTargets = targetCount - registers.length;

      if (!needValue) {
        _emitExpressionAndDiscard(expr);
        continue;
      }

      if (isLast && expr is FunctionCall) {
        final call = _emitFunctionCall(expr, resultCount: remainingTargets);
        final base = call.base;
        if (remainingTargets > 1) {
          _ensureRegister(base + remainingTargets - 1);
        }
        for (var offset = 0; offset < remainingTargets; offset++) {
          registers.add(base + offset);
          temporaries.add(base + offset);
        }
        continue;
      }

      if (isLast && expr is MethodCall) {
        final call = _emitMethodCall(expr, resultCount: remainingTargets);
        final base = call.base;
        if (remainingTargets > 1) {
          _ensureRegister(base + remainingTargets - 1);
        }
        for (var offset = 0; offset < remainingTargets; offset++) {
          registers.add(base + offset);
          temporaries.add(base + offset);
        }
        continue;
      }

      if (isLast && expr is VarArg) {
        final resultReg = _emitVarArg(resultCount: remainingTargets);
        if (remainingTargets > 1) {
          _ensureRegister(resultReg + remainingTargets - 1);
        }
        for (var offset = 0; offset < remainingTargets; offset++) {
          registers.add(resultReg + offset);
          temporaries.add(resultReg + offset);
        }
        continue;
      }

      final reg = _emitExpression(expr);
      registers.add(reg);
      temporaries.add(reg);
    }

    while (registers.length < targetCount) {
      final reg = _allocateRegister();
      emitter.emitABC(opcode: BytecodeOpcode.loadNil, a: reg, b: 0, c: 0);
      registers.add(reg);
      temporaries.add(reg);
    }

    return _ExpressionListResult(
      registers: registers,
      temporaries: temporaries,
    );
  }

  int _emitBinaryExpression(BinaryExpression node, {int? target}) {
    if (node.op == 'and' || node.op == 'or') {
      return _emitLogicalBinaryExpression(node, target: target);
    }

    if (node.op == '..') {
      return _emitConcatenation(node, target: target);
    }

    final literalValue = _literalValue(node.right);
    final leftReg = _emitExpression(node.left, target: target);

    if (literalValue case int intLiteral) {
      if (node.op == '<<' && intLiteral >= 0 && intLiteral <= 255) {
        emitter.emitABC(
          opcode: BytecodeOpcode.shlI,
          a: leftReg,
          b: leftReg,
          c: intLiteral & 0x1FF,
        );
        return leftReg;
      }
      if (node.op == '>>' && intLiteral >= 0 && intLiteral <= 255) {
        emitter.emitABC(
          opcode: BytecodeOpcode.shrI,
          a: leftReg,
          b: leftReg,
          c: intLiteral & 0x1FF,
        );
        return leftReg;
      }
    }

    if (literalValue case num numericValue) {
      final opcode = _opcodeForBinaryConstant(node.op);
      if (opcode != null) {
        final constantIndex = _ensureConstantIndex(numericValue);
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

  int _emitConcatenation(BinaryExpression node, {int? target}) {
    final operands = <AstNode>[];

    void collect(AstNode expr) {
      if (expr is BinaryExpression && expr.op == '..') {
        collect(expr.left);
        collect(expr.right);
      } else {
        operands.add(expr);
      }
    }

    collect(node);

    if (operands.isEmpty) {
      throw StateError('Concatenation requires at least one operand.');
    }

    final firstReg = _emitExpression(operands.first, target: target);
    final tempRegs = <int>[];

    for (var i = 1; i < operands.length; i++) {
      tempRegs.add(_emitExpression(operands[i]));
    }

    final lastReg = tempRegs.isEmpty ? firstReg : tempRegs.last;
    emitter.emitABC(
      opcode: BytecodeOpcode.concat,
      a: firstReg,
      b: firstReg,
      c: lastReg,
    );

    for (var i = tempRegs.length - 1; i >= 0; i--) {
      _releaseRegister(tempRegs[i]);
    }

    return firstReg;
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
      '..' => BytecodeOpcode.concat,
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
      '&' => BytecodeOpcode.bandK,
      '|' => BytecodeOpcode.borK,
      '~' => BytecodeOpcode.bxorK,
      _ => null,
    };
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

  bool _isEnvIdentifier(AstNode node) {
    return node is Identifier && node.name == '_ENV';
  }

  AstNode _buildTableExpression(List<Identifier> path) {
    if (path.isEmpty) {
      throw ArgumentError('Table path must contain at least one segment.');
    }
    AstNode expr = Identifier(path.first.name);
    for (var i = 1; i < path.length; i++) {
      expr = TableFieldAccess(expr, Identifier(path[i].name));
    }
    return expr;
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
      _emitCloseForActiveToBeClosed(clear: true);
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

class _TableConstructorHints {
  const _TableConstructorHints({
    required this.arraySlots,
    required this.hashSlots,
  });

  final int arraySlots;
  final int hashSlots;
}

_TableConstructorHints _computeTableConstructorHints(TableConstructor node) {
  var arraySlots = 0;
  var hashSlots = 0;

  for (var i = 0; i < node.entries.length; i++) {
    final entry = node.entries[i];
    if (entry is TableEntryLiteral) {
      final expr = entry.expr;
      final isTailExpandable =
          i == node.entries.length - 1 &&
          (expr is VarArg || expr is FunctionCall || expr is MethodCall);
      if (!isTailExpandable) {
        arraySlots += 1;
      }
    } else if (entry is KeyedTableEntry || entry is IndexedTableEntry) {
      hashSlots += 1;
    }
  }

  return _TableConstructorHints(arraySlots: arraySlots, hashSlots: hashSlots);
}

class _UpvalueReference {
  const _UpvalueReference({required this.inStack, required this.index});

  final bool inStack;
  final int index;
}
