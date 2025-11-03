import 'dart:async';
import 'dart:math';

import 'package:lualike/src/environment.dart';
import 'package:lualike/src/logging/logger.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/value.dart';

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';

const int _returnAll = -1;

class BytecodeUpvalueCell {
  BytecodeUpvalueCell.fromFrame(_BytecodeFrame frame, int index)
    : _frame = frame,
      _index = index,
      _closedValue = frame.getRegister(index);

  _BytecodeFrame? _frame;
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

class BytecodeClosure {
  BytecodeClosure({
    required this.prototype,
    required List<BytecodeUpvalueCell> upvalues,
  }) : upvalues = List<BytecodeUpvalueCell>.from(upvalues);

  final BytecodePrototype prototype;
  final List<BytecodeUpvalueCell> upvalues;
}

class _BytecodeFrame {
  _BytecodeFrame({
    required this.prototype,
    required List<dynamic> args,
    required List<BytecodeUpvalueCell> capturedUpvalues,
    required this.returnBase,
    required this.expectedResults,
  }) : upvalues = List<BytecodeUpvalueCell>.from(capturedUpvalues),
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
  }

  final BytecodePrototype prototype;
  final List<dynamic> registers;
  final List<BytecodeUpvalueCell> upvalues;
  final List<dynamic> varargs;
  final List<bool> _constFlags;
  final List<bool> _constSealed;
  int lastExecutedPc = -1;
  int pc = 0;
  int returnBase;
  int expectedResults;
  int top = 0;
  final Map<int, BytecodeUpvalueCell> _registerUpvalues =
      <int, BytecodeUpvalueCell>{};
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
          'Const write violation at register $index (pc=${lastExecutedPc}, opcode=$opcode)',
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

  BytecodeUpvalueCell captureRegister(int index) {
    return _registerUpvalues.putIfAbsent(
      index,
      () => BytecodeUpvalueCell.fromFrame(this, index),
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
    BytecodePrototype prototype,
    List<dynamic> args,
  ) {
    final paramCapacity = prototype.paramCount + 1;
    final prototypeCapacity = prototype.registerCount;
    final argsCapacity = args.length + 1;
    final baseCapacity = max(max(paramCapacity, prototypeCapacity), 1);
    return max(baseCapacity, argsCapacity);
  }
}

/// Minimal bytecode VM capable of executing the subset of opcodes currently
/// produced by [BytecodeCompiler]. The implementation will expand as more AST
/// features are lowered to bytecode.
class BytecodeVm {
  BytecodeVm({Environment? environment, LuaRuntime? runtime})
    : environment = environment ?? Environment() {
    this.runtime = runtime ?? this.environment.interpreter;
  }

  final Environment environment;
  late final LuaRuntime? runtime;
  static final Object _metamethodNotFound = Object();

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
      category: 'BytecodeVm',
      categories: categories,
      contextBuilder: contextBuilder,
    );
  }

  String _describeValue(dynamic value) {
    if (value is BytecodeClosure) {
      return 'BytecodeClosure(protoRegisters=${value.prototype.registerCount})';
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

  Future<Object?> execute(BytecodeChunk chunk) async {
    _logVm(
      () => 'Executing chunk',
      categories: const {'Execute'},
      contextBuilder: () => {
        'registers': chunk.mainPrototype.registerCount,
        'instructions': chunk.mainPrototype.instructions.length,
        'constants': chunk.mainPrototype.constants.length,
      },
    );
    final rawResults = await _runFrames(<_BytecodeFrame>[
      _BytecodeFrame(
        prototype: chunk.mainPrototype,
        args: const [],
        capturedUpvalues: const <BytecodeUpvalueCell>[],
        returnBase: 0,
        expectedResults: _returnAll,
      ),
    ], isMainChunk: true);
    return _finalizeResults(rawResults);
  }

  Future<Object?> invokeClosure(
    BytecodeClosure closure,
    List<Object?> args, {
    int expectedResults = _returnAll,
  }) async {
    _logVm(
      () => 'Invoking bytecode closure',
      categories: const {'Execute', 'Call'},
      contextBuilder: () => {
        'params': closure.prototype.paramCount,
        'vararg': closure.prototype.isVararg,
        'args': args.length,
        'expected': expectedResults,
      },
    );
    final rawResults = await _runFrames(<_BytecodeFrame>[
      _BytecodeFrame(
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
    List<_BytecodeFrame> frames, {
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

      _logVm(
        () => 'pc=${frame.pc - 1} opcode=${instruction.opcode.name}',
        categories: const {'Opcode'},
        contextBuilder: () => {
          'frameDepth': frames.length,
          'registerTop': frame.top,
          'returnBase': frame.returnBase,
          'expectedResults': frame.expectedResults,
        },
      );

      switch (instruction.opcode) {
        case BytecodeOpcode.move:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, frame.getRegister(instr.b));
          break;
        case BytecodeOpcode.loadK:
          final instr = instruction as ABxInstruction;
          frame.setRegister(instr.a, _resolveConstant(constants[instr.bx]));
          break;
        case BytecodeOpcode.loadI:
          {
            final instr = instruction as ABCInstruction;
            frame.setRegister(instr.a, signExtend(instr.b, 8));
            break;
          }
        case BytecodeOpcode.loadF:
          {
            final instr = instruction as ABCInstruction;
            frame.setRegister(instr.a, signExtend(instr.b, 8).toDouble());
            break;
          }
        case BytecodeOpcode.loadKx:
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
        case BytecodeOpcode.loadTrue:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, true);
          break;
        case BytecodeOpcode.loadFalse:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, false);
          break;
        case BytecodeOpcode.lFalseSkip:
          {
            final instr = instruction as ABCInstruction;
            frame.setRegister(instr.a, false);
            frame.pc += 1;
            break;
          }
        case BytecodeOpcode.loadNil:
          final instr = instruction as ABCInstruction;
          final count = instr.b;
          for (var offset = 0; offset <= count; offset++) {
            frame.setRegister(instr.a + offset, null);
          }
          break;
        case BytecodeOpcode.getUpval:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, frame.upvalues[instr.b].value);
          break;
        case BytecodeOpcode.setUpval:
          final instr = instruction as ABCInstruction;
          frame.upvalues[instr.b].value = registers[instr.c];
          break;
        case BytecodeOpcode.getTabUp:
          final instr = instruction as ABCInstruction;
          final key = _constantToKey(constants[instr.c]);
          frame.setRegister(instr.a, environment.get(key));
          break;
        case BytecodeOpcode.setTabUp:
          final instr = instruction as ABCInstruction;
          final key = _constantToKey(constants[instr.b]);
          final rawValue = instr.k
              ? _resolveConstant(constants[instr.c])
              : registers[instr.c];
          environment.define(key, _ensureValue(rawValue));
          break;
        case BytecodeOpcode.getTable:
          final instr = instruction as ABCInstruction;
          frame.setRegister(
            instr.a,
            _tableGet(registers[instr.b], registers[instr.c]),
          );
          break;
        case BytecodeOpcode.getField:
          final instr = instruction as ABCInstruction;
          final key = _constantToKey(constants[instr.c]);
          frame.setRegister(instr.a, _tableGet(registers[instr.b], key));
          break;
        case BytecodeOpcode.selfOp:
          {
            final instr = instruction as ABCInstruction;
            final object = registers[instr.b];
            final key = _constantToKey(constants[instr.c]);
            frame.setRegister(instr.a + 1, object);
            frame.setRegister(instr.a, _tableGet(object, key));
            break;
          }
        case BytecodeOpcode.getI:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, _tableGet(registers[instr.b], instr.c));
          break;
        case BytecodeOpcode.varArgPrep:
          // No-op: varargs captured at frame creation.
          break;
        case BytecodeOpcode.varArg:
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
        case BytecodeOpcode.getVarArg:
          {
            final instr = instruction as ABCInstruction;
            final requestedIndex = instr.c <= 0 ? 0 : instr.c - 1;
            final value = requestedIndex < frame.varargs.length
                ? frame.varargs[requestedIndex]
                : null;
            frame.setRegister(instr.a, value);
            break;
          }
        case BytecodeOpcode.test:
          final instr = instruction as ABCInstruction;
          final cond = _isTruthy(registers[instr.a]);
          if ((!cond) == instr.k) {
            frame.pc += 1;
          }
          break;
        case BytecodeOpcode.testSet:
          final instr = instruction as ABCInstruction;
          final cond = _isTruthy(registers[instr.b]);
          if ((!cond) == instr.k) {
            frame.pc += 1;
          } else {
            frame.setRegister(instr.a, registers[instr.b]);
          }
          break;
        case BytecodeOpcode.jmp:
          final instr = instruction as AsJInstruction;
          frame.pc += instr.sJ;
          break;
        case BytecodeOpcode.tForPrep:
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
        case BytecodeOpcode.tForCall:
          final instr = instruction as ABCInstruction;
          await _executeTForCall(frame, instr.a, instr.c);
          break;
        case BytecodeOpcode.tForLoop:
          {
            final instr = instruction as AsBxInstruction;
            if (!_isTruthy(registers[instr.a + 3])) {
              frame.pc += instr.sBx;
            }
            break;
          }
        case BytecodeOpcode.closure:
          final instr = instruction as ABxInstruction;
          frame.setRegister(instr.a, _createClosure(frame, instr.bx));
          break;
        case BytecodeOpcode.call:
          {
            final instr = instruction as ABCInstruction;
            final base = instr.a;
            final args = _collectCallArguments(frame, instr);
            final callee = registers[base];
            final expectedResults = instr.c == 0 ? _returnAll : instr.c - 1;
            BytecodeClosure? closure;
            if (callee is BytecodeClosure) {
              closure = callee;
            } else if (callee is Value && callee.raw is BytecodeClosure) {
              closure = callee.raw as BytecodeClosure;
            }
            _logVm(
              () =>
                  'CALL base=$base args=${args.length} expected=$expectedResults',
              categories: const {'Call'},
              contextBuilder: () => {
                'callee': _describeValue(callee),
                'bytecode': closure != null,
              },
            );
            if (closure != null) {
              frames.add(
                _BytecodeFrame(
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
        case BytecodeOpcode.tailCall:
          {
            final instr = instruction as ABCInstruction;
            final args = _collectCallArguments(frame, instr);
            final callee = registers[instr.a];
            final currentReturnBase = frame.returnBase;
            final currentExpected = frame.expectedResults;
            BytecodeClosure? closure;
            if (callee is BytecodeClosure) {
              closure = callee;
            } else if (callee is Value && callee.raw is BytecodeClosure) {
              closure = callee.raw as BytecodeClosure;
            }
            _logVm(
              () =>
                  'TAILCALL base=${instr.a} args=${args.length} expected=$currentExpected',
              categories: const {'Call', 'TailCall'},
              contextBuilder: () => {
                'callee': _describeValue(callee),
                'bytecode': closure != null,
              },
            );
            if (closure != null) {
              _popCallStackFrame();
              final completed = frames.removeLast();
              await completed.closeToBeClosed(0);
              completed.closeOpenUpvalues();
              frames.add(
                _BytecodeFrame(
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
        case BytecodeOpcode.setTable:
          final instr = instruction as ABCInstruction;
          final value = instr.k
              ? _resolveConstant(constants[instr.c])
              : registers[instr.c];
          _tableSet(registers[instr.a], registers[instr.b], value);
          break;
        case BytecodeOpcode.setField:
          final instr = instruction as ABCInstruction;
          final key = _constantToKey(constants[instr.b]);
          final value = instr.k
              ? _resolveConstant(constants[instr.c])
              : registers[instr.c];
          _tableSet(registers[instr.a], key, value);
          break;
        case BytecodeOpcode.setI:
          final instr = instruction as ABCInstruction;
          final value = instr.k
              ? _resolveConstant(constants[instr.c])
              : registers[instr.c];
          _tableSet(registers[instr.a], instr.b, value);
          break;
        case BytecodeOpcode.setList:
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
        case BytecodeOpcode.newTable:
          final instr = instruction as ABCInstruction;
          final tableStorage = TableStorage();
          if (instr.b > 0) {
            tableStorage.ensureArrayCapacity(instr.b);
          }
          registers[instr.a] = _ensureValue(tableStorage);
          break;
        case BytecodeOpcode.add:
          await _applyBinaryOperation(
            frame,
            instruction as ABCInstruction,
            '+',
          );
          break;
        case BytecodeOpcode.addI:
          {
            final instr = instruction as ABCInstruction;
            await _applyBinaryImmediate(
              frame,
              instr,
              signExtend(instr.c, 9),
              '+',
            );
            break;
          }
        case BytecodeOpcode.addK:
          await _applyBinaryConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '+',
          );
          break;
        case BytecodeOpcode.sub:
          await _applyBinaryOperation(
            frame,
            instruction as ABCInstruction,
            '-',
          );
          break;
        case BytecodeOpcode.subK:
          await _applyBinaryConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '-',
          );
          break;
        case BytecodeOpcode.mul:
          await _applyBinaryOperation(
            frame,
            instruction as ABCInstruction,
            '*',
          );
          break;
        case BytecodeOpcode.mulK:
          await _applyBinaryConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '*',
          );
          break;
        case BytecodeOpcode.div:
          await _applyBinaryOperation(
            frame,
            instruction as ABCInstruction,
            '/',
          );
          break;
        case BytecodeOpcode.divK:
          await _applyBinaryConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '/',
          );
          break;
        case BytecodeOpcode.mod:
          await _applyBinaryOperation(
            frame,
            instruction as ABCInstruction,
            '%',
          );
          break;
        case BytecodeOpcode.modK:
          await _applyBinaryConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '%',
          );
          break;
        case BytecodeOpcode.idiv:
          await _applyBinaryOperation(
            frame,
            instruction as ABCInstruction,
            '//',
          );
          break;
        case BytecodeOpcode.idivK:
          await _applyBinaryConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '//',
          );
          break;
        case BytecodeOpcode.pow:
          await _applyBinaryOperation(
            frame,
            instruction as ABCInstruction,
            '^',
          );
          break;
        case BytecodeOpcode.powK:
          await _applyBinaryConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '^',
          );
          break;
        case BytecodeOpcode.band:
          await _applyBinaryOperation(
            frame,
            instruction as ABCInstruction,
            '&',
          );
          break;
        case BytecodeOpcode.bandK:
          await _applyBinaryConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '&',
          );
          break;
        case BytecodeOpcode.bor:
          await _applyBinaryOperation(
            frame,
            instruction as ABCInstruction,
            '|',
          );
          break;
        case BytecodeOpcode.borK:
          await _applyBinaryConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '|',
          );
          break;
        case BytecodeOpcode.bxor:
          await _applyBinaryOperation(
            frame,
            instruction as ABCInstruction,
            '~',
          );
          break;
        case BytecodeOpcode.bxorK:
          await _applyBinaryConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '~',
          );
          break;
        case BytecodeOpcode.mmBin:
          await _applyBinaryOperation(
            frame,
            instruction as ABCInstruction,
            '+',
          );
          break;
        case BytecodeOpcode.mmBinI:
          {
            final instr = instruction as ABCInstruction;
            await _applyBinaryImmediate(
              frame,
              instr,
              signExtend(instr.c, 9),
              '+',
            );
            break;
          }
        case BytecodeOpcode.mmBinK:
          await _applyBinaryConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '+',
          );
          break;
        case BytecodeOpcode.concat:
          await _applyBinaryOperation(
            frame,
            instruction as ABCInstruction,
            '..',
          );
          break;
        case BytecodeOpcode.close:
          {
            final instr = instruction as ABCInstruction;
            await frame.closeToBeClosed(instr.a);
            frame.closeOpenUpvaluesFrom(instr.a);
            break;
          }
        case BytecodeOpcode.tbc:
          {
            final instr = instruction as ABCInstruction;
            frame.markToBeClosed(instr.a);
            break;
          }
        case BytecodeOpcode.shl:
          await _applyBinaryOperation(
            frame,
            instruction as ABCInstruction,
            '<<',
          );
          break;
        case BytecodeOpcode.shlI:
          {
            final instr = instruction as ABCInstruction;
            final imm = signExtend(instr.c, 9);
            await _applyBinaryImmediate(frame, instr, imm, '<<');
            break;
          }
        case BytecodeOpcode.shr:
          await _applyBinaryOperation(
            frame,
            instruction as ABCInstruction,
            '>>',
          );
          break;
        case BytecodeOpcode.shrI:
          {
            final instr = instruction as ABCInstruction;
            final imm = signExtend(instr.c, 9);
            await _applyBinaryImmediate(frame, instr, imm, '>>');
            break;
          }
        case BytecodeOpcode.eq:
          _binaryComparison(frame, instruction as ABCInstruction, _equals);
          break;
        case BytecodeOpcode.eqK:
          _binaryComparisonConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            _equals,
          );
          break;
        case BytecodeOpcode.eqI:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, _equals(registers[instr.b], instr.c));
          break;
        case BytecodeOpcode.lt:
          _binaryComparison(frame, instruction as ABCInstruction, _lessThan);
          break;
        case BytecodeOpcode.ltI:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, _lessThan(registers[instr.b], instr.c));
          break;
        case BytecodeOpcode.le:
          _binaryComparison(frame, instruction as ABCInstruction, _lessEqual);
          break;
        case BytecodeOpcode.leI:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, _lessEqual(registers[instr.b], instr.c));
          break;
        case BytecodeOpcode.gtI:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, _lessThan(instr.c, registers[instr.b]));
          break;
        case BytecodeOpcode.geI:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, _lessEqual(instr.c, registers[instr.b]));
          break;
        case BytecodeOpcode.unm:
          _unaryNegate(frame, instruction as ABCInstruction);
          break;
        case BytecodeOpcode.bnot:
          _unaryBitwiseNot(frame, instruction as ABCInstruction);
          break;
        case BytecodeOpcode.notOp:
          _unaryBoolean(frame, instruction as ABCInstruction);
          break;
        case BytecodeOpcode.len:
          _unaryLength(frame, instruction as ABCInstruction);
          break;
        case BytecodeOpcode.ret:
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
        case BytecodeOpcode.return0:
          await _handleReturn(frames, const [], handleTopLevelReturn);
          break;
        case BytecodeOpcode.return1:
          final instr = instruction as ABCInstruction;
          await _handleReturn(frames, <dynamic>[
            frame.getRegister(instr.a),
          ], handleTopLevelReturn);
          break;
        case BytecodeOpcode.forPrep:
          final instr = instruction as AsBxInstruction;
          _executeForPrep(frame, instr.a);
          frame.pc += instr.sBx;
          break;
        case BytecodeOpcode.forLoop:
          final instr = instruction as AsBxInstruction;
          final shouldContinue = _executeForLoop(frame, instr.a);
          if (shouldContinue) {
            frame.pc += instr.sBx;
          }
          break;
        case BytecodeOpcode.extraArg:
          // EXTRAARG is consumed by the preceding instruction (e.g., LOADKX).
          // Execution reaches here only if an instruction failed to process it.
          break;
        default:
          _logVm(
            () => 'Unsupported opcode ${instruction.opcode.name}',
            categories: const {'Opcode', 'Error'},
          );
          throw UnsupportedError(
            'Opcode ${instruction.opcode} not yet supported in BytecodeVm',
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
    _BytecodeFrame frame,
    ABCInstruction instruction,
  ) {
    if (instruction.b == 0) {
      final args = <dynamic>[];
      for (
        var index = instruction.a + 1;
        index < frame.registers.length;
        index++
      ) {
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
    _BytecodeFrame frame,
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
      return;
    }
    for (var i = 0; i < expectedResults; i++) {
      final value = i < results.length ? results[i] : null;
      frame.setRegister(base + i, value);
    }
  }

  Future<void> _handleReturn(
    List<_BytecodeFrame> frames,
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
    if (arg is BytecodeClosure) {
      return _ensureValue(arg);
    }
    if (arg is List && arg is! Value) {
      return arg.map(_prepareCallArgument).toList();
    }
    return _ensureValue(arg);
  }

  void _pushCallStackFrame(_BytecodeFrame frame, {bool isMainChunk = false}) {
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

  void _updateCallStackLine(_BytecodeFrame frame, int instructionIndex) {
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

  String _prototypeDisplayName(BytecodePrototype prototype) {
    if (prototype.lineDefined <= 0) {
      return 'function';
    }
    return 'function@${prototype.lineDefined}';
  }

  BytecodeClosure _createClosure(_BytecodeFrame frame, int prototypeIndex) {
    final child = frame.prototype.prototypes[prototypeIndex];
    final captured = <BytecodeUpvalueCell>[];
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
    return BytecodeClosure(prototype: child, upvalues: captured);
  }

  dynamic _resolveConstant(BytecodeConstant constant) {
    return switch (constant) {
      NilConstant() => null,
      BooleanConstant(value: final value) => value,
      IntegerConstant(value: final value) => value,
      NumberConstant(value: final value) => value,
      ShortStringConstant(value: final value) => value,
      LongStringConstant(value: final value) => value,
    };
  }

  String _constantToKey(BytecodeConstant constant) {
    return switch (constant) {
      ShortStringConstant(value: final value) => value,
      LongStringConstant(value: final value) => value,
      _ => throw StateError('Expected string constant for table lookup'),
    };
  }

  Value _valueOf(dynamic raw) {
    return raw is Value ? raw : Value(raw);
  }

  Future<void> _applyBinaryOperation(
    _BytecodeFrame frame,
    ABCInstruction instruction,
    String operation,
  ) async {
    final leftValue = _valueOf(frame.registers[instruction.b]);
    final rightValue = _valueOf(frame.registers[instruction.c]);
    final result = await _evaluateBinaryOperation(
      leftValue,
      rightValue,
      operation,
    );
    frame.setRegister(instruction.a, result);
  }

  Future<void> _applyBinaryConstant(
    _BytecodeFrame frame,
    ABCInstruction instruction,
    List<BytecodeConstant> constants,
    String operation,
  ) async {
    final leftValue = _valueOf(frame.registers[instruction.b]);
    final constantValue = _valueOf(_resolveConstant(constants[instruction.c]));
    final result = await _evaluateBinaryOperation(
      leftValue,
      constantValue,
      operation,
    );
    frame.setRegister(instruction.a, result);
  }

  Future<void> _applyBinaryImmediate(
    _BytecodeFrame frame,
    ABCInstruction instruction,
    int immediate,
    String operation,
  ) async {
    final leftValue = _valueOf(frame.registers[instruction.b]);
    final rightValue = _valueOf(immediate);
    final result = await _evaluateBinaryOperation(
      leftValue,
      rightValue,
      operation,
    );
    frame.setRegister(instruction.a, result);
  }

  Future<dynamic> _evaluateBinaryOperation(
    Value leftValue,
    Value rightValue,
    String operation,
  ) async {
    final metamethodName = _binaryMetamethodName(operation);
    if (metamethodName != null) {
      final metamethodResult = await _invokeBinaryMetamethod(
        metamethodName,
        leftValue,
        rightValue,
      );
      if (!identical(metamethodResult, _metamethodNotFound)) {
        return metamethodResult;
      }
    }
    return _fallbackBinaryOperation(leftValue, rightValue, operation);
  }

  Future<dynamic> _invokeBinaryMetamethod(
    String metamethod,
    Value leftValue,
    Value rightValue,
  ) async {
    Value? callee;
    if (leftValue.hasMetamethod(metamethod)) {
      callee = leftValue;
    } else if (rightValue.hasMetamethod(metamethod)) {
      callee = rightValue;
    }
    if (callee == null) {
      _logVm(
        () => 'Metamethod $metamethod not found',
        categories: const {'Metamethod'},
      );
      return _metamethodNotFound;
    }
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
      final result = await callee.callMetamethodAsync(metamethod, <Value>[
        leftValue,
        rightValue,
      ]);
      _logVm(
        () => 'Metamethod $metamethod result ${_describeValue(result)}',
        categories: const {'Metamethod'},
      );
      return result;
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

  void _binaryComparison(
    _BytecodeFrame frame,
    ABCInstruction instruction,
    bool Function(dynamic, dynamic) comparison,
  ) {
    final registers = frame.registers;
    final left = registers[instruction.b];
    final right = registers[instruction.c];
    frame.setRegister(instruction.a, comparison(left, right));
  }

  void _binaryComparisonConstant(
    _BytecodeFrame frame,
    ABCInstruction instruction,
    List<BytecodeConstant> constants,
    bool Function(dynamic, dynamic) comparison,
  ) {
    final registers = frame.registers;
    final left = registers[instruction.b];
    final constant = _resolveConstant(constants[instruction.c]);
    frame.setRegister(instruction.a, comparison(left, constant));
  }

  void _executeForPrep(_BytecodeFrame frame, int base) {
    final registers = frame.registers;
    final initial = _asNumber(registers[base]);
    final step = _asNumber(registers[base + 2]);
    frame.setRegister(base, initial - step);
    frame.setRegister(base + 3, initial);
  }

  bool _executeForLoop(_BytecodeFrame frame, int base) {
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
    _BytecodeFrame frame,
    int base,
    int resultCount,
  ) async {
    final registers = frame.registers;
    final iterator = registers[base];
    final state = registers[base + 1];
    final control = registers[base + 3];

    final args = <Object?>[state, control];
    final results = await _normalizeResults(await _callValue(iterator, args));
    final controlRaw = results.isNotEmpty ? results.first : null;
    final controlValue =
        controlRaw == null ? null : _ensureValue(controlRaw);
    frame.setRegister(base + 3, controlValue);
    for (var i = 0; i < resultCount; i++) {
      final resultIndex = i + 1;
      final rawValue =
          resultIndex < results.length ? results[resultIndex] : null;
      final storedValue = rawValue == null ? null : _ensureValue(rawValue);
      frame.setRegister(base + 4 + i, storedValue);
    }
  }

  dynamic _tableGet(dynamic tableRef, dynamic key) {
    final tableValue = _ensureValue(tableRef);
    final keyValue = _ensureValue(key);
    final result = tableValue[keyValue];
    if (result is Value) {
      _ensureInterpreterAttached(result);
    }
    return result;
  }

  void _tableSet(dynamic tableRef, dynamic key, dynamic value) {
    final tableValue = _ensureValue(tableRef);
    final keyValue = _ensureValue(key);
    final storedValue = _ensureValue(value);
    tableValue[keyValue] = storedValue;
  }

  void _unaryNegate(_BytecodeFrame frame, ABCInstruction instruction) {
    final value = _valueOf(frame.registers[instruction.b]);
    frame.setRegister(instruction.a, -value);
  }

  void _unaryBitwiseNot(_BytecodeFrame frame, ABCInstruction instruction) {
    final value = _valueOf(frame.registers[instruction.b]);
    frame.setRegister(instruction.a, ~value);
  }

  void _unaryBoolean(_BytecodeFrame frame, ABCInstruction instruction) {
    final value = frame.registers[instruction.b];
    frame.setRegister(instruction.a, !_isTruthy(value));
  }

  void _unaryLength(_BytecodeFrame frame, ABCInstruction instruction) {
    final value = frame.registers[instruction.b];
    frame.setRegister(instruction.a, _lengthOf(value));
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
      final raw = callable.unwrap();
      if (raw is Function) {
        final normalizedArgs = args
            .map((arg) => arg is Value ? arg.raw : arg)
            .toList(growable: false);
        final result = raw(normalizedArgs);
        final awaited = result is Future ? await result : result;
        _logVm(
          () =>
              'callValue result ${_describeValue(awaited)} (Value.raw Function)',
          categories: const {'Call', 'HostCall'},
        );
        return awaited;
      }
      final awaited = await callable.call(args);
      _logVm(
        () => 'callValue result ${_describeValue(awaited)} (Value.call)',
        categories: const {'Call', 'HostCall'},
      );
      return awaited;
    }
    if (callable is Function) {
      final result = callable(args);
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

  bool _equals(dynamic left, dynamic right) {
    if (left is Value || right is Value) {
      final leftValue = _ensureValue(left);
      final rightValue = _ensureValue(right);
      return leftValue.equals(rightValue);
    }

    final leftRaw = _rawValue(left);
    final rightRaw = _rawValue(right);
    if (leftRaw is num && rightRaw is num) {
      if (leftRaw.isNaN || rightRaw.isNaN) {
        return false;
      }
      return leftRaw == rightRaw;
    }

    return leftRaw == rightRaw;
  }

  bool _lessThan(dynamic left, dynamic right) {
    if (left is Value || right is Value) {
      final leftValue = _ensureValue(left);
      final rightValue = _ensureValue(right);
      final result = leftValue < rightValue;
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

    final leftRaw = _rawValue(left);
    final rightRaw = _rawValue(right);
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

  bool _lessEqual(dynamic left, dynamic right) {
    if (left is Value || right is Value) {
      final leftValue = _ensureValue(left);
      final rightValue = _ensureValue(right);
      final result = leftValue <= rightValue;
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

    final leftRaw = _rawValue(left);
    final rightRaw = _rawValue(right);
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

/// Simple bytecode VM capable of executing the subset of opcodes produced by
/// [LoopBytecodeCompiler].
class LoopBytecodeVm {
  LoopBytecodeVm({required this.environment});

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

  void execute(BytecodeChunk chunk) {
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
        case BytecodeOpcode.move:
          final instr = instruction as ABCInstruction;
          registers[instr.a] = registers[instr.b];
          break;
        case BytecodeOpcode.loadK:
          final instr = instruction as ABxInstruction;
          registers[instr.a] = _resolveConstant(constants[instr.bx]);
          break;
        case BytecodeOpcode.getTabUp:
          final instr = instruction as ABCInstruction;
          final key = constants[instr.c];
          final name = _constantToKey(key);
          registers[instr.a] = environment.get(name);
          break;
        case BytecodeOpcode.setTabUp:
          final instr = instruction as ABCInstruction;
          final key = constants[instr.b];
          final name = _constantToKey(key);
          environment.define(name, registers[instr.c]);
          break;
        case BytecodeOpcode.setTable:
          final instr = instruction as ABCInstruction;
          _setTable(registers[instr.a], registers[instr.b], registers[instr.c]);
          break;
        case BytecodeOpcode.add:
          _binaryArithmetic(instruction as ABCInstruction, registers, '+');
          break;
        case BytecodeOpcode.sub:
          _binaryArithmetic(instruction as ABCInstruction, registers, '-');
          break;
        case BytecodeOpcode.mul:
          _binaryArithmetic(instruction as ABCInstruction, registers, '*');
          break;
        case BytecodeOpcode.div:
          _binaryArithmetic(instruction as ABCInstruction, registers, '/');
          break;
        case BytecodeOpcode.mod:
          _binaryArithmetic(instruction as ABCInstruction, registers, '%');
          break;
        case BytecodeOpcode.forPrep:
          final instr = instruction as AsBxInstruction;
          _executeForPrep(registers, instr.a);
          pc += instr.sBx;
          break;
        case BytecodeOpcode.forLoop:
          final instr = instruction as AsBxInstruction;
          final shouldJump = _executeForLoop(registers, instr.a);
          if (shouldJump) {
            pc += instr.sBx;
          }
          break;
        case BytecodeOpcode.return0:
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

  dynamic _resolveConstant(BytecodeConstant constant) {
    return switch (constant) {
      NilConstant() => null,
      BooleanConstant(value: final value) => value,
      IntegerConstant(value: final value) => value,
      NumberConstant(value: final value) => value,
      ShortStringConstant(value: final value) => value,
      LongStringConstant(value: final value) => value,
    };
  }

  String _constantToKey(BytecodeConstant constant) {
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
