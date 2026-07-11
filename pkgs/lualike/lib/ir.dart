/// Public entrypoint for the lualike IR toolset.
library;

import 'src/ir/prototype.dart';
import 'src/ir/ssa.dart';

export 'src/ir/bytecode_lowering.dart';
export 'src/ir/chunk_builder.dart';
export 'src/ir/compiler.dart';
export 'src/ir/control_flow.dart';
export 'src/ir/disassembler.dart';
export 'src/ir/instruction.dart';
export 'src/ir/opcode.dart';
export 'src/ir/peephole_pass.dart';
export 'src/ir/prototype.dart';
export 'src/ir/runtime.dart';
export 'src/ir/serialization.dart';
export 'src/ir/ssa.dart';
export 'src/ir/textual_formatter.dart';

/// Builds a simplified SSA view for a compiled IR prototype.
///
/// Trivial phis are removed and use metadata is rebuilt so the result is ready
/// for dumps, tests, and future SSA tooling.
LualikeIrSsaFunction buildLualikeIrSsaFunction(LualikeIrPrototype prototype) {
  return LualikeIrSsaFunction.fromPrototype(prototype).simplifyTrivialPhis();
}
