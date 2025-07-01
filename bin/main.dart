import 'dart:async';
import 'dart:io';

import 'package:dart_console/dart_console.dart';
import 'package:lualike/history.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/io/lua_file.dart';
import 'package:lualike/src/io/virtual_io_device.dart';
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:lualike/testing.dart';
import 'package:path/path.dart' as path;

bool debugMode = false;
bool isReplMode = false;
bool errorReported = false;

// Create a single instance of the bridge to be used throughout the application
final LuaLike globalBridge = LuaLike();

// Custom print function that doesn't flush stdout
void safePrint(String message) {
  // Use print without flushing
  print(message);
}

Future<void> runFile(String filePath, ExecutionMode mode) async {
  // Reset error reported flag
  errorReported = false;

  try {
    // Resolve the path relative to Platform.script if it's relative
    String resolvedPath = filePath;
    if (!path.isAbsolute(filePath)) {
      try {
        // First try to use the current working directory
        final currentDir = Directory.current.path;
        resolvedPath = path.normalize(path.join(currentDir, filePath));

        // Check if the file exists at this path
        if (!File(resolvedPath).existsSync()) {
          // If file doesn't exist and we're not in product mode (compiled executable),
          // try using Platform.script as a fallback
          if (!isProductMode) {
            try {
              final dartScriptPath = Platform.script.toFilePath();
              if (dartScriptPath.isNotEmpty) {
                final dartScriptDir = path.dirname(dartScriptPath);

                // Try directly in the script directory
                String scriptDirPath = path.normalize(
                  path.join(dartScriptDir, filePath),
                );
                if (File(scriptDirPath).existsSync()) {
                  resolvedPath = scriptDirPath;
                } else {
                  // Go up one level from bin to the project root (for development mode)
                  final projectRoot = path.dirname(dartScriptDir);
                  resolvedPath = path.normalize(
                    path.join(projectRoot, filePath),
                  );
                }
              }
            } catch (e) {
              // Platform.script failed
              if (debugMode) {
                safePrint("Platform.script not available: $e");
              }
            }
          } else if (debugMode) {
            safePrint(
              "Running as compiled executable, skipping Platform.script path resolution",
            );
          }
        }

        if (debugMode) {
          safePrint("Resolved relative path '$filePath' to '$resolvedPath'");
        }
      } catch (e) {
        // If we can't resolve the path, use the original path as a last resort
        if (debugMode) {
          safePrint("Error resolving path: $e, using original path");
        }
      }
    }

    // Check if the file exists before trying to read it
    if (!File(resolvedPath).existsSync()) {
      throw FileSystemException(
        "Cannot open file, path = '$resolvedPath'",
        resolvedPath,
        OSError("No such file or directory", 2),
      );
    }

    final sourceCode = await File(resolvedPath).readAsString();
    // Get the absolute path to ensure it's fully resolved
    final absolutePath = File(resolvedPath).absolute.path;

    // Set the script path in the global bridge before running the code
    globalBridge.setGlobal('_SCRIPT_PATH', absolutePath);
    // Default '_soft' flag used by Lua tests to conditionally
    // execute heavier checks. When undefined our interpreter would
    // throw an error for an unknown global, so define it explicitly.
    globalBridge.setGlobal('_soft', false);

    // Run the code and let the interpreter handle any errors
    await runCode(sourceCode, mode, scriptPath: absolutePath);

    if (debugMode) {
      safePrint('Successfully executed file: $absolutePath');
    }
  } on ReturnException catch (e) {
    // Handle return values from the top level
    final result = e.value;
    if (result != null) {
      safePrint(formatValue(result));
    }
  } on FileSystemException catch (e, s) {
    // Handle file system errors
    safePrint('File error: ${e.message}');
    if (debugMode) {
      safePrint('Stack trace: $s');
    }
    exit(1);
  } catch (e, stackTrace) {
    print(e);
    print(stackTrace);
    // For Lua errors, the error has already been printed by the interpreter
    // Just exit with a non-zero status code
    exit(1);
  }
}

/// Runs the given LuaLike code
Future<void> runCode(
  String code,
  ExecutionMode mode, {
  String? scriptPath,
  bool printResult = false,
}) async {
  // Use the global bridge instance
  final bridge = globalBridge;

  if (debugMode && scriptPath != null) {
    safePrint('Running code with script path: $scriptPath');
  }

  // Mark this as the main chunk when running a script
  if (scriptPath != null) {
    bridge.setGlobal('_MAIN_CHUNK', true);
  }

  // Execute the code with the script path
  // Don't use try-catch here - let the interpreter handle errors
  final result = await bridge.runCode(code, scriptPath: scriptPath);

  // Handle the result based on mode
  if (printResult) {
    print(result);
  }
}

late Environment environment;

/// A custom implementation of the REPL that avoids stream issues
Future<void> runRepl(ExecutionMode mode) async {
  // Disable flushing in the Lua print function to avoid stream conflicts
  LuaLikeConfig().flushAfterPrint = false;

  final history = ReplHistory();

  // Load history from file first
  try {
    history.loadFromFile();
    if (debugMode) {
      safePrint('Loaded ${history.length} commands from history');
    }
  } catch (e) {
    if (debugMode) {
      safePrint('Error loading history: $e');
    }
  }

  // Create a console for terminal control with scrolling support
  final console = Console.scrolling(recordBlanks: false);

  // Set up virtual devices for REPL I/O
  final stdinDevice = VirtualIODevice();
  final stdoutDevice = VirtualIODevice();
  IOLib.defaultInput = LuaFile(stdinDevice);
  IOLib.defaultOutput = LuaFile(stdoutDevice);

  // Custom print function that writes to our buffer instead of stdout
  void customPrint(String message) {
    stdoutDevice.write('$message\n');
    console.writeLine(message);
  }

  // Print welcome message
  customPrint(
    'LuaLike REPL (${mode == ExecutionMode.astInterpreter ? 'AST' : 'Bytecode'} mode)',
  );
  customPrint('Type "exit" to quit');

  // REPL loop
  bool running = true;
  String? multilineBuffer;

  while (running) {
    try {
      // Clear the output buffer before each command
      multilineBuffer = null;

      // Determine prompt based on whether we're in multiline mode
      String prompt = multilineBuffer != null ? '>> ' : '> ';

      // Read input line using console.readLine which supports history navigation
      console.write(prompt);
      final line = console.readLine(
        cancelOnBreak: true,
        callback: (text, lastPressed) {
          if (lastPressed.isControl) {
            if (lastPressed.controlChar == ControlCharacter.ctrlC) {
              running = false;
            }
          }
        },
      );

      // Check for exit or EOF
      if (line == null ||
          (multilineBuffer == null && line.toLowerCase() == 'exit')) {
        running = false;
        continue;
      }

      // Write input to the virtual stdin device
      stdinDevice.write('$line\n');

      // Add to history if not empty
      if (line.isNotEmpty) {
        history.add(line);
      }

      // Handle multiline input
      String codeToExecute;
      if (multilineBuffer != null) {
        // We're in multiline mode
        if (line.trim().isEmpty) {
          // Empty line ends multiline input
          codeToExecute = multilineBuffer;
          multilineBuffer = null;
        } else {
          // Add to multiline buffer
          multilineBuffer += '\n$line';
          continue;
        }
      } else {
        // Check if this might be the start of multiline input
        if (line.trim().endsWith('{') ||
            line.trim().endsWith('(') ||
            line.trim().endsWith('do') ||
            line.trim().endsWith('then') ||
            line.trim().endsWith('else') ||
            line.trim().endsWith('function') ||
            line.trim().endsWith('=')) {
          multilineBuffer = line;
          continue;
        }
        codeToExecute = line;
      }

      // Execute the code
      Object? result;
      try {
        result = await executeCode(
          codeToExecute,
          mode,
          onInterpreterSetup: (vm) {
            // setupPrint(vm);
            environment = vm.globals;
          },
        );
      } on ReturnException catch (e) {
        result = e.value;
      } catch (e) {
        if (e.toString().contains('unexpected symbol near') ||
            e.toString().contains('syntax error')) {
          // This might be an incomplete statement, try multiline mode
          if (multilineBuffer == null) {
            multilineBuffer = codeToExecute;
            continue;
          } else {
            // If we're already in multiline mode and still have syntax errors,
            // show the error and reset
            // Format error message in Lua style
            String errorMsg = e.toString();
            if (errorMsg.startsWith('Exception: ')) {
              errorMsg = errorMsg.substring('Exception: '.length);
            }
            customPrint('stdin:1: $errorMsg');
            multilineBuffer = null;
            continue;
          }
        } else {
          // Other errors
          // Format error message in Lua style
          String errorMsg = e.toString();
          if (errorMsg.startsWith('Exception: ')) {
            errorMsg = errorMsg.substring('Exception: '.length);
          }
          customPrint('stdin:1: $errorMsg');
          continue;
        }
      }
      if (!isReplMode) {
        result = '';
      }

      // Print the result
      if (result != null) {
        customPrint('= ${formatValue(result)}');
      } else if (isReplMode && codeToExecute.trim().isNotEmpty) {
        // Directly evaluate and print expressions like '1'
        try {
          final evalResult = await executeCode(
            codeToExecute,
            mode,
            onInterpreterSetup: (vm) {
              // setupPrint(vm);
              environment = vm.globals;
            },
          );
          if (evalResult != null) {
            customPrint('= ${formatValue(evalResult)}');
          } else {
            // Check if it's a numeric literal or variable and print its value or nil
            final trimmedCode = codeToExecute.trim();
            final numValue = num.tryParse(trimmedCode);
            if (numValue != null) {
              customPrint('= $numValue');
            } else {
              final variableValue = environment.get(trimmedCode);
              customPrint('= ${formatValue(variableValue)}');
            }
          }
        } catch (e) {
          customPrint('Error: $e');
        }
      }
    } catch (e, stack) {
      customPrint('Error: $e');
      if (debugMode) {
        customPrint('Stack trace: $stack');
      }
      // Reset multiline buffer on error
      multilineBuffer = null;
    }
  }

  // Save history to file before exiting
  try {
    history.saveToFile();
  } catch (e) {
    if (debugMode) {
      customPrint('Error saving history: $e');
    }
  }

  customPrint('\nGoodbye!');
}

void printUsage() {
  safePrint('''
Usage: lualike [options] [script] [args]
Options:
  --ast       Run using AST interpreter (default)
  --bytecode  Run using bytecode VM
  -e code     Execute string 'code'
  --debug     Enable debug mode with detailed logging
  --help      Show this help message

If no script or code is provided, starts REPL mode.
''');
}

/// Main entry point for the LuaLike interpreter
Future<void> main(List<String> args) async {
  ExecutionMode mode = ExecutionMode.astInterpreter;
  String? scriptPath;
  String? codeToExecute;

  if (args.contains('--help')) {
    printUsage();
    return;
  }

  if (args.contains('--debug')) {
    debugMode = true;
    Logger.setEnabled(debugMode);
    safePrint('Debug mode enabled');
    // Remove the debug flag from args to avoid processing it again
    args = args.where((arg) => arg != '--debug').toList();
  }

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--ast':
        mode = ExecutionMode.astInterpreter;
      case '--bytecode':
        mode = ExecutionMode.bytecodeVM;
      case '-e':
        if (i + 1 < args.length) {
          codeToExecute = args[++i];
        } else {
          safePrint('Error: -e requires an argument');
          printUsage();
          exit(1);
        }
      default:
        if (args[i].startsWith('-')) {
          safePrint('Unknown option: ${args[i]}');
          printUsage();
          exit(1);
        }
        scriptPath = args[i];
    }
  }

  if (codeToExecute != null) {
    await runCode(codeToExecute, mode);
  } else if (scriptPath != null) {
    await runFile(scriptPath, mode);
  } else {
    isReplMode = true;
    await runRepl(mode);
  }
}

// Helper function to format values nicely
String formatValue(dynamic value) {
  if (value == null) return 'nil';
  if (value is Value) {
    if (value.raw == null) return 'nil';
    return formatValue(value.raw);
  }
  if (value is String) return '"$value"';
  if (value is List) return '[${value.map(formatValue).join(", ")}]';
  if (value is Map) {
    return '{${value.entries.map((e) => '${formatValue(e.key)} = ${formatValue(e.value)}').join(", ")}}';
  }
  return value.toString();
}
