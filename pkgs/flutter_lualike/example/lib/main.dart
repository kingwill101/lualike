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
      title: 'flutter_lualike Example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
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
    _add('=== flutter_lualike Example ===');
    _add('');

    // 1. Load compiled bytecode from assets.
    _add('1. Loading bytecode from assets...');
    final data = await rootBundle.load('build/lua/hello.lua');
    final bytecode = data.buffer.asUint8List();
    _add('   ${bytecode.length} bytes loaded');
    _add('');

    // 2. Execute via LuaBytecodeRuntime.
    _add('2. Executing bytecode...');
    final runtime = LuaBytecodeRuntime();
    final chunk = await runtime.loadBytecode(bytecode, moduleName: 'hello.lua');
    final moduleResult = await runtime.callFunction(chunk, const <Object?>[]);
    final module = moduleResult as Value;
    _add('   Module loaded: ${module.runtimeType}');

    final greetFn = module['greet'] as Value;
    greetFn.interpreter ??= runtime;
    final greeting = await runtime.callFunction(greetFn, const <Object?>['Flutter']);
    _add('   M.greet("Flutter") = ${(greeting as Value).unwrap()}');

    final addFn = module['add'] as Value;
    addFn.interpreter ??= runtime;
    final sum = await runtime.callFunction(addFn, const <Object?>[2, 3]);
    _add('   M.add(2, 3) = ${(sum as Value).unwrap()}');
    _add('');

    // 3. Set up asset bundle backend for require().
    _add('3. Setting up asset bundle backend...');
    await useAssetBundle(rootBundle, assetRoot: 'build/lua');
    _add('   require("hello") now resolves from assets');
    _add('');

    // 4. Execute Lua source directly.
    _add('4. Direct source execution...');
    final result = await executeCode('return 10 + 20');
    _add('   10 + 20 = ${(result as Value).unwrap()}');
    _add('');

    _add('=== Done ===');
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('flutter_lualike Example')),
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
