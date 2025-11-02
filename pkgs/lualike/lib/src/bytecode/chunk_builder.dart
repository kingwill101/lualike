import 'instruction.dart';
import 'prototype.dart';

/// Utility for building bytecode prototypes with automatic constant interning.
class BytecodePrototypeBuilder {
  BytecodePrototypeBuilder({
    this.registerCount = 0,
    this.paramCount = 0,
    this.isVararg = false,
    this.lineDefined = 0,
    this.lastLineDefined = 0,
  });

  int registerCount;
  int paramCount;
  bool isVararg;
  int lineDefined;
  int lastLineDefined;

  final List<BytecodeInstruction> _instructions = [];
  final List<BytecodeConstant> _constants = [];
  final Map<Object?, int> _constantIndex = {};
  final List<BytecodePrototypeBuilder> _childBuilders = [];
  final List<BytecodeUpvalueDescriptor> upvalueDescriptors = [];
  BytecodeDebugInfo? debugInfo;

  List<BytecodeInstruction> get instructions => List.unmodifiable(_instructions);

  int addInstruction(BytecodeInstruction instruction) {
    _instructions.add(instruction);
    return _instructions.length - 1;
  }

  void replaceInstruction(int index, BytecodeInstruction instruction) {
    _instructions[index] = instruction;
  }

  int addConstant(BytecodeConstant constant) {
    final key = _constantKey(constant);
    final existing = _constantIndex[key];
    if (existing != null) {
      return existing;
    }
    final index = _constants.length;
    _constants.add(constant);
    _constantIndex[key] = index;
    return index;
  }

  BytecodePrototypeBuilder addChild(BytecodePrototypeBuilder builder) {
    _childBuilders.add(builder);
    return builder;
  }

  BytecodePrototype build() {
    return BytecodePrototype(
      registerCount: registerCount,
      paramCount: paramCount,
      isVararg: isVararg,
      upvalueDescriptors: List.unmodifiable(upvalueDescriptors),
      instructions: List.unmodifiable(_instructions),
      constants: List.unmodifiable(_constants),
      prototypes: _childBuilders.map((b) => b.build()).toList(),
      lineDefined: lineDefined,
      lastLineDefined: lastLineDefined,
      debugInfo: debugInfo,
    );
  }

  Object? _constantKey(BytecodeConstant constant) {
    return switch (constant) {
      NilConstant() => const Symbol('nil'),
      BooleanConstant(value: final value) => value,
      IntegerConstant(value: final value) => ('int', value),
      NumberConstant(value: final value) => ('num', value),
      ShortStringConstant(value: final value) => ('short', value),
      LongStringConstant(value: final value) => ('long', value),
    };
  }
}

class BytecodeChunkBuilder {
  BytecodeChunkBuilder({
    this.flags = const BytecodeChunkFlags(),
  });

  BytecodeChunkFlags flags;
  final BytecodePrototypeBuilder mainPrototypeBuilder =
      BytecodePrototypeBuilder();

  BytecodeChunk build() {
    return BytecodeChunk(
      flags: flags,
      mainPrototype: mainPrototypeBuilder.build(),
    );
  }
}
