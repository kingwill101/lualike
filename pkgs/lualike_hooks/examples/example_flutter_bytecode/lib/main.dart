/// Bytecode mode example.
///
/// Lua scripts are compiled to Lua 5.5 bytecode at build time.
/// At runtime, load the bytecode bytes from the asset bundle and
/// execute via LuaBytecodeRuntime.
///
/// ## Flow
///
/// ```text
/// assets/lua/hello.lua
///       ↓  (build hook: CompileMode.bytecode)
/// build/lua/hello.lua  (binary bytecode)
///       ↓  (rootBundle.load)
/// LuaBytecodeRuntime.loadBytecode(bytes)
///       ↓
/// runtime.callFunction(chunk)
/// ```
///
/// ## When to use
///
/// - Flutter apps with asset bundle
/// - Dart CLI with file-based loading
/// - Build-time validation and optimization
/// - Smaller output than source
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lualike/flutter_lualike.dart';
import 'package:lualike/lualike.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key, this.autoRun = true});

  final bool autoRun;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bytecode Mode',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
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
    _add('=== Bytecode Mode ===');
    _add('');

    // 1. Load compiled bytecode from the asset bundle.
    _add('1. Loading bytecode from assets...');
    final data = await rootBundle.load('build/lua/hello.lua');
    final bytecode = data.buffer.asUint8List();
    _add('   ${bytecode.length} bytes loaded');
    _add('');

    // 2. Execute via LuaBytecodeRuntime.
    _add('2. Executing via LuaBytecodeRuntime...');
    final runtime = LuaBytecodeRuntime();
    final chunk = await runtime.loadBytecode(bytecode, moduleName: 'hello.lua');
    final module = await runtime.callFunction(chunk, const <Object?>[]);
    _add('   Module type: ${module.runtimeType}');
    _add('');

    // 3. Use flutter_lualike for require() support.
    _add('3. Setting up flutter_lualike...');
    await useAssetBundle(rootBundle, assetRoot: 'build/lua');
    _add('   require("hello") now resolves from assets');
    _add('');

    _add('=== Done ===');
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bytecode Mode')),
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
