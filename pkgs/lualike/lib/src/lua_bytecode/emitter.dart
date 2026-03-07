import 'dart:math' as math;

import '../ast.dart';
import '../parse.dart';
import 'builder.dart';
import 'chunk.dart';
import 'instruction.dart';
import 'serializer.dart';

/// Semantic facts shared between the direct source -> lua_bytecode backends.
final class LuaBytecodeEmitterFacts {
  const LuaBytecodeEmitterFacts({
    required this.locals,
    required this.nextRegister,
    required this.hasExplicitReturn,
  });

  final List<LuaBytecodeLocalFact> locals;
  final int nextRegister;
  final bool hasExplicitReturn;

  int get maxStackSize => nextRegister == 0 ? 2 : nextRegister;
}

final class LuaBytecodeLocalFact {
  const LuaBytecodeLocalFact({
    required this.name,
    required this.register,
    required this.statementIndex,
    required this.attribute,
  });

  final String name;
  final int register;
  final int statementIndex;
  final String attribute;
}

final class LuaBytecodeEmitterArtifact {
  const LuaBytecodeEmitterArtifact({
    required this.facts,
    required this.chunk,
    required this.bytes,
  });

  final LuaBytecodeEmitterFacts facts;
  final LuaBytecodeBinaryChunk chunk;
  final List<int> bytes;
}

final class LuaBytecodeEmitter {
  const LuaBytecodeEmitter();

  LuaBytecodeEmitterArtifact compileSource(
    String source, {
    String chunkName = '=(lua_bytecode emitter)',
  }) {
    final program = parse(source, url: chunkName);
    return compileProgram(program, chunkName: chunkName);
  }

  LuaBytecodeEmitterArtifact compileProgram(
    Program program, {
    String chunkName = '=(lua_bytecode emitter)',
  }) {
    final builder = LuaBytecodeChunkBuilder.foundation(chunkName: chunkName);
    final compiler = _LuaBytecodeStructuredCompiler.topLevel(
      builder.mainPrototype,
    );
    compiler.compileProgram(program);

    final chunk = builder.build();
    return LuaBytecodeEmitterArtifact(
      facts: compiler.buildFacts(),
      chunk: chunk,
      bytes: serializeLuaBytecodeChunk(chunk),
    );
  }
}

const Set<String> _supportedUnaryOps = <String>{'-', '~', 'not', '#'};
const Set<String> _supportedBinaryOps = <String>{
  '+',
  '-',
  '*',
  '/',
  '//',
  '%',
  '^',
  '&',
  '|',
  '~',
  '<<',
  '>>',
  '==',
  '~=',
  '<',
  '<=',
  '>',
  '>=',
  '..',
};

final class _LuaBytecodeStructuredCompiler {
  _LuaBytecodeStructuredCompiler.topLevel(this._prototype)
    : _parent = null,
      _nextRegister = 0,
      _nextTemp = 0 {
    _enterScope();
  }

  _LuaBytecodeStructuredCompiler.nested(
    this._prototype,
    this._parent, {
    required List<Identifier> parameters,
  }) : _nextRegister = _prototype.parameterCount,
       _nextTemp = _prototype.parameterCount {
    _enterScope();
    for (var index = 0; index < parameters.length; index++) {
      _declareParameter(parameters[index].name, register: index);
    }
  }

  final LuaBytecodePrototypeBuilder _prototype;
  final _LuaBytecodeStructuredCompiler? _parent;
  final Map<String, List<_LuaBytecodeStructuredLocal>> _localsByName =
      <String, List<_LuaBytecodeStructuredLocal>>{};
  final List<List<_LuaBytecodeStructuredLocal>> _scopes =
      <List<_LuaBytecodeStructuredLocal>>[];
  final List<List<_LuaBytecodeStructuredLabel>> _labelScopes =
      <List<_LuaBytecodeStructuredLabel>>[];
  final Map<String, _LuaBytecodeStructuredUpvalue> _upvaluesByName =
      <String, _LuaBytecodeStructuredUpvalue>{};
  final Map<String, List<_LuaBytecodeStructuredLabel>> _labelsByName =
      <String, List<_LuaBytecodeStructuredLabel>>{};
  final List<_LuaBytecodeStructuredPendingGoto> _pendingGotos =
      <_LuaBytecodeStructuredPendingGoto>[];
  final List<List<int>> _breakFixups = <List<int>>[];
  final List<LuaBytecodeLocalFact> _factLocals = <LuaBytecodeLocalFact>[];
  var _nextRegister = 0;
  var _nextTemp = 0;
  var _hasExplicitReturn = false;
  var _loopDepth = 0;

  bool get _isTopLevel => _parent == null;

  LuaBytecodeEmitterFacts buildFacts() {
    return LuaBytecodeEmitterFacts(
      locals: List<LuaBytecodeLocalFact>.unmodifiable(_factLocals),
      nextRegister: _nextRegister,
      hasExplicitReturn: _hasExplicitReturn,
    );
  }

  void compileProgram(Program program) {
    _compileStatements(program.statements, trackStatementIndexes: _isTopLevel);
    _ensureResolvedGotos();
    _finalizeFunction();
  }

  void compileFunctionBody(List<AstNode> statements) {
    _compileStatements(statements, trackStatementIndexes: false);
    _ensureResolvedGotos();
    _finalizeFunction();
  }

  void _compileStatements(
    List<AstNode> statements, {
    required bool trackStatementIndexes,
  }) {
    if (_isTopLevel || _prototypeHasVarargs) {
      _prototype.emitVarargPrep();
    }

    for (var index = 0; index < statements.length; index++) {
      _compileStatement(
        statements[index],
        statementIndex: trackStatementIndexes ? index : -1,
      );
    }
  }

  void _finalizeFunction() {
    _prototype.emitReturn(
      firstRegister: _nextRegister == 0 ? 0 : _nextRegister,
      resultCount: 0,
    );
    final endPc = _prototype.currentPc + 1;
    while (_scopes.isNotEmpty) {
      _exitScope(endPc: endPc);
    }
  }

  void _compileStatement(AstNode statement, {required int statementIndex}) {
    switch (statement) {
      case LocalDeclaration():
        _compileLocalDeclaration(statement, statementIndex: statementIndex);
      case Assignment():
        _compileAssignment(statement);
      case ExpressionStatement():
        _compileExpressionStatement(statement);
      case ReturnStatement():
        _compileReturn(statement);
      case IfStatement():
        _compileIfStatement(statement);
      case WhileStatement():
        _compileWhileStatement(statement);
      case ForLoop():
        _compileForLoop(statement);
      case ForInLoop():
        _compileForInLoop(statement);
      case RepeatUntilLoop():
        _compileRepeatUntilLoop(statement);
      case Break():
        _compileBreak();
      case Label():
        _compileLabel(statement);
      case Goto():
        _compileGoto(statement);
      case LocalFunctionDef():
        _compileLocalFunctionDef(statement, statementIndex: statementIndex);
      case FunctionDef():
        _compileFunctionDef(statement);
      default:
        throw UnsupportedError(
          'lua_bytecode emitter does not support ${statement.runtimeType}',
        );
    }
  }

  void _compileLocalDeclaration(
    LocalDeclaration statement, {
    required int statementIndex,
  }) {
    for (final attribute in statement.attributes) {
      if (attribute.isNotEmpty) {
        throw UnsupportedError(
          'lua_bytecode emitter does not support local attributes',
        );
      }
    }

    final pendingLocals = <_LuaBytecodeStructuredLocal>[];
    for (
      var localIndex = 0;
      localIndex < statement.names.length;
      localIndex++
    ) {
      pendingLocals.add(
        _prepareLocal(
          statement.names[localIndex].name,
          statementIndex: statementIndex,
          attribute: localIndex < statement.attributes.length
              ? statement.attributes[localIndex]
              : '',
        ),
      );
    }

    var localIndex = 0;
    for (var exprIndex = 0; exprIndex < statement.exprs.length; exprIndex++) {
      final expr = statement.exprs[exprIndex];
      final isLastExpression = exprIndex == statement.exprs.length - 1;
      final remainingLocals = pendingLocals.length - localIndex;

      if (remainingLocals <= 0) {
        if (isLastExpression && _isCallExpression(expr)) {
          _emitDiscardedCall(_unwrapExpression(expr) as Call);
        } else {
          final scratch = _reserveTempBlock(1);
          _emitExpressionToRegister(expr, scratch);
          _releaseTempBlock(scratch, 1);
        }
        continue;
      }

      if (isLastExpression && _isCallExpression(expr)) {
        _emitFixedResultCall(
          _unwrapExpression(expr) as Call,
          baseRegister: pendingLocals[localIndex].register,
          resultCount: remainingLocals,
        );
        localIndex = pendingLocals.length;
        continue;
      }

      _emitExpressionToRegister(expr, pendingLocals[localIndex].register);
      localIndex += 1;
    }

    while (localIndex < pendingLocals.length) {
      _prototype.emitLoadNil(target: pendingLocals[localIndex].register);
      localIndex += 1;
    }

    final startPc = _prototype.currentPc + 1;
    for (final local in pendingLocals) {
      _activatePreparedLocal(local, startPc: startPc);
    }
  }

  void _compileAssignment(Assignment statement) {
    final targets = [
      for (final target in statement.targets) _resolveStoreTarget(target),
    ];
    try {
      _emitValueList(
        statement.exprs,
        valueCount: targets.length,
        onValue: (index, register) {
          if (index >= targets.length) {
            return;
          }
          _storeRegisterToTarget(register, targets[index]);
        },
        onNil: (index) {
          if (index >= targets.length) {
            return;
          }
          final scratch = _reserveTempBlock(1);
          _prototype.emitLoadNil(target: scratch);
          _storeRegisterToTarget(scratch, targets[index]);
          _releaseTempBlock(scratch, 1);
        },
      );
    } finally {
      for (final target in targets.reversed) {
        _releaseStoreTargetTemps(target);
      }
    }
  }

  void _compileExpressionStatement(ExpressionStatement statement) {
    final expr = _unwrapExpression(statement.expr);
    if (expr is! Call) {
      throw UnsupportedError(
        'lua_bytecode emitter only supports call expression statements',
      );
    }
    _emitDiscardedCall(expr);
  }

  void _compileReturn(ReturnStatement statement) {
    _hasExplicitReturn = true;
    if (statement.expr.isEmpty) {
      _prototype.emitReturn(firstRegister: 0, resultCount: 0);
      return;
    }

    if (statement.expr.length == 1) {
      final expr = _unwrapExpression(statement.expr.single);
      if (expr case Identifier(name: final name)) {
        switch (_resolveVariable(name)) {
          case _LuaBytecodeStructuredResolvedVariable(
            kind: _LuaBytecodeStructuredResolvedVariableKind.local,
            register: final register,
          ):
            _prototype.emitReturn(firstRegister: register!, resultCount: 1);
            return;
          case _LuaBytecodeStructuredResolvedVariable(
            kind: _LuaBytecodeStructuredResolvedVariableKind.upvalue,
            upvalueIndex: final upvalueIndex,
          ):
            final scratch = _reserveTempBlock(1);
            _prototype.emitGetUpvalue(target: scratch, upvalue: upvalueIndex!);
            _prototype.emitReturn(firstRegister: scratch, resultCount: 1);
            _releaseTempBlock(scratch, 1);
            return;
          default:
            break;
        }
      }

      if (expr is Call) {
        final base = _reserveTempBlock(_callRegisterWidth(expr));
        _emitTailCall(expr, baseRegister: base);
        _prototype.emitOpenReturn(firstRegister: base);
        return;
      }
    }

    final lastExpression = _unwrapExpression(statement.expr.last);
    final prefixCount = _isCallExpression(lastExpression)
        ? statement.expr.length - 1
        : statement.expr.length;
    final reservedWidth = _isCallExpression(lastExpression)
        ? prefixCount + _callRegisterWidth(lastExpression as Call)
        : prefixCount;
    final returnBase = _reserveTempBlock(math.max(reservedWidth, 1));

    for (var index = 0; index < prefixCount; index++) {
      _emitExpressionToRegister(statement.expr[index], returnBase + index);
    }

    if (lastExpression case Call()) {
      final callBase = returnBase + prefixCount;
      _emitOpenResultCall(lastExpression, baseRegister: callBase);
      _prototype.emitOpenReturn(firstRegister: returnBase);
      return;
    }

    _prototype.emitReturn(
      firstRegister: returnBase,
      resultCount: statement.expr.length,
    );
  }

  void _compileIfStatement(IfStatement statement) {
    final endJumps = <int>[];
    var nextClausePc = _emitFalseJumpForCondition(statement.cond);
    _compileScopedBlock(statement.thenBlock);

    final hasTrailingBranch =
        statement.elseIfs.isNotEmpty || statement.elseBlock.isNotEmpty;
    if (hasTrailingBranch) {
      endJumps.add(_prototype.emitJumpPlaceholder());
    }
    _prototype.patchJumpTarget(
      instructionPc: nextClausePc,
      targetPc: _prototype.currentPc,
    );

    for (var index = 0; index < statement.elseIfs.length; index++) {
      final clause = statement.elseIfs[index];
      nextClausePc = _emitFalseJumpForCondition(clause.cond);
      _compileScopedBlock(clause.thenBlock);
      final hasMoreBranches =
          index != statement.elseIfs.length - 1 ||
          statement.elseBlock.isNotEmpty;
      if (hasMoreBranches) {
        endJumps.add(_prototype.emitJumpPlaceholder());
      }
      _prototype.patchJumpTarget(
        instructionPc: nextClausePc,
        targetPc: _prototype.currentPc,
      );
    }

    if (statement.elseBlock.isNotEmpty) {
      _compileScopedBlock(statement.elseBlock);
    }

    final endPc = _prototype.currentPc;
    for (final jumpPc in endJumps) {
      _prototype.patchJumpTarget(instructionPc: jumpPc, targetPc: endPc);
    }
  }

  void _compileWhileStatement(WhileStatement statement) {
    final loopStartPc = _prototype.currentPc;
    final exitJumpPc = _emitFalseJumpForCondition(statement.cond);
    _breakFixups.add(<int>[]);
    _loopDepth += 1;
    _compileScopedBlock(statement.body);
    _loopDepth -= 1;
    _prototype.emitJump(loopStartPc - _prototype.currentPc - 1);
    final endPc = _prototype.currentPc;
    _prototype.patchJumpTarget(instructionPc: exitJumpPc, targetPc: endPc);
    for (final breakJump in _breakFixups.removeLast()) {
      _prototype.patchJumpTarget(instructionPc: breakJump, targetPc: endPc);
    }
  }

  void _compileForLoop(ForLoop statement) {
    final baseRegister = _allocateRegisters(3);
    _emitExpressionToRegister(statement.start, baseRegister);
    _emitExpressionToRegister(statement.endExpr, baseRegister + 1);
    _emitExpressionToRegister(statement.stepExpr, baseRegister + 2);

    final forPrepPc = _prototype.emitAbxPlaceholder('FORPREP', a: baseRegister);
    final bodyStartPc = _prototype.currentPc;

    _enterScope();
    _bindAllocatedRegister(
      statement.varName.name,
      register: baseRegister + 2,
      statementIndex: -1,
      attribute: '',
      startPc: bodyStartPc + 1,
    );
    _breakFixups.add(<int>[]);
    _loopDepth += 1;
    for (final bodyStatement in statement.body) {
      _compileStatement(bodyStatement, statementIndex: -1);
    }
    _loopDepth -= 1;

    final forLoopPc = _prototype.currentPc;
    _prototype.emitAbx(
      'FORLOOP',
      a: baseRegister,
      bx: forLoopPc + 1 - bodyStartPc,
    );
    final endPc = _prototype.currentPc;
    _prototype.patchBx(instructionPc: forPrepPc, bx: endPc - forPrepPc - 2);
    for (final breakJump in _breakFixups.removeLast()) {
      _prototype.patchJumpTarget(instructionPc: breakJump, targetPc: endPc);
    }
    _exitScope(endPc: endPc + 1);
  }

  void _compileForInLoop(ForInLoop statement) {
    if (statement.names.isEmpty || statement.iterators.isEmpty) {
      throw UnsupportedError(
        'lua_bytecode emitter requires names and iterators for ForInLoop',
      );
    }

    final baseRegister = _allocateRegisters(3 + statement.names.length);
    _emitValueList(
      statement.iterators,
      valueCount: 4,
      onValue: (index, register) {
        final targetRegister = baseRegister + index;
        if (register != targetRegister) {
          _prototype.emitMove(target: targetRegister, source: register);
        }
      },
      onNil: (index) {
        _prototype.emitLoadNil(target: baseRegister + index);
      },
    );

    final tforPrepPc = _prototype.emitTForPrepPlaceholder(
      baseRegister: baseRegister,
    );
    final bodyStartPc = _prototype.currentPc;

    _enterScope();
    for (var index = 0; index < statement.names.length; index++) {
      _bindAllocatedRegister(
        statement.names[index].name,
        register: baseRegister + 3 + index,
        statementIndex: -1,
        attribute: '',
        startPc: bodyStartPc + 1,
      );
    }
    _breakFixups.add(<int>[]);
    _loopDepth += 1;
    for (final bodyStatement in statement.body) {
      _compileStatement(bodyStatement, statementIndex: -1);
    }
    _loopDepth -= 1;
    _exitScope(endPc: _prototype.currentPc + 1);

    final tforCallPc = _prototype.currentPc;
    _prototype.emitTForCall(
      baseRegister: baseRegister,
      loopVariableCount: statement.names.length,
    );

    final tforLoopPc = _prototype.currentPc;
    _prototype.emitTForLoop(
      baseRegister: baseRegister,
      bx: tforLoopPc + 1 - bodyStartPc,
    );

    final closePc = _prototype.currentPc;
    _prototype.emitClose(fromRegister: baseRegister);

    _prototype.patchBx(
      instructionPc: tforPrepPc,
      bx: tforCallPc - (tforPrepPc + 1),
    );
    for (final breakJump in _breakFixups.removeLast()) {
      _prototype.patchJumpTarget(instructionPc: breakJump, targetPc: closePc);
    }
  }

  void _compileRepeatUntilLoop(RepeatUntilLoop statement) {
    final loopStartPc = _prototype.currentPc;
    _enterScope();
    _breakFixups.add(<int>[]);
    _loopDepth += 1;
    for (final bodyStatement in statement.body) {
      _compileStatement(bodyStatement, statementIndex: -1);
    }
    _loopDepth -= 1;

    final retryJumpPc = _emitFalseJumpForCondition(statement.cond);
    final endPc = _prototype.currentPc;
    _prototype.patchJumpTarget(
      instructionPc: retryJumpPc,
      targetPc: loopStartPc,
    );
    for (final breakJump in _breakFixups.removeLast()) {
      _prototype.patchJumpTarget(instructionPc: breakJump, targetPc: endPc);
    }
    _exitScope(endPc: endPc + 1);
  }

  void _compileLabel(Label statement) {
    final name = statement.label.name;
    final visible = _visibleLocals();
    final existing = _labelsByName[name];
    if (existing != null &&
        existing.isNotEmpty &&
        existing.last.scopeDepth == _scopes.length) {
      throw UnsupportedError(
        'lua_bytecode emitter does not support duplicate label $name in one scope',
      );
    }
    final label = _LuaBytecodeStructuredLabel(
      name: name,
      targetPc: _prototype.currentPc,
      scopeDepth: _scopes.length,
      loopDepth: _loopDepth,
      visibleLocals: visible,
    );
    _labelScopes.last.add(label);
    (_labelsByName[name] ??= <_LuaBytecodeStructuredLabel>[]).add(label);
    _resolvePendingGotos(name);
  }

  void _compileGoto(Goto statement) {
    final pending = _LuaBytecodeStructuredPendingGoto(
      label: statement.label.name,
      jumpPc: _prototype.emitJumpPlaceholder(),
      scopeDepth: _scopes.length,
      loopDepth: _loopDepth,
      visibleLocals: _visibleLocals(),
    );
    _pendingGotos.add(pending);
    _resolvePendingGotos(statement.label.name);
  }

  void _compileBreak() {
    if (_breakFixups.isEmpty) {
      throw UnsupportedError(
        'lua_bytecode emitter does not support break here',
      );
    }
    _breakFixups.last.add(_prototype.emitJumpPlaceholder());
  }

  void _compileLocalFunctionDef(
    LocalFunctionDef statement, {
    required int statementIndex,
  }) {
    final binding = _prepareLocal(
      statement.name.name,
      statementIndex: statementIndex,
      attribute: '',
    );
    _activatePreparedLocal(binding, startPc: _prototype.currentPc + 1);
    _emitFunctionBodyToRegister(statement.funcBody, binding.register);
  }

  void _compileFunctionDef(FunctionDef statement) {
    final scratch = _reserveTempBlock(1);
    _emitFunctionBodyToRegister(
      statement.body,
      scratch,
      implicitSelf: statement.implicitSelf,
    );

    if (!statement.implicitSelf && statement.name.rest.isEmpty) {
      final target = _resolveStoreTarget(statement.name.first);
      _storeRegisterToTarget(scratch, target);
    } else {
      _storeRegisterToFunctionNamePath(statement.name, scratch);
    }
    _releaseTempBlock(scratch, 1);
  }

  void _compileScopedBlock(List<AstNode> statements) {
    _enterScope();
    for (final statement in statements) {
      _compileStatement(statement, statementIndex: -1);
    }
    _exitScope(endPc: _prototype.currentPc + 1);
  }

  void _emitValueList(
    List<AstNode> expressions, {
    required int valueCount,
    required void Function(int index, int register) onValue,
    required void Function(int index) onNil,
  }) {
    if (valueCount == 0) {
      if (expressions.isNotEmpty && _isCallExpression(expressions.last)) {
        _emitDiscardedCall(_unwrapExpression(expressions.last) as Call);
      }
      return;
    }

    var valueIndex = 0;
    for (var exprIndex = 0; exprIndex < expressions.length; exprIndex++) {
      final expr = expressions[exprIndex];
      final isLastExpression = exprIndex == expressions.length - 1;
      final remainingValues = valueCount - valueIndex;

      if (remainingValues <= 0) {
        if (isLastExpression && _isCallExpression(expr)) {
          _emitDiscardedCall(_unwrapExpression(expr) as Call);
        } else {
          final scratch = _reserveTempBlock(1);
          _emitExpressionToRegister(expr, scratch);
          _releaseTempBlock(scratch, 1);
        }
        continue;
      }

      if (isLastExpression && _isCallExpression(expr)) {
        final emitted = _emitCallToTemporary(
          _unwrapExpression(expr) as Call,
          resultCount: remainingValues,
        );
        for (var offset = 0; offset < remainingValues; offset++) {
          onValue(valueIndex + offset, emitted.base + offset);
        }
        _releaseTempBlock(emitted.base, emitted.width);
        valueIndex = valueCount;
        continue;
      }

      final scratch = _reserveTempBlock(1);
      _emitExpressionToRegister(expr, scratch);
      onValue(valueIndex, scratch);
      _releaseTempBlock(scratch, 1);
      valueIndex += 1;
    }

    while (valueIndex < valueCount) {
      onNil(valueIndex);
      valueIndex += 1;
    }
  }

  int _emitFalseJumpForCondition(AstNode condition) {
    final register = _reserveTempBlock(1);
    _emitExpressionToRegister(condition, register);
    _prototype.emitTest(register: register, kFlag: false);
    final jumpPc = _prototype.emitJumpPlaceholder();
    _releaseTempBlock(register, 1);
    return jumpPc;
  }

  void _emitExpressionToRegister(AstNode node, int targetRegister) {
    switch (_unwrapExpression(node)) {
      case NilValue():
        _prototype.emitLoadNil(target: targetRegister);
      case BooleanLiteral(value: final value):
        _prototype.emitLoadLiteral(target: targetRegister, literal: value);
      case NumberLiteral(value: final value):
        _prototype.emitLoadLiteral(target: targetRegister, literal: value);
      case StringLiteral(value: final value):
        _prototype.emitLoadLiteral(target: targetRegister, literal: value);
      case Identifier(name: final name):
        _emitIdentifierToRegister(name, targetRegister);
      case UnaryExpression(op: final op, expr: final expr):
        _emitUnaryExpression(op, expr, targetRegister);
      case BinaryExpression(op: '..'):
        _emitConcatExpression(node, targetRegister);
      case BinaryExpression(left: final left, op: final op, right: final right):
        _emitBinaryExpression(left, op, right, targetRegister);
      case TableFieldAccess(table: final table, fieldName: final fieldName):
        _emitTableFieldAccess(table, fieldName.name, targetRegister);
      case TableIndexAccess(table: final table, index: final index):
        _emitTableIndexAccess(table, index, targetRegister);
      case TableAccessExpr(table: final table, index: final index):
        _emitLegacyTableAccess(table, index, targetRegister);
      case TableConstructor(entries: final entries):
        _emitTableConstructor(entries, targetRegister);
      case FunctionCall():
        _emitSingleResultCall(
          _unwrapExpression(node) as FunctionCall,
          targetRegister: targetRegister,
        );
      case MethodCall():
        _emitSingleResultCall(
          _unwrapExpression(node) as MethodCall,
          targetRegister: targetRegister,
        );
      case FunctionLiteral(funcBody: final funcBody):
        _emitFunctionBodyToRegister(funcBody, targetRegister);
      default:
        throw UnsupportedError(
          'lua_bytecode emitter does not support ${node.runtimeType} expressions',
        );
    }
  }

  void _emitIdentifierToRegister(String name, int targetRegister) {
    switch (_resolveVariable(name)) {
      case _LuaBytecodeStructuredResolvedVariable(
        kind: _LuaBytecodeStructuredResolvedVariableKind.local,
        register: final register,
      ):
        if (register != targetRegister) {
          _prototype.emitMove(target: targetRegister, source: register!);
        }
      case _LuaBytecodeStructuredResolvedVariable(
        kind: _LuaBytecodeStructuredResolvedVariableKind.upvalue,
        upvalueIndex: final upvalueIndex,
      ):
        _prototype.emitGetUpvalue(
          target: targetRegister,
          upvalue: upvalueIndex!,
        );
      case _LuaBytecodeStructuredResolvedVariable(
        kind: _LuaBytecodeStructuredResolvedVariableKind.global,
        name: final globalName,
      ):
        _prototype.emitGetTabUp(
          target: targetRegister,
          upvalue: _environmentUpvalueIndex,
          constantIndex: _prototype.addStringConstant(globalName!),
        );
    }
  }

  void _emitUnaryExpression(String op, AstNode expr, int targetRegister) {
    if (!_supportedUnaryOps.contains(op)) {
      throw UnsupportedError(
        'lua_bytecode emitter does not support unary operator $op',
      );
    }

    final operandRegister = _reserveTempBlock(1);
    _emitExpressionToRegister(expr, operandRegister);
    final opcode = switch (op) {
      '-' => 'UNM',
      '~' => 'BNOT',
      'not' => 'NOT',
      '#' => 'LEN',
      _ => throw UnsupportedError(
        'lua_bytecode emitter does not support unary operator $op',
      ),
    };
    _prototype.emitAbc(opcode, a: targetRegister, b: operandRegister, c: 0);
    _releaseTempBlock(operandRegister, 1);
  }

  void _emitBinaryExpression(
    AstNode left,
    String op,
    AstNode right,
    int targetRegister,
  ) {
    if (_isComparisonOperator(op)) {
      _emitComparisonExpression(left, op, right, targetRegister);
      return;
    }
    if (!_supportedBinaryOps.contains(op)) {
      throw UnsupportedError(
        'lua_bytecode emitter does not support binary operator $op',
      );
    }
    if (op == '..') {
      _emitConcatExpression(BinaryExpression(left, op, right), targetRegister);
      return;
    }

    final operandBase = _reserveTempBlock(2);
    _emitExpressionToRegister(left, operandBase);
    _emitExpressionToRegister(right, operandBase + 1);
    _prototype.emitAbc(
      _binaryOpcodeFor(op),
      a: targetRegister,
      b: operandBase,
      c: operandBase + 1,
    );
    _releaseTempBlock(operandBase, 2);
  }

  void _emitComparisonExpression(
    AstNode left,
    String op,
    AstNode right,
    int targetRegister,
  ) {
    final operandBase = _reserveTempBlock(2);
    final comparison = _comparisonPlanFor(op);
    _emitExpressionToRegister(comparison.$1 ? right : left, operandBase);
    _emitExpressionToRegister(comparison.$1 ? left : right, operandBase + 1);
    _prototype.emitAbc(
      comparison.$2,
      a: operandBase,
      b: operandBase + 1,
      c: 0,
      k: comparison.$3,
    );
    _prototype.emitJump(1);
    _prototype.emitAbc('LFALSESKIP', a: targetRegister, b: 0, c: 0);
    _prototype.emitAbc('LOADTRUE', a: targetRegister, b: 0, c: 0);
    _releaseTempBlock(operandBase, 2);
  }

  void _emitConcatExpression(AstNode node, int targetRegister) {
    final operands = <AstNode>[];
    _collectConcatOperands(_unwrapExpression(node), operands);
    final operandBase = _reserveTempBlock(operands.length);
    for (var index = 0; index < operands.length; index++) {
      _emitExpressionToRegister(operands[index], operandBase + index);
    }
    _prototype.emitAbc('CONCAT', a: operandBase, b: operands.length, c: 0);
    if (operandBase != targetRegister) {
      _prototype.emitMove(target: targetRegister, source: operandBase);
    }
    _releaseTempBlock(operandBase, operands.length);
  }

  void _collectConcatOperands(AstNode node, List<AstNode> operands) {
    switch (_unwrapExpression(node)) {
      case BinaryExpression(left: final left, op: '..', right: final right):
        _collectConcatOperands(left, operands);
        _collectConcatOperands(right, operands);
      case final expr:
        operands.add(expr);
    }
  }

  void _emitTableFieldAccess(
    AstNode table,
    String fieldName,
    int targetRegister,
  ) {
    _emitExpressionToRegister(table, targetRegister);
    _prototype.emitGetField(
      target: targetRegister,
      table: targetRegister,
      constantIndex: _prototype.addStringConstant(fieldName),
    );
  }

  void _emitTableIndexAccess(AstNode table, AstNode index, int targetRegister) {
    _emitExpressionToRegister(table, targetRegister);
    final immediateIndex = _immediateIndex(index);
    if (immediateIndex != null) {
      _prototype.emitGetI(
        target: targetRegister,
        table: targetRegister,
        index: immediateIndex,
      );
      return;
    }

    final keyRegister = _reserveTempBlock(1);
    _emitExpressionToRegister(index, keyRegister);
    _prototype.emitGetTable(
      target: targetRegister,
      table: targetRegister,
      key: keyRegister,
    );
    _releaseTempBlock(keyRegister, 1);
  }

  void _emitLegacyTableAccess(
    AstNode table,
    AstNode index,
    int targetRegister,
  ) {
    if (_unwrapExpression(index) case Identifier(name: final name)) {
      _emitTableFieldAccess(table, name, targetRegister);
      return;
    }
    _emitTableIndexAccess(table, index, targetRegister);
  }

  void _emitTableConstructor(List<TableEntry> entries, int targetRegister) {
    final arrayEntryCount = entries.whereType<TableEntryLiteral>().length;
    final trailingOpenEntry = _trailingOpenResultConstructorEntry(entries);
    final needsSetList = arrayEntryCount > 0;
    if (!needsSetList) {
      _prototype.emitNewTable(target: targetRegister, arraySize: 0);
      _emitTableConstructorKeyedEntries(entries, targetRegister);
      return;
    }

    final workingWidth = math.max(
      LuaBytecodeInstructionLayout.maxArgVB,
      trailingOpenEntry == null ? 0 : _callRegisterWidth(trailingOpenEntry),
    );
    final constructorBase = _reserveTempBlock(workingWidth + 1);
    final tableRegister = constructorBase;
    final valueBase = constructorBase + 1;
    _prototype.emitNewTable(target: tableRegister, arraySize: arrayEntryCount);

    final pendingArrayEntries = <AstNode>[];
    var nextArrayIndex = 1;

    void flushPendingArrayEntries() {
      if (pendingArrayEntries.isEmpty) {
        return;
      }

      var offset = 0;
      while (offset < pendingArrayEntries.length) {
        final chunkEnd = math.min(
          offset + LuaBytecodeInstructionLayout.maxArgVB,
          pendingArrayEntries.length,
        );
        final chunk = pendingArrayEntries.sublist(offset, chunkEnd);
        for (var index = 0; index < chunk.length; index++) {
          _emitExpressionToRegister(chunk[index], valueBase + index);
        }
        _prototype.emitSetList(
          table: tableRegister,
          count: chunk.length,
          startIndex: nextArrayIndex,
        );
        nextArrayIndex += chunk.length;
        offset = chunkEnd;
      }

      pendingArrayEntries.clear();
    }

    try {
      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        switch (entry) {
          case TableEntryLiteral(expr: final expr):
            final isLastEntry = index == entries.length - 1;
            final openCall = isLastEntry ? _unwrapExpression(expr) : null;
            if (openCall is Call) {
              flushPendingArrayEntries();
              _emitOpenResultCall(openCall, baseRegister: valueBase);
              _prototype.emitSetList(
                table: tableRegister,
                count: 0,
                startIndex: nextArrayIndex,
              );
              nextArrayIndex += 1;
              continue;
            }

            pendingArrayEntries.add(expr);
            if (pendingArrayEntries.length ==
                LuaBytecodeInstructionLayout.maxArgVB) {
              flushPendingArrayEntries();
            }
          case KeyedTableEntry(key: final key, value: final value):
            flushPendingArrayEntries();
            final field = _unwrapExpression(key);
            if (field is! Identifier) {
              throw UnsupportedError(
                'lua_bytecode emitter only supports identifier keyed table entries',
              );
            }
            final valueRegister = _reserveTempBlock(1);
            _emitExpressionToRegister(value, valueRegister);
            _prototype.emitSetField(
              table: tableRegister,
              constantIndex: _prototype.addStringConstant(field.name),
              source: valueRegister,
            );
            _releaseTempBlock(valueRegister, 1);
          case IndexedTableEntry(key: final key, value: final value):
            flushPendingArrayEntries();
            final valueRegister = _reserveTempBlock(1);
            _emitExpressionToRegister(value, valueRegister);
            _emitTableIndexStore(
              tableRegister: tableRegister,
              index: key,
              sourceRegister: valueRegister,
            );
            _releaseTempBlock(valueRegister, 1);
        }
      }

      flushPendingArrayEntries();
      if (tableRegister != targetRegister) {
        _prototype.emitMove(target: targetRegister, source: tableRegister);
      }
    } finally {
      _releaseTempBlock(constructorBase, workingWidth + 1);
    }
  }

  void _emitTableConstructorKeyedEntries(
    List<TableEntry> entries,
    int tableRegister,
  ) {
    for (final entry in entries) {
      switch (entry) {
        case TableEntryLiteral():
          throw UnsupportedError(
            'lua_bytecode emitter expected array entries for setlist-backed constructors',
          );
        case KeyedTableEntry(key: final key, value: final value):
          final field = _unwrapExpression(key);
          if (field is! Identifier) {
            throw UnsupportedError(
              'lua_bytecode emitter only supports identifier keyed table entries',
            );
          }
          final valueRegister = _reserveTempBlock(1);
          _emitExpressionToRegister(value, valueRegister);
          _prototype.emitSetField(
            table: tableRegister,
            constantIndex: _prototype.addStringConstant(field.name),
            source: valueRegister,
          );
          _releaseTempBlock(valueRegister, 1);
        case IndexedTableEntry(key: final key, value: final value):
          final valueRegister = _reserveTempBlock(1);
          _emitExpressionToRegister(value, valueRegister);
          _emitTableIndexStore(
            tableRegister: tableRegister,
            index: key,
            sourceRegister: valueRegister,
          );
          _releaseTempBlock(valueRegister, 1);
      }
    }
  }

  Call? _trailingOpenResultConstructorEntry(List<TableEntry> entries) {
    if (entries.isEmpty) {
      return null;
    }
    final lastEntry = entries.last;
    if (lastEntry case TableEntryLiteral(expr: final expr)) {
      final normalized = _unwrapExpression(expr);
      if (normalized is Call) {
        return normalized;
      }
    }
    return null;
  }

  void _emitFunctionBodyToRegister(
    FunctionBody body,
    int targetRegister, {
    bool implicitSelf = false,
  }) {
    if (body.implicitSelf && !implicitSelf) {
      throw UnsupportedError(
        'lua_bytecode emitter does not support implicit-self function bodies',
      );
    }
    final parameterList = <Identifier>[...?body.parameters];
    if (implicitSelf &&
        (parameterList.isEmpty || parameterList.first.name != 'self')) {
      parameterList.insert(0, Identifier('self'));
    }
    final childPrototype = LuaBytecodePrototypeBuilder(
      lineDefined: _startLine(body),
      lastLineDefined: _endLine(body),
      parameterCount: parameterList.length,
      flags: body.isVararg ? LuaBytecodePrototypeFlags.hasHiddenVarargs : 0,
      source: _prototype.source,
    );
    final childCompiler = _LuaBytecodeStructuredCompiler.nested(
      childPrototype,
      this,
      parameters: parameterList,
    );
    childCompiler.compileFunctionBody(body.body);
    final childIndex = _prototype.addChildPrototype(childPrototype);
    _prototype.emitClosure(target: targetRegister, childIndex: childIndex);
  }

  void _storeRegisterToFunctionNamePath(FunctionName name, int sourceRegister) {
    late final String fieldName;
    final tablePath = <Identifier>[name.first];

    if (name.method != null) {
      fieldName = name.method!.name;
      tablePath.addAll(name.rest);
    } else {
      fieldName = name.rest.last.name;
      tablePath.addAll(name.rest.take(name.rest.length - 1));
    }

    final tableRegister = _reserveTempBlock(1);
    _emitQualifiedTablePathToRegister(tablePath, tableRegister);
    _prototype.emitSetField(
      table: tableRegister,
      constantIndex: _prototype.addStringConstant(fieldName),
      source: sourceRegister,
    );
    _releaseTempBlock(tableRegister, 1);
  }

  void _emitQualifiedTablePathToRegister(
    List<Identifier> path,
    int targetRegister,
  ) {
    if (path.isEmpty) {
      throw UnsupportedError(
        'lua_bytecode emitter requires a non-empty function target path',
      );
    }

    _emitIdentifierToRegister(path.first.name, targetRegister);
    for (final segment in path.skip(1)) {
      _prototype.emitGetField(
        target: targetRegister,
        table: targetRegister,
        constantIndex: _prototype.addStringConstant(segment.name),
      );
    }
  }

  void _emitTableIndexStore({
    required int tableRegister,
    required AstNode index,
    required int sourceRegister,
  }) {
    final immediateIndex = _immediateIndex(index);
    if (immediateIndex != null) {
      _prototype.emitSetI(
        table: tableRegister,
        index: immediateIndex,
        source: sourceRegister,
      );
      return;
    }

    final keyRegister = _reserveTempBlock(1);
    _emitExpressionToRegister(index, keyRegister);
    _prototype.emitSetTable(
      table: tableRegister,
      key: keyRegister,
      source: sourceRegister,
    );
    _releaseTempBlock(keyRegister, 1);
  }

  void _emitSingleResultCall(Call call, {required int targetRegister}) {
    final emitted = _emitCallToTemporary(call, resultCount: 1);
    if (emitted.base != targetRegister) {
      _prototype.emitMove(target: targetRegister, source: emitted.base);
    }
    _releaseTempBlock(emitted.base, emitted.width);
  }

  ({int base, int width}) _emitCallToTemporary(
    Call call, {
    required int resultCount,
  }) {
    final width = math.max(_callRegisterWidth(call), math.max(resultCount, 1));
    final base = _reserveTempBlock(width);
    _emitFixedResultCall(call, baseRegister: base, resultCount: resultCount);
    return (base: base, width: width);
  }

  void _emitDiscardedCall(Call call) {
    final width = _callRegisterWidth(call);
    final base = _reserveTempBlock(width);
    _emitNoResultCall(call, baseRegister: base);
    _releaseTempBlock(base, width);
  }

  void _emitOpenResultCall(Call call, {required int baseRegister}) {
    switch (call) {
      case FunctionCall(name: final name, args: final args):
        _emitExpressionToRegister(name, baseRegister);
        for (var index = 0; index < args.length; index++) {
          _emitExpressionToRegister(args[index], baseRegister + index + 1);
        }
        _prototype.emitCallWithOpenResults(
          baseRegister: baseRegister,
          argumentCount: args.length,
        );
      case MethodCall(
        prefix: final prefix,
        methodName: final methodName,
        args: final args,
      ):
        final method = _unwrapExpression(methodName);
        if (method is! Identifier) {
          throw UnsupportedError(
            'lua_bytecode emitter only supports identifier method names',
          );
        }
        _emitExpressionToRegister(prefix, baseRegister);
        _prototype.emitSelf(
          target: baseRegister,
          receiver: baseRegister,
          constantIndex: _prototype.addStringConstant(method.name),
        );
        for (var index = 0; index < args.length; index++) {
          _emitExpressionToRegister(args[index], baseRegister + index + 2);
        }
        _prototype.emitCallWithOpenResults(
          baseRegister: baseRegister,
          argumentCount: args.length + 1,
        );
    }
  }

  void _emitFixedResultCall(
    Call call, {
    required int baseRegister,
    required int resultCount,
  }) {
    switch (call) {
      case FunctionCall(name: final name, args: final args):
        _emitExpressionToRegister(name, baseRegister);
        for (var index = 0; index < args.length; index++) {
          _emitExpressionToRegister(args[index], baseRegister + index + 1);
        }
        _prototype.emitCall(
          baseRegister: baseRegister,
          argumentCount: args.length,
          resultCount: resultCount,
        );
      case MethodCall(
        prefix: final prefix,
        methodName: final methodName,
        args: final args,
      ):
        final method = _unwrapExpression(methodName);
        if (method is! Identifier) {
          throw UnsupportedError(
            'lua_bytecode emitter only supports identifier method names',
          );
        }
        _emitExpressionToRegister(prefix, baseRegister);
        _prototype.emitSelf(
          target: baseRegister,
          receiver: baseRegister,
          constantIndex: _prototype.addStringConstant(method.name),
        );
        for (var index = 0; index < args.length; index++) {
          _emitExpressionToRegister(args[index], baseRegister + index + 2);
        }
        _prototype.emitCall(
          baseRegister: baseRegister,
          argumentCount: args.length + 1,
          resultCount: resultCount,
        );
    }
  }

  void _emitNoResultCall(Call call, {required int baseRegister}) {
    _emitFixedResultCall(call, baseRegister: baseRegister, resultCount: 0);
  }

  void _emitTailCall(Call call, {required int baseRegister}) {
    switch (call) {
      case FunctionCall(name: final name, args: final args):
        _emitExpressionToRegister(name, baseRegister);
        for (var index = 0; index < args.length; index++) {
          _emitExpressionToRegister(args[index], baseRegister + index + 1);
        }
        _prototype.emitTailCall(
          baseRegister: baseRegister,
          argumentCount: args.length,
        );
      case MethodCall(
        prefix: final prefix,
        methodName: final methodName,
        args: final args,
      ):
        final method = _unwrapExpression(methodName);
        if (method is! Identifier) {
          throw UnsupportedError(
            'lua_bytecode emitter only supports identifier method names',
          );
        }
        _emitExpressionToRegister(prefix, baseRegister);
        _prototype.emitSelf(
          target: baseRegister,
          receiver: baseRegister,
          constantIndex: _prototype.addStringConstant(method.name),
        );
        for (var index = 0; index < args.length; index++) {
          _emitExpressionToRegister(args[index], baseRegister + index + 2);
        }
        _prototype.emitTailCall(
          baseRegister: baseRegister,
          argumentCount: args.length + 1,
        );
    }
  }

  int _callRegisterWidth(Call call) => switch (call) {
    FunctionCall(args: final args) => args.length + 1,
    MethodCall(args: final args) => args.length + 2,
    _ => throw UnsupportedError(
      'lua_bytecode emitter does not support ${call.runtimeType} call expressions',
    ),
  };

  _LuaBytecodeStructuredResolvedVariable _resolveVariable(String name) {
    final local = _lookupLocal(name);
    if (local != null) {
      return _LuaBytecodeStructuredResolvedVariable.local(
        name: name,
        register: local.register,
      );
    }

    final capture = _provideCapture(name);
    if (capture != null) {
      return _LuaBytecodeStructuredResolvedVariable.upvalue(
        name: name,
        upvalueIndex: capture.index,
      );
    }

    return _LuaBytecodeStructuredResolvedVariable.global(name: name);
  }

  _LuaBytecodeStructuredStoreTarget _resolveStoreTarget(AstNode node) {
    final target = _unwrapExpression(node);
    switch (target) {
      case Identifier(name: final name):
        final resolved = _resolveVariable(name);
        return switch (resolved.kind) {
          _LuaBytecodeStructuredResolvedVariableKind.local =>
            _LuaBytecodeStructuredStoreTarget.local(
              register: resolved.register!,
            ),
          _LuaBytecodeStructuredResolvedVariableKind.upvalue =>
            _LuaBytecodeStructuredStoreTarget.upvalue(
              upvalueIndex: resolved.upvalueIndex!,
            ),
          _LuaBytecodeStructuredResolvedVariableKind.global =>
            _LuaBytecodeStructuredStoreTarget.global(name: resolved.name!),
        };
      case TableFieldAccess(table: final table, fieldName: final fieldName):
        final tableRegister = _reserveTempBlock(1);
        _emitExpressionToRegister(table, tableRegister);
        return _LuaBytecodeStructuredStoreTarget.field(
          tableRegister: tableRegister,
          fieldName: fieldName.name,
          tempWidth: 1,
        );
      case TableIndexAccess(table: final table, index: final index):
        final immediateIndex = _immediateIndex(index);
        if (immediateIndex != null) {
          final tableRegister = _reserveTempBlock(1);
          _emitExpressionToRegister(table, tableRegister);
          return _LuaBytecodeStructuredStoreTarget.immediateIndex(
            tableRegister: tableRegister,
            index: immediateIndex,
            tempWidth: 1,
          );
        }
        final tempBase = _reserveTempBlock(2);
        _emitExpressionToRegister(table, tempBase);
        _emitExpressionToRegister(index, tempBase + 1);
        return _LuaBytecodeStructuredStoreTarget.computedIndex(
          tableRegister: tempBase,
          keyRegister: tempBase + 1,
          tempWidth: 2,
        );
      case TableAccessExpr(table: final table, index: final index):
        if (_unwrapExpression(index) case Identifier(name: final name)) {
          final tableRegister = _reserveTempBlock(1);
          _emitExpressionToRegister(table, tableRegister);
          return _LuaBytecodeStructuredStoreTarget.field(
            tableRegister: tableRegister,
            fieldName: name,
            tempWidth: 1,
          );
        }
        return _resolveStoreTarget(TableIndexAccess(table, index));
      default:
        throw UnsupportedError(
          'lua_bytecode emitter does not support ${target.runtimeType} assignment targets',
        );
    }
  }

  void _storeRegisterToTarget(
    int sourceRegister,
    _LuaBytecodeStructuredStoreTarget target,
  ) {
    switch (target.kind) {
      case _LuaBytecodeStructuredStoreTargetKind.local:
        if (target.register != sourceRegister) {
          _prototype.emitMove(target: target.register!, source: sourceRegister);
        }
      case _LuaBytecodeStructuredStoreTargetKind.upvalue:
        _prototype.emitSetUpvalue(
          source: sourceRegister,
          upvalue: target.upvalueIndex!,
        );
      case _LuaBytecodeStructuredStoreTargetKind.global:
        _prototype.emitSetTabUp(
          upvalue: _environmentUpvalueIndex,
          constantIndex: _prototype.addStringConstant(target.name!),
          source: sourceRegister,
        );
      case _LuaBytecodeStructuredStoreTargetKind.field:
        _prototype.emitSetField(
          table: target.tableRegister!,
          constantIndex: _prototype.addStringConstant(target.name!),
          source: sourceRegister,
        );
      case _LuaBytecodeStructuredStoreTargetKind.immediateIndex:
        _prototype.emitSetI(
          table: target.tableRegister!,
          index: target.index!,
          source: sourceRegister,
        );
      case _LuaBytecodeStructuredStoreTargetKind.keyedIndex:
        _prototype.emitSetTable(
          table: target.tableRegister!,
          key: target.keyRegister!,
          source: sourceRegister,
        );
    }
  }

  void _releaseStoreTargetTemps(_LuaBytecodeStructuredStoreTarget target) {
    final width = target.tempWidth;
    if (width == null || width == 0) {
      return;
    }
    _releaseTempBlock(target.tableRegister!, width);
  }

  _LuaBytecodeStructuredCapture? _provideCapture(String name) {
    final local = _lookupLocal(name);
    if (local != null) {
      return _LuaBytecodeStructuredCapture(
        index: local.register,
        inStack: true,
      );
    }

    final existing = _upvaluesByName[name];
    if (existing != null) {
      return _LuaBytecodeStructuredCapture(
        index: existing.index,
        inStack: false,
      );
    }

    if (_parent == null) {
      if (name == '_ENV') {
        return const _LuaBytecodeStructuredCapture(index: 0, inStack: false);
      }
      return null;
    }

    final parentCapture = _parent._provideCapture(name);
    if (parentCapture == null) {
      return null;
    }

    final index = _prototype.upvalues.length;
    _prototype.addUpvalue(
      LuaBytecodeUpvalueDescriptor(
        inStack: parentCapture.inStack,
        index: parentCapture.index,
        kind: name == '_ENV'
            ? LuaBytecodeUpvalueKind.globalRegister
            : LuaBytecodeUpvalueKind.localRegister,
        name: name,
      ),
    );
    _upvaluesByName[name] = _LuaBytecodeStructuredUpvalue(
      name: name,
      index: index,
    );
    return _LuaBytecodeStructuredCapture(index: index, inStack: false);
  }

  int get _environmentUpvalueIndex => _provideCapture('_ENV')!.index;

  bool get _prototypeHasVarargs =>
      (_prototype.flags & LuaBytecodePrototypeFlags.hasHiddenVarargs) != 0;

  _LuaBytecodeStructuredLocal? _lookupLocal(String name) {
    final candidates = _localsByName[name];
    if (candidates == null || candidates.isEmpty) {
      return null;
    }
    return candidates.last;
  }

  _LuaBytecodeStructuredLocal _prepareLocal(
    String name, {
    required int statementIndex,
    required String attribute,
  }) {
    final register = _allocateRegisters(1);
    return _LuaBytecodeStructuredLocal(
      name: name,
      register: register,
      startPc: _prototype.currentPc + 1,
      statementIndex: statementIndex,
      attribute: attribute,
    );
  }

  void _activatePreparedLocal(
    _LuaBytecodeStructuredLocal local, {
    required int startPc,
  }) {
    _bindAllocatedRegister(
      local.name,
      register: local.register,
      statementIndex: local.statementIndex,
      attribute: local.attribute,
      startPc: startPc,
    );
  }

  void _declareParameter(String name, {required int register}) {
    _bindAllocatedRegister(
      name,
      register: register,
      statementIndex: -1,
      attribute: '',
      startPc: 1,
    );
  }

  void _bindAllocatedRegister(
    String name, {
    required int register,
    required int statementIndex,
    required String attribute,
    required int startPc,
  }) {
    final local = _LuaBytecodeStructuredLocal(
      name: name,
      register: register,
      startPc: startPc,
      statementIndex: statementIndex,
      attribute: attribute,
    );
    _scopes.last.add(local);
    (_localsByName[name] ??= <_LuaBytecodeStructuredLocal>[]).add(local);
    if (_isTopLevel && statementIndex >= 0) {
      _factLocals.add(
        LuaBytecodeLocalFact(
          name: name,
          register: register,
          statementIndex: statementIndex,
          attribute: attribute,
        ),
      );
    }
  }

  int _allocateRegisters(int count) {
    final base = _nextRegister;
    _nextRegister += count;
    _nextTemp = math.max(_nextTemp, _nextRegister);
    _prototype.ensureStack(_nextRegister);
    return base;
  }

  int _reserveTempBlock(int count) {
    _nextTemp = math.max(_nextTemp, _nextRegister);
    final base = _nextTemp;
    _nextTemp += count;
    _prototype.ensureStack(_nextTemp);
    return base;
  }

  void _releaseTempBlock(int base, int count) {
    final expectedTop = base + count;
    if (_nextTemp != expectedTop) {
      throw StateError(
        'lua_bytecode emitter temp release order mismatch: '
        'expected $expectedTop, found $_nextTemp',
      );
    }
    _nextTemp = base;
  }

  void _enterScope() {
    _scopes.add(<_LuaBytecodeStructuredLocal>[]);
    _labelScopes.add(<_LuaBytecodeStructuredLabel>[]);
  }

  void _exitScope({required int endPc}) {
    final labels = _labelScopes.removeLast();
    for (final label in labels.reversed) {
      final bindings = _labelsByName[label.name]!;
      bindings.removeLast();
      if (bindings.isEmpty) {
        _labelsByName.remove(label.name);
      }
    }

    final locals = _scopes.removeLast();
    for (final local in locals) {
      _prototype.addLocalVariable(
        name: local.name,
        startPc: local.startPc,
        endPc: endPc,
      );
    }
    for (final local in locals.reversed) {
      final bindings = _localsByName[local.name]!;
      bindings.removeLast();
      if (bindings.isEmpty) {
        _localsByName.remove(local.name);
      }
    }
  }

  Set<_LuaBytecodeStructuredLocal> _visibleLocals() {
    return <_LuaBytecodeStructuredLocal>{for (final scope in _scopes) ...scope};
  }

  void _resolvePendingGotos(String name) {
    final labels = _labelsByName[name];
    if (labels == null || labels.isEmpty) {
      return;
    }
    final label = labels.last;
    for (var index = 0; index < _pendingGotos.length;) {
      final pending = _pendingGotos[index];
      if (pending.label != name) {
        index += 1;
        continue;
      }
      if (!_canResolveGotoToLabel(pending, label)) {
        index += 1;
        continue;
      }
      _prototype.patchJumpTarget(
        instructionPc: pending.jumpPc,
        targetPc: label.targetPc,
      );
      _pendingGotos.removeAt(index);
    }
  }

  bool _canResolveGotoToLabel(
    _LuaBytecodeStructuredPendingGoto pending,
    _LuaBytecodeStructuredLabel label,
  ) {
    if (label.loopDepth != pending.loopDepth) {
      return false;
    }
    if (label.scopeDepth > pending.scopeDepth) {
      return false;
    }
    for (final local in label.visibleLocals) {
      if (!pending.visibleLocals.contains(local)) {
        return false;
      }
    }
    return true;
  }

  void _ensureResolvedGotos() {
    if (_pendingGotos.isEmpty) {
      return;
    }
    final unresolved = _pendingGotos
        .map((goto) => goto.label)
        .toSet()
        .join(', ');
    throw UnsupportedError(
      'lua_bytecode emitter has no visible label for goto $unresolved',
    );
  }

  int _startLine(AstNode node) => node.getSpan()?.start.line ?? 0;

  int _endLine(AstNode node) => node.getSpan()?.end.line ?? 0;
}

final class _LuaBytecodeStructuredLocal {
  const _LuaBytecodeStructuredLocal({
    required this.name,
    required this.register,
    required this.startPc,
    required this.statementIndex,
    required this.attribute,
  });

  final String name;
  final int register;
  final int startPc;
  final int statementIndex;
  final String attribute;
}

final class _LuaBytecodeStructuredUpvalue {
  const _LuaBytecodeStructuredUpvalue({
    required this.name,
    required this.index,
  });

  final String name;
  final int index;
}

final class _LuaBytecodeStructuredCapture {
  const _LuaBytecodeStructuredCapture({
    required this.index,
    required this.inStack,
  });

  final int index;
  final bool inStack;
}

final class _LuaBytecodeStructuredLabel {
  const _LuaBytecodeStructuredLabel({
    required this.name,
    required this.targetPc,
    required this.scopeDepth,
    required this.loopDepth,
    required this.visibleLocals,
  });

  final String name;
  final int targetPc;
  final int scopeDepth;
  final int loopDepth;
  final Set<_LuaBytecodeStructuredLocal> visibleLocals;
}

final class _LuaBytecodeStructuredPendingGoto {
  const _LuaBytecodeStructuredPendingGoto({
    required this.label,
    required this.jumpPc,
    required this.scopeDepth,
    required this.loopDepth,
    required this.visibleLocals,
  });

  final String label;
  final int jumpPc;
  final int scopeDepth;
  final int loopDepth;
  final Set<_LuaBytecodeStructuredLocal> visibleLocals;
}

enum _LuaBytecodeStructuredResolvedVariableKind { local, upvalue, global }

final class _LuaBytecodeStructuredResolvedVariable {
  const _LuaBytecodeStructuredResolvedVariable.local({
    required String name,
    required int register,
  }) : this._(
         kind: _LuaBytecodeStructuredResolvedVariableKind.local,
         name: name,
         register: register,
       );

  const _LuaBytecodeStructuredResolvedVariable.upvalue({
    required String name,
    required int upvalueIndex,
  }) : this._(
         kind: _LuaBytecodeStructuredResolvedVariableKind.upvalue,
         name: name,
         upvalueIndex: upvalueIndex,
       );

  const _LuaBytecodeStructuredResolvedVariable.global({required String name})
    : this._(
        kind: _LuaBytecodeStructuredResolvedVariableKind.global,
        name: name,
      );

  const _LuaBytecodeStructuredResolvedVariable._({
    required this.kind,
    this.name,
    this.register,
    this.upvalueIndex,
  });

  final _LuaBytecodeStructuredResolvedVariableKind kind;
  final String? name;
  final int? register;
  final int? upvalueIndex;
}

enum _LuaBytecodeStructuredStoreTargetKind {
  local,
  upvalue,
  global,
  field,
  immediateIndex,
  keyedIndex,
}

final class _LuaBytecodeStructuredStoreTarget {
  const _LuaBytecodeStructuredStoreTarget.local({required int register})
    : this._(
        kind: _LuaBytecodeStructuredStoreTargetKind.local,
        register: register,
      );

  const _LuaBytecodeStructuredStoreTarget.upvalue({required int upvalueIndex})
    : this._(
        kind: _LuaBytecodeStructuredStoreTargetKind.upvalue,
        upvalueIndex: upvalueIndex,
      );

  const _LuaBytecodeStructuredStoreTarget.global({required String name})
    : this._(kind: _LuaBytecodeStructuredStoreTargetKind.global, name: name);

  const _LuaBytecodeStructuredStoreTarget.field({
    required int tableRegister,
    required String fieldName,
    required int tempWidth,
  }) : this._(
         kind: _LuaBytecodeStructuredStoreTargetKind.field,
         tableRegister: tableRegister,
         name: fieldName,
         tempWidth: tempWidth,
       );

  const _LuaBytecodeStructuredStoreTarget.immediateIndex({
    required int tableRegister,
    required int index,
    required int tempWidth,
  }) : this._(
         kind: _LuaBytecodeStructuredStoreTargetKind.immediateIndex,
         tableRegister: tableRegister,
         index: index,
         tempWidth: tempWidth,
       );

  const _LuaBytecodeStructuredStoreTarget.computedIndex({
    required int tableRegister,
    required int keyRegister,
    required int tempWidth,
  }) : this._(
         kind: _LuaBytecodeStructuredStoreTargetKind.keyedIndex,
         tableRegister: tableRegister,
         keyRegister: keyRegister,
         tempWidth: tempWidth,
       );

  const _LuaBytecodeStructuredStoreTarget._({
    required this.kind,
    this.register,
    this.upvalueIndex,
    this.name,
    this.tableRegister,
    this.keyRegister,
    this.index,
    this.tempWidth,
  });

  final _LuaBytecodeStructuredStoreTargetKind kind;
  final int? register;
  final int? upvalueIndex;
  final String? name;
  final int? tableRegister;
  final int? keyRegister;
  final int? index;
  final int? tempWidth;
}

AstNode _unwrapExpression(AstNode node) => switch (node) {
  GroupedExpression(expr: final expr) => _unwrapExpression(expr),
  _ => node,
};

bool _isCallExpression(AstNode node) => _unwrapExpression(node) is Call;

bool _isComparisonOperator(String op) => switch (op) {
  '==' || '~=' || '<' || '<=' || '>' || '>=' => true,
  _ => false,
};

String _binaryOpcodeFor(String op) => switch (op) {
  '+' => 'ADD',
  '-' => 'SUB',
  '*' => 'MUL',
  '%' => 'MOD',
  '^' => 'POW',
  '/' => 'DIV',
  '//' => 'IDIV',
  '&' => 'BAND',
  '|' => 'BOR',
  '~' => 'BXOR',
  '<<' => 'SHL',
  '>>' => 'SHR',
  _ => throw UnsupportedError(
    'lua_bytecode emitter does not support binary operator $op',
  ),
};

(bool, String, bool) _comparisonPlanFor(String op) => switch (op) {
  '==' => (false, 'EQ', true),
  '~=' => (false, 'EQ', false),
  '<' => (false, 'LT', true),
  '<=' => (false, 'LE', true),
  '>' => (true, 'LT', true),
  '>=' => (true, 'LE', true),
  _ => throw UnsupportedError(
    'lua_bytecode emitter does not support comparison operator $op',
  ),
};

int? _immediateIndex(AstNode node) {
  final expr = _unwrapExpression(node);
  final value = switch (expr) {
    NumberLiteral(value: final int value) => value,
    NumberLiteral(value: final BigInt value)
        when value >= BigInt.zero &&
            value <= BigInt.from(LuaBytecodeInstructionLayout.maxArgC) =>
      value.toInt(),
    _ => null,
  };
  if (value == null || value < 0) {
    return null;
  }
  if (value > LuaBytecodeInstructionLayout.maxArgC) {
    return null;
  }
  return value;
}
