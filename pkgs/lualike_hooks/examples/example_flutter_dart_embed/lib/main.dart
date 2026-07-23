import 'package:flutter/material.dart';
import 'package:lualike/lualike.dart';

import 'generated/lua/hello.lua.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key, this.autoRun = true});

  final bool autoRun;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dart Embed Mode',
      theme: ThemeData(colorSchemeSeed: Colors.orange, useMaterial3: true),
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
    _add('=== Dart Embed Mode ===');
    _add('');

    _add('Build hook generates a Dart file under lib/generated/lua:');
    _add('  assets/lua/hello.lua → lib/generated/lua/hello.lua.dart');
    _add('');

    _add('Generated file provides:');
    _add('  final List<int> helloLuaModule = <int>[...]');
    _add('');

    _add('At runtime, pass the constant to LuaBytecodeRuntime:');
    final runtime = LuaBytecodeRuntime();
    final chunk = await runtime.loadBytecode(
      helloLuaModule,
      moduleName: 'hello.lua',
    );
    final moduleResult = await runtime.callFunction(chunk, const <Object?>[]);
    final module = moduleResult as Value;
    _add('  module type: ${module.runtimeType}');

    final greetFn = module['greet'] as Value;
    greetFn.interpreter ??= runtime;
    final greeting = await runtime.callFunction(greetFn, const <Object?>['Flutter']);
    _add('  M.greet("Flutter") = ${(greeting as Value).unwrap()}');

    final addFn = module['add'] as Value;
    addFn.interpreter ??= runtime;
    final sum = await runtime.callFunction(addFn, const <Object?>[2, 3]);
    _add('  M.add(2, 3) = ${(sum as Value).unwrap()}');
    _add('');

    _add('Benefits:');
    _add('  - no asset bundle needed');
    _add('  - bytecode is a Dart constant');
    _add('  - imports from lib/generated/');
    _add('');

    _add('=== Done ===');
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dart Embed Mode')),
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
