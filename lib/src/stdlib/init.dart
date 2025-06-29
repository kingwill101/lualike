import 'package:lualike/src/bytecode/vm.dart' show BytecodeVM;
import 'package:lualike/src/interpreter/interpreter.dart' show Interpreter;
import '../environment.dart';
import '../io/lua_file.dart';
import '../value.dart' show Value;
import 'lib_base.dart';
import 'lib_string.dart';
import 'lib_table.dart';
import 'lib_math.dart';
import 'lib_io.dart';
import 'lib_os.dart';
import 'lib_debug.dart';
import 'lib_utf8.dart';
import 'lib_package.dart';
import 'metatables.dart';
import 'lib_dart_string.dart';
import 'lib_convert.dart';
import 'lib_crypto.dart';
// import 'lib_convert.dart';

// Define a function signature for the library definition callback
typedef LibraryDefinitionCallback =
    void Function({
      required Environment env,
      Interpreter? astVm,
      BytecodeVM? bytecodeVm,
    });

/// Helper function to define a standard library
void defineLibrary(
  LibraryDefinitionCallback definitionCallback, {
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  definitionCallback(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
}

/// Initialize all standard libraries for both VMs (AST and Bytecode)
void initializeStandardLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  // Define the package library first, as other libraries may depend on it
  definePackageLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);

  // Define the base library (which includes require)
  defineBaseLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineDebugLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);

  MetaTable.initialize(astVm!);
  defineStringLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineTableLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineMathLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineIOLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineOSLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineUTF8Library(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineDartStringLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineConvertLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineCryptoLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  // defineConvertLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  // Define other standard libraries
  final packageTable = env.get("package");
  final preloadTable = packageTable?["preload"];

  if (preloadTable != null) {
    // Register standard libraries in package.preload
    preloadTable["string"] = Value((List<Object?> args) {
      final stringLib = <String, dynamic>{};
      StringLib.functions.forEach((key, value) {
        stringLib[key] = value;
      });
      return Value(stringLib, metatable: StringLib.stringClass.metamethods);
    });

    preloadTable["table"] = Value((List<Object?> args) {
      final tableLib = <String, dynamic>{};
      TableLib.functions.forEach((key, value) {
        tableLib[key] = value;
      });
      return Value(tableLib, metatable: TableLib.tableClass.metamethods);
    });

    preloadTable["math"] = Value((List<Object?> args) {
      return Value(MathLib.functions);
    });

    preloadTable["io"] = Value((List<Object?> args) {
      final ioLib = <String, dynamic>{};
      IOLib.functions.forEach((key, value) {
        ioLib[key] = value;
      });

      // Add standard streams
      ioLib["stdin"] = Value(
        LuaFile(IOLib.stdinDevice),
        metatable: IOLib.fileClass.metamethods,
      );
      ioLib["stdout"] = Value(
        LuaFile(IOLib.stdoutDevice),
        metatable: IOLib.fileClass.metamethods,
      );
      ioLib["stderr"] = Value(
        LuaFile(IOLib.stderrDevice),
        metatable: IOLib.fileClass.metamethods,
      );

      return Value(ioLib);
    });

    preloadTable["os"] = Value((List<Object?> args) {
      final osLib = <String, dynamic>{};
      OSLibrary.functions.forEach((key, value) {
        osLib[key] = value;
      });
      return Value(osLib);
    });

    preloadTable["debug"] = Value((List<Object?> args) {
      final debugLib = <String, dynamic>{};
      DebugLib.functions.forEach((key, value) {
        debugLib[key] = value;
      });
      return Value(debugLib);
    });

    preloadTable["utf8"] = Value((List<Object?> args) {
      return Value(UTF8Lib.functions, metatable: UTF8Lib.utf8Class.metamethods);
    });
  }
}
