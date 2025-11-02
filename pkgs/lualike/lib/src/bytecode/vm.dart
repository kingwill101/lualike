import 'dart:async';
import 'dart:math';

import 'package:lualike/src/environment.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/value.dart';

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';

const int _returnAll = -1;

class _UpvalueCell {
  _UpvalueCell.fromRegister(List<dynamic> registers, int index)
    : _registers = registers,
      _index = index,
      _closedValue = registers[index];

  _UpvalueCell.fromCell(_UpvalueCell other)
    : _registers = other._registers,
      _index = other._index,
      _closedValue = other._closedValue;

  List<dynamic>? _registers;
  final int _index;
  dynamic _closedValue;

  dynamic get value {
    final registers = _registers;
    if (registers != null) {
      return registers[_index];
    }
    return _closedValue;
  }

  set value(dynamic newValue) {
    final registers = _registers;
    if (registers != null) {
      registers[_index] = newValue;
    }
    _closedValue = newValue;
  }

  void close() {
    final registers = _registers;
    if (registers != null) {
      _closedValue = registers[_index];
      _registers = null;
    }
  }
}

class BytecodeClosure {
  BytecodeClosure({
    required this.prototype,
    required List<_UpvalueCell> upvalues,
  }) : upvalues = List<_UpvalueCell>.from(upvalues);

  final BytecodePrototype prototype;
  final List<_UpvalueCell> upvalues;
}

class _BytecodeFrame {
  _BytecodeFrame({
    required this.prototype,
    required List<dynamic> args,
    required List<_UpvalueCell> capturedUpvalues,
    required this.returnBase,
    required this.expectedResults,
  }) : upvalues = List<_UpvalueCell>.from(capturedUpvalues),
       registers = List<dynamic>.filled(
         _initialRegisterCapacity(prototype, args),
         null,
         growable: true,
       ),
       varargs = prototype.isVararg && args.length > prototype.paramCount
           ? List<dynamic>.from(args.sublist(prototype.paramCount))
           : <dynamic>[] {
    final paramCount = prototype.paramCount;
    for (var i = 0; i < paramCount; i++) {
      setRegister(i, i < args.length ? args[i] : null);
    }
  }

  final BytecodePrototype prototype;
  final List<dynamic> registers;
  final List<_UpvalueCell> upvalues;
  final List<dynamic> varargs;
  int pc = 0;
  int returnBase;
  int expectedResults;
  int top = 0;
  final Map<int, _UpvalueCell> _registerUpvalues = <int, _UpvalueCell>{};

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
    registers[index] = value;
    if (index >= top) {
      top = index + 1;
    }
  }

  _UpvalueCell captureRegister(int index) {
    return _registerUpvalues.putIfAbsent(
      index,
      () => _UpvalueCell.fromRegister(registers, index),
    );
  }

  void closeOpenUpvalues() {
    for (final cell in _registerUpvalues.values) {
      cell.close();
    }
    _registerUpvalues.clear();
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
  BytecodeVm({Environment? environment})
    : environment = environment ?? Environment();

  final Environment environment;

  Future<Object?> execute(BytecodeChunk chunk) async {
    final frames = <_BytecodeFrame>[
      _BytecodeFrame(
        prototype: chunk.mainPrototype,
        args: const [],
        capturedUpvalues: const <_UpvalueCell>[],
        returnBase: 0,
        expectedResults: _returnAll,
      ),
    ];
    List<dynamic>? finalResults;

    void handleTopLevelReturn(List<dynamic> results) {
      finalResults = results;
    }

    while (frames.isNotEmpty) {
      final frame = frames.last;
      final instructions = frame.prototype.instructions;
      final constants = frame.prototype.constants;
      final registers = frame.registers;

      if (frame.pc >= instructions.length) {
        _handleReturn(frames, const [], handleTopLevelReturn);
        continue;
      }

      final instruction = instructions[frame.pc];
      frame.pc += 1;

      switch (instruction.opcode) {
        case BytecodeOpcode.move:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, frame.getRegister(instr.b));
          break;
        case BytecodeOpcode.loadK:
          final instr = instruction as ABxInstruction;
          frame.setRegister(instr.a, _resolveConstant(constants[instr.bx]));
          break;
        case BytecodeOpcode.loadTrue:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, true);
          break;
        case BytecodeOpcode.loadFalse:
          final instr = instruction as ABCInstruction;
          frame.setRegister(instr.a, false);
          break;
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
          final value = instr.k
              ? _resolveConstant(constants[instr.c])
              : registers[instr.c];
          environment.define(key, value);
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
            frame.setRegister(
              instr.a,
              Value.multi(List<dynamic>.from(frame.varargs)),
            );
          } else {
            for (var i = 0; i < requested; i++) {
              final value = i < frame.varargs.length ? frame.varargs[i] : null;
              frame.setRegister(instr.a + i, value);
            }
          }
          break;
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
          final instr = instruction as AsBxInstruction;
          frame.pc += instr.sBx;
          break;
        case BytecodeOpcode.tForCall:
          final instr = instruction as ABCInstruction;
          await _executeTForCall(frame, instr.a, instr.c);
          break;
        case BytecodeOpcode.tForLoop:
          final instr = instruction as AsBxInstruction;
          if (!_isTruthy(registers[instr.a + 2])) {
            frame.pc += instr.sBx;
          }
          break;
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
              continue;
            }
            final results = await _normalizeResults(
              await _callValue(callee, args),
            );
            _storeResults(frame, base, expectedResults, results);
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
            if (closure != null) {
              frames.removeLast();
              frames.add(
                _BytecodeFrame(
                  prototype: closure.prototype,
                  args: args,
                  capturedUpvalues: closure.upvalues,
                  returnBase: currentReturnBase,
                  expectedResults: currentExpected,
                ),
              );
              continue;
            }
            final results = await _normalizeResults(
              await _callValue(callee, args),
            );
            final completed = frames.removeLast();
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
        case BytecodeOpcode.newTable:
          final instr = instruction as ABCInstruction;
          final tableStorage = TableStorage();
          if (instr.b > 0) {
            tableStorage.ensureArrayCapacity(instr.b);
          }
          registers[instr.a] = Value(tableStorage);
          break;
        case BytecodeOpcode.add:
          _binaryArithmetic(frame, instruction as ABCInstruction, '+');
          break;
        case BytecodeOpcode.addK:
          _binaryArithmeticConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '+',
          );
          break;
        case BytecodeOpcode.sub:
          _binaryArithmetic(frame, instruction as ABCInstruction, '-');
          break;
        case BytecodeOpcode.subK:
          _binaryArithmeticConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '-',
          );
          break;
        case BytecodeOpcode.mul:
          _binaryArithmetic(frame, instruction as ABCInstruction, '*');
          break;
        case BytecodeOpcode.mulK:
          _binaryArithmeticConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '*',
          );
          break;
        case BytecodeOpcode.div:
          _binaryArithmetic(frame, instruction as ABCInstruction, '/');
          break;
        case BytecodeOpcode.divK:
          _binaryArithmeticConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '/',
          );
          break;
        case BytecodeOpcode.mod:
          _binaryArithmetic(frame, instruction as ABCInstruction, '%');
          break;
        case BytecodeOpcode.modK:
          _binaryArithmeticConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '%',
          );
          break;
        case BytecodeOpcode.idiv:
          _binaryArithmetic(frame, instruction as ABCInstruction, '//');
          break;
        case BytecodeOpcode.idivK:
          _binaryArithmeticConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '//',
          );
          break;
        case BytecodeOpcode.pow:
          _binaryArithmetic(frame, instruction as ABCInstruction, '^');
          break;
        case BytecodeOpcode.powK:
          _binaryArithmeticConstant(
            frame,
            instruction as ABCInstruction,
            constants,
            '^',
          );
          break;
        case BytecodeOpcode.band:
          _binaryBitwise(
            frame,
            instruction as ABCInstruction,
            NumberUtils.bitwiseAnd,
          );
          break;
        case BytecodeOpcode.bor:
          _binaryBitwise(
            frame,
            instruction as ABCInstruction,
            NumberUtils.bitwiseOr,
          );
          break;
        case BytecodeOpcode.bxor:
          _binaryBitwise(
            frame,
            instruction as ABCInstruction,
            NumberUtils.bitwiseXor,
          );
          break;
        case BytecodeOpcode.shl:
          _binaryBitwise(
            frame,
            instruction as ABCInstruction,
            NumberUtils.leftShift,
          );
          break;
        case BytecodeOpcode.shr:
          _binaryBitwise(
            frame,
            instruction as ABCInstruction,
            NumberUtils.rightShift,
          );
          break;
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
          _unaryBitwise(
            frame,
            instruction as ABCInstruction,
            NumberUtils.bitwiseNot,
          );
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
            _handleReturn(frames, results, handleTopLevelReturn);
          } else {
            final count = instr.b - 1;
            final results = <dynamic>[];
            for (var i = 0; i < count; i++) {
              results.add(frame.getRegister(instr.a + i));
            }
            _handleReturn(frames, results, handleTopLevelReturn);
          }
          break;
        case BytecodeOpcode.return0:
          _handleReturn(frames, const [], handleTopLevelReturn);
          break;
        case BytecodeOpcode.return1:
          final instr = instruction as ABCInstruction;
          _handleReturn(frames, <dynamic>[
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
        default:
          throw UnsupportedError(
            'Opcode ${instruction.opcode} not yet supported in BytecodeVm',
          );
      }
    }

    return _finalizeResults(finalResults);
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
      return args;
    }
    final argCount = instruction.b - 1;
    final args = <dynamic>[];
    for (var i = 0; i < argCount; i++) {
      args.addAll(_expandValue(frame.registers[instruction.a + 1 + i]));
    }
    return args;
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

  void _handleReturn(
    List<_BytecodeFrame> frames,
    List<dynamic> results,
    void Function(List<dynamic>) onTopLevel, {
    int? returnBase,
    int? expectedResults,
  }) {
    final completed = frames.removeLast();
    completed.closeOpenUpvalues();
    if (frames.isEmpty) {
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
    if (value is List && value is! Value) {
      return List<dynamic>.from(value);
    }
    return <dynamic>[value];
  }

  Object? _finalizeResults(List<dynamic>? results) {
    if (results == null || results.isEmpty) {
      return null;
    }
    if (results.length == 1) {
      return results.first;
    }
    return List<dynamic>.from(results, growable: false);
  }

  BytecodeClosure _createClosure(_BytecodeFrame frame, int prototypeIndex) {
    final child = frame.prototype.prototypes[prototypeIndex];
    final captured = <_UpvalueCell>[];
    for (final descriptor in child.upvalueDescriptors) {
      if (descriptor.inStack == 1) {
        captured.add(frame.captureRegister(descriptor.index));
      } else {
        captured.add(frame.upvalues[descriptor.index]);
      }
    }
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

  void _binaryArithmetic(
    _BytecodeFrame frame,
    ABCInstruction instruction,
    String operation,
  ) {
    final registers = frame.registers;
    final left = _rawValue(registers[instruction.b]);
    final right = _rawValue(registers[instruction.c]);
    frame.setRegister(
      instruction.a,
      NumberUtils.performArithmetic(operation, left, right),
    );
  }

  void _binaryArithmeticConstant(
    _BytecodeFrame frame,
    ABCInstruction instruction,
    List<BytecodeConstant> constants,
    String operation,
  ) {
    final registers = frame.registers;
    final left = _rawValue(registers[instruction.b]);
    final constant = _resolveConstant(constants[instruction.c]);
    frame.setRegister(
      instruction.a,
      NumberUtils.performArithmetic(operation, left, constant),
    );
  }

  void _binaryBitwise(
    _BytecodeFrame frame,
    ABCInstruction instruction,
    dynamic Function(dynamic, dynamic) operation,
  ) {
    final registers = frame.registers;
    final left = _rawValue(registers[instruction.b]);
    final right = _rawValue(registers[instruction.c]);
    frame.setRegister(instruction.a, operation(left, right));
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
    final control = registers[base + 2];

    final args = <Object?>[state, control];
    final results = await _normalizeResults(await _callValue(iterator, args));

    frame.setRegister(base + 2, results.isNotEmpty ? results.first : null);
    for (var i = 0; i < resultCount; i++) {
      final resultIndex = i + 1;
      final value = resultIndex < results.length ? results[resultIndex] : null;
      frame.setRegister(base + 3 + i, value);
    }
  }

  dynamic _tableGet(dynamic tableRef, dynamic key) {
    final tableValue = tableRef is Value ? tableRef : Value(tableRef);
    final keyValue = key is Value ? key : Value(key);
    final result = tableValue[keyValue];
    return result;
  }

  void _tableSet(dynamic tableRef, dynamic key, dynamic value) {
    final tableValue = tableRef is Value ? tableRef : Value(tableRef);
    final keyValue = key is Value ? key : Value(key);
    final storedValue = value is Value ? value : Value(value);
    tableValue[keyValue] = storedValue;
  }

  void _unaryNegate(_BytecodeFrame frame, ABCInstruction instruction) {
    final value = _rawValue(frame.registers[instruction.b]);
    frame.setRegister(instruction.a, NumberUtils.negate(value));
  }

  void _unaryBitwise(
    _BytecodeFrame frame,
    ABCInstruction instruction,
    dynamic Function(dynamic) transform,
  ) {
    final value = _rawValue(frame.registers[instruction.b]);
    frame.setRegister(instruction.a, transform(value));
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
    if (callable is Value) {
      final raw = callable.unwrap();
      if (raw is Function) {
        final result = raw(args);
        return result is Future ? await result : result;
      }
      final result = callable.call(args);
      return result is Future ? await result : result;
    }
    if (callable is Function) {
      final result = callable(args);
      return result is Future ? await result : result;
    }
    throw LuaError.typeError('attempt to call a ${callable.runtimeType} value');
  }

  Future<List<dynamic>> _normalizeResults(dynamic result) async {
    if (result == null) {
      return const [];
    }
    if (result is Value) {
      if (result.isMulti) {
        final rawList = result.raw as List<Object?>;
        return List<dynamic>.from(rawList);
      }
      return <dynamic>[result];
    }
    if (result is List) {
      return List<dynamic>.from(result);
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
      final leftValue = left is Value ? left : Value(left);
      final rightValue = right is Value ? right : Value(right);
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
      final leftValue = left is Value ? left : Value(left);
      final rightValue = right is Value ? right : Value(right);
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
      final leftValue = left is Value ? left : Value(left);
      final rightValue = right is Value ? right : Value(right);
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
      return Value(value).length;
    }
    throw LuaError.typeError('attempt to get length of a ${value.runtimeType}');
  }
}

/// Simple bytecode VM capable of executing the subset of opcodes produced by
/// [LoopBytecodeCompiler].
class LoopBytecodeVm {
  LoopBytecodeVm({required this.environment});

  final Environment environment;

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
    final left = _rawValue(registers[instr.b]);
    final right = _rawValue(registers[instr.c]);
    registers[instr.a] = NumberUtils.performArithmetic(operation, left, right);
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

  dynamic _callValue(dynamic callable, List<Object?> args) {
    if (callable is Value) {
      final result = callable.call(args);
      if (result is Future) {
        throw LuaError('asynchronous iterators are not supported in bytecode');
      }
      return result;
    }
    if (callable is Function) {
      final result = callable(args);
      if (result is Future) {
        throw LuaError('asynchronous iterators are not supported in bytecode');
      }
      return result;
    }
    throw LuaError.typeError('attempt to call a ${callable.runtimeType} value');
  }

  List<dynamic> _normalizeResults(dynamic result) {
    if (result == null) {
      return const [];
    }
    if (result is Value) {
      if (result.isMulti) {
        final rawList = result.raw as List<Object?>;
        return List<dynamic>.from(rawList);
      }
      return <dynamic>[result];
    }
    if (result is List) {
      return List<dynamic>.from(result);
    }
    return <dynamic>[result];
  }

  void _setTable(dynamic tableRef, dynamic keyRef, dynamic valueRef) {
    final tableValue = tableRef is Value ? tableRef : Value(tableRef);
    final keyValue = keyRef is Value ? keyRef : Value(keyRef);
    final storedValue = valueRef is Value ? valueRef : Value(valueRef);

    if (tableValue.raw is Map) {
      tableValue[keyValue] = storedValue;
      return;
    }

    throw LuaError.typeError(
      'attempt to index a ${tableValue.raw.runtimeType} value',
    );
  }
}
