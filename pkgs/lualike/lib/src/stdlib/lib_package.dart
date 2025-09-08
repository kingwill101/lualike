import 'package:lualike/lualike.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/utils/file_system_utils.dart';
import 'package:lualike/src/utils/platform_utils.dart' as platform;
import 'package:path/path.dart' as path_lib;

class PackageLib {
  final Interpreter vm;
  final FileManager fileManager;

  PackageLib(this.vm) : fileManager = vm.fileManager;

  final ValueClass packageClass = ValueClass.create({
    "__index": (List<Object?> args) {
      final table = args[0] as Value;
      final key = args[1] as Value;
      if (key.raw == "path") {
        // Default package path
        return Value("./?.lua;./?/init.lua");
      }
      if (key.raw == "cpath") {
        // Default C module path
        return Value("./?.so;./?.dll");
      }

      if (table.raw is Map) {
        final map = table.raw as Map;
        if (map.containsKey(key.raw)) {
          return map[key.raw];
        }
      }
      return Value(null);
    },
  });

  Map<String, dynamic> createFunctions() {
    return {
      'loadlib': _LoadLib(),
      'searchpath': _SearchPath(fileManager),
      'preload': ValueClass.table({}), // Table for preloaded modules
      'loaded': ValueClass.table({}), // Table for loaded modules
      'path': Value("./?.lua;./?/init.lua"),
      'cpath': Value("./?.so;./?.dll"),
      'config': Value(_getConfig()),
      'searchers': Value(
        _createDefaultSearchers(),
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
        final name = (args[0] as Value).raw.toString();
        final preload = vm.globals.get("package")?.raw?["preload"] as Map?;
        if (preload != null && preload.containsKey(name)) {
          Logger.debug(
            "Preload searcher found module: $name",
            category: 'Package',
          );
          return [preload[name], Value("preload:$name")];
        }
        return Value("no field package.preload['$name']");
      }),

      // 2. Lua module loader
      Value(_LuaLoader(vm, fileManager)),

      // 3. C module loader (simulated for Dart)
      Value((List<Object?> args) {
        final name = (args[0] as Value).raw.toString();
        return Value("no C module loader implemented for '$name'");
      }),

      // 4. All-in-one loader
      Value((List<Object?> args) {
        final name = (args[0] as Value).raw.toString();
        return Value("no all-in-one loader implemented for '$name'");
      }),
    ];
  }
}

class _LoadLib implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw Exception("loadlib requires library path and function name");
    }

    final libpath = (args[0] as Value).raw.toString();
    final funcname = (args[1] as Value).raw.toString();

    // We don't actually load C libraries, just simulate the interface
    if (funcname == '*') {
      // Check whether the library exists
      if (!await fileExists(libpath)) {
        // In Lua, a missing library returns nil plus an error message and the
        // string 'absent'.
        return [Value(null), Value('cannot load $libpath'), Value('absent')];
      }
      // Library found; return a true value like Lua does
      return Value(true);
    }

    // For specific symbols, check if the library exists first
    if (!await fileExists(libpath)) {
      return [Value(null), Value('cannot load $libpath'), Value('absent')];
    }

    // Library exists but symbol loading is not supported
    return [
      Value(null),
      Value('dynamic libraries not supported'),
      Value('init'),
    ];
  }
}

class _SearchPath implements BuiltinFunction {
  final FileManager fileManager;

  _SearchPath(this.fileManager);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw Exception('searchpath requires name and path');
    }

    final name = (args[0] as Value).raw.toString();
    final searchPath = (args[1] as Value).raw.toString();
    final sep = args.length > 2 ? (args[2] as Value).raw.toString() : '.';
    final rep = args.length > 3
        ? (args[3] as Value).raw.toString()
        : path_lib.separator;

    // Avoid Dart's replaceAll behavior with empty pattern
    final replacedName = sep.isEmpty ? name : name.replaceAll(sep, rep);
    final templates = searchPath.split(';');
    final tried = <String>[];

    for (final template in templates) {
      if (template.isEmpty) continue;
      final filename = template.replaceAll('?', replacedName);
      tried.add(filename);
      if (await fileExists(filename)) {
        return Value(filename);
      }
    }

    final err = tried.map((f) => "\n\tno file '$f'").join();
    return [Value(null), Value(err)];
  }
}

class _LuaLoader implements BuiltinFunction {
  final Interpreter vm;
  final FileManager fileManager;

  _LuaLoader(this.vm, this.fileManager);

  @override
  Future<Object?> call(List<Object?> args) async {
    final name = (args[0] as Value).raw.toString();
    Logger.debug("_LuaLoader called for module: $name", category: 'Package');

    // Special case: If the current script is in a special directory like .lua-tests,
    // and the module name doesn't contain a path separator, try to load it from the same directory first
    String? modulePath;
    if (!name.contains('.') &&
        !name.contains('/') &&
        vm.currentScriptPath != null) {
      final scriptDir = path_lib.dirname(vm.currentScriptPath!);
      final directPath = path_lib.join(scriptDir, '$name.lua');
      Logger.debug("Trying direct path in script directory: $directPath", category: 'Package');

      if (await fileExists(directPath)) {
        Logger.debug("Module found in script directory: $directPath", category: 'Package');
        modulePath = directPath;
      }
    }

    // If not found in the script directory, use the regular resolution
    if (modulePath == null) {
      // Try to find the module file
      Logger.debug("Attempting to resolve module path for: $name", category: 'Package');
      modulePath = await fileManager.resolveModulePath(name);

      // Print the resolved globs for debugging
      fileManager.printResolvedGlobs();
    }

    Logger.debug("Module path resolved to: $modulePath", category: 'Package');

    // Return a loader function that will load and execute the module
    return [
      Value((List<Object?> args) async {
        final name = (args[0] as Value).raw.toString();
        final modulePath = (args[1] as Value).raw.toString();
        Logger.debug(
          "Loader function called for module: $name with path: $modulePath",
          category: 'Package',
        );

        try {
          // Load the source code
          Logger.debug("Attempting to load source from: $modulePath", category: 'Package');
          final source = await fileManager.loadSource(modulePath);
          if (source == null) {
            Logger.debug(
              "Source not found for module: $name at path: $modulePath",
              category: 'Package',
            );
            throw Exception("cannot load module '$name': file not found");
          }

          Logger.debug("Source loaded successfully, length: ${source.length}", category: 'Package');

          try {
            // Parse the module code
            Logger.debug("Parsing module code", category: 'Package');
            final ast = parse(source, url: modulePath);
            Logger.debug("Module code parsed successfully", category: 'Package');

            // Create a new environment for the module
            Logger.debug("Creating new environment for module", category: 'Package');
            final moduleEnv = Environment(parent: vm.globals, interpreter: vm);

            // Pass arguments like Lua's loader function (...)
            moduleEnv.declare(
              '...',
              Value.multi([Value(name), Value(modulePath)]),
            );

            // Execute the module code in the new environment
            Logger.debug("Creating interpreter for module", category: 'Package');
            final interpreter = Interpreter(
              environment: moduleEnv,
              fileManager: fileManager,
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
              Logger.debug(
                "Resolved module path to absolute path: $absoluteModulePath",
                category: 'Package',
              );
            }

            // Set the current script path to the module path
            Logger.debug("Setting script path to: $absoluteModulePath", category: 'Package');
            interpreter.currentScriptPath = absoluteModulePath;

            // Store the script path in the module environment (normalized)
            final normalizedModulePath = path_lib.url.joinAll(
              path_lib.split(path_lib.normalize(absoluteModulePath)),
            );
            final moduleDir = path_lib.dirname(absoluteModulePath);
            final normalizedModuleDir = path_lib.url.joinAll(
              path_lib.split(path_lib.normalize(moduleDir)),
            );
            moduleEnv.define('_SCRIPT_PATH', Value(normalizedModulePath));
            moduleEnv.define('_SCRIPT_DIR', Value(normalizedModuleDir));

            // Also set _MODULE_NAME global
            moduleEnv.define('_MODULE_NAME', Value(name));

            Logger.debug(
              "Module environment set up with _SCRIPT_PATH=$absoluteModulePath, _SCRIPT_DIR=$moduleDir, _MODULE_NAME=$name",
              category: 'Package',
            );
            Logger.debug(
              "Module environment set up with _SCRIPT_PATH(norm)=$normalizedModulePath, _SCRIPT_DIR(norm)=$normalizedModuleDir | originals: path=$absoluteModulePath, dir=$moduleDir, _MODULE_NAME=$name",
              category: 'Package',
            );

            // Set the globals in the module environment
            vm.globals.define('_SCRIPT_PATH', Value(normalizedModulePath));
            vm.globals.define('_SCRIPT_DIR', Value(normalizedModuleDir));
            vm.globals.define('_MODULE_NAME', Value(name));

            Logger.debug(
              "Global environment updated with _SCRIPT_PATH=$absoluteModulePath, _SCRIPT_DIR=$moduleDir, _MODULE_NAME=$name",
              category: 'Package',
            );

            Object? result;
            try {
              // Run the module code
              Logger.debug("Running module code", category: 'Package');
              await interpreter.run(ast.statements);
              Logger.debug("Module code executed successfully", category: 'Package');
              // If no explicit return, the result is nil
              result = Value(null);
            } on ReturnException catch (e) {
              // Handle explicit return from module
              Logger.debug("Module returned a value", category: 'Package');
              result = e.value;
            }

            // If the module didn't return anything, return an empty table
            if ((result is Value && result.raw == null)) {
              Logger.debug("Module returned nil, defaulting to empty table", category: 'Package');
              result = Value({});
            } else {
              Logger.debug("Module returned: ${result.runtimeType}", category: 'Package');
            }

            // Store the result in package.loaded immediately to ensure it's available
            // for any recursive requires within the module
            Logger.debug("Storing module in package.loaded", category: 'Package');
            final packageVal = vm.globals.get("package");
            if (packageVal is Value && packageVal.raw is Map) {
              final packageTable = packageVal.raw as Map;
              if (packageTable.containsKey("loaded")) {
                final loadedValue = packageTable["loaded"] as Value;
                final loaded = loadedValue.raw as Map;
                loaded[name] = result;
                Logger.debug("Module '$name' stored in package.loaded", category: 'Package');
                Logger.debug(
                  "Module '$name' stored in package.loaded during load",
                  category: 'Package',
                );
              }
            }

            Logger.debug("Module loading completed successfully", category: 'Package');
            return result;
          } catch (e) {
            Logger.error("Error parsing/executing module: $e", category: 'Package');
            throw Exception("error loading module '$name': $e");
          }
        } catch (e) {
          Logger.error("Error loading module source: $e", category: 'Package');
          throw Exception("error loading module '$name': $e");
        }
      }),
      Value(path_lib.normalize(modulePath ?? '')),
    ];
  }
}

void definePackageLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  final packageLib = PackageLib(astVm ?? Interpreter());

  // Create package table with metamethods
  final packageTable = ValueClass.table();
  packageLib.createFunctions().forEach((key, value) {
    packageTable[key] = value;
  });

  // Add default searchers
  final searchers = <Value>[
    // 1. Package preload searcher
    Value((List<Object?> args) {
      final name = (args[0] as Value).raw.toString();
      final preload = packageTable['preload'];
      if (preload.containsKey(name)) {
        return [preload[name], Value("preload")];
      }
      return [Value(null), Value("not found in preload")];
    }),

    // 2. Lua/Dart module loader
    Value((List<Object?> args) {
      final name = (args[0] as Value).raw.toString();
      final path = packageTable['path'] as Value;

      try {
        final searcher = _SearchPath(packageLib.fileManager);
        final filename = searcher.call([Value(name), path]);

        if (filename is Value && filename.raw != null) {
          final source = packageLib.fileManager.loadSource(
            filename.raw.toString(),
          );
          // Return loader function
          return [
            Value((loaderArgs) {
              // Module loading will be handled by require
              return Value(source);
            }),
            Value(path_lib.normalize(filename.raw.toString())),
          ];
        }
      } catch (e) {
        return [Value(null), Value(e.toString())];
      }
      return [Value(null), Value("module '$name' not found")];
    }),

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
    //     return [Value(null), Value(e.toString())];
    //   }
    //   return [Value(null), Value("Dart module '$name' not found")];
    // }),

    // 4. All-in-one loader
    Value((List<Object?> args) {
      return [Value(null), Value("all-in-one loading not supported")];
    }),
  ];
  packageTable['searchers'] = Value(searchers);

  astVm?.globals.define(
    "package",
    Value(packageTable, metatable: packageLib.packageClass.metamethods),
  );
}
