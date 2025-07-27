import 'dart:convert';
import 'dart:typed_data';

import 'bytecode.dart';
import 'opcode.dart';

/// Bytecode serializer/deserializer
class BytecodeSerializer {
  static const int _magicNumber = 0x1B4C4B45; // 'LKE\x1b'
  static const int _version = 1;

  /// Serialize a bytecode chunk to bytes
  static Uint8List serialize(BytecodeChunk chunk) {
    final builder = BytesBuilder();

    // Write header
    _writeUint32(builder, _magicNumber);
    _writeUint32(builder, _version);

    // Write chunk info
    _writeString(builder, chunk.name);
    _writeBool(builder, chunk.isMainChunk);
    _writeUint32(builder, chunk.numRegisters);

    // Write constants
    _writeUint32(builder, chunk.constants.length);
    for (final constant in chunk.constants) {
      _writeConstant(builder, constant);
    }

    // Write instructions
    _writeUint32(builder, chunk.instructions.length);
    for (final instruction in chunk.instructions) {
      _writeInstruction(builder, instruction);
    }

    return builder.takeBytes();
  }

  /// Deserialize bytes back into a bytecode chunk
  static BytecodeChunk deserialize(Uint8List bytes) {
    final reader = _ByteReader(bytes);

    // Verify header
    final magic = reader.readUint32();
    if (magic != _magicNumber) {
      throw Exception('Invalid bytecode format');
    }

    final version = reader.readUint32();
    if (version != _version) {
      throw Exception('Unsupported bytecode version');
    }

    // Read chunk info
    final name = reader.readString();
    final isMainChunk = reader.readBool();
    final numRegisters = reader.readUint32();

    // Read constants
    final constantCount = reader.readUint32();
    final constants = <dynamic>[];
    for (var i = 0; i < constantCount; i++) {
      constants.add(reader.readConstant());
    }

    // Read instructions
    final instructionCount = reader.readUint32();
    final instructions = <Instruction>[];
    for (var i = 0; i < instructionCount; i++) {
      instructions.add(reader.readInstruction());
    }

    return BytecodeChunk(
      instructions: instructions,
      constants: constants,
      numRegisters: numRegisters,
      name: name,
      isMainChunk: isMainChunk,
    );
  }

  // Helper methods for writing values
  static void _writeUint32(BytesBuilder builder, int value) {
    builder.addByte(value & 0xFF);
    builder.addByte((value >> 8) & 0xFF);
    builder.addByte((value >> 16) & 0xFF);
    builder.addByte((value >> 24) & 0xFF);
  }

  static void _writeString(BytesBuilder builder, String value) {
    final bytes = utf8.encode(value);
    _writeUint32(builder, bytes.length);
    builder.add(bytes);
  }

  static void _writeBool(BytesBuilder builder, bool value) {
    builder.addByte(value ? 1 : 0);
  }

  static void _writeConstant(BytesBuilder builder, dynamic constant) {
    if (constant == null) {
      builder.addByte(0); // nil
    } else if (constant is bool) {
      builder.addByte(1);
      _writeBool(builder, constant);
    } else if (constant is num) {
      builder.addByte(2);
      _writeString(builder, constant.toString());
    } else if (constant is String) {
      builder.addByte(3);
      _writeString(builder, constant);
    } else if (constant is BytecodeChunk) {
      builder.addByte(4);
      builder.add(serialize(constant));
    } else {
      throw Exception('Unsupported constant type: ${constant.runtimeType}');
    }
  }

  static void _writeInstruction(BytesBuilder builder, Instruction instruction) {
    _writeUint32(builder, instruction.op.index);
    _writeUint32(builder, instruction.operands.length);
    for (final operand in instruction.operands) {
      _writeConstant(builder, operand);
    }
  }
}

/// Helper class for reading serialized bytes
class _ByteReader {
  final ByteData _data;
  int _position = 0;

  _ByteReader(Uint8List bytes) : _data = ByteData.view(bytes.buffer);

  int readUint32() {
    final value = _data.getUint32(_position, Endian.little);
    _position += 4;
    return value;
  }

  String readString() {
    final length = readUint32();
    final bytes = Uint8List.view(_data.buffer, _position, length);
    _position += length;
    return utf8.decode(bytes);
  }

  bool readBool() {
    final value = _data.getUint8(_position) != 0;
    _position += 1;
    return value;
  }

  dynamic readConstant() {
    final type = _data.getUint8(_position++);
    switch (type) {
      case 0:
        return null;
      case 1:
        return readBool();
      case 2:
        return num.parse(readString());
      case 3:
        return readString();
      case 4:
        final bytes = Uint8List.view(_data.buffer, _position);
        _position += bytes.length;
        return BytecodeSerializer.deserialize(bytes);
      default:
        throw Exception('Unknown constant type: $type');
    }
  }

  Instruction readInstruction() {
    final opcode = OpCode.values[readUint32()];
    final operandCount = readUint32();
    final operands = <dynamic>[];
    for (var i = 0; i < operandCount; i++) {
      operands.add(readConstant());
    }
    return Instruction(opcode, operands);
  }
}
