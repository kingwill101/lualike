import 'dart:typed_data';

import 'chunk.dart';
import 'instruction.dart';
import '../number_limits.dart';
import '../number_utils.dart';

typedef _PrototypeDebugInfo = ({
  List<int> lineInfo,
  List<LuaBytecodeAbsLineInfo> absoluteLineInfo,
  List<LuaBytecodeLocalVariableDebugInfo> localVariables,
  List<String?> upvalueNames,
});

final class LuaBytecodeParser {
  const LuaBytecodeParser();

  LuaBytecodeBinaryChunk parse(List<int> bytes) {
    final reader = _LuaBytecodeReader(bytes);
    return reader.readChunk();
  }
}

final class _LuaBytecodeReader {
  _LuaBytecodeReader(List<int> bytes)
    : _bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      _savedStrings = <String?>[null] {
    _byteData = ByteData.sublistView(_bytes);
  }

  final Uint8List _bytes;
  final List<String?> _savedStrings;
  late final ByteData _byteData;
  var _offset = 0;

  LuaBytecodeBinaryChunk readChunk() {
    final header = _readHeader();
    final rootUpvalueCount = _readByte();
    final mainPrototype = _readPrototype(header);
    if (_offset != _bytes.length) {
      throw _formatError('Trailing bytes after Lua chunk payload');
    }
    return LuaBytecodeBinaryChunk(
      header: header,
      rootUpvalueCount: rootUpvalueCount,
      mainPrototype: mainPrototype,
    );
  }

  LuaBytecodeChunkHeader _readHeader() {
    final signature = _readBytes(4);
    final version = _readByte();
    final format = _readByte();
    final luacData = _readBytes(6);
    final intSize = _readByte();
    final luacInt = _readSignedFixedInt(intSize);
    final instructionSize = _readByte();
    final luacInstruction = _readUnsignedFixedInt(instructionSize);
    final luaIntegerSize = _readByte();
    final luaIntegerSentinel = _readSignedFixedInt(luaIntegerSize);
    final luaNumberSize = _readByte();
    final luacNumber = _readFixedDouble(luaNumberSize);

    if (!_matchesBytes(signature, LuaBytecodeChunkSentinels.signature)) {
      throw _formatError('Not a Lua binary chunk');
    }
    if (version != LuaBytecodeChunkSentinels.officialVersion) {
      throw _formatError(
        'Unsupported Lua bytecode version 0x${version.toRadixString(16)}',
      );
    }
    if (format != LuaBytecodeChunkSentinels.officialFormat) {
      throw _formatError('Unsupported Lua bytecode format $format');
    }
    if (!_matchesBytes(luacData, LuaBytecodeChunkSentinels.luacData)) {
      throw _formatError('Corrupted Lua chunk header');
    }
    if (intSize != LuaBytecodeChunkSentinels.intSize ||
        instructionSize != LuaBytecodeChunkSentinels.instructionSize ||
        luaIntegerSize != LuaBytecodeChunkSentinels.luaIntegerSize ||
        luaNumberSize != LuaBytecodeChunkSentinels.luaNumberSize ||
        luacInt != LuaBytecodeChunkSentinels.luacInt ||
        luaIntegerSentinel != LuaBytecodeChunkSentinels.luacInt ||
        luacInstruction != LuaBytecodeChunkSentinels.luacInstruction ||
        luacNumber != LuaBytecodeChunkSentinels.luacNumber) {
      throw _formatError('Unsupported numeric layout in Lua chunk header');
    }
    return LuaBytecodeChunkHeader(
      signature: signature,
      version: version,
      format: format,
      luacData: luacData,
      intSize: intSize,
      instructionSize: instructionSize,
      luaIntegerSize: luaIntegerSize,
      luaNumberSize: luaNumberSize,
      luacInt: luacInt,
      luacInstruction: luacInstruction,
      luacNumber: luacNumber,
    );
  }

  LuaBytecodePrototype _readPrototype(LuaBytecodeChunkHeader header) {
    final lineDefined = _readVarint();
    final lastLineDefined = _readVarint();
    final parameterCount = _readByte();
    final flags = _readByte();
    final maxStackSize = _readByte();

    final code = _readCode(header.instructionSize);
    final constants = _readConstants(header);
    final upvalues = _readUpvalues();
    final prototypes = _readPrototypes(header);
    final source = _readString();
    final debugInfo = _readDebugInfo(
      intSize: header.intSize,
      upvalueCount: upvalues.length,
    );

    final namedUpvalues = <LuaBytecodeUpvalueDescriptor>[
      for (var index = 0; index < upvalues.length; index++)
        LuaBytecodeUpvalueDescriptor(
          inStack: upvalues[index].inStack,
          index: upvalues[index].index,
          kind: upvalues[index].kind,
          name: index < debugInfo.upvalueNames.length
              ? debugInfo.upvalueNames[index]
              : upvalues[index].name,
        ),
    ];

    return LuaBytecodePrototype(
      lineDefined: lineDefined,
      lastLineDefined: lastLineDefined,
      parameterCount: parameterCount,
      flags: flags,
      maxStackSize: maxStackSize,
      code: code,
      constants: constants,
      upvalues: namedUpvalues,
      prototypes: prototypes,
      source: source,
      lineInfo: debugInfo.lineInfo,
      absoluteLineInfo: debugInfo.absoluteLineInfo,
      localVariables: debugInfo.localVariables,
      upvalueNames: debugInfo.upvalueNames,
    );
  }

  List<LuaBytecodeInstructionWord> _readCode(int instructionSize) {
    final instructionCount = _readVarint();
    _alignTo(instructionSize);
    return <LuaBytecodeInstructionWord>[
      for (var index = 0; index < instructionCount; index++)
        LuaBytecodeInstructionWord(_readUnsignedFixedInt(instructionSize)),
    ];
  }

  List<LuaBytecodeConstant> _readConstants(LuaBytecodeChunkHeader header) {
    final constantCount = _readVarint();
    return <LuaBytecodeConstant>[
      for (var index = 0; index < constantCount; index++) _readConstant(header),
    ];
  }

  LuaBytecodeConstant _readConstant(LuaBytecodeChunkHeader header) {
    final tag = _readByte();
    return switch (tag) {
      0x00 => const LuaBytecodeNilConstant(),
      0x01 => const LuaBytecodeBooleanConstant(false),
      0x11 => const LuaBytecodeBooleanConstant(true),
      0x13 => LuaBytecodeFloatConstant(_readFixedDouble(header.luaNumberSize)),
      0x03 => LuaBytecodeIntegerConstant(_readLuaInteger()),
      0x04 => LuaBytecodeStringConstant(
        _readString() ??
            (throw _formatError('Short string constant cannot be null')),
        isLong: false,
      ),
      0x14 => LuaBytecodeStringConstant(
        _readString() ??
            (throw _formatError('Long string constant cannot be null')),
        isLong: true,
      ),
      _ => throw _formatError(
        'Unknown constant tag 0x${tag.toRadixString(16)}',
      ),
    };
  }

  List<LuaBytecodeUpvalueDescriptor> _readUpvalues() {
    final upvalueCount = _readVarint();
    return <LuaBytecodeUpvalueDescriptor>[
      for (var index = 0; index < upvalueCount; index++)
        LuaBytecodeUpvalueDescriptor(
          inStack: _readByte() != 0,
          index: _readByte(),
          kind: LuaBytecodeUpvalueKind.fromValue(_readByte()),
        ),
    ];
  }

  List<LuaBytecodePrototype> _readPrototypes(LuaBytecodeChunkHeader header) {
    final prototypeCount = _readVarint();
    return <LuaBytecodePrototype>[
      for (var index = 0; index < prototypeCount; index++)
        _readPrototype(header),
    ];
  }

  _PrototypeDebugInfo _readDebugInfo({
    required int intSize,
    required int upvalueCount,
  }) {
    final lineInfoCount = _readVarint();
    final lineInfo = <int>[
      for (var index = 0; index < lineInfoCount; index++)
        _toSignedByte(_readByte()),
    ];

    final absoluteLineInfoCount = _readVarint();
    final absoluteLineInfo = <LuaBytecodeAbsLineInfo>[];
    if (absoluteLineInfoCount > 0) {
      _alignTo(intSize);
      for (var index = 0; index < absoluteLineInfoCount; index++) {
        absoluteLineInfo.add(
          LuaBytecodeAbsLineInfo(
            pc: _readSignedFixedInt(intSize),
            line: _readSignedFixedInt(intSize),
          ),
        );
      }
    }

    final localVariableCount = _readVarint();
    final localVariables = <LuaBytecodeLocalVariableDebugInfo>[
      for (var index = 0; index < localVariableCount; index++)
        LuaBytecodeLocalVariableDebugInfo(
          name: _readString(),
          startPc: _readVarint(),
          endPc: _readVarint(),
          register: null,
        ),
    ];

    final upvalueNameCount = _readVarint();
    final actualUpvalueNameCount = upvalueNameCount == 0 ? 0 : upvalueCount;
    final upvalueNames = <String?>[
      for (var index = 0; index < actualUpvalueNameCount; index++)
        _readString(),
    ];

    return (
      lineInfo: lineInfo,
      absoluteLineInfo: absoluteLineInfo,
      localVariables: localVariables,
      upvalueNames: upvalueNames,
    );
  }

  String? _readString() {
    final size = _readVarint();
    if (size == 0) {
      final reuseIndex = _readVarint();
      if (reuseIndex == 0) {
        return null;
      }
      if (reuseIndex >= _savedStrings.length) {
        throw _formatError('Invalid reused string index $reuseIndex');
      }
      return _savedStrings[reuseIndex];
    }

    final rawBytes = _readBytes(size);
    if (rawBytes.isEmpty || rawBytes.last != 0) {
      throw _formatError('Lua string payload is missing trailing NUL');
    }
    final value = String.fromCharCodes(rawBytes.take(size - 1));
    _savedStrings.add(value);
    return value;
  }

  int _readLuaInteger() {
    final encoded = _readBigVarint();
    final integer = encoded.isOdd
        ? -((encoded >> 1) + BigInt.one)
        : (encoded >> 1);
    if (integer < BigInt.from(NumberLimits.minInteger) ||
        integer > BigInt.from(NumberLimits.maxInteger)) {
      throw _formatError(
        'Lua integer constant exceeds signed ${NumberLimits.sizeInBits}-bit range',
      );
    }
    return NumberUtils.toInt(integer);
  }

  int _readVarint() {
    return _readBigVarint().toInt();
  }

  BigInt _readBigVarint() {
    var value = BigInt.zero;
    while (true) {
      final byte = _readByte();
      value = (value << 7) | BigInt.from(byte & 0x7f);
      if ((byte & 0x80) == 0) {
        return value;
      }
    }
  }

  int _readByte() {
    _ensureAvailable(1);
    return _bytes[_offset++];
  }

  List<int> _readBytes(int count) {
    _ensureAvailable(count);
    final bytes = _bytes.sublist(_offset, _offset + count);
    _offset += count;
    return bytes;
  }

  void _alignTo(int alignment) {
    final remainder = _offset % alignment;
    if (remainder == 0) {
      return;
    }
    final padding = alignment - remainder;
    _ensureAvailable(padding);
    _offset += padding;
  }

  int _readUnsignedFixedInt(int size) {
    _ensureAvailable(size);
    final value = switch (size) {
      1 => _byteData.getUint8(_advance(size) - size),
      2 => _byteData.getUint16(_advance(size) - size, Endian.little),
      4 => _byteData.getUint32(_advance(size) - size, Endian.little),
      8 => _byteData.getUint64(_advance(size) - size, Endian.little),
      _ => _readArbitraryFixedInt(size, signed: false),
    };
    return value;
  }

  int _readSignedFixedInt(int size) {
    _ensureAvailable(size);
    final value = switch (size) {
      1 => _byteData.getInt8(_advance(size) - size),
      2 => _byteData.getInt16(_advance(size) - size, Endian.little),
      4 => _byteData.getInt32(_advance(size) - size, Endian.little),
      8 => _byteData.getInt64(_advance(size) - size, Endian.little),
      _ => _readArbitraryFixedInt(size, signed: true),
    };
    return value;
  }

  double _readFixedDouble(int size) {
    _ensureAvailable(size);
    return switch (size) {
      4 => _byteData.getFloat32(_advance(size) - size, Endian.little),
      8 => _byteData.getFloat64(_advance(size) - size, Endian.little),
      _ => throw _formatError('Unsupported Lua number size $size'),
    };
  }

  int _readArbitraryFixedInt(int size, {required bool signed}) {
    final bytes = _readBytes(size);
    var value = 0;
    for (var index = 0; index < bytes.length; index++) {
      value |= bytes[index] << (index * 8);
    }
    if (!signed) {
      return value;
    }

    final signBit = 1 << ((size * 8) - 1);
    if ((value & signBit) == 0) {
      return value;
    }
    final mask = 1 << (size * 8);
    return value - mask;
  }

  int _advance(int count) {
    _offset += count;
    return _offset;
  }

  int _toSignedByte(int value) => value >= 0x80 ? value - 0x100 : value;

  void _ensureAvailable(int count) {
    if (_offset + count > _bytes.length) {
      throw _formatError('Unexpected end of Lua chunk');
    }
  }

  FormatException _formatError(String message) =>
      FormatException('$message at byte offset $_offset');

  bool _matchesBytes(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}
