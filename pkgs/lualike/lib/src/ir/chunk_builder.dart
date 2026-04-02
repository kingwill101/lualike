import 'instruction.dart';
import 'prototype.dart';

/// Utility for building lualike IR prototypes with automatic constant interning.
class LualikeIrPrototypeBuilder {
  LualikeIrPrototypeBuilder({
    this.registerCount = 0,
    this.paramCount = 0,
    this.isVararg = false,
    this.namedVarargRegister,
    this.lineDefined = 0,
    this.lastLineDefined = 0,
  });

  int registerCount;
  int paramCount;
  bool isVararg;
  int? namedVarargRegister;
  int lineDefined;
  int lastLineDefined;
  String? sourcePath;
  String? preferredDebugName;
  String preferredDebugNameWhat = '';

  final List<LualikeIrInstruction> _instructions = [];
  final List<LualikeIrConstant> _constants = [];
  final Map<Object?, int> _constantIndex = {};
  final List<LualikeIrPrototypeBuilder> _childBuilders = [];
  final List<LualikeIrUpvalueDescriptor> upvalueDescriptors = [];
  final List<String> upvalueNames = [];
  final List<LocalDebugEntry> localDebugEntries = [];
  final Map<int, String> toBeClosedNamesByPc = <int, String>{};
  LualikeIrDebugInfo? debugInfo;
  final List<int> _lineInfo = [];
  final Set<int> _constRegisters = <int>{};
  final Map<int, List<int>> _constSealPoints = <int, List<int>>{};

  List<LualikeIrInstruction> get instructions =>
      List.unmodifiable(_instructions);

  int addInstruction(LualikeIrInstruction instruction, {int? line}) {
    _instructions.add(instruction);
    _lineInfo.add(line ?? 0);
    return _instructions.length - 1;
  }

  void replaceInstruction(int index, LualikeIrInstruction instruction) {
    _instructions[index] = instruction;
  }

  int addConstant(LualikeIrConstant constant) {
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
    final builder = LualikeIrPrototypeBuilder();
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
    final list = _constSealPoints.putIfAbsent(instructionIndex, () => <int>[]);
    list.add(register);
  }

  LualikeIrPrototype build() {
    LualikeIrDebugInfo? info = debugInfo;
    if (_lineInfo.length < _instructions.length) {
      _lineInfo.addAll(
        List<int>.filled(_instructions.length - _lineInfo.length, 0),
      );
    }
    if (info == null &&
        (_lineInfo.isNotEmpty ||
            sourcePath != null ||
            preferredDebugName != null ||
            preferredDebugNameWhat.isNotEmpty)) {
      info = LualikeIrDebugInfo(
        lineInfo: List.unmodifiable(_lineInfo),
        absoluteSourcePath: sourcePath,
        localNames: List.unmodifiable(localDebugEntries),
        upvalueNames: List.unmodifiable(upvalueNames),
        toBeClosedNamesByPc: Map<int, String>.unmodifiable(toBeClosedNamesByPc),
        preferredName: preferredDebugName,
        preferredNameWhat: preferredDebugNameWhat,
      );
    } else if (info != null &&
        (preferredDebugName != null ||
            preferredDebugNameWhat.isNotEmpty ||
            toBeClosedNamesByPc.isNotEmpty)) {
      info = LualikeIrDebugInfo(
        lineInfo: info.lineInfo,
        absoluteSourcePath: info.absoluteSourcePath,
        localNames: info.localNames.isEmpty
            ? List.unmodifiable(localDebugEntries)
            : info.localNames,
        upvalueNames: info.upvalueNames.isEmpty
            ? List.unmodifiable(upvalueNames)
            : info.upvalueNames,
        toBeClosedNamesByPc: info.toBeClosedNamesByPc.isEmpty
            ? Map<int, String>.unmodifiable(toBeClosedNamesByPc)
            : info.toBeClosedNamesByPc,
        preferredName: preferredDebugName ?? info.preferredName,
        preferredNameWhat: preferredDebugNameWhat.isNotEmpty
            ? preferredDebugNameWhat
            : info.preferredNameWhat,
      );
    }

    final constFlags = List<bool>.filled(registerCount, false);
    for (final index in _constRegisters) {
      if (index >= 0 && index < constFlags.length) {
        constFlags[index] = true;
      }
    }

    return LualikeIrPrototype(
      registerCount: registerCount,
      paramCount: paramCount,
      isVararg: isVararg,
      namedVarargRegister: namedVarargRegister,
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

  Object? _constantKey(LualikeIrConstant constant) {
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

  final LualikeIrPrototypeBuilder builder;
  final int index;
}

class LualikeIrChunkBuilder {
  LualikeIrChunkBuilder({this.flags = const LualikeIrChunkFlags()});

  LualikeIrChunkFlags flags;
  final LualikeIrPrototypeBuilder mainPrototypeBuilder =
      LualikeIrPrototypeBuilder();

  LualikeIrChunk build() {
    final mainPrototype = mainPrototypeBuilder.build();
    final effectiveFlags = LualikeIrChunkFlags(
      hasDebugInfo: flags.hasDebugInfo || _prototypeHasDebugInfo(mainPrototype),
      hasConstantHash: flags.hasConstantHash,
    );
    return LualikeIrChunk(flags: effectiveFlags, mainPrototype: mainPrototype);
  }

  bool _prototypeHasDebugInfo(LualikeIrPrototype prototype) {
    if (prototype.debugInfo != null) {
      return true;
    }

    for (final child in prototype.prototypes) {
      if (_prototypeHasDebugInfo(child)) {
        return true;
      }
    }

    return false;
  }
}
