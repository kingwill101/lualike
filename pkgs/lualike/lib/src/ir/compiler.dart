import 'package:lualike/src/ast.dart';

import 'chunk_builder.dart';
import 'emitter.dart';
import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';

/// Compiles AST programs into lualike IR chunks understood by the upcoming VM.
///
/// The initial implementation focuses on a restricted subset (literal
/// expressions, expression statements, and basic return statements) to validate
/// the lualike IR infrastructure. Coverage will expand incrementally as we port
/// additional interpreter features.
class LualikeIrCompiler {
  LualikeIrChunk compile(Program program) {
    final chunkBuilder = LualikeIrChunkBuilder();
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

abstract class _AssignmentTargetPlan {
  _AssignmentTargetPlan({required List<int> temporaries})
    : temporaries = List<int>.unmodifiable(temporaries);

  final List<int> temporaries;
}

class _IdentifierAssignmentPlan extends _AssignmentTargetPlan {
  _IdentifierAssignmentPlan(this.name) : super(temporaries: const []);

  final String name;
}

class _EnvFieldAssignmentPlan extends _AssignmentTargetPlan {
  _EnvFieldAssignmentPlan({
    required this.fieldConstIndex,
    List<int> temporaries = const [],
  }) : super(temporaries: temporaries);

  final int fieldConstIndex;
}

class _TableFieldAssignmentPlan extends _AssignmentTargetPlan {
  _TableFieldAssignmentPlan({
    required this.tableReg,
    required this.fieldConstIndex,
    List<int> temporaries = const [],
  }) : super(temporaries: temporaries);

  final int tableReg;
  final int fieldConstIndex;
}

class _TableIndexAssignmentPlan extends _AssignmentTargetPlan {
  _TableIndexAssignmentPlan({
    required this.tableReg,
    this.indexReg,
    this.numericIndex,
    List<int> temporaries = const [],
  }) : super(temporaries: temporaries);

  final int tableReg;
  final int? indexReg;
  final int? numericIndex;
}

class _PrototypeContext {
  _PrototypeContext(
    this.builder, {
    this.parent,
    List<String> parameterNames = const <String>[],
    this.isVararg = false,
  }) : emitter = LualikeIrEmitter(builder),
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

  final LualikeIrPrototypeBuilder builder;
  final LualikeIrEmitter emitter;
  final _PrototypeContext? parent;
  final bool isVararg;

  bool hasExplicitReturn = false;

  int _nextRegister;
  int _maxRegister;
  final List<Map<String, int>> _localScopes;
  final List<List<int>> _toBeClosedScopes;
  final Map<String, int> _upvalues = <String, int>{};
  final Map<String, int> _labelPositions = <String, int>{};
  final List<_PendingGoto> _pendingGotos = <_PendingGoto>[];

  bool _isRegisterOccupiedByLocal(int reg) {
    for (final scope in _localScopes) {
      if (scope.containsValue(reg)) {
        return true;
      }
    }
    return false;
  }

  int _firstFreeRegister() {
    var maxReg = -1;
    for (final scope in _localScopes) {
      for (final reg in scope.values) {
        if (reg > maxReg) {
          maxReg = reg;
        }
      }
    }
    return maxReg + 1;
  }

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
        opcode: LualikeIrOpcode.close,
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

  bool _reassignLocalRegister(int oldRegister, int newRegister) {
    for (var i = _localScopes.length - 1; i >= 0; i--) {
      final scope = _localScopes[i];
      for (final entry in scope.entries) {
        if (entry.value == oldRegister) {
          scope[entry.key] = newRegister;
          return true;
        }
      }
    }
    return false;
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
    emitter.emitABC(opcode: LualikeIrOpcode.close, a: minReg, b: 0, c: 0);
    if (clear) {
      for (final scope in _toBeClosedScopes) {
        scope.clear();
      }
    }
    return true;
  }

  void _emitVarargPrep(int fixedParamCount) {
    emitter.emitABC(
      opcode: LualikeIrOpcode.varArgPrep,
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
      LualikeIrUpvalueDescriptor(
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
      if (localRegister >= builder.paramCount) {
        builder.upvalueDescriptors.add(
          LualikeIrUpvalueDescriptor(inStack: 1, index: localRegister),
        );
      }
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
      LualikeIrUpvalueDescriptor(
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
      case GlobalDeclaration():
        _emitGlobalDeclaration(node);
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
      case Label():
        _trackSource(node);
        _defineLabel(node.label.name);
        return false;
      case Goto():
        _emitGoto(node);
        return false;
      default:
        throw UnsupportedError(
          'Lualike IR compiler does not yet support statement type: '
          '${node.runtimeType}',
        );
    }
    return false;
  }

  void _emitReturn(ReturnStatement node) {
    _trackSource(node);
    hasExplicitReturn = true;
    _emitCloseForActiveToBeClosed(clear: true);

    if (node.expr.isEmpty) {
      emitter.emitABC(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0);
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
        emitter.emitABC(opcode: LualikeIrOpcode.ret, a: reg, b: 0, c: 0);
        return;
      }

      if (expression is FunctionLiteral) {
        final reg = _emitExpression(expression);
        emitter.emitABC(opcode: LualikeIrOpcode.return1, a: reg, b: 0, c: 0);
        return;
      }

      final reg = _emitExpression(expression, target: 0);
      emitter.emitABC(opcode: LualikeIrOpcode.return1, a: reg, b: 0, c: 0);
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
        opcode: LualikeIrOpcode.ret,
        a: returnBase,
        b: 0,
        c: fixedCount,
      );
      return;
    }

    final valueCount = valueRegs.length;
    emitter.emitABC(
      opcode: LualikeIrOpcode.ret,
      a: returnBase,
      b: valueCount + 1,
      c: 0,
    );
  }

  int _emitExpression(AstNode node, {int? target}) {
    _trackSource(node);
    if (node is BinaryExpression && node.op == '..') {
      return _emitConcatenation(node, target: target);
    }
    switch (node) {
      case NumberLiteral(:final value):
        final reg = _materializeRegister(target);
        final constant = value is int
            ? IntegerConstant(value)
            : NumberConstant(value.toDouble());
        final index = builder.addConstant(constant);
        emitter.emitABx(opcode: LualikeIrOpcode.loadK, a: reg, bx: index);
        return reg;
      case BooleanLiteral(:final value):
        final reg = _materializeRegister(target);
        emitter.emitABC(
          opcode: value ? LualikeIrOpcode.loadTrue : LualikeIrOpcode.loadFalse,
          a: reg,
          b: 0,
          c: 0,
        );
        return reg;
      case NilValue():
        final reg = _materializeRegister(target);
        emitter.emitABC(opcode: LualikeIrOpcode.loadNil, a: reg, b: 0, c: 0);
        return reg;
      case StringLiteral(:final bytes):
        final reg = _materializeRegister(target);
        final text = String.fromCharCodes(bytes);
        final constant = text.length <= 40
            ? ShortStringConstant(text)
            : LongStringConstant(text);
        final index = builder.addConstant(constant);
        emitter.emitABx(opcode: LualikeIrOpcode.loadK, a: reg, bx: index);
        return reg;
      case Identifier(:final name):
        final localReg = _lookupLocal(name);
        if (localReg != null) {
          if (target != null) {
            final dest = _materializeRegister(target);
            if (dest != localReg) {
              emitter.emitABC(
                opcode: LualikeIrOpcode.move,
                a: dest,
                b: localReg,
                c: 0,
              );
            }
            return dest;
          }
          final temp = _allocateRegister();
          emitter.emitABC(
            opcode: LualikeIrOpcode.move,
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
            opcode: LualikeIrOpcode.getUpval,
            a: dest,
            b: upvalueIndex,
            c: 0,
          );
          return dest;
        }
        final envField = _emitEnvFieldRead(name, target: target);
        if (envField != null) {
          return envField;
        }
        final reg = _materializeRegister(target);
        final constant = name.length <= 40
            ? ShortStringConstant(name)
            : LongStringConstant(name);
        final index = builder.addConstant(constant);
        emitter.emitABC(
          opcode: LualikeIrOpcode.getTabUp,
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
          'Lualike IR compiler does not yet support expression type: '
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
          'Lualike IR compiler does not yet support assignment target type: '
          '${target.runtimeType}',
        );
    }
  }

  void _emitAssignment(Assignment node) {
    _trackSource(node);
    if (node.targets.length == 1 && node.exprs.length == 1) {
      _emitSingleAssignment(node.targets.single, node.exprs.single);
      return;
    }

    final targetPlans = <_AssignmentTargetPlan>[];
    final targetTemporaries = <int>[];
    for (final target in node.targets) {
      final plan = _prepareAssignmentTarget(target);
      targetPlans.add(plan);
      targetTemporaries.addAll(plan.temporaries);
    }

    final result = _emitAssignmentValues(node.exprs, node.targets.length);
    final protected = <int>{};

    for (var i = 0; i < targetPlans.length; i++) {
      final plan = targetPlans[i];
      final valueReg = result.registers[i];
      _ensureRegister(valueReg);
      if (plan is _IdentifierAssignmentPlan) {
        final name = plan.name;
        final localReg = _lookupLocal(name);
        if (localReg != null) {
          if (localReg != valueReg) {
            emitter.emitABC(
              opcode: LualikeIrOpcode.move,
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
            opcode: LualikeIrOpcode.setUpval,
            a: 0,
            b: upvalueIndex,
            c: valueReg,
          );
          continue;
        }

        final constantIndex = _ensureConstantIndex(name);
        emitter.emitABC(
          opcode: LualikeIrOpcode.setTabUp,
          a: 0,
          b: constantIndex,
          c: valueReg,
        );
        continue;
      }

      if (plan is _EnvFieldAssignmentPlan) {
        emitter.emitABC(
          opcode: LualikeIrOpcode.setTabUp,
          a: 0,
          b: plan.fieldConstIndex,
          c: valueReg,
        );
        continue;
      }

      if (plan is _TableFieldAssignmentPlan) {
        emitter.emitABC(
          opcode: LualikeIrOpcode.setField,
          a: plan.tableReg,
          b: plan.fieldConstIndex,
          c: valueReg,
        );
        continue;
      }

      if (plan is _TableIndexAssignmentPlan) {
        if (plan.numericIndex != null) {
          emitter.emitABC(
            opcode: LualikeIrOpcode.setI,
            a: plan.tableReg,
            b: plan.numericIndex!,
            c: valueReg,
          );
          continue;
        }
        emitter.emitABC(
          opcode: LualikeIrOpcode.setTable,
          a: plan.tableReg,
          b: plan.indexReg!,
          c: valueReg,
        );
        continue;
      }

      throw UnsupportedError(
        'Lualike IR compiler does not yet support assignment target type: '
        '${plan.runtimeType}',
      );
    }

    for (var i = result.temporaries.length - 1; i >= 0; i--) {
      final reg = result.temporaries[i];
      if (protected.contains(reg)) {
        continue;
      }
      _releaseRegister(reg);
    }

    for (var i = targetTemporaries.length - 1; i >= 0; i--) {
      final reg = targetTemporaries[i];
      if (protected.contains(reg)) {
        continue;
      }
      _releaseRegister(reg);
    }
  }

  _AssignmentTargetPlan _prepareAssignmentTarget(AstNode target) {
    if (target is Identifier) {
      return _IdentifierAssignmentPlan(target.name);
    }

    if (target is TableFieldAccess) {
      if (_isEnvIdentifier(target.table)) {
        final fieldIndex = _ensureConstantIndex(target.fieldName.name);
        return _EnvFieldAssignmentPlan(fieldConstIndex: fieldIndex);
      }
      final tableReg = _emitExpression(target.table);
      return _TableFieldAssignmentPlan(
        tableReg: tableReg,
        fieldConstIndex: _ensureConstantIndex(target.fieldName.name),
        temporaries: <int>[tableReg],
      );
    }

    if (target is TableIndexAccess) {
      return _prepareTableIndexAssignment(target.table, target.index);
    }

    if (target is TableAccessExpr) {
      final index = target.index;
      if (index is Identifier) {
        return _prepareAssignmentTarget(TableFieldAccess(target.table, index));
      }
      return _prepareTableIndexAssignment(target.table, index);
    }

    if (target is AssignmentIndexAccessExpr) {
      return _prepareTableIndexAssignment(target.target, target.index);
    }

    throw UnsupportedError(
      'Lualike IR compiler does not yet support assignment target type: '
      '${target.runtimeType}',
    );
  }

  _AssignmentTargetPlan _prepareTableIndexAssignment(
    AstNode tableNode,
    AstNode indexNode,
  ) {
    if (_isEnvIdentifier(tableNode) && indexNode is StringLiteral) {
      final fieldName = String.fromCharCodes(indexNode.bytes);
      final fieldIndex = _ensureConstantIndex(fieldName);
      return _EnvFieldAssignmentPlan(fieldConstIndex: fieldIndex);
    }

    final tableReg = _emitExpression(tableNode);
    final temporaries = <int>[tableReg];
    final numericIndex = _numericLiteralValue(indexNode);
    if (numericIndex is int) {
      return _TableIndexAssignmentPlan(
        tableReg: tableReg,
        numericIndex: numericIndex,
        temporaries: temporaries,
      );
    }

    final indexReg = _emitExpression(indexNode);
    temporaries.add(indexReg);
    return _TableIndexAssignmentPlan(
      tableReg: tableReg,
      indexReg: indexReg,
      temporaries: temporaries,
    );
  }

  void _emitLocalDeclaration(LocalDeclaration node) {
    _trackSource(node);
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
      if (attribute == 'const') {
        // Const locals behave like regular locals in the VM today. Enforcement
        // is handled by the interpreter when values escape to environments.
        continue;
      }
      throw UnsupportedError(
        'Lualike IR compiler does not yet support local declaration attribute '
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

    final targets = <({String name, int register})>[];
    for (final identifier in node.names) {
      final register = _allocateRegister();
      targets.add((name: identifier.name, register: register));
    }
    final result = _emitAssignmentValues(node.exprs, nameCount);
    final protected = <int>{};

    for (var i = 0; i < nameCount; i++) {
      final target = targets[i];
      _declareLocal(target.name, target.register);
      final targetReg = target.register;
      final valueReg = result.registers[i];
      final attribute = node.attributes.length > i ? node.attributes[i] : '';
      final isConst = attribute == 'const';
      if (targetReg != valueReg) {
        emitter.emitABC(
          opcode: LualikeIrOpcode.move,
          a: targetReg,
          b: valueReg,
          c: 0,
        );
        if (isConst) {
          final sealPc = _currentInstructionIndex - 1;
          builder.scheduleConstSeal(sealPc, targetReg);
        }
      } else {
        protected.add(valueReg);
        if (isConst) {
          final sealPc = _currentInstructionIndex - 1;
          builder.scheduleConstSeal(sealPc, targetReg);
        }
      }
      if (isConst) {
        builder.markRegisterConst(targetReg);
      }
    }

    if (closableIndices.isNotEmpty) {
      final reg = targets[closableIndices.first].register;
      emitter.emitABC(opcode: LualikeIrOpcode.tbc, a: reg, b: 0, c: 0);
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

  void _emitGlobalDeclaration(GlobalDeclaration node) {
    _trackSource(node);
    if (node.isWildcard || node.names.isEmpty) {
      return;
    }

    final result = _emitAssignmentValues(node.exprs, node.names.length);
    try {
      for (var index = 0; index < node.names.length; index++) {
        final name = node.names[index].name;
        final valueReg = result.registers[index];
        _ensureRegister(valueReg);
        if (_emitEnvFieldWrite(name, valueReg)) {
          continue;
        }
        final constantIndex = _ensureConstantIndex(name);
        emitter.emitABC(
          opcode: LualikeIrOpcode.setTabUp,
          a: 0,
          b: constantIndex,
          c: valueReg,
        );
      }
    } finally {
      for (var i = result.temporaries.length - 1; i >= 0; i--) {
        _releaseRegister(result.temporaries[i]);
      }
    }
  }

  bool _emitDoBlock(DoBlock node) {
    _trackSource(node);
    return _emitBlock(node.body);
  }

  void _emitAssignmentIndexAccessExpr(AssignmentIndexAccessExpr node) {
    _trackSource(node);
    _emitTableIndexAssignment(node.target, node.index, node.value);
  }

  int _emitTableConstructor(TableConstructor node, {int? target}) {
    _trackSource(node);
    final hints = _computeTableConstructorHints(node);
    final originalTarget = target;
    final bool needsTempTarget =
        target != null && _isRegisterOccupiedByLocal(target);
    final int tableReg = needsTempTarget
        ? _allocateRegister()
        : _materializeRegister(target);
    final arrayHint = hints.arraySlots.clamp(0, 0xFF).toInt();
    final hashHint = hints.hashSlots.clamp(0, 0xFF).toInt();
    emitter.emitABC(
      opcode: LualikeIrOpcode.newTable,
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
        opcode: LualikeIrOpcode.setList,
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
        opcode: LualikeIrOpcode.setList,
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
              opcode: LualikeIrOpcode.setField,
              a: tableReg,
              b: fieldIndex,
              c: valueReg,
            );
            _releaseRegister(valueReg);
          } else {
            emitter.emitABC(
              opcode: LualikeIrOpcode.setTable,
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
            opcode: LualikeIrOpcode.setTable,
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
    if (originalTarget != null && tableReg != originalTarget) {
      emitter.emitABC(
        opcode: LualikeIrOpcode.move,
        a: originalTarget,
        b: tableReg,
        c: 0,
      );
      _releaseRegister(tableReg);
      return originalTarget;
    }
    return tableReg;
  }

  void _emitTableFieldAssignment(TableFieldAccess target, AstNode valueNode) {
    final fieldIndex = _ensureConstantIndex(target.fieldName.name);
    if (_isEnvIdentifier(target.table)) {
      final valueReg = _emitExpression(valueNode);
      emitter.emitABC(
        opcode: LualikeIrOpcode.setTabUp,
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
      opcode: LualikeIrOpcode.setField,
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
        opcode: LualikeIrOpcode.setI,
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
        opcode: LualikeIrOpcode.setTabUp,
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
      opcode: LualikeIrOpcode.setTable,
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
        opcode: LualikeIrOpcode.setUpval,
        a: 0,
        b: upvalueIndex,
        c: valueReg,
      );
      _releaseRegister(valueReg);
      return;
    }

    final valueReg = _emitExpression(valueNode);
    if (_emitEnvFieldWrite(name, valueReg)) {
      _releaseRegister(valueReg);
      return;
    }
    final constantIndex = _ensureConstantIndex(name);
    emitter.emitABC(
      opcode: LualikeIrOpcode.setTabUp,
      a: 0,
      b: constantIndex,
      c: valueReg,
    );
    _releaseRegister(valueReg);
  }

  int? _emitEnvFieldRead(String name, {int? target}) {
    final envReg = _lookupLocal('_ENV');
    if (envReg == null) {
      return null;
    }
    final dest = _materializeRegister(target);
    final envValueReg = _allocateRegister();
    emitter.emitABC(
      opcode: LualikeIrOpcode.move,
      a: envValueReg,
      b: envReg,
      c: 0,
    );
    final constant = name.length <= 40
        ? ShortStringConstant(name)
        : LongStringConstant(name);
    final index = builder.addConstant(constant);
    emitter.emitABC(
      opcode: LualikeIrOpcode.getField,
      a: dest,
      b: envValueReg,
      c: index,
    );
    _releaseRegister(envValueReg);
    return dest;
  }

  bool _emitEnvFieldWrite(String name, int valueReg) {
    final envReg = _lookupLocal('_ENV');
    if (envReg == null) {
      return false;
    }
    final envValueReg = _allocateRegister();
    emitter.emitABC(
      opcode: LualikeIrOpcode.move,
      a: envValueReg,
      b: envReg,
      c: 0,
    );
    final constant = name.length <= 40
        ? ShortStringConstant(name)
        : LongStringConstant(name);
    final index = builder.addConstant(constant);
    emitter.emitABC(
      opcode: LualikeIrOpcode.setField,
      a: envValueReg,
      b: index,
      c: valueReg,
    );
    _releaseRegister(envValueReg);
    return true;
  }

  bool _emitIfStatement(IfStatement node) {
    _trackSource(node);
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
    _trackSource(node);
    final loopStart = _currentInstructionIndex;
    final exitJump = _emitConditionJump(node.cond, jumpWhenTrue: false);
    _emitBlock(node.body, useNewScope: true);

    final backJumpIndex = emitter.emitAsJ(opcode: LualikeIrOpcode.jmp, sJ: 0);
    _patchJump(backJumpIndex, loopStart);
    _patchJump(exitJump, _currentInstructionIndex);
  }

  void _emitForLoop(ForLoop node) {
    _trackSource(node);
    final base = _allocateRegister();
    final limitReg = _allocateRegister();
    final stepReg = _allocateRegister();
    final controlReg = _allocateRegister();

    _emitExpression(node.start, target: base);
    _emitExpression(node.endExpr, target: limitReg);

    _emitExpression(node.stepExpr, target: stepReg);

    emitter.emitABC(opcode: LualikeIrOpcode.move, a: controlReg, b: base, c: 0);

    final forPrepIndex = emitter.emitAsBx(
      opcode: LualikeIrOpcode.forPrep,
      a: base,
      sBx: 0,
    );

    final bodyStart = _currentInstructionIndex;

    _pushLocalScope();
    _declareLocal(node.varName.name, controlReg);
    _emitBlock(node.body, useNewScope: false);
    _popLocalScope();

    final forLoopIndex = emitter.emitAsBx(
      opcode: LualikeIrOpcode.forLoop,
      a: base,
      sBx: 0,
    );

    final patchedForPrep = AsBxInstruction(
      opcode: LualikeIrOpcode.forPrep,
      a: base,
      sBx: forLoopIndex - forPrepIndex - 1,
    );
    builder.replaceInstruction(forPrepIndex, patchedForPrep);

    final forLoopOffset = bodyStart - (forLoopIndex + 1);
    final patchedForLoop = AsBxInstruction(
      opcode: LualikeIrOpcode.forLoop,
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
    _trackSource(node);
    if (node.iterators.isEmpty || node.names.isEmpty) {
      throw UnsupportedError('Generic for loop requires iterators and names');
    }

    final iteratorCount = node.iterators.length;
    if (iteratorCount > 3) {
      throw UnsupportedError(
        'Lualike IR compiler supports up to three iterator expressions',
      );
    }

    final base = _allocateRegister();
    final stateReg = _ensureRegister(base + 1);
    final controlReg = _ensureRegister(base + 2);
    final closingReg = _ensureRegister(base + 3);
    final loopVarRegs = <int>[];
    for (var i = 0; i < node.names.length; i++) {
      loopVarRegs.add(_ensureRegister(base + 4 + i));
    }

    var filledSlots = 0;
    for (var i = 0; i < iteratorCount; i++) {
      final iterator = node.iterators[i];
      final targetReg = base + i;
      final isFirstIterator = i == 0;
      if (isFirstIterator) {
        switch (iterator) {
          case FunctionCall():
            _emitFunctionCall(
              iterator,
              resultCount: 3,
              baseRegister: targetReg,
            );
            filledSlots = 3;
            continue;
          case MethodCall():
            _emitMethodCall(iterator, resultCount: 3, baseRegister: targetReg);
            filledSlots = 3;
            continue;
          default:
            break;
        }
      }
      _emitExpression(iterator, target: targetReg);
      filledSlots = i + 1;
    }
    if (filledSlots < 3) {
      for (var i = filledSlots; i < 3; i++) {
        emitter.emitABC(
          opcode: LualikeIrOpcode.loadNil,
          a: base + i,
          b: 0,
          c: 0,
        );
      }
    }

    final tforPrepIndex = emitter.emitAsBx(
      opcode: LualikeIrOpcode.tForPrep,
      a: base,
      sBx: 0,
    );

    final bodyStart = _currentInstructionIndex;

    for (var i = node.names.length - 1; i >= 0; i--) {
      emitter.emitABC(
        opcode: LualikeIrOpcode.move,
        a: loopVarRegs[i],
        b: base + 4 + i,
        c: 0,
      );
    }

    _pushLocalScope();
    for (var i = 0; i < node.names.length; i++) {
      _declareLocal(node.names[i].name, loopVarRegs[i]);
    }
    _emitBlock(node.body, useNewScope: false);
    _popLocalScope();

    final tforCallIndex = emitter.emitABC(
      opcode: LualikeIrOpcode.tForCall,
      a: base,
      b: 0,
      c: node.names.length,
    );

    final tforLoopIndex = emitter.emitAsBx(
      opcode: LualikeIrOpcode.tForLoop,
      a: base,
      sBx: 0,
    );

    final exitIndex = _currentInstructionIndex;

    final patchedTforPrep = AsBxInstruction(
      opcode: LualikeIrOpcode.tForPrep,
      a: base,
      sBx: tforCallIndex - (tforPrepIndex + 1),
    );
    builder.replaceInstruction(tforPrepIndex, patchedTforPrep);

    final patchedTforLoop = AsBxInstruction(
      opcode: LualikeIrOpcode.tForLoop,
      a: base,
      sBx: bodyStart - (tforLoopIndex + 1),
    );
    builder.replaceInstruction(tforLoopIndex, patchedTforLoop);

    for (var reg = _nextRegister - 1; reg >= base; reg--) {
      _releaseRegister(reg);
    }
  }

  void _emitFunctionDef(FunctionDef node) {
    _trackSource(node);
    final register = _allocateRegister();
    final prototypeIndex = _compileFunctionBody(node.body);
    emitter.emitABx(
      opcode: LualikeIrOpcode.closure,
      a: register,
      bx: prototypeIndex,
    );

    final rest = node.name.rest;
    if (!node.implicitSelf && rest.isEmpty) {
      final envReg = _lookupLocal('_ENV');
      final constantIndex = _ensureConstantIndex(node.name.first.name);
      if (envReg != null) {
        emitter.emitABC(
          opcode: LualikeIrOpcode.setField,
          a: envReg,
          b: constantIndex,
          c: register,
        );
      } else {
        emitter.emitABC(
          opcode: LualikeIrOpcode.setTabUp,
          a: 0,
          b: constantIndex,
          c: register,
        );
      }
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
      final envReg = _lookupLocal('_ENV');
      final constantIndex = _ensureConstantIndex(fieldName);
      if (envReg != null) {
        emitter.emitABC(
          opcode: LualikeIrOpcode.setField,
          a: envReg,
          b: constantIndex,
          c: register,
        );
      } else {
        emitter.emitABC(
          opcode: LualikeIrOpcode.setTabUp,
          a: 0,
          b: constantIndex,
          c: register,
        );
      }
      _releaseRegister(register);
      return;
    }

    final usesEnv = tablePath.length == 1 && tablePath.first.name == '_ENV';
    final fieldIndex = _ensureConstantIndex(fieldName);

    if (usesEnv) {
      final envReg = _lookupLocal('_ENV');
      if (envReg != null) {
        emitter.emitABC(
          opcode: LualikeIrOpcode.setField,
          a: envReg,
          b: fieldIndex,
          c: register,
        );
      } else {
        emitter.emitABC(
          opcode: LualikeIrOpcode.setTabUp,
          a: 0,
          b: fieldIndex,
          c: register,
        );
      }
      _releaseRegister(register);
      return;
    }

    final tableExpr = _buildTableExpression(tablePath);
    final tableReg = _emitExpression(tableExpr);
    emitter.emitABC(
      opcode: LualikeIrOpcode.setField,
      a: tableReg,
      b: fieldIndex,
      c: register,
    );
    _releaseRegister(tableReg);
    _releaseRegister(register);
  }

  void _emitLocalFunctionDef(LocalFunctionDef node) {
    _trackSource(node);
    final register = _allocateRegister();
    _declareLocal(node.name.name, register);
    final prototypeIndex = _compileFunctionBody(node.funcBody);
    emitter.emitABx(
      opcode: LualikeIrOpcode.closure,
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
      final terminated = childContext.emitStatement(statement);
      if (terminated) {
        break;
      }
    }
    childContext.finalize();
    return childBuilder.index;
  }

  int _emitFunctionLiteral(FunctionLiteral node, {int? target}) {
    final originalTarget = target;
    int? preservedLocalRegister;
    if (target != null && _isRegisterOccupiedByLocal(target)) {
      preservedLocalRegister = _allocateRegister();
      emitter.emitABC(
        opcode: LualikeIrOpcode.move,
        a: preservedLocalRegister,
        b: target,
        c: 0,
      );
      _reassignLocalRegister(target, preservedLocalRegister);
    }

    int register;
    if (preservedLocalRegister != null) {
      register = _allocateRegister();
    } else {
      register = _materializeRegister(target);
    }
    final prototypeIndex = _compileFunctionBody(node.funcBody);
    emitter.emitABx(
      opcode: LualikeIrOpcode.closure,
      a: register,
      bx: prototypeIndex,
    );
    if (originalTarget != null && register != originalTarget) {
      emitter.emitABC(
        opcode: LualikeIrOpcode.move,
        a: originalTarget,
        b: register,
        c: 0,
      );
      _releaseRegister(register);
      return originalTarget;
    }
    return register;
  }

  int _emitVarArg({int? target, int resultCount = 1}) {
    _ensureVarargAvailable();
    final register = _materializeRegister(target);
    final bOperand = resultCount == 0 ? 0 : resultCount + 1;
    emitter.emitABC(
      opcode: LualikeIrOpcode.varArg,
      a: register,
      b: bOperand,
      c: 0,
    );
    return register;
  }

  int _emitConditionJump(AstNode cond, {required bool jumpWhenTrue}) {
    final condReg = _emitExpression(cond);
    emitter.emitABC(
      opcode: LualikeIrOpcode.test,
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
    return emitter.emitAsJ(opcode: LualikeIrOpcode.jmp, sJ: 0);
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
    _trackSource(node);
    final isAnd = node.op == 'and';
    final tempReg = _emitExpression(node.left);
    emitter.emitABC(
      opcode: LualikeIrOpcode.test,
      a: tempReg,
      b: 0,
      c: 0,
      k: !isAnd,
    );
    final jumpIndex = _emitJumpPlaceholder();
    _emitExpression(node.right, target: tempReg);
    _patchJump(jumpIndex, _currentInstructionIndex);

    if (target != null) {
      final destination = _ensureRegister(target);
      if (destination != tempReg) {
        emitter.emitABC(
          opcode: LualikeIrOpcode.move,
          a: destination,
          b: tempReg,
          c: 0,
        );
        _releaseRegister(tempReg);
      }
      return destination;
    }

    return tempReg;
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
    _trackSource(node);
    assert(
      !(captureAll && resultCount != null),
      'Cannot request a fixed result count when capturing all results.',
    );

    var base = baseRegister != null
        ? _ensureRegister(baseRegister)
        : _allocateRegister();
    if (baseRegister == null) {
      while (_isRegisterOccupiedByLocal(base)) {
        base = _allocateRegister();
      }
    }
    _emitExpression(node.name, target: base);

    final argRegs = <int>[];
    var hasVariadicArgs = false;
    for (var i = 0; i < node.args.length; i++) {
      final argument = node.args[i];
      final reg = baseRegister != null
          ? _ensureRegister(base + i + 1)
          : _allocateRegister();
      argRegs.add(reg);
      final isLastArg = i == node.args.length - 1;
      if (argument is VarArg) {
        final requested = isLastArg ? 0 : 1;
        _emitVarArg(target: reg, resultCount: requested);
        if (requested == 0) {
          hasVariadicArgs = true;
        }
      } else if (argument is FunctionCall && isLastArg) {
        final call = _emitFunctionCall(
          argument,
          captureAll: true,
          baseRegister: reg,
        );
        if (call.capturesAll) {
          hasVariadicArgs = true;
        }
      } else if (argument is MethodCall && isLastArg) {
        final call = _emitMethodCall(
          argument,
          captureAll: true,
          baseRegister: reg,
        );
        if (call.capturesAll) {
          hasVariadicArgs = true;
        }
      } else {
        _emitExpression(argument, target: reg);
      }
    }

    final bOperand = hasVariadicArgs ? 0 : argRegs.length + 1;
    final opcode = asTailCall ? LualikeIrOpcode.tailCall : LualikeIrOpcode.call;

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

    if (hasVariadicArgs || captureAll) {
      while (_nextRegister > base + 1) {
        _releaseRegister(_nextRegister - 1);
      }
    }

    if (baseRegister == null && !hasVariadicArgs && !captureAll) {
      for (var i = argRegs.length - 1; i >= 0; i--) {
        _releaseRegister(argRegs[i]);
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
    _trackSource(node);
    if (node.methodName is! Identifier) {
      throw UnsupportedError(
        'Lualike IR compiler requires identifier method names for method calls.',
      );
    }

    final methodIdentifier = node.methodName as Identifier;
    var funcReg = baseRegister != null
        ? _ensureRegister(baseRegister)
        : _allocateRegister();
    if (baseRegister == null) {
      while (_isRegisterOccupiedByLocal(funcReg)) {
        funcReg = _allocateRegister();
      }
    }
    final fieldIndex = _ensureConstantIndex(methodIdentifier.name);

    final argRegs = <int>[];
    var hasVariadicArgs = false;
    _ensureRegister(funcReg + 1);
    final objectReg = _emitExpression(node.prefix, target: funcReg + 1);
    emitter.emitABC(
      opcode: LualikeIrOpcode.selfOp,
      a: funcReg,
      b: objectReg,
      c: fieldIndex,
    );
    argRegs.add(funcReg + 1);

    for (var i = 0; i < node.args.length; i++) {
      final reg = funcReg + 2 + i;
      _ensureRegister(reg);
      argRegs.add(reg);
      final argument = node.args[i];
      final isLastArg = i == node.args.length - 1;
      if (argument is VarArg) {
        final requested = isLastArg ? 0 : 1;
        _emitVarArg(target: reg, resultCount: requested);
        if (requested == 0) {
          hasVariadicArgs = true;
        }
      } else if (argument is FunctionCall && isLastArg) {
        final call = _emitFunctionCall(
          argument,
          captureAll: true,
          baseRegister: reg,
        );
        if (call.capturesAll) {
          hasVariadicArgs = true;
        }
      } else if (argument is MethodCall && isLastArg) {
        final call = _emitMethodCall(
          argument,
          captureAll: true,
          baseRegister: reg,
        );
        if (call.capturesAll) {
          hasVariadicArgs = true;
        }
      } else {
        _emitExpression(argument, target: reg);
      }
    }

    final opcode = asTailCall ? LualikeIrOpcode.tailCall : LualikeIrOpcode.call;
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

    if (hasVariadicArgs || captureAll) {
      while (_nextRegister > funcReg + 1) {
        _releaseRegister(_nextRegister - 1);
      }
    }

    if (!hasVariadicArgs && !captureAll) {
      for (var i = argRegs.length - 1; i >= 0; i--) {
        _releaseRegister(argRegs[i]);
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
        emitter.emitABC(opcode: LualikeIrOpcode.move, a: dest, b: base, c: 0);
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
      emitter.emitABC(opcode: LualikeIrOpcode.loadNil, a: reg, b: 0, c: 0);
      registers.add(reg);
      temporaries.add(reg);
    }

    return _ExpressionListResult(
      registers: registers,
      temporaries: temporaries,
    );
  }

  int _emitBinaryExpression(BinaryExpression node, {int? target}) {
    _trackSource(node);
    if (node.op == 'and' || node.op == 'or') {
      return _emitLogicalBinaryExpression(node, target: target);
    }

    if (node.op == '..') {
      return _emitConcatenation(node, target: target);
    }

    final isComparison = const {
      '==',
      '~=',
      '!=',
      '<',
      '>',
      '<=',
      '>=',
    }.contains(node.op);

    final leftReg = isComparison
        ? _emitExpression(node.left)
        : _emitExpression(node.left, target: target);
    final resultReg = target != null ? _materializeRegister(target) : leftReg;

    final literalInfo = _literalValue(node.right);
    final literalValue = literalInfo.value;

    if (isComparison) {
      if (literalInfo.isLiteral) {
        final handled = switch (node.op) {
          '==' => _emitEqualityWithLiteral(
            leftReg,
            resultReg,
            literalValue,
            negate: false,
          ),
          '~=' || '!=' => _emitEqualityWithLiteral(
            leftReg,
            resultReg,
            literalValue,
            negate: true,
          ),
          '<' => _emitRelationalWithLiteral(
            leftReg,
            resultReg,
            literalValue,
            LualikeIrOpcode.ltI,
          ),
          '<=' => _emitRelationalWithLiteral(
            leftReg,
            resultReg,
            literalValue,
            LualikeIrOpcode.leI,
          ),
          '>' => _emitRelationalWithLiteral(
            leftReg,
            resultReg,
            literalValue,
            LualikeIrOpcode.gtI,
          ),
          '>=' => _emitRelationalWithLiteral(
            leftReg,
            resultReg,
            literalValue,
            LualikeIrOpcode.geI,
          ),
          _ => false,
        };
        if (handled) {
          if (resultReg != leftReg) {
            _releaseRegister(leftReg);
          }
          return resultReg;
        }
      }

      final rightReg = _emitExpression(node.right);
      switch (node.op) {
        case '==':
          emitter.emitABC(
            opcode: LualikeIrOpcode.eq,
            a: resultReg,
            b: leftReg,
            c: rightReg,
          );
          break;
        case '~=':
        case '!=':
          emitter.emitABC(
            opcode: LualikeIrOpcode.eq,
            a: resultReg,
            b: leftReg,
            c: rightReg,
          );
          emitter.emitABC(
            opcode: LualikeIrOpcode.notOp,
            a: resultReg,
            b: resultReg,
            c: 0,
          );
          break;
        case '<':
          emitter.emitABC(
            opcode: LualikeIrOpcode.lt,
            a: resultReg,
            b: leftReg,
            c: rightReg,
          );
          break;
        case '>':
          emitter.emitABC(
            opcode: LualikeIrOpcode.lt,
            a: resultReg,
            b: rightReg,
            c: leftReg,
          );
          break;
        case '<=':
          emitter.emitABC(
            opcode: LualikeIrOpcode.le,
            a: resultReg,
            b: leftReg,
            c: rightReg,
          );
          break;
        case '>=':
          emitter.emitABC(
            opcode: LualikeIrOpcode.le,
            a: resultReg,
            b: rightReg,
            c: leftReg,
          );
          break;
      }
      _releaseRegister(rightReg);
      if (resultReg != leftReg) {
        _releaseRegister(leftReg);
      }
      return resultReg;
    }

    if (literalInfo.isLiteral && literalValue is int) {
      final intLiteral = literalValue;
      if (node.op == '<<' && intLiteral >= 0 && intLiteral <= 255) {
        emitter.emitABC(
          opcode: LualikeIrOpcode.shlI,
          a: leftReg,
          b: leftReg,
          c: intLiteral & 0x1FF,
        );
        return leftReg;
      }
      if (node.op == '>>' && intLiteral >= 0 && intLiteral <= 255) {
        emitter.emitABC(
          opcode: LualikeIrOpcode.shrI,
          a: leftReg,
          b: leftReg,
          c: intLiteral & 0x1FF,
        );
        return leftReg;
      }
    }

    if (literalInfo.isLiteral && literalValue is num) {
      final numericValue = literalValue;
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

    if (literalInfo.isLiteral) {
      final value = literalValue;
      final handled = switch (node.op) {
        '==' => _emitEqualityWithLiteral(
          leftReg,
          leftReg,
          value,
          negate: false,
        ),
        '~=' ||
        '!=' => _emitEqualityWithLiteral(leftReg, leftReg, value, negate: true),
        '<' => _emitRelationalWithLiteral(
          leftReg,
          leftReg,
          value,
          LualikeIrOpcode.ltI,
        ),
        '<=' => _emitRelationalWithLiteral(
          leftReg,
          leftReg,
          value,
          LualikeIrOpcode.leI,
        ),
        '>' => _emitRelationalWithLiteral(
          leftReg,
          leftReg,
          value,
          LualikeIrOpcode.gtI,
        ),
        '>=' => _emitRelationalWithLiteral(
          leftReg,
          leftReg,
          value,
          LualikeIrOpcode.geI,
        ),
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
          opcode: LualikeIrOpcode.eq,
          a: leftReg,
          b: leftReg,
          c: rightReg,
        );
        break;
      case '~=':
      case '!=':
        emitter.emitABC(
          opcode: LualikeIrOpcode.eq,
          a: leftReg,
          b: leftReg,
          c: rightReg,
        );
        emitter.emitABC(
          opcode: LualikeIrOpcode.notOp,
          a: leftReg,
          b: leftReg,
          c: 0,
        );
        break;
      case '<':
        emitter.emitABC(
          opcode: LualikeIrOpcode.lt,
          a: leftReg,
          b: leftReg,
          c: rightReg,
        );
        break;
      case '>':
        emitter.emitABC(
          opcode: LualikeIrOpcode.lt,
          a: leftReg,
          b: rightReg,
          c: leftReg,
        );
        break;
      case '<=':
        emitter.emitABC(
          opcode: LualikeIrOpcode.le,
          a: leftReg,
          b: leftReg,
          c: rightReg,
        );
        break;
      case '>=':
        emitter.emitABC(
          opcode: LualikeIrOpcode.le,
          a: leftReg,
          b: rightReg,
          c: leftReg,
        );
        break;
      case '..':
        _releaseRegister(rightReg);
        _releaseRegister(leftReg);
        return _emitConcatenation(node, target: target);
      default:
        final opcode = _opcodeForBinary(node.op);
        if (opcode == null) {
          _releaseRegister(rightReg);
          throw UnsupportedError(
            'Operator ${node.op} is not supported by lualike IR compiler',
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

    final tempRegs = <int>[];
    for (final operand in operands) {
      final reg = _allocateRegister();
      _emitExpression(operand, target: reg);
      tempRegs.add(reg);
    }

    final baseReg = tempRegs.first;
    final lastReg = tempRegs.last;
    emitter.emitABC(
      opcode: LualikeIrOpcode.concat,
      a: baseReg,
      b: baseReg,
      c: lastReg,
    );

    for (var i = tempRegs.length - 1; i >= 1; i--) {
      _releaseRegister(tempRegs[i]);
    }

    final resultReg = tempRegs.first;
    if (target != null && resultReg != target) {
      emitter.emitABC(
        opcode: LualikeIrOpcode.move,
        a: target,
        b: resultReg,
        c: 0,
      );
      _releaseRegister(resultReg);
      return target;
    }

    return resultReg;
  }

  LualikeIrOpcode? _opcodeForBinary(String operatorToken) {
    return switch (operatorToken) {
      '+' => LualikeIrOpcode.add,
      '-' => LualikeIrOpcode.sub,
      '*' => LualikeIrOpcode.mul,
      '/' => LualikeIrOpcode.div,
      '%' => LualikeIrOpcode.mod,
      '^' => LualikeIrOpcode.pow,
      '//' => LualikeIrOpcode.idiv,
      '&' => LualikeIrOpcode.band,
      '|' => LualikeIrOpcode.bor,
      '~' => LualikeIrOpcode.bxor,
      '<<' => LualikeIrOpcode.shl,
      '>>' => LualikeIrOpcode.shr,
      '..' => LualikeIrOpcode.concat,
      _ => null,
    };
  }

  LualikeIrOpcode? _opcodeForBinaryConstant(String operatorToken) {
    return switch (operatorToken) {
      '+' => LualikeIrOpcode.addK,
      '-' => LualikeIrOpcode.subK,
      '*' => LualikeIrOpcode.mulK,
      '/' => LualikeIrOpcode.divK,
      '%' => LualikeIrOpcode.modK,
      '^' => LualikeIrOpcode.powK,
      '//' => LualikeIrOpcode.idivK,
      '&' => LualikeIrOpcode.bandK,
      '|' => LualikeIrOpcode.borK,
      '~' => LualikeIrOpcode.bxorK,
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

  ({bool isLiteral, Object? value}) _literalValue(AstNode node) {
    switch (node) {
      case NilValue():
        return (isLiteral: true, value: null);
      case BooleanLiteral(value: final value):
        return (isLiteral: true, value: value);
      case StringLiteral(:final bytes):
        return (isLiteral: true, value: String.fromCharCodes(bytes));
      case NumberLiteral():
      case UnaryExpression():
        final numeric = _numericLiteralValue(node);
        return (isLiteral: numeric != null, value: numeric);
      default:
        return (isLiteral: false, value: null);
    }
  }

  bool _emitEqualityWithLiteral(
    int leftReg,
    int resultReg,
    Object? value, {
    required bool negate,
  }) {
    if (value is int) {
      emitter.emitABC(
        opcode: LualikeIrOpcode.eqI,
        a: resultReg,
        b: leftReg,
        c: value,
      );
    } else {
      final constantIndex = _ensureConstantIndex(value);
      emitter.emitABC(
        opcode: LualikeIrOpcode.eqK,
        a: resultReg,
        b: leftReg,
        c: constantIndex,
      );
    }

    if (negate) {
      emitter.emitABC(
        opcode: LualikeIrOpcode.notOp,
        a: resultReg,
        b: resultReg,
        c: 0,
      );
    }

    return true;
  }

  bool _emitRelationalWithLiteral(
    int leftReg,
    int resultReg,
    Object? value,
    LualikeIrOpcode opcode,
  ) {
    if (value is! int) {
      return false;
    }
    emitter.emitABC(opcode: opcode, a: resultReg, b: leftReg, c: value);
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
      opcode: LualikeIrOpcode.getField,
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
        opcode: LualikeIrOpcode.getI,
        a: tableReg,
        b: tableReg,
        c: numericIndex,
      );
      return tableReg;
    }

    final indexReg = _emitExpression(indexNode);
    emitter.emitABC(
      opcode: LualikeIrOpcode.getTable,
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
      'not' => LualikeIrOpcode.notOp,
      '-' => LualikeIrOpcode.unm,
      '~' => LualikeIrOpcode.bnot,
      '#' => LualikeIrOpcode.len,
      _ => throw UnsupportedError(
        'Unary operator ${node.op} is not supported by lualike IR compiler',
      ),
    };

    emitter.emitABC(opcode: opcode, a: reg, b: reg, c: 0);
    return reg;
  }

  void finalize() {
    if (!hasExplicitReturn) {
      _emitCloseForActiveToBeClosed(clear: true);
      emitter.emitABC(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0);
    }

    if (_pendingGotos.isNotEmpty) {
      final unresolved = _pendingGotos.map((g) => g.label).toSet().join(', ');
      throw UnsupportedError('no visible label for goto $unresolved');
    }

    final registers = _maxRegister == 0 ? 1 : _maxRegister;
    builder.registerCount = registers;
  }

  void _trackSource(AstNode node) {
    final span = node.span;
    if (span == null) {
      return;
    }
    final line = span.start.line + 1;
    emitter.currentLine = line;
    final url = span.sourceUrl;
    if (url != null && builder.sourcePath == null) {
      builder.sourcePath = _normalizeSourcePath(url);
    }
    if (builder.lineDefined == 0 && line > 0) {
      builder.lineDefined = line;
    }
    if (line > builder.lastLineDefined) {
      builder.lastLineDefined = line;
    }
  }

  String _normalizeSourcePath(Uri url) {
    if (url.scheme == 'file' || url.scheme.isEmpty) {
      try {
        return url.toFilePath();
      } catch (_) {
        // Fall back to string form below
      }
    }
    return url.toString();
  }

  void _emitGoto(Goto node) {
    _trackSource(node);
    final jumpIndex = emitter.emitAsJ(opcode: LualikeIrOpcode.jmp, sJ: 0);
    _pendingGotos.add(
      _PendingGoto(label: node.label.name, jumpIndex: jumpIndex),
    );
    _resolveGoto(node.label.name);
  }

  void _defineLabel(String name) {
    final position = _currentInstructionIndex;
    _labelPositions[name] = position;
    _resolveGoto(name);
  }

  void _resolveGoto(String label) {
    final target = _labelPositions[label];
    if (target == null) {
      return;
    }
    for (var i = 0; i < _pendingGotos.length;) {
      final entry = _pendingGotos[i];
      if (entry.label != label) {
        i += 1;
        continue;
      }
      final instruction =
          builder.instructions[entry.jumpIndex] as AsJInstruction;
      final offset = target - entry.jumpIndex - 1;
      builder.replaceInstruction(
        entry.jumpIndex,
        AsJInstruction(opcode: instruction.opcode, sJ: offset),
      );
      _pendingGotos.removeAt(i);
    }
  }

  int _materializeRegister(int? target) {
    if (target != null) {
      return _ensureRegister(target);
    }
    return _allocateRegister();
  }

  int _allocateRegister() {
    final minFree = _firstFreeRegister();
    if (_nextRegister < minFree) {
      _nextRegister = minFree;
    }
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
    final minFree = _firstFreeRegister();
    if (_nextRegister < minFree) {
      _nextRegister = minFree;
    }
  }
}

class _PendingGoto {
  const _PendingGoto({required this.label, required this.jumpIndex});

  final String label;
  final int jumpIndex;
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
