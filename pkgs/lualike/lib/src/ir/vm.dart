import 'dart:async';
import 'dart:math';

import 'package:lualike/src/environment.dart';
import 'package:lualike/src/logging/logger.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/number_limits.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/runtime/vararg_table.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/value.dart';

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';

const int _returnAll = -1;

class LualikeIrUpvalueCell {
  LualikeIrUpvalueCell.fromFrame(IrFrame frame, int index)
    : _frame = frame,
      _index = index,
      _closedValue = frame.getRegister(index);

  LualikeIrUpvalueCell.closed([dynamic value])
    : _frame = null,
      _index = -1,
      _closedValue = value;

  IrFrame? _frame;
  final int _index;
  dynamic _closedValue;

  dynamic get value {
    final frame = _frame;
    if (frame != null) {
      return frame.getRegister(_index);
    }
    return _closedValue;
  }

  set value(dynamic newValue) {
    final frame = _frame;
    if (frame != null) {
      frame.setRegister(_index, newValue);
      _closedValue = frame.getRegister(_index);
      return;
    }
    _closedValue = newValue;
  }

  void close() {
    final frame = _frame;
    if (frame != null) {
      _closedValue = frame.getRegister(_index);
      _frame = null;
    }
  }
}

class _ToBeClosedRecord {
  _ToBeClosedRecord({required this.register, required this.value});

  final int register;
  final Value value;
}

class LualikeIrClosure implements LuaCallableArtifact {
  LualikeIrClosure({
    required this.prototype,
    required List<LualikeIrUpvalueCell> upvalues,
  }) : upvalues = List<LualikeIrUpvalueCell>.from(upvalues);

  final LualikeIrPrototype prototype;
  final List<LualikeIrUpvalueCell> upvalues;

  @override
  LuaFunctionDebugInfo? get debugInfo {
    final source = prototype.debugInfo?.absoluteSourcePath;
    if (source == null) {
      return LuaFunctionDebugInfo(
        source: '=[C]',
        shortSource: '[C]',
        what: 'Lua',
        lineDefined: prototype.lineDefined > 0 ? prototype.lineDefined : -1,
        lastLineDefined: prototype.lastLineDefined > 0
            ? prototype.lastLineDefined
            : -1,
        nups: prototype.upvalueCount,
        nparams: prototype.paramCount,
        isVararg: prototype.isVararg,
      );
    }

    final shortSource = source.split('/').isNotEmpty
        ? source.split('/').last
        : source;
    return LuaFunctionDebugInfo(
      source: source,
      shortSource: shortSource,
      what: 'Lua',
      lineDefined: prototype.lineDefined > 0 ? prototype.lineDefined : -1,
      lastLineDefined: prototype.lastLineDefined > 0
          ? prototype.lastLineDefined
          : -1,
      nups: prototype.upvalueCount,
      nparams: prototype.paramCount,
      isVararg: prototype.isVararg,
    );
  }
}

class IrFrame {
  IrFrame({
    required this.prototype,
    required List<dynamic> args,
    required List<LualikeIrUpvalueCell> capturedUpvalues,
    required this.returnBase,
    required this.expectedResults,
  }) : upvalues = List<LualikeIrUpvalueCell>.from(capturedUpvalues),
       registers = List<dynamic>.filled(
         _initialRegisterCapacity(prototype, args),
         null,
         growable: true,
       ),
       varargs = prototype.isVararg && args.length > prototype.paramCount
           ? List<dynamic>.from(args.sublist(prototype.paramCount))
           : <dynamic>[],
       _constFlags = List<bool>.from(prototype.registerConstFlags),
       _constSealed = List<bool>.filled(
         prototype.registerConstFlags.length,
         false,
       ) {
    final paramCount = prototype.paramCount;
    for (var i = 0; i < paramCount; i++) {
      setRegister(i, i < args.length ? args[i] : null);
    }
    if (prototype.namedVarargRegister case final int register) {
      setRegister(register, packVarargsTable(varargs));
    }
  }

  final LualikeIrPrototype prototype;
  final List<dynamic> registers;
  final List<LualikeIrUpvalueCell> upvalues;
  final List<dynamic> varargs;
  final List<bool> _constFlags;
  final List<bool> _constSealed;
  int lastExecutedPc = -1;
  int pc = 0;
  int returnBase;
  int expectedResults;
  int top = 0;
  final Map<int, LualikeIrUpvalueCell> _registerUpvalues =
      <int, LualikeIrUpvalueCell>{};
  final List<_ToBeClosedRecord> _toBeClosed = <_ToBeClosedRecord>[];

  dynamic getRegister(int index) {
    if (index >= registers.length) {
      return null;
    }
    return registers[index];
  }

  void setRegister(int index, dynamic value) {
    if (index >= registers.length) {
      registers.length = index + 1;
    }
    if (index < _constFlags.length && _constFlags[index]) {
      if (_constSealed[index]) {
        final opcode =
            lastExecutedPc >= 0 &&
                lastExecutedPc < prototype.instructions.length
            ? prototype.instructions[lastExecutedPc].opcode.name
            : 'unknown';
        // Temporary instrumentation
        // ignore: avoid_print
        print(
          'Const write violation at register $index (pc=$lastExecutedPc, opcode=$opcode)',
        );
        throw LuaError('attempt to assign to const variable');
      }
    }
    registers[index] = value;
    if (index >= top) {
      top = index + 1;
    }
  }

  void sealConstRegister(int index) {
    if (index >= 0 && index < _constSealed.length) {
      _constSealed[index] = true;
    }
  }

  void truncateRegisters(int newTop) {
    if (newTop < 0) {
      newTop = 0;
    }
    if (newTop >= top) {
      return;
    }
    for (var i = newTop; i < top; i++) {
      if (i < registers.length) {
        registers[i] = null;
      }
    }
    top = newTop;
  }

  LualikeIrUpvalueCell captureRegister(int index) {
    return _registerUpvalues.putIfAbsent(
      index,
      () => LualikeIrUpvalueCell.fromFrame(this, index),
    );
  }

  void closeOpenUpvalues() {
    closeOpenUpvaluesFrom();
  }

  void closeOpenUpvaluesFrom([int fromIndex = 0]) {
    final keys =
        _registerUpvalues.keys.where((key) => key >= fromIndex).toList()
          ..sort((a, b) => b.compareTo(a));
    for (final key in keys) {
      final cell = _registerUpvalues.remove(key);
      cell?.close();
    }
  }

  void markToBeClosed(int registerIndex) {
    final rawValue = getRegister(registerIndex);
    try {
      final closable = Value.toBeClose(rawValue);
      setRegister(registerIndex, closable);
      _toBeClosed.removeWhere((entry) => entry.register == registerIndex);
      _toBeClosed.add(
        _ToBeClosedRecord(register: registerIndex, value: closable),
      );
    } on UnsupportedError catch (error, stackTrace) {
      final message = error.message ?? error.toString();
      throw LuaError(message, cause: error, stackTrace: stackTrace);
    }
  }

  Future<void> closeToBeClosed(int fromIndex, [dynamic error]) async {
    for (var i = _toBeClosed.length - 1; i >= 0; i--) {
      final entry = _toBeClosed[i];
      if (entry.register < fromIndex) {
        continue;
      }
      _toBeClosed.removeAt(i);
      await entry.value.close(error);
    }
  }

  static int _initialRegisterCapacity(
    LualikeIrPrototype prototype,
    List<dynamic> args,
  ) {
    final paramCapacity = prototype.paramCount + 1;
    final prototypeCapacity = prototype.registerCount;
    final argsCapacity = args.length + 1;
    final baseCapacity = max(max(paramCapacity, prototypeCapacity), 1);
    return max(baseCapacity, argsCapacity);
  }
}

/// Minimal lualike IR VM capable of executing the subset of opcodes currently
/// produced by [LualikeIrCompiler]. The implementation will expand as more AST
/// features are lowered to lualike IR.
class LualikeIrVm {
  LualikeIrVm({Environment? environment, LuaRuntime? runtime})
    : environment = environment ?? Environment() {
    this.runtime = runtime ?? this.environment.interpreter;
    final activeRuntime = this.runtime;
    if (activeRuntime != null && this.environment.interpreter == null) {
      this.environment.interpreter = activeRuntime;
    }
  }

  final Environment environment;
  late final LuaRuntime? runtime;
  static final Object _metamethodNotFound = Object();
  Value? get _globalEnvValue {
    final global = environment.get('_G');
    return global is Value ? global : null;
  }

  Value? get _envTableValue {
    final envEntry = environment.get('_ENV');
    if (envEntry is! Value) {
      return null;
    }
    final raw = envEntry.raw;
    if (raw == null) {
      return null;
    }
    final global = _globalEnvValue;
    if (global != null && identical(global.raw, raw)) {
      return null;
    }
    return envEntry;
  }

  void _logVm(
    String Function() messageBuilder, {
    Set<String>? categories,
    Map<String, Object?> Function()? contextBuilder,
  }) {
    if (!Logger.enabled) {
      return;
    }
    Logger.debugLazy(
      messageBuilder,
      category: 'LualikeIrVm',
      categories: categories,
      contextBuilder: contextBuilder,
    );
  }

  String _describeValue(dynamic value) {
    if (value is LualikeIrClosure) {
      return 'LualikeIrClosure(protoRegisters=${value.prototype.registerCount})';
    }
    if (value is Value) {
      final raw = value.raw;
      final typeName = raw == null ? 'nil' : raw.runtimeType.toString();
      return 'Value<$typeName>';
    }
    if (value == null) {
      return 'null';
    }
    return value.runtimeType.toString();
  }

  String _describeRegisters(IrFrame frame, LualikeIrInstruction instruction) {
    return instruction.when(
      abc: (instr) {
        final a = frame.getRegister(instr.a);
        final b = frame.getRegister(instr.b);
        final c = frame.getRegister(instr.c);
        return 'A=${_describeValue(a)} B=${_describeValue(b)} C=${_describeValue(c)}';
      },
      abx: (instr) {
        final a = frame.getRegister(instr.a);
        return 'A=${_describeValue(a)} Bx=${instr.bx}';
      },
      asbx: (instr) {
        final a = frame.getRegister(instr.a);
        return 'A=${_describeValue(a)} sBx=${instr.sBx}';
      },
      ax: (instr) => 'Ax=${instr.ax}',
      asj: (instr) => 'sJ=${instr.sJ}',
      avbc: (instr) {
        final a = frame.getRegister(instr.a);
        final vB = frame.getRegister(instr.vB);
        final vC = frame.getRegister(instr.vC);
        return 'A=${_describeValue(a)} vB=${_describeValue(vB)} vC=${_describeValue(vC)}';
      },
    );
  }

  void _logTableTypeMismatch(
    IrFrame frame,
    int registerIndex,
    String opcodeName,
  ) {
    if (!Logger.enabled) {
      return;
    }
    final tableValue = frame.getRegister(registerIndex);
    final raw = tableValue is Value ? tableValue.raw : tableValue;
    if (raw is! num) {
      return;
    }
    final pc = frame.lastExecutedPc;
    final lineInfo = frame.prototype.debugInfo?.lineInfo;
    final line = lineInfo != null && pc >= 0 && pc < lineInfo.length
        ? lineInfo[pc]
        : -1;
    _logVm(
      () =>
          'Type mismatch $opcodeName r$registerIndex value=${_describeValue(tableValue)} pc=$pc line=$line',
      categories: const {'Table', 'Error'},
    );
  }

  Future<Object?> execute(LualikeIrChunk chunk) async {
    _logVm(
      () => 'Executing chunk',
      categories: const {'Execute'},
      contextBuilder: () => {
        'registers': chunk.mainPrototype.registerCount,
        'instructions': chunk.mainPrototype.instructions.length,
        'constants': chunk.mainPrototype.constants.length,
      },
    );
    final rawResults = await _runFrames(<IrFrame>[
      IrFrame(
        prototype: chunk.mainPrototype,
        args: const [],
        capturedUpvalues: const <LualikeIrUpvalueCell>[],
        returnBase: 0,
        expectedResults: _returnAll,
      ),
    ], isMainChunk: true);
    return _finalizeResults(rawResults);
  }

  Future<Object?> invokeClosure(
    LualikeIrClosure closure,
    List<Object?> args, {
    int expectedResults = _returnAll,
  }) async {
    _logVm(
      () => 'Invoking lualike IR closure',
      categories: const {'Execute', 'Call'},
      contextBuilder: () => {
        'params': closure.prototype.paramCount,
        'vararg': closure.prototype.isVararg,
        'args': args.length,
        'expected': expectedResults,
      },
    );
    final rawResults = await _runFrames(<IrFrame>[
      IrFrame(
        prototype: closure.prototype,
        args: args,
        capturedUpvalues: closure.upvalues,
        returnBase: 0,
        expectedResults: expectedResults,
      ),
    ]);
    return _finalizeResults(rawResults);
  }

  Future<List<dynamic>> _runFrames(
    List<IrFrame> frames, {
    bool isMainChunk = false,
  }) async {
    List<dynamic>? finalResults;

    if (frames.isNotEmpty) {
      _pushCallStackFrame(frames.last, isMainChunk: isMainChunk);
    }

    int signExtend(int value, int bitCount) {
      final limit = 1 << (bitCount - 1);
      final mask = (1 << bitCount) - 1;
      final unsigned = value & mask;
      return unsigned >= limit ? unsigned - (1 << bitCount) : unsigned;
    }

    void handleTopLevelReturn(List<dynamic> results) {
      finalResults = results;
    }

    while (frames.isNotEmpty) {
      final frame = frames.last;
      final instructions = frame.prototype.instructions;
      final constants = frame.prototype.constants;
      final registers = frame.registers;

      if (frame.pc >= instructions.length) {
        await _handleReturn(frames, const [], handleTopLevelReturn);
        continue;
      }

      final instruction = instructions[frame.pc];
      frame.pc += 1;
      frame.lastExecutedPc = frame.pc - 1;

      _updateCallStackLine(frame, frame.pc - 1);

      final lineInfo = frame.prototype.debugInfo?.lineInfo;
      final line = lineInfo != null
          ? lineInfo[frame.lastExecutedPc < lineInfo.length
                ? frame.lastExecutedPc
                : lineInfo.length - 1]
          : -1;

      _logVm(
        () =>
            'pc=${frame.pc - 1} line=$line opcode=${instruction.opcode.name} regs=${_describeRegisters(frame, instruction)}',
        categories: const {'Opcode'},
        contextBuilder: () => {
          'frameDepth': frames.length,
          'registerTop': frame.top,
          'returnBase': frame.returnBase,
          'expectedResults': frame.expectedResults,
          'line': line,
        },
      );

      switch (instruction.opcode) {
        case LualikeIrOpcode.move:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, frame.getRegister(instr.b));
          break;
        case LualikeIrOpcode.loadK:
          final instr = instruction as ABxInstruction;
          frame.setRegister(instr.a, _resolveConstant(constants[instr.bx]));
          break;
        case LualikeIrOpcode.loadI:
          {
            final instr = instruction as ABCInstruction;
            frame.setRegister(instr.a, signExtend(instr.b, 8));
            break;
          }
        case LualikeIrOpcode.loadF:
          {
            final instr = instruction as ABCInstruction;
            frame.setRegister(instr.a, signExtend(instr.b, 8).toDouble());
            break;
          }
        case LualikeIrOpcode.loadKx:
          {
            final nextIndex = frame.pc;
            if (nextIndex >= instructions.length) {
              throw StateError('LOADKX missing EXTRAARG');
            }
            final extra = instructions[nextIndex];
            if (extra is! AxInstruction) {
              throw StateError(
                'LOADKX expected EXTRAARG following instruction',
              );
            }
            frame.pc += 1;
            final instr = instruction as ABxInstruction;
            frame.setRegister(instr.a, _resolveConstant(constants[extra.ax]));
            break;
          }
        case LualikeIrOpcode.loadTrue:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, true);
          break;
        case LualikeIrOpcode.loadFalse:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, false);
          break;
        case LualikeIrOpcode.lFalseSkip:
          {
            final instr = instruction as ABCInstruction;
            frame.setRegister(instr.a, false);
            frame.pc += 1;
            break;
          }
        case LualikeIrOpcode.loadNil:
          final instr = instruction as ABCInstruction;
          final count = instr.b;
          for (var offset = 0; offset <= count; offset++) {
            frame.setRegister(instr.a + offset, null);
          }
          break;
        case LualikeIrOpcode.getUpval:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, frame.upvalues[instr.b].value);
          break;
        case LualikeIrOpcode.setUpval:
          final instr = instruction as ABCInstruction;
          frame.upvalues[instr.b].value = registers[instr.c];
          break;
        case LualikeIrOpcode.getTabUp:
          final instr = instruction as ABCInstruction;
          final key = _constantToKey(constants[instr.c]);
          if (key == '_ENV') {
            frame.setRegister(instr.a, environment.get('_ENV'));
            break;
          }
          if (key == '_G') {
            frame.setRegister(instr.a, environment.get('_G'));
            break;
          }
          final envTable = _envTableValue ?? _globalEnvValue;
          if (envTable != null) {
            final value = await _tableGet(envTable, key);
            frame.setRegister(instr.a, value);
            break;
          }
          frame.setRegister(instr.a, environment.get(key));
          break;
        case LualikeIrOpcode.setTabUp:
          final instr = instruction as ABCInstruction;
          final key = _constantToKey(constants[instr.b]);
          final rawValue = instr.k
              ? _resolveConstant(constants[instr.c])
              : registers[instr.c];
          final storedValue = _ensureValue(rawValue);
          if (key == '_ENV') {
            environment.define('_ENV', storedValue);
            break;
          }
          final envTable = _envTableValue ?? _globalEnvValue;
          if (envTable != null) {
            _tableSet(envTable, key, storedValue);
            break;
          }
          environment.define(key, storedValue);
          break;
        case LualikeIrOpcode.getTable:
          {
            final instr = instruction as ABCInstruction;
            final value = await _tableGet(
              registers[instr.b],
              registers[instr.c],
            );
            frame.setRegister(instr.a, value);
            break;
          }
        case LualikeIrOpcode.getField:
          final instr = instruction as ABCInstruction;
          final key = _constantToKey(constants[instr.c]);
          frame.setRegister(instr.a, await _tableGet(registers[instr.b], key));
          break;
        case LualikeIrOpcode.selfOp:
          {
            final instr = instruction as ABCInstruction;
            final object = registers[instr.b];
            final key = _constantToKey(constants[instr.c]);
            frame.setRegister(instr.a + 1, object);
            frame.setRegister(instr.a, await _tableGet(object, key));
            break;
          }
        case LualikeIrOpcode.getI:
          final instr = instruction as ABCInstruction;
          frame.setRegister(
            instr.a,
            await _tableGet(registers[instr.b], instr.c),
          );
          break;
        case LualikeIrOpcode.varArgPrep:
          // No-op: varargs captured at frame creation.
          break;
        case LualikeIrOpcode.varArg:
          final instr = instruction as ABCInstruction;
          final requested = instr.b == 0 ? _returnAll : instr.b - 1;
          if (requested == _returnAll) {
            final start = instr.a;
            for (var i = 0; i < frame.varargs.length; i++) {
              frame.setRegister(start + i, frame.varargs[i]);
            }
            frame.truncateRegisters(start + frame.varargs.length);
          } else {
            for (var i = 0; i < requested; i++) {
              final value = i < frame.varargs.length ? frame.varargs[i] : null;
              frame.setRegister(instr.a + i, value);
            }
          }
          break;
        case LualikeIrOpcode.getVarArg:
          {
            final instr = instruction as ABCInstruction;
            final requestedIndex = instr.c <= 0 ? 0 : instr.c - 1;
            final value = requestedIndex < frame.varargs.length
                ? frame.varargs[requestedIndex]
                : null;
            frame.setRegister(instr.a, value);
            break;
          }
        case LualikeIrOpcode.test:
          final instr = instruction as ABCInstruction;
          final cond = _isTruthy(registers[instr.a]);
          if ((!cond) == instr.k) {
            frame.pc += 1;
          }
          break;
        case LualikeIrOpcode.testSet:
          final instr = instruction as ABCInstruction;
          final cond = _isTruthy(registers[instr.b]);
          if ((!cond) == instr.k) {
            frame.pc += 1;
          } else {
            frame.setRegister(instr.a, registers[instr.b]);
          }
          break;
        case LualikeIrOpcode.jmp:
          final instr = instruction as AsJInstruction;
          frame.pc += instr.sJ;
          break;
        case LualikeIrOpcode.tForPrep:
          {
            final instr = instruction as AsBxInstruction;
            final base = instr.a;
            final closing = frame.getRegister(base + 3);
            final control = frame.getRegister(base + 2);
            frame.setRegister(base + 3, control);
            frame.setRegister(base + 2, closing);
            frame.pc += instr.sBx;
            break;
          }
        case LualikeIrOpcode.tForCall:
          final instr = instruction as ABCInstruction;
          await _executeTForCall(frame, instr.a, instr.c);
          break;
        case LualikeIrOpcode.tForLoop:
          {
            final instr = instruction as AsBxInstruction;
            final control = registers[instr.a + 3];
            if (!_isNilControl(control)) {
              frame.pc += instr.sBx;
            }
            break;
          }
        case LualikeIrOpcode.closure:
          final instr = instruction as ABxInstruction;
          frame.setRegister(instr.a, _createClosure(frame, instr.bx));
          break;
        case LualikeIrOpcode.call:
          {
            final instr = instruction as ABCInstruction;
            final base = instr.a;
            final args = _collectCallArguments(frame, instr);
            final callee = registers[base];
            final expectedResults = instr.c == 0 ? _returnAll : instr.c - 1;
            LualikeIrClosure? closure;
            if (callee is LualikeIrClosure) {
              closure = callee;
            } else if (callee is Value && callee.raw is LualikeIrClosure) {
              closure = callee.raw as LualikeIrClosure;
            }
            _logVm(
              () =>
                  'CALL base=$base args=${args.length} expected=$expectedResults',
              categories: const {'Call'},
              contextBuilder: () => {
                'callee': _describeValue(callee),
                'ir': closure != null,
              },
            );
            if (closure != null) {
              frames.add(
                IrFrame(
                  prototype: closure.prototype,
                  args: args,
                  capturedUpvalues: closure.upvalues,
                  returnBase: base,
                  expectedResults: expectedResults,
                ),
              );
              _pushCallStackFrame(frames.last);
              continue;
            }
            final results = await _normalizeResults(
              await _callValue(callee, args),
            );
            _storeResults(frame, base, expectedResults, results);
            _logVm(
              () => 'CALL completed results=${results.length}',
              categories: const {'Call'},
            );
            break;
          }
        case LualikeIrOpcode.tailCall:
          {
            final instr = instruction as ABCInstruction;
            final args = _collectCallArguments(frame, instr);
            final callee = registers[instr.a];
            final currentReturnBase = frame.returnBase;
            final currentExpected = frame.expectedResults;
            LualikeIrClosure? closure;
            if (callee is LualikeIrClosure) {
              closure = callee;
            } else if (callee is Value && callee.raw is LualikeIrClosure) {
              closure = callee.raw as LualikeIrClosure;
            }
            _logVm(
              () =>
                  'TAILCALL base=${instr.a} args=${args.length} expected=$currentExpected',
              categories: const {'Call', 'TailCall'},
              contextBuilder: () => {
                'callee': _describeValue(callee),
                'ir': closure != null,
              },
            );
            if (closure != null) {
              _popCallStackFrame();
              final completed = frames.removeLast();
              await completed.closeToBeClosed(0);
              completed.closeOpenUpvalues();
              frames.add(
                IrFrame(
                  prototype: closure.prototype,
                  args: args,
                  capturedUpvalues: closure.upvalues,
                  returnBase: currentReturnBase,
                  expectedResults: currentExpected,
                ),
              );
              _pushCallStackFrame(frames.last);
              continue;
            }
            final results = await _normalizeResults(
              await _callValue(callee, args),
            );
            _popCallStackFrame();
            final completed = frames.removeLast();
            await completed.closeToBeClosed(0);
            completed.closeOpenUpvalues();
            if (frames.isEmpty) {
              handleTopLevelReturn(results);
            } else {
              final caller = frames.last;
              _storeResults(
                caller,
                currentReturnBase,
                currentExpected,
                results,
              );
              _logVm(
                () => 'TAILCALL fallback results=${results.length}',
                categories: const {'Call', 'TailCall'},
              );
            }
            break;
          }
        case LualikeIrOpcode.setTable:
          final instr = instruction as ABCInstruction;
          _logTableTypeMismatch(frame, instr.a, 'SETTABLE');
          final value = instr.k
              ? _resolveConstant(constants[instr.c])
              : registers[instr.c];
          _tableSet(registers[instr.a], registers[instr.b], value);
          break;
        case LualikeIrOpcode.setField:
          final instr = instruction as ABCInstruction;
          _logTableTypeMismatch(frame, instr.a, 'SETFIELD');
          final key = _constantToKey(constants[instr.b]);
          final value = instr.k
              ? _resolveConstant(constants[instr.c])
              : registers[instr.c];
          _tableSet(registers[instr.a], key, value);
          break;
        case LualikeIrOpcode.setI:
          final instr = instruction as ABCInstruction;
          _logTableTypeMismatch(frame, instr.a, 'SETI');
          final value = instr.k
              ? _resolveConstant(constants[instr.c])
              : registers[instr.c];
          _tableSet(registers[instr.a], instr.b, value);
          break;
        case LualikeIrOpcode.setList:
          final instr = instruction as ABCInstruction;
          final table = registers[instr.a];
          var startIndex = instr.c;
          if (startIndex == 0) {
            final extraIndex = frame.pc;
            if (extraIndex >= instructions.length) {
              throw StateError('SETLIST missing EXTRAARG');
            }
            final extra = instructions[extraIndex];
            if (extra is! AxInstruction) {
              throw StateError(
                'SETLIST expected EXTRAARG following instruction',
              );
            }
            frame.pc += 1;
            startIndex = extra.ax;
          }
          if (instr.b == 0) {
            final firstReg = instr.a + 1;
            var arraySlot = startIndex;
            for (var regIndex = firstReg; regIndex < frame.top; regIndex++) {
              _tableSet(table, arraySlot, registers[regIndex]);
              arraySlot += 1;
            }
            frame.truncateRegisters(firstReg);
          } else {
            for (var i = 0; i < instr.b; i++) {
              final value = registers[instr.a + 1 + i];
              _tableSet(table, startIndex + i, value);
            }
            frame.truncateRegisters(instr.a + 1);
          }
          break;
        case LualikeIrOpcode.newTable:
          final instr = instruction as ABCInstruction;
          final tableStorage = TableStorage();
          if (instr.b > 0) {
            tableStorage.ensureArrayCapacity(instr.b);
          }
          registers[instr.a] = _ensureValue(tableStorage);
          break;
        case LualikeIrOpcode.add:
          {
            final future = _maybeFuture(
              _applyBinaryOperation(frame, instruction as ABCInstruction, '+'),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.addI:
          {
            final instr = instruction as ABCInstruction;
            final future = _maybeFuture(
              _applyBinaryImmediate(frame, instr, signExtend(instr.c, 9), '+'),
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.addK:
          {
            final future = _maybeFuture(
              _applyBinaryConstant(
                frame,
                instruction as ABCInstruction,
                constants,
                '+',
              ),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.sub:
          {
            final future = _maybeFuture(
              _applyBinaryOperation(frame, instruction as ABCInstruction, '-'),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.subK:
          {
            final future = _maybeFuture(
              _applyBinaryConstant(
                frame,
                instruction as ABCInstruction,
                constants,
                '-',
              ),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.mul:
          {
            final future = _maybeFuture(
              _applyBinaryOperation(frame, instruction as ABCInstruction, '*'),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.mulK:
          {
            final future = _maybeFuture(
              _applyBinaryConstant(
                frame,
                instruction as ABCInstruction,
                constants,
                '*',
              ),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.div:
          {
            final future = _maybeFuture(
              _applyBinaryOperation(frame, instruction as ABCInstruction, '/'),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.divK:
          {
            final future = _maybeFuture(
              _applyBinaryConstant(
                frame,
                instruction as ABCInstruction,
                constants,
                '/',
              ),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.mod:
          {
            final future = _maybeFuture(
              _applyBinaryOperation(frame, instruction as ABCInstruction, '%'),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.modK:
          {
            final future = _maybeFuture(
              _applyBinaryConstant(
                frame,
                instruction as ABCInstruction,
                constants,
                '%',
              ),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.idiv:
          {
            final future = _maybeFuture(
              _applyBinaryOperation(frame, instruction as ABCInstruction, '//'),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.idivK:
          {
            final future = _maybeFuture(
              _applyBinaryConstant(
                frame,
                instruction as ABCInstruction,
                constants,
                '//',
              ),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.pow:
          {
            final future = _maybeFuture(
              _applyBinaryOperation(frame, instruction as ABCInstruction, '^'),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.powK:
          {
            final future = _maybeFuture(
              _applyBinaryConstant(
                frame,
                instruction as ABCInstruction,
                constants,
                '^',
              ),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.band:
          {
            final future = _maybeFuture(
              _applyBinaryOperation(frame, instruction as ABCInstruction, '&'),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.bandK:
          {
            final future = _maybeFuture(
              _applyBinaryConstant(
                frame,
                instruction as ABCInstruction,
                constants,
                '&',
              ),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.bor:
          {
            final future = _maybeFuture(
              _applyBinaryOperation(frame, instruction as ABCInstruction, '|'),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.borK:
          {
            final future = _maybeFuture(
              _applyBinaryConstant(
                frame,
                instruction as ABCInstruction,
                constants,
                '|',
              ),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.bxor:
          {
            final future = _maybeFuture(
              _applyBinaryOperation(frame, instruction as ABCInstruction, '~'),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.bxorK:
          {
            final future = _maybeFuture(
              _applyBinaryConstant(
                frame,
                instruction as ABCInstruction,
                constants,
                '~',
              ),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.mmBin:
          {
            final future = _maybeFuture(
              _applyBinaryOperation(frame, instruction as ABCInstruction, '+'),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.mmBinI:
          {
            final instr = instruction as ABCInstruction;
            final future = _maybeFuture(
              _applyBinaryImmediate(frame, instr, signExtend(instr.c, 9), '+'),
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.mmBinK:
          {
            final future = _maybeFuture(
              _applyBinaryConstant(
                frame,
                instruction as ABCInstruction,
                constants,
                '+',
              ),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.concat:
          {
            final instr = instruction as ABCInstruction;
            final future = _maybeFuture(_applyConcatRange(frame, instr));
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.close:
          {
            final instr = instruction as ABCInstruction;
            await frame.closeToBeClosed(instr.a);
            frame.closeOpenUpvaluesFrom(instr.a);
            break;
          }
        case LualikeIrOpcode.tbc:
          {
            final instr = instruction as ABCInstruction;
            frame.markToBeClosed(instr.a);
            break;
          }
        case LualikeIrOpcode.shl:
          {
            final future = _maybeFuture(
              _applyBinaryOperation(frame, instruction as ABCInstruction, '<<'),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.shlI:
          {
            final instr = instruction as ABCInstruction;
            final imm = signExtend(instr.c, 9);
            final future = _maybeFuture(
              _applyBinaryImmediate(frame, instr, imm, '<<'),
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.shr:
          {
            final future = _maybeFuture(
              _applyBinaryOperation(frame, instruction as ABCInstruction, '>>'),
            );
            if (future != null) {
              await future;
            }
          }
          break;
        case LualikeIrOpcode.shrI:
          {
            final instr = instruction as ABCInstruction;
            final imm = signExtend(instr.c, 9);
            final future = _maybeFuture(
              _applyBinaryImmediate(frame, instr, imm, '>>'),
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.eq:
          {
            final instr = instruction as ABCInstruction;
            final future = _compareAndStore(
              frame,
              instr.a,
              registers[instr.b],
              registers[instr.c],
              '==',
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.eqK:
          {
            final instr = instruction as ABCInstruction;
            final constant = _resolveConstant(constants[instr.c]);
            final future = _compareAndStore(
              frame,
              instr.a,
              registers[instr.b],
              constant,
              '==',
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.eqI:
          {
            final instr = instruction as ABCInstruction;
            final future = _compareAndStore(
              frame,
              instr.a,
              registers[instr.b],
              instr.c,
              '==',
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.lt:
          {
            final instr = instruction as ABCInstruction;
            final future = _compareAndStore(
              frame,
              instr.a,
              registers[instr.b],
              registers[instr.c],
              '<',
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.ltI:
          {
            final instr = instruction as ABCInstruction;
            final future = _compareAndStore(
              frame,
              instr.a,
              registers[instr.b],
              instr.c,
              '<',
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.le:
          {
            final instr = instruction as ABCInstruction;
            final future = _compareAndStore(
              frame,
              instr.a,
              registers[instr.b],
              registers[instr.c],
              '<=',
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.leI:
          {
            final instr = instruction as ABCInstruction;
            final future = _compareAndStore(
              frame,
              instr.a,
              registers[instr.b],
              instr.c,
              '<=',
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.gtI:
          {
            final instr = instruction as ABCInstruction;
            final future = _compareAndStore(
              frame,
              instr.a,
              registers[instr.b],
              instr.c,
              '>',
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.geI:
          {
            final instr = instruction as ABCInstruction;
            final future = _compareAndStore(
              frame,
              instr.a,
              registers[instr.b],
              instr.c,
              '>=',
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.unm:
          {
            final future = _maybeFuture(
              _unaryNegate(frame, instruction as ABCInstruction),
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.bnot:
          {
            final future = _maybeFuture(
              _unaryBitwiseNot(frame, instruction as ABCInstruction),
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.notOp:
          _unaryBoolean(frame, instruction as ABCInstruction);
          break;
        case LualikeIrOpcode.len:
          {
            final future = _maybeFuture(
              _unaryLength(frame, instruction as ABCInstruction),
            );
            if (future != null) {
              await future;
            }
            break;
          }
        case LualikeIrOpcode.ret:
          final instr = instruction as ABCInstruction;
          if (instr.b == 0) {
            final fixedCount = instr.c;
            final results = <dynamic>[];
            for (var i = 0; i < fixedCount; i++) {
              results.add(frame.getRegister(instr.a + i));
            }
            final startIndex = instr.a + fixedCount;
            for (var index = startIndex; index < frame.top; index++) {
              results.addAll(_expandValue(frame.getRegister(index)));
            }
            await _handleReturn(frames, results, handleTopLevelReturn);
          } else {
            final count = instr.b - 1;
            final results = <dynamic>[];
            for (var i = 0; i < count; i++) {
              results.add(frame.getRegister(instr.a + i));
            }
            await _handleReturn(frames, results, handleTopLevelReturn);
          }
          break;
        case LualikeIrOpcode.return0:
          await _handleReturn(frames, const [], handleTopLevelReturn);
          break;
        case LualikeIrOpcode.return1:
          final instr = instruction as ABCInstruction;
          frame.truncateRegisters(instr.a + 1);
          await _handleReturn(frames, <dynamic>[
            frame.getRegister(instr.a),
          ], handleTopLevelReturn);
          break;
        case LualikeIrOpcode.forPrep:
          final instr = instruction as AsBxInstruction;
          _executeForPrep(frame, instr.a);
          frame.pc += instr.sBx;
          break;
        case LualikeIrOpcode.forLoop:
          final instr = instruction as AsBxInstruction;
          final shouldContinue = _executeForLoop(frame, instr.a);
          if (shouldContinue) {
            frame.pc += instr.sBx;
          }
          break;
        case LualikeIrOpcode.extraArg:
          // EXTRAARG is consumed by the preceding instruction (e.g., LOADKX).
          // Execution reaches here only if an instruction failed to process it.
          break;
        default:
          _logVm(
            () => 'Unsupported opcode ${instruction.opcode.name}',
            categories: const {'Opcode', 'Error'},
          );
          throw UnsupportedError(
            'Opcode ${instruction.opcode} not yet supported in LualikeIrVm',
          );
      }

      final seals = frame.prototype.constSealPoints[frame.lastExecutedPc];
      if (seals != null) {
        for (final reg in seals) {
          frame.sealConstRegister(reg);
        }
      }
    }

    return finalResults ?? const <dynamic>[];
  }

  List<dynamic> _collectCallArguments(
    IrFrame frame,
    ABCInstruction instruction,
  ) {
    if (instruction.b == 0) {
      final args = <dynamic>[];
      var topIndex = frame.top;
      while (topIndex > instruction.a + 1 &&
          frame.registers[topIndex - 1] == null) {
        topIndex -= 1;
      }
      for (var index = instruction.a + 1; index < topIndex; index++) {
        args.addAll(_expandValue(frame.registers[index]));
      }
      return _prepareCallArguments(args);
    }
    final argCount = instruction.b - 1;
    final args = <dynamic>[];
    for (var i = 0; i < argCount; i++) {
      args.addAll(_expandValue(frame.registers[instruction.a + 1 + i]));
    }
    return _prepareCallArguments(args);
  }

  void _storeResults(
    IrFrame frame,
    int base,
    int expectedResults,
    List<dynamic> results,
  ) {
    if (expectedResults == 0) {
      return;
    }
    if (expectedResults == _returnAll) {
      for (var i = 0; i < results.length; i++) {
        frame.setRegister(base + i, results[i]);
      }
      frame.truncateRegisters(base + results.length);
      return;
    }
    for (var i = 0; i < expectedResults; i++) {
      final value = i < results.length ? results[i] : null;
      frame.setRegister(base + i, value);
    }
  }

  Future<void> _handleReturn(
    List<IrFrame> frames,
    List<dynamic> results,
    void Function(List<dynamic>) onTopLevel, {
    int? returnBase,
    int? expectedResults,
  }) async {
    if (Logger.enabled && frames.isNotEmpty) {
      final frame = frames.last;
      _logVm(
        () => 'Returning ${results.length} value(s)',
        categories: const {'Return'},
        contextBuilder: () => {
          'remainingFrames': frames.length - 1,
          'returnBase': returnBase ?? frame.returnBase,
          'expectedResults': expectedResults ?? frame.expectedResults,
        },
      );
    }
    final completed = frames.removeLast();
    _popCallStackFrame();
    await completed.closeToBeClosed(0);
    completed.closeOpenUpvalues();
    if (frames.isEmpty) {
      _logVm(
        () => 'Top-level return (${results.length} value(s))',
        categories: const {'Return'},
      );
      onTopLevel(results);
      return;
    }
    final base = returnBase ?? completed.returnBase;
    final expected = expectedResults ?? completed.expectedResults;
    final caller = frames.last;
    _storeResults(caller, base, expected, results);
  }

  List<dynamic> _expandValue(dynamic value) {
    if (value is Value && value.isMulti && value.raw is List) {
      return List<dynamic>.from(value.raw as List);
    }
    if (value is List) {
      return List<dynamic>.from(value);
    }
    return <dynamic>[value];
  }

  Object? _finalizeResults(List<dynamic>? results) {
    if (results == null || results.isEmpty) {
      return null;
    }
    if (results.length == 1) {
      return _finalizeValue(results.first);
    }
    return List<dynamic>.from(results.map(_finalizeValue), growable: false);
  }

  dynamic _finalizeValue(dynamic value) {
    if (value is Value && value.isPrimitiveLike) {
      return value.raw;
    }
    return value;
  }

  void _ensureInterpreterAttached(Value value) {
    final runtime = environment.interpreter;
    if (runtime != null && !identical(value.interpreter, runtime)) {
      value.interpreter = runtime;
    }
  }

  Value _ensureValue(dynamic raw) {
    if (raw is Value) {
      _ensureInterpreterAttached(raw);
      return raw;
    }
    final value = Value(raw);
    _ensureInterpreterAttached(value);
    return value;
  }

  List<dynamic> _prepareCallArguments(List<dynamic> args) {
    if (args.isEmpty) {
      return const <dynamic>[];
    }
    return args.map(_prepareCallArgument).toList(growable: false);
  }

  dynamic _prepareCallArgument(dynamic arg) {
    if (arg is Value) {
      _ensureInterpreterAttached(arg);
      return arg;
    }
    if (arg is LualikeIrClosure) {
      return _ensureValue(arg);
    }
    if (arg is List && arg is! Value) {
      return arg.map(_prepareCallArgument).toList();
    }
    return _ensureValue(arg);
  }

  void _pushCallStackFrame(IrFrame frame, {bool isMainChunk = false}) {
    final runtime = this.runtime;
    if (runtime == null) {
      return;
    }
    final debugPath = frame.prototype.debugInfo?.absoluteSourcePath;
    final previousPath = runtime.callStack.scriptPath;
    if (debugPath != null) {
      runtime.callStack.setScriptPath(debugPath);
    }
    final name = isMainChunk
        ? 'main_chunk'
        : _prototypeDisplayName(frame.prototype);
    runtime.callStack.push(name, env: environment);
    if (debugPath != null) {
      runtime.callStack.setScriptPath(previousPath);
    }
    final top = runtime.callStack.top;
    if (top != null) {
      final fallbackLine = frame.prototype.lineDefined > 0
          ? frame.prototype.lineDefined
          : 1;
      if (fallbackLine > 0) {
        top.currentLine = fallbackLine;
      }
    }
    _updateCallStackLine(frame, frame.pc - 1);
  }

  void _popCallStackFrame() {
    runtime?.callStack.pop();
  }

  void _updateCallStackLine(IrFrame frame, int instructionIndex) {
    final runtime = this.runtime;
    if (runtime == null) {
      return;
    }
    final debugInfo = frame.prototype.debugInfo;
    final top = runtime.callStack.top;
    if (top != null) {
      final fallbackLine = frame.prototype.lineDefined > 0
          ? frame.prototype.lineDefined
          : 1;
      if (debugInfo == null ||
          debugInfo.lineInfo.isEmpty ||
          instructionIndex < 0 ||
          instructionIndex >= debugInfo.lineInfo.length) {
        if (fallbackLine > 0 && top.currentLine <= 0) {
          top.currentLine = fallbackLine;
        }
        return;
      }
      final line = debugInfo.lineInfo[instructionIndex];
      if (line <= 0) {
        if (fallbackLine > 0 && top.currentLine <= 0) {
          top.currentLine = fallbackLine;
        }
        return;
      }
      top.currentLine = line;
    }
  }

  String _prototypeDisplayName(LualikeIrPrototype prototype) {
    if (prototype.lineDefined <= 0) {
      return 'function';
    }
    return 'function@${prototype.lineDefined}';
  }

  LualikeIrClosure _createClosure(IrFrame frame, int prototypeIndex) {
    final child = frame.prototype.prototypes[prototypeIndex];
    final captured = <LualikeIrUpvalueCell>[];
    for (final descriptor in child.upvalueDescriptors) {
      if (descriptor.inStack == 1) {
        captured.add(frame.captureRegister(descriptor.index));
      } else {
        captured.add(frame.upvalues[descriptor.index]);
      }
    }
    _logVm(
      () =>
          'Create closure prototype=$prototypeIndex captured=${captured.length}',
      categories: const {'Closure'},
    );
    return LualikeIrClosure(prototype: child, upvalues: captured);
  }

  dynamic _resolveConstant(LualikeIrConstant constant) {
    return switch (constant) {
      NilConstant() => null,
      BooleanConstant(value: final value) => value,
      IntegerConstant(value: final value) => value,
      NumberConstant(value: final value) => value,
      ShortStringConstant(value: final value) => value,
      LongStringConstant(value: final value) => value,
    };
  }

  String _constantToKey(LualikeIrConstant constant) {
    return switch (constant) {
      ShortStringConstant(value: final value) => value,
      LongStringConstant(value: final value) => value,
      _ => throw StateError('Expected string constant for table lookup'),
    };
  }

  Value _valueOf(dynamic raw) {
    return raw is Value ? raw : Value(raw);
  }

  ({bool handled, dynamic value}) _tryNumericBinary(
    dynamic left,
    dynamic right,
    String operation,
  ) {
    final metamethod = _binaryMetamethodName(operation);
    if (metamethod != null) {
      if (left is Value && left.hasMetamethod(metamethod)) {
        return (handled: false, value: null);
      }
      if (right is Value && right.hasMetamethod(metamethod)) {
        return (handled: false, value: null);
      }
    }

    final leftRaw = _rawValue(left);
    final rightRaw = _rawValue(right);
    if (!_isNumericCandidate(operation, leftRaw, rightRaw)) {
      return (handled: false, value: null);
    }

    final value = _performNumericBinary(operation, leftRaw, rightRaw);
    return (handled: true, value: value);
  }

  bool _isNumericCandidate(String operation, dynamic left, dynamic right) {
    if (operation == '..') {
      return false;
    }
    return _isNumericLike(left) && _isNumericLike(right);
  }

  bool _isNumericLike(dynamic value) {
    return value is num || value is BigInt;
  }

  dynamic _performNumericBinary(String operation, dynamic left, dynamic right) {
    switch (operation) {
      case '+':
        final fastAdd = _fastIntAdd(left, right);
        if (fastAdd != null) {
          return fastAdd;
        }
        return NumberUtils.add(left, right);
      case '-':
        final fastSub = _fastIntSub(left, right);
        if (fastSub != null) {
          return fastSub;
        }
        return NumberUtils.subtract(left, right);
      case '*':
        final fastMul = _fastIntMul(left, right);
        if (fastMul != null) {
          return fastMul;
        }
        return NumberUtils.multiply(left, right);
      case '/':
        return NumberUtils.divide(left, right);
      case '%':
        return NumberUtils.modulo(left, right);
      case '^':
        return NumberUtils.exponentiate(left, right);
      case '//':
        return NumberUtils.floorDivide(left, right);
      case '&':
        return NumberUtils.bitwiseAnd(left, right);
      case '|':
        return NumberUtils.bitwiseOr(left, right);
      case '~':
        return NumberUtils.bitwiseXor(left, right);
      case '<<':
        return NumberUtils.leftShift(left, right);
      case '>>':
        return NumberUtils.rightShift(left, right);
      default:
        throw UnsupportedError('Unsupported numeric operation $operation');
    }
  }

  int? _fastIntAdd(dynamic left, dynamic right) {
    if (left is int && right is int) {
      final result = left + right;
      if (_withinInt64(result)) {
        return result;
      }
    }
    return null;
  }

  int? _fastIntSub(dynamic left, dynamic right) {
    if (left is int && right is int) {
      final result = left - right;
      if (_withinInt64(result)) {
        return result;
      }
    }
    return null;
  }

  int? _fastIntMul(dynamic left, dynamic right) {
    if (left is int && right is int) {
      final result = left * right;
      if (_withinInt64(result)) {
        return result;
      }
    }
    return null;
  }

  bool _withinInt64(int value) {
    return value <= NumberLimits.maxInteger && value >= NumberLimits.minInteger;
  }

  Future<void>? _maybeFuture(FutureOr<void> result) {
    if (result is Future<void>) {
      return result;
    }
    if (result is Future) {
      return result;
    }
    return null;
  }

  FutureOr<void> _applyBinaryOperation(
    IrFrame frame,
    ABCInstruction instruction,
    String operation,
  ) {
    final left = frame.registers[instruction.b];
    final right = frame.registers[instruction.c];
    final numeric = _tryNumericBinary(left, right, operation);
    if (numeric.handled) {
      frame.setRegister(instruction.a, numeric.value);
      return null;
    }

    final leftCandidate = left is Value ? left : _ensureValue(left);
    final rightCandidate = right is Value ? right : _ensureValue(right);
    final leftValue = _canonicalizeValue(leftCandidate);
    final rightValue = _canonicalizeValue(rightCandidate);
    final result = _evaluateBinaryOperation(leftValue, rightValue, operation);
    if (result is Future) {
      return result.then((resolved) {
        frame.setRegister(instruction.a, resolved);
      });
    }
    frame.setRegister(instruction.a, result);
  }

  FutureOr<void> _applyBinaryConstant(
    IrFrame frame,
    ABCInstruction instruction,
    List<LualikeIrConstant> constants,
    String operation,
  ) {
    final left = frame.registers[instruction.b];
    final constant = _resolveConstant(constants[instruction.c]);
    final numeric = _tryNumericBinary(left, constant, operation);
    if (numeric.handled) {
      frame.setRegister(instruction.a, numeric.value);
      return null;
    }

    final leftValue = left is Value ? left : _ensureValue(left);
    final constantValue = constant is Value ? constant : _ensureValue(constant);
    final result = _evaluateBinaryOperation(
      leftValue,
      constantValue,
      operation,
    );
    if (result is Future) {
      return result.then((resolved) {
        frame.setRegister(instruction.a, resolved);
      });
    }
    frame.setRegister(instruction.a, result);
  }

  Future<void> _applyConcatRange(
    IrFrame frame,
    ABCInstruction instruction,
  ) async {
    final registers = frame.registers;
    final start = instruction.b;
    var end = instruction.c;
    if (start >= registers.length) {
      frame.setRegister(instruction.a, null);
      return;
    }
    if (end >= registers.length) {
      end = registers.length - 1;
    }
    if (start >= end) {
      frame.setRegister(instruction.a, registers[start]);
      return;
    }
    while (end > start) {
      final leftIndex = end - 1;
      final rightIndex = end;
      final leftRaw = registers[leftIndex];
      final rightRaw = registers[rightIndex];
      final leftValue = leftRaw is Value ? leftRaw : _ensureValue(leftRaw);
      final rightValue = rightRaw is Value ? rightRaw : _ensureValue(rightRaw);
      final combined = _evaluateBinaryOperation(leftValue, rightValue, '..');
      final resolved = combined is Future ? await combined : combined;
      registers[leftIndex] = resolved;
      end -= 1;
    }
    frame.setRegister(instruction.a, registers[start]);
  }

  FutureOr<void> _applyBinaryImmediate(
    IrFrame frame,
    ABCInstruction instruction,
    int immediate,
    String operation,
  ) {
    final left = frame.registers[instruction.b];
    final numeric = _tryNumericBinary(left, immediate, operation);
    if (numeric.handled) {
      frame.setRegister(instruction.a, numeric.value);
      return null;
    }

    final leftValue = left is Value ? left : _ensureValue(left);
    final rightValue = _ensureValue(immediate);
    final result = _evaluateBinaryOperation(leftValue, rightValue, operation);
    if (result is Future) {
      return result.then((resolved) {
        frame.setRegister(instruction.a, resolved);
      });
    }
    frame.setRegister(instruction.a, result);
  }

  FutureOr<dynamic> _evaluateBinaryOperation(
    Value leftValue,
    Value rightValue,
    String operation,
  ) {
    final metamethodName = _binaryMetamethodName(operation);
    if (metamethodName != null) {
      final metamethodResult = _invokeBinaryMetamethod(
        metamethodName,
        leftValue,
        rightValue,
      );
      if (metamethodResult is Future) {
        return metamethodResult.then((resolved) {
          return _normalizeResults(resolved).then((values) {
            if (values.isNotEmpty) {
              final primary = values.first;
              if (!identical(primary, _metamethodNotFound)) {
                return primary;
              }
            }
            return _fallbackBinaryOperation(leftValue, rightValue, operation);
          });
        });
      }
      return _normalizeResults(metamethodResult).then((values) {
        if (values.isNotEmpty) {
          final primary = values.first;
          if (!identical(primary, _metamethodNotFound)) {
            return primary;
          }
        }
        return _fallbackBinaryOperation(leftValue, rightValue, operation);
      });
    }
    return _fallbackBinaryOperation(leftValue, rightValue, operation);
  }

  FutureOr<dynamic> _invokeBinaryMetamethod(
    String metamethod,
    Value leftValue,
    Value rightValue,
  ) {
    final leftHas = leftValue.hasMetamethod(metamethod);
    final rightHas = rightValue.hasMetamethod(metamethod);
    if (!leftHas && !rightHas) {
      _logVm(
        () => 'Metamethod $metamethod not found',
        categories: const {'Metamethod'},
      );
      return _metamethodNotFound;
    }
    final callee = leftHas ? leftValue : rightValue;
    try {
      _logVm(
        () => 'Metamethod $metamethod invoked',
        categories: const {'Metamethod'},
        contextBuilder: () => {
          'callee': _describeValue(callee),
          'left': _describeValue(leftValue),
          'right': _describeValue(rightValue),
        },
      );
      final future = callee
          .callMetamethodAsync(metamethod, <Value>[leftValue, rightValue])
          .then((result) {
            _logVm(
              () => 'Metamethod $metamethod result ${_describeValue(result)}',
              categories: const {'Metamethod'},
            );
            return result;
          });
      return future;
    } on UnsupportedError {
      _logVm(
        () => 'Metamethod $metamethod unsupported',
        categories: const {'Metamethod'},
      );
      return _metamethodNotFound;
    }
  }

  dynamic _fallbackBinaryOperation(
    Value leftValue,
    Value rightValue,
    String operation,
  ) {
    switch (operation) {
      case '+':
        return leftValue + rightValue;
      case '-':
        return leftValue - rightValue;
      case '*':
        return leftValue * rightValue;
      case '/':
        return leftValue / rightValue;
      case '%':
        return leftValue % rightValue;
      case '^':
        return leftValue.exp(rightValue);
      case '//':
        return leftValue ~/ rightValue;
      case '&':
        return leftValue & rightValue;
      case '|':
        return leftValue | rightValue;
      case '~':
        return leftValue ^ rightValue;
      case '<<':
        return leftValue << rightValue;
      case '>>':
        return leftValue >> rightValue;
      case '..':
        return leftValue.concat(rightValue);
      default:
        throw UnsupportedError('Unsupported operation $operation');
    }
  }

  String? _binaryMetamethodName(String operation) {
    switch (operation) {
      case '+':
        return '__add';
      case '-':
        return '__sub';
      case '*':
        return '__mul';
      case '/':
        return '__div';
      case '%':
        return '__mod';
      case '^':
        return '__pow';
      case '//':
        return '__idiv';
      case '&':
        return '__band';
      case '|':
        return '__bor';
      case '~':
        return '__bxor';
      case '<<':
        return '__shl';
      case '>>':
        return '__shr';
      case '..':
        return '__concat';
      default:
        return null;
    }
  }

  void _executeForPrep(IrFrame frame, int base) {
    final registers = frame.registers;
    final initial = _asNumber(registers[base]);
    final step = _asNumber(registers[base + 2]);
    frame.setRegister(base, initial - step);
    frame.setRegister(base + 3, initial);
  }

  bool _executeForLoop(IrFrame frame, int base) {
    final registers = frame.registers;
    final step = _asNumber(registers[base + 2]);
    final limit = _asNumber(registers[base + 1]);
    final nextValue = _asNumber(registers[base]) + step;
    frame.setRegister(base, nextValue);
    final continueLoop = step > 0 ? nextValue <= limit : nextValue >= limit;
    if (continueLoop) {
      frame.setRegister(base + 3, nextValue);
    }
    return continueLoop;
  }

  Future<void> _executeTForCall(
    IrFrame frame,
    int base,
    int resultCount,
  ) async {
    final registers = frame.registers;
    final iterator = registers[base];
    final state = registers[base + 1];
    final control = registers[base + 3];

    final args = <Object?>[state, control];
    final results = await _normalizeResults(await _callValue(iterator, args));
    for (var i = 0; i < resultCount; i++) {
      final rawValue = i < results.length ? results[i] : null;
      final storedValue = rawValue == null ? null : _ensureValue(rawValue);
      frame.setRegister(base + 4 + i, storedValue);
    }
    final controlRaw = results.isNotEmpty ? results.first : null;
    final controlValue = controlRaw == null ? null : _ensureValue(controlRaw);
    frame.setRegister(base + 3, controlValue);
  }

  dynamic _ensureMetamethodLookup(Value subject, Value key, dynamic result) {
    final isNilResult =
        result == null || (result is Value && result.raw == null);
    if (!isNilResult) {
      return result;
    }
    final stringLib = environment.get('string');
    if (stringLib is! Value) {
      return result;
    }
    final methodEntry = stringLib[Value(key.raw)];
    if (methodEntry is! Value || methodEntry.raw == null) {
      return result;
    }
    return Value((List<Object?> callArgs) async {
      final normalizedArgs = callArgs.map(_prepareCallArgument).toList();
      final hasSelf =
          normalizedArgs.isNotEmpty &&
          normalizedArgs.first is Value &&
          (normalizedArgs.first as Value).raw == subject.raw;
      _logVm(
        () =>
            'metamethod fallback key=${key.raw} hasSelf=$hasSelf args=${normalizedArgs.map(_describeValue).join(', ')}',
        categories: const {'Metamethod', 'String'},
      );
      if (!hasSelf) {
        normalizedArgs.insert(0, subject);
        _logVm(
          () =>
              'metamethod fallback inserted subject -> ${normalizedArgs.map(_describeValue).join(', ')}',
          categories: const {'Metamethod', 'String'},
        );
      }
      final result = await _callValue(methodEntry, normalizedArgs);
      return result;
    });
  }

  Future<Value> _awaitValue(dynamic value) async {
    dynamic current = value;
    while (true) {
      if (current is Future) {
        current = await current;
        continue;
      }
      if (current is Value && current.raw is Future) {
        current = await current.raw;
        continue;
      }
      return _ensureValue(current);
    }
  }

  Future<dynamic> _tableGet(dynamic tableRef, dynamic key) async {
    final tableValue = _ensureValue(tableRef);
    final keyValue = _ensureValue(key);
    final bool rawHasKey = tableValue.rawContainsKey(keyValue);
    dynamic lookup = tableValue[keyValue];
    final bool usedMetamethod =
        !rawHasKey || lookup == null || (lookup is Value && lookup.raw == null);
    if (lookup is Future || (lookup is Value && lookup.raw is Future)) {
      lookup = await _awaitValue(lookup);
    }
    var resolved = _ensureMetamethodLookup(tableValue, keyValue, lookup);
    if (resolved is Future || (resolved is Value && resolved.raw is Future)) {
      resolved = await _awaitValue(resolved);
    }
    if (resolved is Value) {
      if (usedMetamethod && resolved.raw is List) {
        final list = resolved.raw as List;
        if (list.isEmpty) {
          final nilValue = Value(null);
          _ensureInterpreterAttached(nilValue);
          return nilValue;
        }
        final firstValue = _ensureValue(list.first);
        _ensureInterpreterAttached(firstValue);
        return firstValue;
      }
      _ensureInterpreterAttached(resolved);
    }
    return resolved;
  }

  void _tableSet(dynamic tableRef, dynamic key, dynamic value) {
    final rawTable = tableRef is Value ? tableRef.raw : tableRef;
    final rawKey = key is Value ? key.raw : key;
    if (rawTable is num) {
      throw LuaError.typeError('attempt to index a number value');
    }
    if (rawKey == null) {
      throw LuaError.typeError('table index is nil');
    }
    if (rawKey is num && rawKey.isNaN) {
      throw LuaError.typeError('table index is NaN');
    }
    final tableValue = _ensureValue(tableRef);
    final keyValue = _ensureValue(key);
    final storedValue = _ensureValue(value);
    tableValue[keyValue] = storedValue;
  }

  Future<void> _applyUnaryMetamethod(
    IrFrame frame,
    ABCInstruction instruction,
    String metamethod,
    dynamic Function(Value operandValue, dynamic rawOperand) fallback,
  ) async {
    final rawOperand = frame.registers[instruction.b];
    final operandValue = _valueOf(rawOperand);
    if (operandValue.hasMetamethod(metamethod)) {
      final result = await operandValue.callMetamethodAsync(metamethod, <Value>[
        operandValue,
        operandValue,
      ]);
      final normalized = await _normalizeResults(result);
      if (normalized.isEmpty) {
        frame.setRegister(instruction.a, null);
        return;
      }
      final primary = normalized.first;
      if (primary == null) {
        frame.setRegister(instruction.a, null);
      } else if (primary is Value) {
        frame.setRegister(instruction.a, _ensureValue(primary));
      } else {
        frame.setRegister(instruction.a, primary);
      }
      return;
    }
    final fallbackResult = fallback(operandValue, rawOperand);
    if (fallbackResult == null) {
      frame.setRegister(instruction.a, null);
    } else if (fallbackResult is Value) {
      frame.setRegister(instruction.a, _ensureValue(fallbackResult));
    } else {
      frame.setRegister(instruction.a, fallbackResult);
    }
  }

  Future<void> _unaryNegate(IrFrame frame, ABCInstruction instruction) {
    return _applyUnaryMetamethod(
      frame,
      instruction,
      '__unm',
      (value, _) => -value,
    );
  }

  Future<void> _unaryBitwiseNot(IrFrame frame, ABCInstruction instruction) {
    return _applyUnaryMetamethod(
      frame,
      instruction,
      '__bnot',
      (value, _) => ~value,
    );
  }

  void _unaryBoolean(IrFrame frame, ABCInstruction instruction) {
    final value = frame.registers[instruction.b];
    frame.setRegister(instruction.a, !_isTruthy(value));
  }

  Future<void> _unaryLength(IrFrame frame, ABCInstruction instruction) {
    return _applyUnaryMetamethod(
      frame,
      instruction,
      '__len',
      (value, raw) => _lengthOf(raw),
    );
  }

  dynamic _rawValue(dynamic value) {
    return value is Value ? value.raw : value;
  }

  Future<dynamic> _callValue(dynamic callable, List<Object?> args) async {
    _logVm(
      () => 'callValue target=${_describeValue(callable)} args=${args.length}',
      categories: const {'Call', 'HostCall'},
    );
    if (callable is Value) {
      _ensureInterpreterAttached(callable);
      final preparedArgs = args.isEmpty
          ? const <Object?>[]
          : args.map(_prepareCallArgument).toList(growable: false);
      final raw = callable.unwrap();
      if (raw is Function) {
        final result = raw(preparedArgs);
        final awaited = result is Future ? await result : result;
        _logVm(
          () =>
              'callValue result ${_describeValue(awaited)} (Value.raw Function)',
          categories: const {'Call', 'HostCall'},
        );
        return awaited;
      }
      final awaited = await callable.call(preparedArgs);
      _logVm(
        () => 'callValue result ${_describeValue(awaited)} (Value.call)',
        categories: const {'Call', 'HostCall'},
      );
      return awaited;
    }
    if (callable is Function) {
      final preparedArgs = args.isEmpty
          ? const <Object?>[]
          : args.map(_prepareCallArgument).toList(growable: false);
      final result = callable(preparedArgs);
      final awaited = result is Future ? await result : result;
      _logVm(
        () => 'callValue result ${_describeValue(awaited)} (Function)',
        categories: const {'Call', 'HostCall'},
      );
      return awaited;
    }
    throw LuaError.typeError('attempt to call a ${callable.runtimeType} value');
  }

  Future<List<dynamic>> _normalizeResults(dynamic result) async {
    if (result == null) {
      return const [];
    }
    if (result is Value) {
      _ensureInterpreterAttached(result);
      if (result.isMulti) {
        final rawList = result.raw as List<Object?>;
        return List<dynamic>.from(rawList);
      }
      return <dynamic>[result];
    }
    if (result is List) {
      return List<dynamic>.from(
        result.map((item) {
          if (item is Value) {
            _ensureInterpreterAttached(item);
          }
          return item;
        }),
      );
    }
    return <dynamic>[result];
  }

  num _asNumber(dynamic value) {
    final raw = _rawValue(value);
    if (raw is num) {
      return raw;
    }
    if (raw is BigInt) {
      if (raw.bitLength <= 63) {
        return raw.toInt();
      }
      return raw.toDouble();
    }
    try {
      final coerced = NumberUtils.performArithmetic('+', raw, 0);
      if (coerced is num) {
        return coerced;
      }
      if (coerced is BigInt) {
        if (coerced.bitLength <= 63) {
          return coerced.toInt();
        }
        return coerced.toDouble();
      }
    } catch (_) {
      // fallthrough to error below
    }
    throw LuaError("attempt to perform arithmetic on a ${raw.runtimeType}");
  }

  FutureOr<bool> _equals(dynamic left, dynamic right) {
    final leftCandidate = left is Value ? left : _ensureValue(left);
    final rightCandidate = right is Value ? right : _ensureValue(right);
    final leftValue = _canonicalizeValue(leftCandidate);
    final rightValue = _canonicalizeValue(rightCandidate);

    Value? callee;
    if (leftValue.hasMetamethod('__eq')) {
      callee = leftValue;
    } else if (rightValue.hasMetamethod('__eq')) {
      callee = rightValue;
    }

    if (callee != null) {
      final future = callee.callMetamethodAsync('__eq', <Value>[
        leftValue,
        rightValue,
      ]);
      return future.then((result) => _finalizeComparisonResult(result, false));
    }

    return leftValue.equals(rightValue);
  }

  FutureOr<bool> _orderedCompare(
    String operation,
    dynamic left,
    dynamic right,
  ) {
    return switch (operation) {
      '<' => _lessThan(left, right),
      '<=' => _lessEqual(left, right),
      '>' => _lessThan(right, left),
      '>=' => _lessEqual(right, left),
      '==' => _equals(left, right),
      _ => throw StateError('Unsupported comparison $operation'),
    };
  }

  Future<void>? _compareAndStore(
    IrFrame frame,
    int target,
    dynamic left,
    dynamic right,
    String operation,
  ) {
    final result = _orderedCompare(operation, left, right);
    if (result is Future<bool>) {
      return result.then((value) {
        frame.setRegister(target, value);
      });
    }
    frame.setRegister(target, result);
    return null;
  }

  Future<bool> _finalizeComparisonResult(dynamic result, bool invert) async {
    final normalized = await _normalizeResults(result);
    final primary = normalized.isEmpty ? null : normalized.first;
    final outcome = _isTruthy(primary);
    return invert ? !outcome : outcome;
  }

  ({Value callee, String metamethod, bool swapArgs, bool invertResult})?
  _selectComparisonMetamethod(String operation, Value left, Value right) {
    switch (operation) {
      case '<':
        if (left.hasMetamethod('__lt')) {
          return (
            callee: left,
            metamethod: '__lt',
            swapArgs: false,
            invertResult: false,
          );
        }
        if (right.hasMetamethod('__lt')) {
          return (
            callee: right,
            metamethod: '__lt',
            swapArgs: false,
            invertResult: false,
          );
        }
        return null;
      case '<=':
        if (left.hasMetamethod('__le')) {
          return (
            callee: left,
            metamethod: '__le',
            swapArgs: false,
            invertResult: false,
          );
        }
        if (right.hasMetamethod('__le')) {
          return (
            callee: right,
            metamethod: '__le',
            swapArgs: false,
            invertResult: false,
          );
        }
        if (right.hasMetamethod('__lt')) {
          return (
            callee: right,
            metamethod: '__lt',
            swapArgs: true,
            invertResult: true,
          );
        }
        if (left.hasMetamethod('__lt')) {
          return (
            callee: left,
            metamethod: '__lt',
            swapArgs: false,
            invertResult: true,
          );
        }
        return null;
      default:
        return null;
    }
  }

  bool _coerceComparisonValue(dynamic result) {
    if (result is Value) {
      return _isTruthy(result);
    }
    if (result is bool) {
      return result;
    }
    throw LuaError.typeError(
      'comparison returned unexpected type ${result.runtimeType}',
    );
  }

  Value _canonicalizeValue(Value value) {
    if (value.raw is Map) {
      final canonical = Value.lookupCanonicalTableWrapper(value.raw);
      if (canonical != null) {
        _ensureInterpreterAttached(canonical);
        return canonical;
      }
    }
    return value;
  }

  FutureOr<bool> _lessThan(dynamic left, dynamic right) {
    final leftCandidate = left is Value ? left : _ensureValue(left);
    final rightCandidate = right is Value ? right : _ensureValue(right);
    final leftValue = _canonicalizeValue(leftCandidate);
    final rightValue = _canonicalizeValue(rightCandidate);

    final config = _selectComparisonMetamethod('<', leftValue, rightValue);
    if (config != null) {
      // ignore: avoid_print
      final args = config.swapArgs
          ? <Value>[rightValue, leftValue]
          : <Value>[leftValue, rightValue];
      final future = config.callee.callMetamethodAsync(config.metamethod, args);
      return future.then(
        (result) => _finalizeComparisonResult(result, config.invertResult),
      );
    }

    try {
      final result = leftValue < rightValue;
      return _coerceComparisonValue(result);
    } on UnsupportedError {
      // fall back to raw comparison below
    }

    final leftRaw = _rawValue(leftValue);
    final rightRaw = _rawValue(rightValue);
    if (leftRaw is num && rightRaw is num) {
      return leftRaw < rightRaw;
    }
    if (leftRaw is String && rightRaw is String) {
      return leftRaw.compareTo(rightRaw) < 0;
    }

    throw LuaError.typeError(
      'attempt to compare ${leftRaw.runtimeType} with ${rightRaw.runtimeType}',
    );
  }

  FutureOr<bool> _lessEqual(dynamic left, dynamic right) {
    final leftValue = left is Value ? left : _ensureValue(left);
    final rightValue = right is Value ? right : _ensureValue(right);

    final config = _selectComparisonMetamethod('<=', leftValue, rightValue);
    if (config != null) {
      final args = config.swapArgs
          ? <Value>[rightValue, leftValue]
          : <Value>[leftValue, rightValue];
      final future = config.callee.callMetamethodAsync(config.metamethod, args);
      return future.then(
        (result) => _finalizeComparisonResult(result, config.invertResult),
      );
    }

    try {
      final result = leftValue <= rightValue;
      return _coerceComparisonValue(result);
    } on UnsupportedError {
      // fall back to raw comparison below
    }

    final leftRaw = _rawValue(leftValue);
    final rightRaw = _rawValue(rightValue);
    if (leftRaw is num && rightRaw is num) {
      return leftRaw <= rightRaw;
    }
    if (leftRaw is String && rightRaw is String) {
      return leftRaw.compareTo(rightRaw) <= 0;
    }

    throw LuaError.typeError(
      'attempt to compare ${leftRaw.runtimeType} with ${rightRaw.runtimeType}',
    );
  }

  bool _isTruthy(dynamic value) {
    final raw = value is Value ? value.raw : value;
    return !(raw == null || raw == false);
  }

  bool _isNilControl(dynamic value) {
    if (value == null) {
      return true;
    }
    if (value is Value && value.raw == null) {
      return true;
    }
    if (value is Value && value.isMulti) {
      final raw = value.raw;
      if (raw is List && raw.isEmpty) {
        return true;
      }
    }
    return false;
  }

  bool _isNil(dynamic value) {
    if (value == null) {
      return true;
    }
    if (value is Value) {
      return value.raw == null;
    }
    return false;
  }

  int _lengthOf(dynamic value) {
    if (value is Value) {
      return value.length;
    }
    if (value is String) {
      return value.length;
    }
    if (value is List) {
      return value.length;
    }
    if (value is Map) {
      return _ensureValue(value).length;
    }
    throw LuaError.typeError('attempt to get length of a ${value.runtimeType}');
  }
}

/// Simple lualike IR VM capable of executing the subset of opcodes produced by
/// [LoopIrCompiler].
class LoopIrVm {
  LoopIrVm({required this.environment});

  final Environment environment;

  Value _ensureValue(dynamic raw) {
    if (raw is Value) {
      final runtime = environment.interpreter;
      if (runtime != null && !identical(raw.interpreter, runtime)) {
        raw.interpreter = runtime;
      }
      return raw;
    }
    final value = Value(raw);
    final runtime = environment.interpreter;
    if (runtime != null) {
      value.interpreter = runtime;
    }
    return value;
  }

  Value _valueOf(dynamic raw) => _ensureValue(raw);

  dynamic _applyBinaryOperation(dynamic left, dynamic right, String operation) {
    final leftValue = _valueOf(left);
    return switch (operation) {
      '+' => leftValue + right,
      '-' => leftValue - right,
      '*' => leftValue * right,
      '/' => leftValue / right,
      '%' => leftValue % right,
      _ => throw UnsupportedError('Unsupported operation $operation'),
    };
  }

  void execute(LualikeIrChunk chunk) {
    final prototype = chunk.mainPrototype;
    final registers = List<dynamic>.filled(
      max(prototype.registerCount, 8),
      null,
      growable: true,
    );
    final instructions = prototype.instructions;
    final constants = prototype.constants;
    var pc = 0;

    while (pc < instructions.length) {
      final instruction = instructions[pc];
      pc += 1;

      switch (instruction.opcode) {
        case LualikeIrOpcode.move:
          final instr = instruction as ABCInstruction;
          registers[instr.a] = registers[instr.b];
          break;
        case LualikeIrOpcode.loadK:
          final instr = instruction as ABxInstruction;
          registers[instr.a] = _resolveConstant(constants[instr.bx]);
          break;
        case LualikeIrOpcode.getTabUp:
          final instr = instruction as ABCInstruction;
          final key = constants[instr.c];
          final name = _constantToKey(key);
          registers[instr.a] = environment.get(name);
          break;
        case LualikeIrOpcode.setTabUp:
          final instr = instruction as ABCInstruction;
          final key = constants[instr.b];
          final name = _constantToKey(key);
          environment.define(name, registers[instr.c]);
          break;
        case LualikeIrOpcode.setTable:
          final instr = instruction as ABCInstruction;
          _setTable(registers[instr.a], registers[instr.b], registers[instr.c]);
          break;
        case LualikeIrOpcode.add:
          _binaryArithmetic(instruction as ABCInstruction, registers, '+');
          break;
        case LualikeIrOpcode.sub:
          _binaryArithmetic(instruction as ABCInstruction, registers, '-');
          break;
        case LualikeIrOpcode.mul:
          _binaryArithmetic(instruction as ABCInstruction, registers, '*');
          break;
        case LualikeIrOpcode.div:
          _binaryArithmetic(instruction as ABCInstruction, registers, '/');
          break;
        case LualikeIrOpcode.mod:
          _binaryArithmetic(instruction as ABCInstruction, registers, '%');
          break;
        case LualikeIrOpcode.forPrep:
          final instr = instruction as AsBxInstruction;
          _executeForPrep(registers, instr.a);
          pc += instr.sBx;
          break;
        case LualikeIrOpcode.forLoop:
          final instr = instruction as AsBxInstruction;
          final shouldJump = _executeForLoop(registers, instr.a);
          if (shouldJump) {
            pc += instr.sBx;
          }
          break;
        case LualikeIrOpcode.return0:
          return;
        default:
          throw UnsupportedError(
            'Opcode ${instruction.opcode} not supported in loop VM',
          );
      }
    }
  }

  void _binaryArithmetic(
    ABCInstruction instr,
    List<dynamic> registers,
    String operation,
  ) {
    final left = registers[instr.b];
    final right = registers[instr.c];
    registers[instr.a] = _applyBinaryOperation(left, right, operation);
  }

  void _executeForPrep(List<dynamic> registers, int base) {
    var initial = _asNumber(registers[base]);
    final step = _asNumber(registers[base + 2]);
    registers[base] = initial - step;
    registers[base + 3] = initial;
  }

  bool _executeForLoop(List<dynamic> registers, int base) {
    final step = _asNumber(registers[base + 2]);
    final limit = _asNumber(registers[base + 1]);
    final nextValue = _asNumber(registers[base]) + step;
    registers[base] = nextValue;
    final continueLoop = step > 0 ? nextValue <= limit : nextValue >= limit;
    if (continueLoop) {
      registers[base + 3] = nextValue;
    }
    return continueLoop;
  }

  dynamic _resolveConstant(LualikeIrConstant constant) {
    return switch (constant) {
      NilConstant() => null,
      BooleanConstant(value: final value) => value,
      IntegerConstant(value: final value) => value,
      NumberConstant(value: final value) => value,
      ShortStringConstant(value: final value) => value,
      LongStringConstant(value: final value) => value,
    };
  }

  String _constantToKey(LualikeIrConstant constant) {
    return switch (constant) {
      ShortStringConstant(value: final value) => value,
      LongStringConstant(value: final value) => value,
      _ => throw StateError('Expected string constant for table access'),
    };
  }

  num _asNumber(dynamic value) {
    final raw = _rawValue(value);
    if (raw is num) {
      return raw;
    }
    if (raw is BigInt) {
      if (raw.bitLength <= 63) {
        return raw.toInt();
      }
      return raw.toDouble();
    }
    try {
      final coerced = NumberUtils.performArithmetic('+', raw, 0);
      if (coerced is num) {
        return coerced;
      }
      if (coerced is BigInt) {
        if (coerced.bitLength <= 63) {
          return coerced.toInt();
        }
        return coerced.toDouble();
      }
    } catch (_) {
      // fallthrough to error below
    }
    throw LuaError("attempt to perform arithmetic on a ${raw.runtimeType}");
  }

  dynamic _rawValue(dynamic value) {
    return value is Value ? value.raw : value;
  }

  void _setTable(dynamic tableRef, dynamic keyRef, dynamic valueRef) {
    final tableValue = _ensureValue(tableRef);
    final keyValue = _ensureValue(keyRef);
    final storedValue = _ensureValue(valueRef);

    if (tableValue.raw is Map) {
      tableValue[keyValue] = storedValue;
      return;
    }

    throw LuaError.typeError(
      'attempt to index a ${tableValue.raw.runtimeType} value',
    );
  }
}
