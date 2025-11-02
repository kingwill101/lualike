import 'dart:async';
import 'dart:math';

import 'package:lualike/src/environment.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/value.dart';

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';

/// Minimal bytecode VM capable of executing the subset of opcodes currently
/// produced by [BytecodeCompiler]. The implementation will expand as more AST
/// features are lowered to bytecode.
class BytecodeVm {
  BytecodeVm({Environment? environment})
    : environment = environment ?? Environment();

  final Environment environment;

  Future<Object?> execute(BytecodeChunk chunk) async {
    final proto = chunk.mainPrototype;
    final registers = List<dynamic>.filled(max(proto.registerCount, 1), null);
    final instructions = proto.instructions;
    final constants = proto.constants;
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
        case BytecodeOpcode.loadTrue:
          final instr = instruction as ABCInstruction;
          registers[instr.a] = true;
          break;
        case BytecodeOpcode.loadFalse:
          final instr = instruction as ABCInstruction;
          registers[instr.a] = false;
          break;
        case BytecodeOpcode.loadNil:
          final instr = instruction as ABCInstruction;
          final count = instr.b;
          for (var offset = 0; offset <= count; offset++) {
            registers[instr.a + offset] = null;
          }
          break;
        case BytecodeOpcode.getTabUp:
          final instr = instruction as ABCInstruction;
          final key = _constantToKey(constants[instr.c]);
          registers[instr.a] = environment.get(key);
          break;
        case BytecodeOpcode.getTable:
          final instr = instruction as ABCInstruction;
          registers[instr.a] = _tableGet(
            registers[instr.b],
            registers[instr.c],
          );
          break;
        case BytecodeOpcode.getField:
          final instr = instruction as ABCInstruction;
          final key = _constantToKey(constants[instr.c]);
          registers[instr.a] = _tableGet(registers[instr.b], key);
          break;
        case BytecodeOpcode.getI:
          final instr = instruction as ABCInstruction;
          registers[instr.a] = _tableGet(registers[instr.b], instr.c);
          break;
        case BytecodeOpcode.test:
          final instr = instruction as ABCInstruction;
          final cond = _isTruthy(registers[instr.a]);
          if ((!cond) == instr.k) {
            pc += 1;
          }
          break;
        case BytecodeOpcode.testSet:
          final instr = instruction as ABCInstruction;
          final cond = _isTruthy(registers[instr.b]);
          if ((!cond) == instr.k) {
            pc += 1;
          } else {
            registers[instr.a] = registers[instr.b];
          }
          break;
        case BytecodeOpcode.jmp:
          final instr = instruction as AsJInstruction;
          pc += instr.sJ;
          break;
        case BytecodeOpcode.tForPrep:
          final instr = instruction as AsBxInstruction;
          pc += instr.sBx;
          break;
        case BytecodeOpcode.tForCall:
          final instr = instruction as ABCInstruction;
          await _executeTForCall(registers, instr.a, instr.c);
          break;
        case BytecodeOpcode.tForLoop:
          final instr = instruction as AsBxInstruction;
          if (!_isTruthy(registers[instr.a + 2])) {
            pc += instr.sBx;
          }
          break;
        case BytecodeOpcode.call:
          final instr = instruction as ABCInstruction;
          final base = instr.a;
          final argCount = instr.b - 1;
          final args = <Object?>[for (var i = 0; i < argCount; i++) registers[base + 1 + i]];
          final results = await _normalizeResults(
            await _callValue(registers[base], args),
          );
          final resultSlots = instr.c - 1;
          if (resultSlots > 0) {
            for (var i = 0; i < resultSlots; i++) {
              registers[base + i] = i < results.length ? results[i] : null;
            }
          }
          break;
        case BytecodeOpcode.tailCall:
          final instr = instruction as ABCInstruction;
          final base = instr.a;
          final argCount = instr.b - 1;
          final args = <Object?>[for (var i = 0; i < argCount; i++) registers[base + 1 + i]];
          final results = await _normalizeResults(
            await _callValue(registers[base], args),
          );
          if (results.isEmpty) {
            return null;
          }
          if (results.length == 1) {
            return results.first;
          }
          return List<dynamic>.from(results, growable: false);
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
        case BytecodeOpcode.add:
          _binaryArithmetic(instruction as ABCInstruction, registers, '+');
          break;
        case BytecodeOpcode.addK:
          _binaryArithmeticConstant(
            instruction as ABCInstruction,
            registers,
            constants,
            '+',
          );
          break;
        case BytecodeOpcode.sub:
          _binaryArithmetic(instruction as ABCInstruction, registers, '-');
          break;
        case BytecodeOpcode.subK:
          _binaryArithmeticConstant(
            instruction as ABCInstruction,
            registers,
            constants,
            '-',
          );
          break;
        case BytecodeOpcode.mul:
          _binaryArithmetic(instruction as ABCInstruction, registers, '*');
          break;
        case BytecodeOpcode.mulK:
          _binaryArithmeticConstant(
            instruction as ABCInstruction,
            registers,
            constants,
            '*',
          );
          break;
        case BytecodeOpcode.div:
          _binaryArithmetic(instruction as ABCInstruction, registers, '/');
          break;
        case BytecodeOpcode.divK:
          _binaryArithmeticConstant(
            instruction as ABCInstruction,
            registers,
            constants,
            '/',
          );
          break;
        case BytecodeOpcode.mod:
          _binaryArithmetic(instruction as ABCInstruction, registers, '%');
          break;
        case BytecodeOpcode.modK:
          _binaryArithmeticConstant(
            instruction as ABCInstruction,
            registers,
            constants,
            '%',
          );
          break;
        case BytecodeOpcode.idiv:
          _binaryArithmetic(instruction as ABCInstruction, registers, '//');
          break;
        case BytecodeOpcode.idivK:
          _binaryArithmeticConstant(
            instruction as ABCInstruction,
            registers,
            constants,
            '//',
          );
          break;
        case BytecodeOpcode.pow:
          _binaryArithmetic(instruction as ABCInstruction, registers, '^');
          break;
        case BytecodeOpcode.powK:
          _binaryArithmeticConstant(
            instruction as ABCInstruction,
            registers,
            constants,
            '^',
          );
          break;
        case BytecodeOpcode.band:
          _binaryBitwise(
            instruction as ABCInstruction,
            registers,
            NumberUtils.bitwiseAnd,
          );
          break;
        case BytecodeOpcode.bor:
          _binaryBitwise(
            instruction as ABCInstruction,
            registers,
            NumberUtils.bitwiseOr,
          );
          break;
        case BytecodeOpcode.bxor:
          _binaryBitwise(
            instruction as ABCInstruction,
            registers,
            NumberUtils.bitwiseXor,
          );
          break;
        case BytecodeOpcode.shl:
          _binaryBitwise(
            instruction as ABCInstruction,
            registers,
            NumberUtils.leftShift,
          );
          break;
        case BytecodeOpcode.shr:
          _binaryBitwise(
            instruction as ABCInstruction,
            registers,
            NumberUtils.rightShift,
          );
          break;
        case BytecodeOpcode.eq:
          _binaryComparison(instruction as ABCInstruction, registers, _equals);
          break;
        case BytecodeOpcode.eqK:
          _binaryComparisonConstant(
            instruction as ABCInstruction,
            registers,
            constants,
            _equals,
          );
          break;
        case BytecodeOpcode.eqI:
          final instr = instruction as ABCInstruction;
          registers[instr.a] = _equals(registers[instr.b], instr.c);
          break;
        case BytecodeOpcode.lt:
          _binaryComparison(
            instruction as ABCInstruction,
            registers,
            _lessThan,
          );
          break;
        case BytecodeOpcode.ltI:
          final instr = instruction as ABCInstruction;
          registers[instr.a] = _lessThan(registers[instr.b], instr.c);
          break;
        case BytecodeOpcode.le:
          _binaryComparison(
            instruction as ABCInstruction,
            registers,
            _lessEqual,
          );
          break;
        case BytecodeOpcode.leI:
          final instr = instruction as ABCInstruction;
          registers[instr.a] = _lessEqual(registers[instr.b], instr.c);
          break;
        case BytecodeOpcode.gtI:
          final instr = instruction as ABCInstruction;
          registers[instr.a] = _lessThan(instr.c, registers[instr.b]);
          break;
        case BytecodeOpcode.geI:
          final instr = instruction as ABCInstruction;
          registers[instr.a] = _lessEqual(instr.c, registers[instr.b]);
          break;
        case BytecodeOpcode.unm:
          _unaryNegate(instruction as ABCInstruction, registers);
          break;
        case BytecodeOpcode.bnot:
          _unaryBitwise(
            instruction as ABCInstruction,
            registers,
            NumberUtils.bitwiseNot,
          );
          break;
        case BytecodeOpcode.notOp:
          _unaryBoolean(instruction as ABCInstruction, registers);
          break;
        case BytecodeOpcode.len:
          _unaryLength(instruction as ABCInstruction, registers);
          break;
        case BytecodeOpcode.ret:
          final instr = instruction as ABCInstruction;
          final resultCount = instr.b - 1;
          if (resultCount <= 0) {
            return null;
          }
          if (resultCount == 1) {
            return registers[instr.a];
          }
          return List<dynamic>.generate(
            resultCount,
            (index) => registers[instr.a + index],
            growable: false,
          );
        case BytecodeOpcode.return0:
          return null;
        case BytecodeOpcode.return1:
          final instr = instruction as ABCInstruction;
          return registers[instr.a];
        case BytecodeOpcode.forPrep:
          final instr = instruction as AsBxInstruction;
          _executeForPrep(registers, instr.a);
          pc += instr.sBx;
          break;
        case BytecodeOpcode.forLoop:
          final instr = instruction as AsBxInstruction;
          final shouldContinue = _executeForLoop(registers, instr.a);
          if (shouldContinue) {
            pc += instr.sBx;
          }
          break;
        default:
          throw UnsupportedError(
            'Opcode ${instruction.opcode} not yet supported in BytecodeVm',
          );
      }
    }

    return null;
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
    ABCInstruction instruction,
    List<dynamic> registers,
    String operation,
  ) {
    final left = _rawValue(registers[instruction.b]);
    final right = _rawValue(registers[instruction.c]);
    registers[instruction.a] = NumberUtils.performArithmetic(
      operation,
      left,
      right,
    );
  }

  void _binaryArithmeticConstant(
    ABCInstruction instruction,
    List<dynamic> registers,
    List<BytecodeConstant> constants,
    String operation,
  ) {
    final left = _rawValue(registers[instruction.b]);
    final constant = _resolveConstant(constants[instruction.c]);
    registers[instruction.a] = NumberUtils.performArithmetic(
      operation,
      left,
      constant,
    );
  }

  void _binaryBitwise(
    ABCInstruction instruction,
    List<dynamic> registers,
    dynamic Function(dynamic, dynamic) operation,
  ) {
    final left = _rawValue(registers[instruction.b]);
    final right = _rawValue(registers[instruction.c]);
    registers[instruction.a] = operation(left, right);
  }

  void _binaryComparison(
    ABCInstruction instruction,
    List<dynamic> registers,
    bool Function(dynamic, dynamic) comparison,
  ) {
    final left = registers[instruction.b];
    final right = registers[instruction.c];
    registers[instruction.a] = comparison(left, right);
  }

  void _binaryComparisonConstant(
    ABCInstruction instruction,
    List<dynamic> registers,
    List<BytecodeConstant> constants,
    bool Function(dynamic, dynamic) comparison,
  ) {
    final left = registers[instruction.b];
    final constant = _resolveConstant(constants[instruction.c]);
    registers[instruction.a] = comparison(left, constant);
  }

  void _executeForPrep(List<dynamic> registers, int base) {
    final initial = _asNumber(registers[base]);
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

  Future<void> _executeTForCall(
    List<dynamic> registers,
    int base,
    int resultCount,
  ) async {
    final iterator = registers[base];
    final state = registers[base + 1];
    final control = registers[base + 2];

    final args = <Object?>[state, control];
    final results = await _normalizeResults(await _callValue(iterator, args));

    registers[base + 2] = results.isNotEmpty ? results.first : null;
    for (var i = 0; i < resultCount; i++) {
      final resultIndex = i + 1;
      final value = resultIndex < results.length ? results[resultIndex] : null;
      registers[base + 3 + i] = value;
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

  void _unaryNegate(ABCInstruction instruction, List<dynamic> registers) {
    final value = _rawValue(registers[instruction.b]);
    registers[instruction.a] = NumberUtils.negate(value);
  }

  void _unaryBitwise(
    ABCInstruction instruction,
    List<dynamic> registers,
    dynamic Function(dynamic) transform,
  ) {
    final value = _rawValue(registers[instruction.b]);
    registers[instruction.a] = transform(value);
  }

  void _unaryBoolean(ABCInstruction instruction, List<dynamic> registers) {
    final value = registers[instruction.b];
    registers[instruction.a] = !_isTruthy(value);
  }

  void _unaryLength(ABCInstruction instruction, List<dynamic> registers) {
    final value = registers[instruction.b];
    registers[instruction.a] = _lengthOf(value);
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
    throw LuaError.typeError(
      'attempt to call a ${callable.runtimeType} value',
    );
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
    throw LuaError.typeError(
      'attempt to call a ${callable.runtimeType} value',
    );
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
