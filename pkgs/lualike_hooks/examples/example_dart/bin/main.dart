import 'package:lualike/lualike.dart';

Future<void> main() async {
  print('LuaLike Hooks Example (Dart CLI)');
  print('================================');
  print('');

  // The loader checks both build/lua/ and the CLI bundle assets.
  final loader = LuaAssetLoader();

  final bytecode = await loader.loadBytecode('hello.lua');
  if (bytecode == null) {
    print('ERROR: build/lua/hello.lua not found.');
    print('Run "dart build cli --target=bin/main.dart" first.');
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
