import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/llvm_lowering.dart';
import 'package:lualike/src/ir/ssa.dart';
import 'package:lualike/src/ir/ssa_type_analysis.dart';
import 'package:lualike/src/parse.dart';

void main() {
  final program = parse('local x = 1 + 2; return x');
  final chunk = LualikeIrCompiler().compile(program);
  final ssa = LualikeIrSsaFunction.fromPrototype(chunk.mainPrototype).simplifyTrivialPhis();
  final ta = analyzeLualikeIrSsaTypes(chunk.mainPrototype, ssa);
  final llvm = LualikeIrToLlvm(prototype: chunk.mainPrototype, ssaFunction: ssa, typeAnalysis: ta);
  print(llvm.generateModule());
}
