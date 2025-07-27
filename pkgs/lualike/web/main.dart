import 'package:lualike/lualike.dart';
import 'package:lualike/src/io/lua_file.dart';
import 'package:lualike/src/io/virtual_io_device.dart';
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:web/web.dart' as web;

import 'output_device.dart';
import 'examples.dart';

void main() {
  final app = LuaLikeWebApp();
  app.initialize();
}

class LuaLikeWebApp {
  late final web.HTMLDivElement sourceCode =
      web.document.querySelector('#sourceCode') as web.HTMLDivElement;
  late final web.HTMLDivElement output =
      web.document.querySelector('#output') as web.HTMLDivElement;
  late final web.HTMLButtonElement runBtn =
      web.document.querySelector('#run') as web.HTMLButtonElement;
  late final web.HTMLButtonElement clearBtn =
      web.document.querySelector('#clear') as web.HTMLButtonElement;
  late final web.HTMLButtonElement clearOutputBtn =
      web.document.querySelector('#clearOutput') as web.HTMLButtonElement;
  late final web.HTMLSelectElement examplesSelect =
      web.document.querySelector('#examples') as web.HTMLSelectElement;
  late final LuaLike luaLike;

  void initialize() {
    // Initialize LuaLike interpreter
    luaLike = LuaLike();

    // Set up virtual devices for web I/O (similar to interactive REPL)
    final stdinDevice = VirtualIODevice();
    final stdoutDevice = WebOutputDevice(output);
    IOLib.defaultInput = LuaFile(stdinDevice);
    IOLib.defaultOutput = LuaFile(stdoutDevice);

    // Populate examples dropdown
    populateExamplesDropdown();

    runBtn.onClick.listen((_) => runCode());
    clearBtn.onClick.listen((_) => clearCode());
    clearOutputBtn.onClick.listen((_) => clearOutput());
    examplesSelect.onChange.listen((_) {
      loadExample();
    });

    // Allow running code with Ctrl+Enter
    sourceCode.onKeyDown.listen((event) {
      if (event.ctrlKey && event.key == 'Enter') {
        event.preventDefault();
        runCode();
      }
    });

    // Show welcome message
    showWelcomeMessage();
  }

  void populateExamplesDropdown() {
    // Clear existing options (except the first placeholder)
    while (examplesSelect.children.length > 1) {
      examplesSelect.removeChild(examplesSelect.children.item(1)!);
    }

    // Add options for each example
    for (final entry in LuaExamples.allExamples) {
      final option =
          web.document.createElement('option') as web.HTMLOptionElement;
      option.value = entry.key;
      option.text = LuaExamples.getDisplayName(entry.key) ?? entry.key;
      examplesSelect.appendChild(option);
    }
  }

  void showWelcomeMessage() {
    appendOutput('🌙 Welcome to LuaLike Web REPL!', 'info');
    appendOutput(
      'Press Ctrl+Enter to run code, or click the Run button.',
      'info',
    );
    appendOutput(
      'Choose an example from the dropdown to get started.\n',
      'info',
    );
  }

  void runCode() async {
    final code = sourceCode.textContent?.trim() ?? '';

    if (code.isEmpty) {
      appendOutput('No code to run!', 'error');
      return;
    }

    // Clear previous output and show running indicator
    clearOutput();
    appendOutput('⚡ Running code...\n', 'info');

    try {
      // Execute the code - print statements will automatically go to our WebOutputDevice
      await luaLike.execute(code);

      appendOutput('✅ Code executed successfully!', 'success');
    } catch (e) {
      appendOutput('❌ Error: $e', 'error');
    }
  }

  void clearCode() {
    sourceCode.textContent = '';
    sourceCode.focus();
  }

  void clearOutput() {
    output.textContent = '';
  }

  void appendOutput(String text, String type) {
    final line = web.document.createElement('div') as web.HTMLDivElement;
    line.className = type;
    line.textContent = text;
    output.appendChild(line);

    // Auto-scroll to bottom
    output.scrollTop = output.scrollHeight;
  }

  void loadExample() {
    final selectedValue = examplesSelect.value;
    if (selectedValue.isEmpty) return;

    final example = LuaExamples.getExample(selectedValue);
    if (example != null) {
      sourceCode.textContent = example;
      // Focus on code area
      sourceCode.focus();
    }
  }
}
