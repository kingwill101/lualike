/// Dart source mode example.
///
/// Lua scripts are compiled to standalone Dart source code at build time.
/// The generated `.dart` files contain functions that execute the Lua
/// logic directly — no bytecode VM or asset loading needed.
///
/// ## Flow
///
/// ```text
/// assets/lua/hello.lua
///       ↓  (build hook: CompileMode.dartSource)
/// build/lua/hello.lua.dart  (Dart source with IR functions)
///       ↓  (import)
/// import 'build/lua/hello.lua.dart';
///       ↓
/// Call _lua_fn_0(runtime, args, upvals, varargs)
/// ```
///
/// ## When to use
///
/// - Dart CLI apps (static linking, no runtime parsing)
/// - When you want Lua logic as native Dart code
/// - Tree-shaking friendly (unused functions can be eliminated)
/// - No asset bundle needed
///
/// ## Tradeoffs
///
/// - Generated Dart code is verbose and not meant to be read
/// - Requires lualike runtime types (Value, LuaRuntime) at runtime
/// - Build step is required before Dart analysis will pass
import 'package:flutter/material.dart';
import 'package:lualike/lualike.dart' show executeCode, Value;

// The build hook generates this file from assets/lua/hello.lua.
// It contains functions like:
//   Future<Value> _lua_fn_0(LuaRuntime rt, List<Value> args, ...) async { ... }
//
// The generated file is in build/lua/hello.lua.dart — add it to your
// include paths or reference it with a relative import.
//
// For this example, we demonstrate the concept by executing source directly.
// In a real project, you would import the generated file.

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key, this.autoRun = true});

  final bool autoRun;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dart Source Mode',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: HomePage(autoRun: autoRun),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.autoRun = true});

  final bool autoRun;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<String> _log = [];
  bool _running = true;

  @override
  void initState() {
    super.initState();
    if (widget.autoRun) {
      _run();
    } else {
      setState(() => _running = false);
    }
  }

  void _add(String line) => setState(() => _log.add(line));

  Future<void> _run() async {
    _add('=== Dart Source Mode ===');
    _add('');

    // In a real project, you would do:
    //   import 'build/lua/hello.lua.dart';
    //   final result = await _lua_fn_0(runtime, args, upvals, varargs);
    //
    // The generated Dart file contains the full Lua logic compiled to
    // Dart IR instructions. No bytecode VM needed.

    _add('Build hook generates Dart source from Lua:');
    _add('  assets/lua/hello.lua → build/lua/hello.lua.dart');
    _add('');

    _add('Generated file contains:');
    _add('  import "package:lualike/src/value.dart";');
    _add('  import "package:lualike/src/runtime/lua_runtime.dart";');
    _add('');
    _add('  Future<Value> _lua_fn_0(');
    _add('    LuaRuntime rt,');
    _add('    List<Value> args,');
    _add('    List<Value> upvals,');
    _add('    List<Value> varargs,');
    _add('  ) async { ... }');
    _add('');

    // For demonstration, we execute the source directly via the AST engine.
    _add('Demonstrating with direct execution (same logic):');
    final result = await executeCode('''
      local M = {}
      function M.greet(name) return "Hello, " .. name .. "!" end
      function M.add(a, b) return a + b end
      return M.greet("Flutter")
    ''');
    _add('  Result: ${(result as Value).unwrap()}');
    _add('');

    _add('=== Done ===');
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dart Source Mode')),
      body: _running
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final line in _log)
                  Text(line, style: const TextStyle(fontFamily: 'monospace')),
              ],
            ),
    );
  }
}
