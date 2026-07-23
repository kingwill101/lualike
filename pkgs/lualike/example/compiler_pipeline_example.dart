/// Example: using the multi-pass compiler pipeline from Dart.
///
/// Shows how to bundle dependencies, fold constants, compile to bytecode,
/// and load the result into the Lua 5.5 VM — all from Dart code.
library;


import 'package:lualike/src/compile/compiler_pass.dart';
import 'package:lualike/src/compile/constant_folding_pass.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/compile/simplify_pass.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/parse.dart';

Future<void> main(List<String> args) async {
  final script = args.isNotEmpty ? args.first : _exampleSource;
  print('=== Compiler Pipeline Demo ===\n');

  // ---- Step 1: Parse ----
  print('1. Parsing source...');
  final program = parse(script, url: 'demo.lua');

  // ---- Step 2: Run passes manually ----
  print('2. Running compiler passes...');
  final context = CompilerContext(program);

  final passes = <CompilerPass>[
    ConstantFoldingPass(),
    ASTSimplifier(),
  ];

  for (final pass in passes) {
    print('   -> ${pass.name}');
    context.program = pass.run(context.program, context);
  }

  // ---- Step 3: Compile to bytecode ----
  print('3. Compiling to Lua 5.5 bytecode...');
  final pipeline = CompilePipeline(
    config: const CompilePipelineConfig(
      enableConstantFolding: true,
      target: CompileBackend.luaBytecode,
    ),
  );
  final artifact = pipeline.compile(program);
  final luaArtifact = artifact as LuaBytecodeArtifact;

  print('   -> ${luaArtifact.serializedBytes.length} bytes');
  print('   -> ${luaArtifact.chunk.mainPrototype.code.length} instructions');

  // ---- Step 4: Load into runtime ----
  print('4. Loading bytecode into Lua VM...');
  final runtime = LuaBytecodeRuntime();
  final chunk = await runtime.loadBytecode(
    luaArtifact.serializedBytes,
    moduleName: 'demo',
  );

  // ---- Step 5: Run ----
  print('5. Running compiled bytecode:\n');
  await runtime.callFunction(chunk, []);

  // ---- Bonus: Compare with/without peephole ----
  print('\n6. Peephole optimization comparison:');
  final withPeephole = CompilePipeline(
    config: const CompilePipelineConfig(
      enableConstantFolding: true,
      enablePeephole: true,
      target: CompileBackend.lualikeIR,
    ),
  ).compileSource(script) as LualikeIrArtifact;

  final withoutPeephole = CompilePipeline(
    config: const CompilePipelineConfig(
      enableConstantFolding: true,
      enablePeephole: false,
      target: CompileBackend.lualikeIR,
    ),
  ).compileSource(script) as LualikeIrArtifact;

  print('   Without peephole: ${withoutPeephole.chunk.mainPrototype.instructions.length} instr');
  print('   With peephole:    ${withPeephole.chunk.mainPrototype.instructions.length} instr');
}

const _exampleSource = '''
local function add(a, b) return a + b end
local function mul(a, b) return a * b end
local result = add(mul(2, 3), mul(4, 5))
print("add(mul(2,3), mul(4,5)) =", result)

local TAU = 2 * math.pi
local HALF_W = 1920 / 2
print("TAU =", TAU)
print("HALF_W =", HALF_W)

if true then
    print("dead branch eliminated")
else
    print("this is never seen")
end
''';
