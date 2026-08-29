import 'package:lualike/src/environment.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/stdlib/init.dart';

/// Installs the runtime-owned state shared by the IR and bytecode wrappers.
///
/// The [Interpreter] has already initialized its own state by the time this
/// is called. The wrappers still need their runtime-local registry and root
/// environment so that their [LuaRuntime] facade remains consistent.
void initializeRuntimeBootstrap({
  required LuaRuntime runtime,
  required Interpreter interpreter,
  required Environment environment,
}) {
  environment.interpreter = runtime;
  interpreter.setCurrentEnv(environment);
  runtime.gc.register(environment);
  initializeStandardLibrary(vm: runtime);
  interpreter.fileManager.setInterpreter(runtime);
}
