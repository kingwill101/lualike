import 'package:dart_console/dart_console.dart';
import 'package:lualike/history.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/io/io_device.dart';
import 'package:lualike/src/io/lua_file.dart';
import 'package:lualike/src/io/virtual_io_device.dart';
import 'package:lualike/src/stdlib/lib_io.dart';

// ConsoleOutputDevice implements IODevice for Console output
class ConsoleOutputDevice implements IODevice {
  final Console console;
  bool _isClosed = false;

  ConsoleOutputDevice(this.console);

  @override
  bool get isClosed => _isClosed;

  @override
  String get mode => 'w';

  @override
  Future<void> close() async {
    _isClosed = true;
  }

  @override
  Future<void> flush() async {}

  @override
  Future<ReadResult> read([String format = "l"]) async {
    throw UnimplementedError("ConsoleOutputDevice does not support read");
  }

  @override
  Future<WriteResult> write(String data) async {
    if (_isClosed) {
      return WriteResult(false, "Device is closed");
    }
    console.write(data);
    return WriteResult(true);
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    throw UnimplementedError("ConsoleOutputDevice does not support seek");
  }

  @override
  Future<void> setBuffering(BufferMode mode, [int? size]) async {}

  @override
  Future<int> getPosition() async => 0;

  @override
  Future<bool> isEOF() async => true;
}

/// Interactive REPL mode for LuaLike
class InteractiveMode {
  static const String lualikeVersion = '0.0.1';
  static const String luaCompatVersion = '5.4';

  final LuaLike bridge;
  final bool debugMode;

  InteractiveMode({required this.bridge, this.debugMode = false});

  Future<void> run() async {
    // Disable flushing in the Lua print function to avoid stream conflicts
    LuaLikeConfig().flushAfterPrint = false;

    final history = ReplHistory();

    // Load history from file first
    try {
      history.loadFromFile();
      if (debugMode) {
        print('Loaded ${history.length} commands from history');
      }
    } catch (e) {
      if (debugMode) {
        print('Error loading history: $e');
      }
    }

    // Create a console for terminal control with scrolling support
    final console = Console.scrolling(recordBlanks: false);

    // Set up virtual devices for REPL I/O
    final stdinDevice = VirtualIODevice();
    final stdoutDevice = ConsoleOutputDevice(console);
    IOLib.defaultInput = LuaFile(stdinDevice);
    IOLib.defaultOutput = Value(
      LuaFile(stdoutDevice),
      metatable: IOLib.fileClass.metamethods,
    );

    // Custom print function that writes to our buffer instead of stdout
    void customPrint(String message) {
      stdoutDevice.write('$message\n');
    }

    // Print welcome message
    customPrint(
      'LuaLike $lualikeVersion (Lua $luaCompatVersion compatible)  AST mode',
    );
    customPrint('Type "exit" to quit');

    // REPL loop
    bool running = true;
    String? multilineBuffer;

    while (running) {
      try {
        // Clear the output buffer before each command
        multilineBuffer = null;

        // Get custom prompt from _PROMPT global variable
        final promptValue = bridge.getGlobal('_PROMPT');
        String basePrompt = '> ';
        if (promptValue != null && promptValue is String) {
          basePrompt = promptValue;
        }

        // Determine prompt based on whether we're in multiline mode
        String prompt = multilineBuffer != null ? '>> ' : basePrompt;

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
          result = await bridge.execute(codeToExecute);
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
            String errorMsg = e.toString();
            if (errorMsg.startsWith('Exception: ')) {
              errorMsg = errorMsg.substring('Exception: '.length);
            }
            customPrint('stdin:1: $errorMsg');
            continue;
          }
        }

        // Print the result
        customPrint('= ${_formatValue(result)}');
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

  /// Format values nicely for display
  String _formatValue(dynamic value) {
    if (value == null) return 'nil';
    if (value is Value) {
      if (value.raw == null) return 'nil';
      return _formatValue(value.raw);
    }
    if (value is String) return '"$value"';
    if (value is List) return '[${value.map(_formatValue).join(", ")}]';
    if (value is Map) {
      return '{${value.entries.map((e) => '${_formatValue(e.key)} = ${_formatValue(e.value)}').join(", ")}}';
    }
    return value.toString();
  }
}
