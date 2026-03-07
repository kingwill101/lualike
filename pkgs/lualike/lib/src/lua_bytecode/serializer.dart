import 'dart:typed_data';

import 'chunk.dart';

Uint8List serializeLuaBytecodeChunk(LuaBytecodeBinaryChunk chunk) {
  final writer = _LuaBytecodeWriter();
  writer.writeChunk(chunk);
  return writer.takeBytes();
}

final class _LuaBytecodeWriter {
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  var _length = 0;

  Uint8List takeBytes() => _bytes.takeBytes();

  void writeChunk(LuaBytecodeBinaryChunk chunk) {
    _writeHeader(chunk.header);
    _writeByte(chunk.rootUpvalueCount);
    _writePrototype(chunk.mainPrototype, chunk.header);
  }

  void _writeHeader(LuaBytecodeChunkHeader header) {
    _writeBytes(header.signature);
    _writeByte(header.version);
    _writeByte(header.format);
    _writeBytes(header.luacData);
    _writeByte(header.intSize);
    _writeSignedFixedInt(header.luacInt, header.intSize);
    _writeByte(header.instructionSize);
    _writeUnsignedFixedInt(header.luacInstruction, header.instructionSize);
    _writeByte(header.luaIntegerSize);
    _writeSignedFixedInt(header.luacInt, header.luaIntegerSize);
    _writeByte(header.luaNumberSize);
    _writeFixedDouble(header.luacNumber, header.luaNumberSize);
  }

  void _writePrototype(
    LuaBytecodePrototype prototype,
    LuaBytecodeChunkHeader header,
  ) {
    _writeVarint(prototype.lineDefined);
    _writeVarint(prototype.lastLineDefined);
    _writeByte(prototype.parameterCount);
    _writeByte(prototype.flags);
    _writeByte(prototype.maxStackSize);

    _writeVarint(prototype.code.length);
    _alignTo(header.instructionSize);
    for (final instruction in prototype.code) {
      _writeUnsignedFixedInt(instruction.rawValue, header.instructionSize);
    }

    _writeVarint(prototype.constants.length);
    for (final constant in prototype.constants) {
      _writeConstant(constant, header);
    }

    _writeVarint(prototype.upvalues.length);
    for (final upvalue in prototype.upvalues) {
      _writeByte(upvalue.inStack ? 1 : 0);
      _writeByte(upvalue.index);
      _writeByte(upvalue.kind.value);
    }

    _writeVarint(prototype.prototypes.length);
    for (final child in prototype.prototypes) {
      _writePrototype(child, header);
    }

    _writeString(prototype.source);

    _writeVarint(prototype.lineInfo.length);
    for (final delta in prototype.lineInfo) {
      _writeByte(delta & 0xff);
    }

    _writeVarint(prototype.absoluteLineInfo.length);
    if (prototype.absoluteLineInfo.isNotEmpty) {
      _alignTo(header.intSize);
      for (final info in prototype.absoluteLineInfo) {
        _writeSignedFixedInt(info.pc, header.intSize);
        _writeSignedFixedInt(info.line, header.intSize);
      }
    }

    _writeVarint(prototype.localVariables.length);
    for (final local in prototype.localVariables) {
      _writeString(local.name);
      _writeVarint(local.startPc);
      _writeVarint(local.endPc);
    }

    if (prototype.upvalueNames.isEmpty) {
      _writeVarint(0);
      return;
    }

    _writeVarint(prototype.upvalueNames.length);
    for (final upvalueName in prototype.upvalueNames) {
      _writeString(upvalueName);
    }
  }

  void _writeConstant(
    LuaBytecodeConstant constant,
    LuaBytecodeChunkHeader header,
  ) {
    _writeByte(constant.tag.value);
    switch (constant) {
      case LuaBytecodeNilConstant():
      case LuaBytecodeBooleanConstant():
        break;
      case LuaBytecodeIntegerConstant(value: final value):
        _writeLuaInteger(value);
      case LuaBytecodeFloatConstant(value: final value):
        _writeFixedDouble(value, header.luaNumberSize);
      case LuaBytecodeStringConstant(value: final value):
        _writeString(value);
    }
  }

  void _writeString(String? value) {
    if (value == null) {
      _writeVarint(0);
      _writeVarint(0);
      return;
    }

    final bytes = value.codeUnits;
    _writeVarint(bytes.length + 1);
    _writeBytes(bytes);
    _writeByte(0);
  }

  void _writeLuaInteger(int value) {
    final encoded = value >= 0 ? value << 1 : ((~value) << 1) | 1;
    _writeVarint(encoded);
  }

  void _writeVarint(int value) {
    if (value < 0) {
      throw RangeError.value(value, 'value', 'Varint must be non-negative');
    }

    final groups = <int>[value & 0x7f];
    var remaining = value >> 7;
    while (remaining > 0) {
      groups.add(remaining & 0x7f);
      remaining >>= 7;
    }

    for (var index = groups.length - 1; index >= 0; index--) {
      final isLast = index == 0;
      _writeByte(groups[index] | (isLast ? 0 : 0x80));
    }
  }

  void _alignTo(int alignment) {
    final remainder = _length % alignment;
    if (remainder == 0) {
      return;
    }
    final padding = alignment - remainder;
    for (var index = 0; index < padding; index++) {
      _writeByte(0);
    }
  }

  void _writeFixedDouble(double value, int size) {
    final data = ByteData(size);
    switch (size) {
      case 4:
        data.setFloat32(0, value, Endian.little);
      case 8:
        data.setFloat64(0, value, Endian.little);
      default:
        throw ArgumentError.value(size, 'size', 'Unsupported Lua number size');
    }
    _writeBytes(data.buffer.asUint8List());
  }

  void _writeSignedFixedInt(int value, int size) {
    final data = ByteData(size);
    switch (size) {
      case 1:
        data.setInt8(0, value);
      case 2:
        data.setInt16(0, value, Endian.little);
      case 4:
        data.setInt32(0, value, Endian.little);
      case 8:
        data.setInt64(0, value, Endian.little);
      default:
        throw ArgumentError.value(size, 'size', 'Unsupported integer size');
    }
    _writeBytes(data.buffer.asUint8List());
  }

  void _writeUnsignedFixedInt(int value, int size) {
    final data = ByteData(size);
    switch (size) {
      case 1:
        data.setUint8(0, value);
      case 2:
        data.setUint16(0, value, Endian.little);
      case 4:
        data.setUint32(0, value, Endian.little);
      case 8:
        data.setUint64(0, value, Endian.little);
      default:
        throw ArgumentError.value(size, 'size', 'Unsupported integer size');
    }
    _writeBytes(data.buffer.asUint8List());
  }

  void _writeBytes(List<int> bytes) {
    _bytes.add(bytes);
    _length += bytes.length;
  }

  void _writeByte(int value) {
    _bytes.addByte(value & 0xff);
    _length += 1;
  }
}
