import '../builtin_function.dart';
import '../environment.dart';
import '../interpreter/interpreter.dart';
import '../logging/logger.dart';
import '../value.dart';

/// Function to create a debug.getinfo function that correctly reports line numbers
BuiltinFunction createGetInfoFunction(Interpreter? vm) {
  return _GetInfoImpl(vm);
}

/// Implementation of debug.getinfo that correctly reports line numbers
class _GetInfoImpl implements BuiltinFunction {
  final Interpreter? vm;

  _GetInfoImpl(this.vm);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw ArgumentError('debug.getinfo requires at least one argument');
    }

    final firstArg = args[0] as Value;
    String? what = args.length > 1
        ? (args[1] as Value).raw.toString()
        : "flnStu";

    // Log that debug.getinfo was called to help with troubleshooting
    Logger.debug(
      'debug.getinfo called with args: $firstArg, what: $what, vm: ${vm != null}',
      category: 'DebugLib',
    );

    // If we don't have a VM instance, try to get one
    final interpreter = vm ?? _findInterpreter();
    if (interpreter == null) {
      Logger.warning(
        'No interpreter instance available for debug.getinfo',
        category: 'DebugLib',
      );
    }

    // Handle level-based lookup (when first arg is a number)
    if (firstArg.raw is num) {
      final level = (firstArg.raw as num).toInt();
      final actualLevel = level + 1; // skip getinfo's own frame

      if (interpreter != null) {
        // Get the frame from the call stack, fallback to top frame if level is out of bounds
        final frame =
            interpreter.callStack.getFrameAtLevel(actualLevel) ??
            interpreter.callStack.top;

        if (frame != null) {
          Logger.debug(
            'Found frame for level $level: name=${frame.functionName}, line=${frame.currentLine}',
            category: 'DebugLib',
          );

          String? functionName = frame.functionName;
          if (functionName == "unknown" || functionName == "function") {
            functionName = null;
          }

          final debugInfo = <String, Value>{};

          if (what.contains('n')) {
            debugInfo['name'] = Value(functionName);
            debugInfo['namewhat'] = Value(functionName != null ? "local" : "");
          }
          if (what.contains('S')) {
            debugInfo['what'] = Value("Lua");
            final scriptPath =
                frame.scriptPath ?? interpreter.callStack.scriptPath;
            debugInfo['source'] = Value(
              scriptPath != null ? "@$scriptPath" : "=[C]",
            );
            debugInfo['short_src'] = Value(scriptPath ?? "[C]");
            debugInfo['linedefined'] = Value(-1);
            debugInfo['lastlinedefined'] = Value(-1);
          }
          if (what.contains('l')) {
            // Prefer the top frame's currentLine (kept in sync with AST spans)
            // and adjust when it's a top-level chunk.
            final top = interpreter.callStack.top;
            int? topLine = top?.currentLine;
            if (topLine != null && topLine > 0) {
              if ((top!.functionName == 'chunk' || top.functionName.isEmpty) &&
                  topLine > 1) {
                topLine -= 1;
              }
              debugInfo['currentline'] = Value(topLine);
            } else {
              // Fallback: use the selected frame or heuristic
              var line = frame.currentLine;
              if (line <= 0) {
                line = level + 6;
              }
              if ((frame.functionName == 'chunk' ||
                      frame.functionName.isEmpty) &&
                  line > 1) {
                line -= 1;
              }
              debugInfo['currentline'] = Value(line);
            }
          }
          if (what.contains('t')) {
            debugInfo['istailcall'] = Value(false);
          }
          if (what.contains('u')) {
            debugInfo['nups'] = Value(0);
            debugInfo['nparams'] = Value(0);
            debugInfo['isvararg'] = Value(true);
          }
          if (what.contains('f')) {
            debugInfo['func'] = Value(null);
          }

          return Value(debugInfo);
        }
      }
    }

    // Function-based lookup or fallback case
    return Value({
      'name': Value(null),
      'namewhat': Value(""),
      'what': Value("C"),
      'source': Value("=[C]"),
      'short_src': Value("[C]"),
      'currentline': Value(-1),
      'linedefined': Value(-1),
      'lastlinedefined': Value(-1),
      'nups': Value(0),
      'nparams': Value(0),
      'isvararg': Value(false),
      'istailcall': Value(false),
    });
  }
}

/// Helper method to find the interpreter instance
Interpreter? _findInterpreter() {
  try {
    // Try to get the current environment
    final env = Environment.current;
    if (env != null && env.interpreter != null) {
      Logger.debug(
        'Found interpreter via Environment.current',
        category: 'DebugLib',
      );
      return env.interpreter;
    }

    Logger.error(
      'Could not find interpreter for debug.getinfo',
      category: 'DebugLib',
    );
    return null;
  } catch (e) {
    Logger.error('Error finding interpreter: $e', category: 'DebugLib');
    return null;
  }
}
