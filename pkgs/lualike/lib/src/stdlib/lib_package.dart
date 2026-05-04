import 'package:lualike/lualike.dart';

import 'package:lualike/src/runtime/lua_results.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/utils/file_system_utils.dart';
import 'package:lualike/src/utils/platform_utils.dart' as platform;
import 'package:path/path.dart' as path_lib;
import 'library.dart';

Object? _rawPackageValue(Object? value) => value is Value ? value.raw : value;

bool _isNilPackageValue(Object? value) => _rawPackageValue(value) == null;

String _packageString(Object? value) => _rawPackageValue(value).toString();

class PackageLib {
  static const _defaultPath = "?.lua;?/?;?/init";
  static const _defaultCPath = "?.so";

  final LuaRuntime vm;
  final FileManager fileManager;

  PackageLib(this.vm) : fileManager = vm.fileManager {
    packageClass = ValueClass.create({
      "__index": (List<Object?> args) {
        final table = args[0] as Value;
        final key = args[1] as Value;
        final rawKey = _rawPackageValue(key);
        if (rawKey == "path") {
          // Default package path
          return vm.constantDartStringValue(_defaultPath);
        }
        if (rawKey == "cpath") {
          // Default C module path
          return vm.constantDartStringValue(_defaultCPath);
        }

        final rawTable = _rawPackageValue(table);
        if (rawTable is Map) {
          final map = rawTable;
          if (map.containsKey(rawKey)) {
            return map[rawKey];
          }
        }
        return vm.constantPrimitiveValue(null);
      },
    });
  }

  late final ValueClass packageClass;

  Map<String, dynamic> createFunctions() {
    return {
      'loadlib': _LoadLib(vm),
      'searchpath': _SearchPath(fileManager, vm),
      'preload': ValueClass.table({}), // Table for preloaded modules
      'loaded': ValueClass.table({}), // Table for loaded modules
      'path': vm.constantDartStringValue(_defaultPath),
      'cpath': vm.constantDartStringValue(_defaultCPath),
      'config': vm.constantDartStringValue(_getConfig()),
      'searchers': Value(
        _createDefaultSearchers(),
        interpreter: vm,
      ), // Populate with default searchers
    };
  }

  static String _getConfig() {
    final isWindowsPlatform = platform.isWindows;
    return [
      isWindowsPlatform ? '\\' : '/', // Directory separator
      ';', // Path separator
      '?', // Template marker
      isWindowsPlatform ? '!' : '', // Executable directory marker
      '-', // Native module ignore mark
    ].join('\n');
  }

  List<Value> _createDefaultSearchers() {
    return [
      // 1. Package preload searcher
      Value((List<Object?> args) {
        final name = _packageString(args[0]);
        final packageTable = _rawPackageValue(vm.globals.get("package"));
        final preload = packageTable is Map
            ? _rawPackageValue(packageTable["preload"])
            : null;
        if (preload is Map && preload.containsKey(name)) {
          Logger.debugLazy(
            () => "Preload searcher found module: $name",
            category: 'Package',
          );
          return [preload[name], vm.constantDartStringValue("preload:$name")];
        }
        return vm.constantDartStringValue("no field package.preload['$name']");
      }, interpreter: vm),

      // 2. Lua module loader
      Value(_LuaLoader(fileManager, vm), interpreter: vm),

      // 3. C module loader (simulated for Dart)
      Value((List<Object?> args) {
        final name = _packageString(args[0]);
        return vm.constantDartStringValue(
          "no C module loader implemented for '$name'",
        );
      }, interpreter: vm),

      // 4. All-in-one loader
      Value((List<Object?> args) {
        final name = _packageString(args[0]);
        return vm.constantDartStringValue(
          "no all-in-one loader implemented for '$name'",
        );
      }, interpreter: vm),
    ];
  }
}

class _LoadLib extends BuiltinFunction {
  _LoadLib(super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError("loadlib requires library path and function name");
    }

    final libpath = _packageString(args[0]);
    final funcname = _packageString(args[1]);

    // We don't actually load C libraries, just simulate the interface
    if (funcname == '*') {
      // Check whether the library exists
      if (!await fileExists(libpath)) {
        // In Lua, a missing library returns nil plus an error message and the
        // string 'absent'.
        return [
          primitiveValue(null),
          dartStringValue('cannot load $libpath'),
          dartStringValue('absent'),
        ];
      }
      // Library found; return a true value like Lua does
      return primitiveValue(true);
    }

    // For specific symbols, check if the library exists first
    if (!await fileExists(libpath)) {
      return [
        primitiveValue(null),
        dartStringValue('cannot load $libpath'),
        dartStringValue('absent'),
      ];
    }

    // Library exists but symbol loading is not supported
    return [
      primitiveValue(null),
      dartStringValue('dynamic libraries not supported'),
      dartStringValue('init'),
    ];
  }
}

class _SearchPath extends BuiltinFunction {
  final FileManager fileManager;

  _SearchPath(this.fileManager, super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError('searchpath requires name and path');
    }

    final name = _packageString(args[0]);
    final searchPath = _packageString(args[1]);
    final sep = args.length > 2 ? _packageString(args[2]) : '.';
    final rep = args.length > 3 ? _packageString(args[3]) : path_lib.separator;

    // Avoid Dart's replaceAll behavior with empty pattern
    final replacedName = sep.isEmpty ? name : name.replaceAll(sep, rep);
    final templates = searchPath.split(';');
    final tried = <String>[];

    for (final template in templates) {
      if (template.isEmpty) continue;
      final filename = template.replaceAll('?', replacedName);
      tried.add(filename);
      if (await fileExists(filename)) {
        return dartStringValue(filename);
      }
    }

    final err = tried.map((f) => "\n\tno file '$f'").join();
    return [primitiveValue(null), dartStringValue(err)];
  }
}

class _LuaLoader extends BuiltinFunction {
  final FileManager fileManager;

  _LuaLoader(this.fileManager, super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    final name = _packageString(args[0]);
    Logger.debugLazy(
      () => "_LuaLoader called for module: $name",
      category: 'Package',
    );

    // Special case: If the current script is in a special directory like .lua-tests,
    // and the module name doesn't contain a path separator, try to load it from the same directory first
    String? modulePath;
    if (!name.contains('.') &&
        !name.contains('/') &&
        interpreter!.currentScriptPath != null) {
      final scriptDir = path_lib.dirname(interpreter!.currentScriptPath!);
      final directPath = path_lib.join(scriptDir, '$name.lua');
      Logger.debugLazy(
        () => "Trying direct path in script directory: $directPath",
        category: 'Package',
      );

      if (await fileExists(directPath)) {
        Logger.debugLazy(
          () => "Module found in script directory: $directPath",
          category: 'Package',
        );
        modulePath = directPath;
      }
    }

    // If not found in the script directory, use the regular resolution
    if (modulePath == null) {
      // Try to find the module file
      Logger.debugLazy(
        () => "Attempting to resolve module path for: $name",
        category: 'Package',
      );
      modulePath = await fileManager.resolveModulePath(name);
    }

    Logger.debugLazy(
      () => "Module path resolved to: $modulePath",
      category: 'Package',
    );

    if (modulePath == null || modulePath.isEmpty) {
      return dartStringValue(_moduleNotFoundDiagnostic(interpreter!, name));
    }

    // Return a loader function that will load and execute the module
    return [
      Value((List<Object?> args) async {
        final name = _packageString(args[0]);
        final modulePath = _packageString(args[1]);
        Logger.debugLazy(
          () =>
              "Loader function called for module: $name with path: $modulePath",
          category: 'Package',
        );

        try {
          // Load the source code
          Logger.debugLazy(
            () => "Attempting to load source from: $modulePath",
            category: 'Package',
          );
          final source = await fileManager.loadSource(modulePath);
          if (source == null) {
            Logger.debugLazy(
              () => "Source not found for module: $name at path: $modulePath",
              category: 'Package',
            );
            throw LuaError("cannot load module '$name': file not found");
          }

          Logger.debugLazy(
            () => "Source loaded successfully, length: ${source.length}",
            category: 'Package',
          );

          try {
            // Parse the module code
            Logger.debugLazy(() => "Parsing module code", category: 'Package');
            final ast = parse(source, url: modulePath);
            Logger.debugLazy(
              () => "Module code parsed successfully",
              category: 'Package',
            );

            // Create a new environment for the module
            Logger.debugLazy(
              () => "Creating new environment for module",
              category: 'Package',
            );
            final moduleEnv = Environment(
              parent: interpreter!.globals.root,
              interpreter: interpreter,
            );

            // Pass arguments like Lua's loader function (...)
            moduleEnv.declare(
              '...',
              LuaResults([
                interpreter!.constantDartStringValue(name),
                interpreter!.constantDartStringValue(modulePath),
              ]),
            );

            // Get the absolute path of the module
            String absoluteModulePath;
            if (path_lib.isAbsolute(modulePath)) {
              absoluteModulePath = modulePath;
            } else {
              // Use the FileManager to resolve the absolute path instead of duplicating logic
              absoluteModulePath = fileManager.resolveAbsoluteModulePath(
                modulePath,
              );
              Logger.debugLazy(
                () =>
                    "Resolved module path to absolute path: $absoluteModulePath",
                category: 'Package',
              );
            }

            // Set the current script path to the module path
            Logger.debugLazy(
              () => "Setting script path to: $absoluteModulePath",
              category: 'Package',
            );
            interpreter!.currentScriptPath = absoluteModulePath;

            // Store the script path in the module environment (normalized)
            final normalizedModulePath = path_lib.url.joinAll(
              path_lib.split(path_lib.normalize(absoluteModulePath)),
            );
            final moduleDir = path_lib.dirname(absoluteModulePath);
            final normalizedModuleDir = path_lib.url.joinAll(
              path_lib.split(path_lib.normalize(moduleDir)),
            );
            moduleEnv.declare(
              '_SCRIPT_PATH',
              interpreter!.constantDartStringValue(normalizedModulePath),
            );
            moduleEnv.declare(
              '_SCRIPT_DIR',
              interpreter!.constantDartStringValue(normalizedModuleDir),
            );

            // Also set _MODULE_NAME global
            moduleEnv.declare(
              '_MODULE_NAME',
              interpreter!.constantDartStringValue(name),
            );

            Logger.debugLazy(
              () =>
                  "Module environment set up with _SCRIPT_PATH=$absoluteModulePath, _SCRIPT_DIR=$moduleDir, _MODULE_NAME=$name",
              category: 'Package',
            );
            Logger.debugLazy(
              () =>
                  "Module environment set up with _SCRIPT_PATH(norm)=$normalizedModulePath, _SCRIPT_DIR(norm)=$normalizedModuleDir | originals: path=$absoluteModulePath, dir=$moduleDir, _MODULE_NAME=$name",
              category: 'Package',
            );

            // Set the globals in the module environment
            interpreter!.globals.define(
              '_SCRIPT_PATH',
              interpreter!.constantDartStringValue(normalizedModulePath),
            );
            interpreter!.globals.define(
              '_SCRIPT_DIR',
              interpreter!.constantDartStringValue(normalizedModuleDir),
            );
            interpreter!.globals.define(
              '_MODULE_NAME',
              interpreter!.constantDartStringValue(name),
            );

            Logger.debugLazy(
              () =>
                  "Global environment updated with _SCRIPT_PATH=$absoluteModulePath, _SCRIPT_DIR=$moduleDir, _MODULE_NAME=$name",
              category: 'Package',
            );

            Object? result;
            final runtime = interpreter!;
            final previousEnv = runtime.getCurrentEnv();
            final previousScriptPath = runtime.currentScriptPath;
            try {
              // Run the module code
              Logger.debugLazy(
                () => "Running module code",
                category: 'Package',
              );
              runtime.setCurrentEnv(moduleEnv);
              runtime.currentScriptPath = absoluteModulePath;
              result = await runtime.runAst(ast.statements);
              Logger.debugLazy(
                () => "Module code executed successfully",
                category: 'Package',
              );
              // If no explicit return, the result is nil.
              result ??= runtime.constantPrimitiveValue(null);
            } on ReturnException catch (e) {
              // Handle explicit return from module
              Logger.debugLazy(
                () => "Module returned a value",
                category: 'Package',
              );
              result = e.value;
            } finally {
              runtime.setCurrentEnv(previousEnv);
              runtime.currentScriptPath = previousScriptPath;
            }

            // If the module didn't return anything, return an empty table
            if (_isNilPackageValue(result)) {
              Logger.debugLazy(
                () => "Module returned nil, defaulting to empty table",
                category: 'Package',
              );
              result = valueFromLuaSlot(runtime, <dynamic, dynamic>{});
            } else {
              Logger.debugLazy(
                () => "Module returned: ${result.runtimeType}",
                category: 'Package',
              );
            }

            // Store the result in package.loaded immediately to ensure it's available
            // for any recursive requires within the module
            Logger.debugLazy(
              () => "Storing module in package.loaded",
              category: 'Package',
            );
            final packageVal = interpreter!.globals.get("package");
            final packageTable = _rawPackageValue(packageVal);
            if (packageTable is Map) {
              if (packageTable.containsKey("loaded")) {
                final loaded = _rawPackageValue(packageTable["loaded"]);
                if (loaded is Map) {
                  loaded[name] = result;
                  Logger.debugLazy(
                    () => "Module '$name' stored in package.loaded",
                    category: 'Package',
                  );
                  Logger.debugLazy(
                    () => "Module '$name' stored in package.loaded during load",
                    category: 'Package',
                  );
                }
              }
            }

            Logger.debugLazy(
              () => "Module loading completed successfully",
              category: 'Package',
            );
            return result;
          } catch (e) {
            Logger.error(
              "Error parsing/executing module: $e",
              category: 'Package',
            );
            throw LuaError("error loading module '$name': $e");
          }
        } catch (e) {
          Logger.error("Error loading module source: $e", category: 'Package');
          throw LuaError("error loading module '$name': $e");
        }
      }, interpreter: interpreter),
      dartStringValue(path_lib.normalize(modulePath)),
    ];
  }
}

String _moduleNotFoundDiagnostic(LuaRuntime runtime, String moduleName) {
  final packageValue = runtime.globals.get('package');
  var packagePath = '';
  final packageTable = _rawPackageValue(packageValue);
  if (packageTable is Map) {
    final rawPath = _rawPackageValue(packageTable['path']);
    if (rawPath is String || rawPath is LuaString) {
      packagePath = rawPath.toString();
    }
  }

  final templates = packagePath.isEmpty
      ? const <String>['?.lua', '?/?', '?/init']
      : packagePath.split(';');
  final modulePath = moduleName.replaceAll('.', path_lib.separator);
  final diagnostics = templates
      .where((template) => template.isNotEmpty)
      .map(
        (template) => "\n\tno file '${template.replaceAll('?', modulePath)}'",
      )
      .join();
  return diagnostics.isEmpty ? "\n\tno file '$moduleName'" : diagnostics;
}

/// Package library implementation using the new Library system
class PackageLibrary extends Library {
  @override
  String get name => ""; // Empty name means base library (no namespace)

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    final packageLib = PackageLib(context.interpreter!);

    // Create package table with metamethods
    final packageTable = ValueClass.table();
    packageLib.createFunctions().forEach((key, value) {
      packageTable[key] = value;
    });

    // Define package table globally
    context.define(
      'package',
      Value(
        packageTable,
        metatable: packageLib.packageClass.metamethods,
        interpreter: context.interpreter,
      ),
    );
  }
}

void definePackageLibrary({required Environment env, LuaRuntime? vm}) {
  final packageLib = PackageLib(vm ?? Interpreter());

  // Create package table with metamethods
  final packageTable = ValueClass.table();
  packageLib.createFunctions().forEach((key, value) {
    packageTable[key] = value;
  });

  // Add default searchers
  final searchers = <Value>[
    // 1. Package preload searcher
    Value((List<Object?> args) {
      final name = _packageString(args[0]);
      final preload = packageTable['preload'];
      if (preload.containsKey(name)) {
        return [
          preload[name],
          packageLib.vm.constantDartStringValue("preload"),
        ];
      }
      return [
        packageLib.vm.constantPrimitiveValue(null),
        packageLib.vm.constantDartStringValue("not found in preload"),
      ];
    }, interpreter: packageLib.vm),

    // 2. Lua/Dart module loader
    Value((List<Object?> args) {
      final name = _packageString(args[0]);
      final path = packageTable['path'] as Value;

      try {
        final searcher = _SearchPath(packageLib.fileManager, packageLib.vm);
        final filename = searcher.call([
          packageLib.vm.constantDartStringValue(name),
          path,
        ]);

        if (filename is Value && !_isNilPackageValue(filename)) {
          final modulePath = _rawPackageValue(filename).toString();
          // Return loader function
          return [
            Value((loaderArgs) async {
              // Module loading will be handled by require
              final source = await packageLib.fileManager.loadSource(
                modulePath,
              );
              if (source == null) {
                throw LuaError("cannot load module '$name': file not found");
              }
              return packageLib.vm.constantDartStringValue(source);
            }, interpreter: packageLib.vm),
            packageLib.vm.constantDartStringValue(
              path_lib.normalize(modulePath),
            ),
          ];
        }
      } catch (e) {
        return [
          packageLib.vm.constantPrimitiveValue(null),
          packageLib.vm.constantDartStringValue(e.toString()),
        ];
      }
      return [
        packageLib.vm.constantPrimitiveValue(null),
        packageLib.vm.constantDartStringValue("module '$name' not found"),
      ];
    }, interpreter: packageLib.vm),

    // // 3. Dart native module loader
    // Value((List<Object?> args) {
    //   final name = (args[0] as Value).raw.toString();

    //   try {
    //     // Check for registered Dart modules
    //     final dartModule = packageLib.fileManager.loadDartModule(name);
    //     if (dartModule != null) {
    //       return [Value(dartModule), Value("dart:$name")];
    //     }
    //   } catch (e) {
    //     return [nil, Value(e.toString())];
    //   }
    //   return [nil, Value("Dart module '$name' not found")];
    // }),

    // 4. All-in-one loader
    Value((List<Object?> args) {
      return [
        packageLib.vm.constantPrimitiveValue(null),
        packageLib.vm.constantDartStringValue(
          "all-in-one loading not supported",
        ),
      ];
    }, interpreter: packageLib.vm),
  ];
  packageTable['searchers'] = Value(searchers, interpreter: packageLib.vm);

  env.define(
    "package",
    Value(
      packageTable,
      metatable: packageLib.packageClass.metamethods,
      interpreter: packageLib.vm,
    ),
  );
}
