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
  String? sourcePath;

  final List<BytecodeInstruction> _instructions = [];
  final List<BytecodeConstant> _constants = [];
  final Map<Object?, int> _constantIndex = {};
  final List<BytecodePrototypeBuilder> _childBuilders = [];
  final List<BytecodeUpvalueDescriptor> upvalueDescriptors = [];
  BytecodeDebugInfo? debugInfo;
  final List<int> _lineInfo = [];
  final Set<int> _constRegisters = <int>{};
  final Map<int, List<int>> _constSealPoints = <int, List<int>>{};

  List<BytecodeInstruction> get instructions =>
      List.unmodifiable(_instructions);

  int addInstruction(BytecodeInstruction instruction, {int? line}) {
    _instructions.add(instruction);
    _lineInfo.add(line ?? 0);
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

  ChildPrototypeBuilder createChild() {
    final builder = BytecodePrototypeBuilder();
    builder.sourcePath = sourcePath;
    final index = _childBuilders.length;
    _childBuilders.add(builder);
    return ChildPrototypeBuilder(builder: builder, index: index);
  }

  void markRegisterConst(int register) {
    if (register >= 0) {
      _constRegisters.add(register);
    }
  }

  void scheduleConstSeal(int instructionIndex, int register) {
    if (instructionIndex < 0) {
      return;
    }
    final list = _constSealPoints.putIfAbsent(
      instructionIndex,
      () => <int>[],
    );
    list.add(register);
  }

  BytecodePrototype build() {
    BytecodeDebugInfo? info = debugInfo;
    if (_lineInfo.length < _instructions.length) {
      _lineInfo.addAll(
        List<int>.filled(_instructions.length - _lineInfo.length, 0),
      );
    }
    if (info == null && (_lineInfo.isNotEmpty || sourcePath != null)) {
      info = BytecodeDebugInfo(
        lineInfo: List.unmodifiable(_lineInfo),
        absoluteSourcePath: sourcePath,
        localNames: const [],
        upvalueNames: const [],
      );
    }

    final constFlags = List<bool>.filled(registerCount, false);
    for (final index in _constRegisters) {
      if (index >= 0 && index < constFlags.length) {
        constFlags[index] = true;
      }
    }

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
      debugInfo: info,
      registerConstFlags: constFlags,
      constSealPoints: _constSealPoints.map(
        (key, value) => MapEntry(key, List<int>.unmodifiable(value)),
      ),
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

class ChildPrototypeBuilder {
  const ChildPrototypeBuilder({required this.builder, required this.index});

  final BytecodePrototypeBuilder builder;
  final int index;
}

class BytecodeChunkBuilder {
  BytecodeChunkBuilder({this.flags = const BytecodeChunkFlags()});

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
