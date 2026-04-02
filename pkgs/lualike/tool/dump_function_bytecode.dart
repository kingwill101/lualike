import 'dart:io';

import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/lua_bytecode/emitter.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/dump_function_bytecode.dart <source.lua> [name-substring]',
    );
    exit(64);
  }

  final sourcePath = args[0];
  final nameFilter = args.length > 1 ? args[1] : null;
  final source = File(sourcePath).readAsStringSync();
  final emitted = const LuaBytecodeEmitter().compileSource(
    source,
    chunkName: sourcePath,
    sourceName: sourcePath,
  );
  final disassembler = const LuaBytecodeDisassembler();
  final chunk = disassembler.disassemble(emitted.chunk);
  _dumpPrototype(
    chunk.mainPrototype,
    nameFilter: nameFilter,
    depth: 0,
  );
}

void _dumpPrototype(
  LuaBytecodePrototypeDisassembly prototype, {
  required String? nameFilter,
  required int depth,
}) {
  final indent = '  ' * depth;
  final header = [
    prototype.label,
    'params=${prototype.prototype.parameterCount}',
    'vararg=${prototype.prototype.isVararg}',
    'stack=${prototype.prototype.maxStackSize}',
    'linedefined=${prototype.prototype.lineDefined}',
    'lastline=${prototype.prototype.lastLineDefined}',
  ].join(' ');

  final matches = nameFilter == null ||
      prototype.label.contains(nameFilter) ||
      prototype.instructions.any(
        (instruction) =>
            instruction.lineNumber != null &&
            instruction.lineNumber.toString().contains(nameFilter),
      );

  if (matches) {
    stdout.writeln('$indent$header');
    for (final instruction in prototype.instructions) {
      stdout.writeln(
        '$indent  ${instruction.pc.toString().padLeft(4)} '
        'L${instruction.lineNumber?.toString() ?? "-"} '
        '${instruction.opcode.name.padRight(10)} ${instruction.operands}',
      );
    }
    stdout.writeln('');
  }

  for (final child in prototype.children) {
    _dumpPrototype(
      child,
      nameFilter: nameFilter,
      depth: depth + 1,
    );
  }
}
