import 'dart:math';

import 'package:lualike/src/environment.dart';
import 'package:lualike/src/value.dart';
import 'package:lualike/src/lua_error.dart';

import 'prototype.dart';
import 'instruction.dart';
import 'opcode.dart';

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
          _binaryArithmetic(
            instruction as ABCInstruction,
            registers,
            (a, b) => a + b,
          );
          break;
        case BytecodeOpcode.sub:
          _binaryArithmetic(
            instruction as ABCInstruction,
            registers,
            (a, b) => a - b,
          );
          break;
        case BytecodeOpcode.mul:
          _binaryArithmetic(
            instruction as ABCInstruction,
            registers,
            (a, b) => a * b,
          );
          break;
        case BytecodeOpcode.div:
          _binaryArithmetic(
            instruction as ABCInstruction,
            registers,
            (a, b) => a / b,
          );
          break;
        case BytecodeOpcode.mod:
          _binaryArithmetic(
            instruction as ABCInstruction,
            registers,
            (a, b) => a % b,
          );
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
    num Function(num, num) operation,
  ) {
    final left = _asNumber(registers[instr.b]);
    final right = _asNumber(registers[instr.c]);
    final result = operation(left, right);
    registers[instr.a] = result;
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
    if (value is num) {
      return value;
    }
    if (value is Value) {
      final raw = value.raw;
      if (raw is num) {
        return raw;
      }
    }
    throw LuaError("attempt to perform arithmetic on a ${value.runtimeType}");
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
