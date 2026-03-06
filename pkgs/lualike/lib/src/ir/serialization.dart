import 'dart:convert';
import 'dart:typed_data';

import 'package:lualike/src/lua_string.dart';

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';

const List<int> _lualikeIrMagic = <int>[0x1B, 0x4C, 0x49, 0x52];
const int _formatMajorVersion = 1;
const int _formatMinorVersion = 0;

const int _instructionModeAbc = 0;
const int _instructionModeAbx = 1;
const int _instructionModeAsBx = 2;
const int _instructionModeAx = 3;
const int _instructionModeAsJ = 4;
const int _instructionModeAvbc = 5;

const int _constantNil = 0;
const int _constantBoolean = 1;
const int _constantInteger = 2;
const int _constantNumber = 3;
const int _constantShortString = 4;
const int _constantLongString = 5;

final Map<LualikeIrOpcode, int> _opcodeIndexByValue =
    Map<LualikeIrOpcode, int>.fromEntries(
      LualikeIrOpcode.values.indexed.map(
        (entry) => MapEntry(entry.$2, entry.$1),
      ),
    );

bool looksLikeLualikeIrBytes(List<int> bytes) {
  if (bytes.length < _lualikeIrMagic.length + 2) {
    return false;
  }

  for (var i = 0; i < _lualikeIrMagic.length; i++) {
    if (bytes[i] != _lualikeIrMagic[i]) {
      return false;
    }
  }

  return true;
}

bool looksLikeLualikeIrString(String value) =>
    looksLikeLualikeIrBytes(value.codeUnits);

Uint8List serializeLualikeIrChunk(LualikeIrChunk chunk) {
  final writer = _LualikeIrWriter();
  writer
    ..writeBytes(_lualikeIrMagic)
    ..writeUint8(_formatMajorVersion)
    ..writeUint8(_formatMinorVersion)
    ..writeUint8(chunk.flags.toByte())
    ..writeUint8(0);
  _writePrototype(writer, chunk.mainPrototype);
  return writer.toBytes();
}

LuaString serializeLualikeIrChunkAsLuaString(LualikeIrChunk chunk) {
  return LuaString.fromBytes(serializeLualikeIrChunk(chunk));
}

LualikeIrChunk deserializeLualikeIrBytes(List<int> bytes) {
  final reader = _LualikeIrReader(bytes);
  final magic = reader.readBytes(_lualikeIrMagic.length);
  if (!_matchesMagic(magic)) {
    throw const FormatException('Not a lualike_ir artifact');
  }

  final majorVersion = reader.readUint8();
  final minorVersion = reader.readUint8();
  if (majorVersion != _formatMajorVersion ||
      minorVersion != _formatMinorVersion) {
    throw FormatException(
      'Unsupported lualike_ir format version '
      '$majorVersion.$minorVersion',
    );
  }

  final flags = LualikeIrChunkFlags.fromByte(reader.readUint8());
  reader.readUint8();

  return LualikeIrChunk(flags: flags, mainPrototype: _readPrototype(reader));
}

bool _matchesMagic(List<int> bytes) {
  if (bytes.length != _lualikeIrMagic.length) {
    return false;
  }

  for (var i = 0; i < _lualikeIrMagic.length; i++) {
    if (bytes[i] != _lualikeIrMagic[i]) {
      return false;
    }
  }

  return true;
}

void _writePrototype(_LualikeIrWriter writer, LualikeIrPrototype prototype) {
  writer
    ..writeUint32(prototype.registerCount)
    ..writeUint32(prototype.paramCount)
    ..writeBool(prototype.isVararg)
    ..writeUint32(prototype.lineDefined)
    ..writeUint32(prototype.lastLineDefined);

  writer.writeUint32(prototype.upvalueDescriptors.length);
  for (final descriptor in prototype.upvalueDescriptors) {
    writer
      ..writeUint8(descriptor.inStack)
      ..writeUint32(descriptor.index)
      ..writeUint8(descriptor.kind);
  }

  writer.writeUint32(prototype.instructions.length);
  for (final instruction in prototype.instructions) {
    _writeInstruction(writer, instruction);
  }

  writer.writeUint32(prototype.constants.length);
  for (final constant in prototype.constants) {
    _writeConstant(writer, constant);
  }

  writer.writeUint32(prototype.prototypes.length);
  for (final child in prototype.prototypes) {
    _writePrototype(writer, child);
  }

  writer.writeUint32(prototype.registerConstFlags.length);
  for (final isConst in prototype.registerConstFlags) {
    writer.writeBool(isConst);
  }

  final sealEntries = prototype.constSealPoints.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  writer.writeUint32(sealEntries.length);
  for (final entry in sealEntries) {
    final points = List<int>.from(entry.value)..sort();
    writer
      ..writeUint32(entry.key)
      ..writeUint32(points.length);
    for (final point in points) {
      writer.writeUint32(point);
    }
  }

  final debugInfo = prototype.debugInfo;
  writer.writeBool(debugInfo != null);
  if (debugInfo == null) {
    return;
  }

  writer.writeUint32(debugInfo.lineInfo.length);
  for (final line in debugInfo.lineInfo) {
    writer.writeUint32(line);
  }

  writer.writeNullableString(debugInfo.absoluteSourcePath);

  writer.writeUint32(debugInfo.localNames.length);
  for (final entry in debugInfo.localNames) {
    writer
      ..writeString(entry.name)
      ..writeUint32(entry.startPc)
      ..writeUint32(entry.endPc);
  }

  writer.writeUint32(debugInfo.upvalueNames.length);
  for (final name in debugInfo.upvalueNames) {
    writer.writeString(name);
  }
}

LualikeIrPrototype _readPrototype(_LualikeIrReader reader) {
  final registerCount = reader.readUint32();
  final paramCount = reader.readUint32();
  final isVararg = reader.readBool();
  final lineDefined = reader.readUint32();
  final lastLineDefined = reader.readUint32();

  final upvalueCount = reader.readUint32();
  final upvalueDescriptors = List<LualikeIrUpvalueDescriptor>.generate(
    upvalueCount,
    (_) => LualikeIrUpvalueDescriptor(
      inStack: reader.readUint8(),
      index: reader.readUint32(),
      kind: reader.readUint8(),
    ),
    growable: false,
  );

  final instructionCount = reader.readUint32();
  final instructions = List<LualikeIrInstruction>.generate(
    instructionCount,
    (_) => _readInstruction(reader),
    growable: false,
  );

  final constantCount = reader.readUint32();
  final constants = List<LualikeIrConstant>.generate(
    constantCount,
    (_) => _readConstant(reader),
    growable: false,
  );

  final childCount = reader.readUint32();
  final prototypes = List<LualikeIrPrototype>.generate(
    childCount,
    (_) => _readPrototype(reader),
    growable: false,
  );

  final registerConstFlagCount = reader.readUint32();
  final registerConstFlags = List<bool>.generate(
    registerConstFlagCount,
    (_) => reader.readBool(),
    growable: false,
  );

  final constSealEntryCount = reader.readUint32();
  final constSealPoints = <int, List<int>>{};
  for (var i = 0; i < constSealEntryCount; i++) {
    final registerIndex = reader.readUint32();
    final pointCount = reader.readUint32();
    constSealPoints[registerIndex] = List<int>.generate(
      pointCount,
      (_) => reader.readUint32(),
      growable: false,
    );
  }

  final debugInfo = reader.readBool() ? _readDebugInfo(reader) : null;

  return LualikeIrPrototype(
    registerCount: registerCount,
    paramCount: paramCount,
    isVararg: isVararg,
    upvalueDescriptors: upvalueDescriptors,
    instructions: instructions,
    constants: constants,
    prototypes: prototypes,
    lineDefined: lineDefined,
    lastLineDefined: lastLineDefined,
    debugInfo: debugInfo,
    registerConstFlags: registerConstFlags,
    constSealPoints: constSealPoints,
  );
}

LualikeIrDebugInfo _readDebugInfo(_LualikeIrReader reader) {
  final lineInfoCount = reader.readUint32();
  final lineInfo = List<int>.generate(
    lineInfoCount,
    (_) => reader.readUint32(),
    growable: false,
  );

  final absoluteSourcePath = reader.readNullableString();
  final localEntryCount = reader.readUint32();
  final localNames = List<LocalDebugEntry>.generate(
    localEntryCount,
    (_) => LocalDebugEntry(
      name: reader.readString(),
      startPc: reader.readUint32(),
      endPc: reader.readUint32(),
    ),
    growable: false,
  );

  final upvalueNameCount = reader.readUint32();
  final upvalueNames = List<String>.generate(
    upvalueNameCount,
    (_) => reader.readString(),
    growable: false,
  );

  return LualikeIrDebugInfo(
    lineInfo: lineInfo,
    absoluteSourcePath: absoluteSourcePath,
    localNames: localNames,
    upvalueNames: upvalueNames,
  );
}

void _writeInstruction(
  _LualikeIrWriter writer,
  LualikeIrInstruction instruction,
) {
  final opcodeIndex = _opcodeIndexByValue[instruction.opcode];
  if (opcodeIndex == null) {
    throw StateError('Unknown lualike_ir opcode ${instruction.opcode.name}');
  }

  writer.writeUint8(opcodeIndex);

  switch (instruction) {
    case ABCInstruction(:final a, :final b, :final c, :final k):
      writer
        ..writeUint8(_instructionModeAbc)
        ..writeUint32(a)
        ..writeUint32(b)
        ..writeUint32(c)
        ..writeBool(k);
    case ABxInstruction(:final a, :final bx):
      writer
        ..writeUint8(_instructionModeAbx)
        ..writeUint32(a)
        ..writeUint32(bx);
    case AsBxInstruction(:final a, :final sBx):
      writer
        ..writeUint8(_instructionModeAsBx)
        ..writeUint32(a)
        ..writeInt32(sBx);
    case AxInstruction(:final ax):
      writer
        ..writeUint8(_instructionModeAx)
        ..writeUint32(ax);
    case AsJInstruction(:final sJ):
      writer
        ..writeUint8(_instructionModeAsJ)
        ..writeInt32(sJ);
    case AvBCInstruction(:final a, :final vB, :final vC, :final k):
      writer
        ..writeUint8(_instructionModeAvbc)
        ..writeUint32(a)
        ..writeUint32(vB)
        ..writeUint32(vC)
        ..writeBool(k);
  }
}

LualikeIrInstruction _readInstruction(_LualikeIrReader reader) {
  final opcodeIndex = reader.readUint8();
  if (opcodeIndex >= LualikeIrOpcode.values.length) {
    throw FormatException('Unknown lualike_ir opcode index $opcodeIndex');
  }

  final opcode = LualikeIrOpcode.values[opcodeIndex];
  return switch (reader.readUint8()) {
    _instructionModeAbc => ABCInstruction(
      opcode: opcode,
      a: reader.readUint32(),
      b: reader.readUint32(),
      c: reader.readUint32(),
      k: reader.readBool(),
    ),
    _instructionModeAbx => ABxInstruction(
      opcode: opcode,
      a: reader.readUint32(),
      bx: reader.readUint32(),
    ),
    _instructionModeAsBx => AsBxInstruction(
      opcode: opcode,
      a: reader.readUint32(),
      sBx: reader.readInt32(),
    ),
    _instructionModeAx => AxInstruction(
      opcode: opcode,
      ax: reader.readUint32(),
    ),
    _instructionModeAsJ => AsJInstruction(
      opcode: opcode,
      sJ: reader.readInt32(),
    ),
    _instructionModeAvbc => AvBCInstruction(
      opcode: opcode,
      a: reader.readUint32(),
      vB: reader.readUint32(),
      vC: reader.readUint32(),
      k: reader.readBool(),
    ),
    final mode => throw FormatException(
      'Unknown lualike_ir instruction mode $mode',
    ),
  };
}

void _writeConstant(_LualikeIrWriter writer, LualikeIrConstant constant) {
  switch (constant) {
    case NilConstant():
      writer.writeUint8(_constantNil);
    case BooleanConstant(:final value):
      writer
        ..writeUint8(_constantBoolean)
        ..writeBool(value);
    case IntegerConstant(:final value):
      writer
        ..writeUint8(_constantInteger)
        ..writeInt64(value);
    case NumberConstant(:final value):
      writer
        ..writeUint8(_constantNumber)
        ..writeFloat64(value);
    case ShortStringConstant(:final value):
      writer
        ..writeUint8(_constantShortString)
        ..writeString(value);
    case LongStringConstant(:final value):
      writer
        ..writeUint8(_constantLongString)
        ..writeString(value);
  }
}

LualikeIrConstant _readConstant(_LualikeIrReader reader) {
  return switch (reader.readUint8()) {
    _constantNil => const NilConstant(),
    _constantBoolean => BooleanConstant(reader.readBool()),
    _constantInteger => IntegerConstant(reader.readInt64()),
    _constantNumber => NumberConstant(reader.readFloat64()),
    _constantShortString => ShortStringConstant(reader.readString()),
    _constantLongString => LongStringConstant(reader.readString()),
    final tag => throw FormatException('Unknown lualike_ir constant tag $tag'),
  };
}

class _LualikeIrWriter {
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  void writeBool(bool value) => writeUint8(value ? 1 : 0);

  void writeBytes(List<int> bytes) => _buffer.add(bytes);

  void writeUint8(int value) => _buffer.addByte(value & 0xff);

  void writeUint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _buffer.add(data.buffer.asUint8List());
  }

  void writeInt32(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    _buffer.add(data.buffer.asUint8List());
  }

  void writeInt64(int value) {
    final data = ByteData(8)..setInt64(0, value, Endian.little);
    _buffer.add(data.buffer.asUint8List());
  }

  void writeFloat64(double value) {
    final data = ByteData(8)..setFloat64(0, value, Endian.little);
    _buffer.add(data.buffer.asUint8List());
  }

  void writeString(String value) {
    final bytes = utf8.encode(value);
    writeUint32(bytes.length);
    writeBytes(bytes);
  }

  void writeNullableString(String? value) {
    writeBool(value != null);
    if (value != null) {
      writeString(value);
    }
  }

  Uint8List toBytes() => _buffer.takeBytes();
}

class _LualikeIrReader {
  _LualikeIrReader(List<int> bytes)
    : _bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  final Uint8List _bytes;
  int _offset = 0;

  bool readBool() => readUint8() != 0;

  int readUint8() {
    _requireAvailable(1);
    return _bytes[_offset++];
  }

  Uint8List readBytes(int length) {
    _requireAvailable(length);
    final bytes = _bytes.sublist(_offset, _offset + length);
    _offset += length;
    return bytes;
  }

  int readUint32() {
    _requireAvailable(4);
    final value = ByteData.sublistView(
      _bytes,
      _offset,
      _offset + 4,
    ).getUint32(0, Endian.little);
    _offset += 4;
    return value;
  }

  int readInt32() {
    _requireAvailable(4);
    final value = ByteData.sublistView(
      _bytes,
      _offset,
      _offset + 4,
    ).getInt32(0, Endian.little);
    _offset += 4;
    return value;
  }

  int readInt64() {
    _requireAvailable(8);
    final value = ByteData.sublistView(
      _bytes,
      _offset,
      _offset + 8,
    ).getInt64(0, Endian.little);
    _offset += 8;
    return value;
  }

  double readFloat64() {
    _requireAvailable(8);
    final value = ByteData.sublistView(
      _bytes,
      _offset,
      _offset + 8,
    ).getFloat64(0, Endian.little);
    _offset += 8;
    return value;
  }

  String readString() {
    final length = readUint32();
    final bytes = readBytes(length);
    return utf8.decode(bytes);
  }

  String? readNullableString() {
    if (!readBool()) {
      return null;
    }
    return readString();
  }

  void _requireAvailable(int length) {
    if (_offset + length > _bytes.length) {
      throw const FormatException('Unexpected end of lualike_ir artifact');
    }
  }
}
