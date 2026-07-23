import 'package:lualike/lualike.dart';

void main() async {
  print('LuaLike Hooks Example (Dart CLI)');
  print('================================');
  print('');

  // The hook writes compiled bytecode to build/lua/ under the package root.
  final loader = LuaAssetLoader();

  final bytecode = await loader.loadBytecode('hello.lua');
  if (bytecode == null) {
    print('ERROR: build/lua/hello.lua not found.');
    print('Run "dart run" to trigger the build hook.');
    return;
  }

  print('Loaded compiled bytecode: ${bytecode.length} bytes');
  print('');

  print('Executing compiled bytecode...');
  final runtime = LuaBytecodeRuntime();
  final chunk = await runtime.loadBytecode(bytecode, moduleName: 'hello.lua');
  final result = await runtime.callFunction(chunk, const <Object?>[]);
  print('');
  print('Result: ${result.unwrap()}');
}
