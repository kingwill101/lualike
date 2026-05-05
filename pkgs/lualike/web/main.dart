import 'dart:async';
import 'dart:js_interop';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/io/lua_file.dart';
import 'package:lualike/src/io/memory_io_device.dart';
import 'package:lualike/src/io/virtual_io_device.dart';
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:web/web.dart' as web;

import 'examples.dart';
import 'output_device.dart';

@JS('mountLuaLikeEditor')
external JSPromise<JSAny?> _mountLuaLikeEditor(JSString initialValue);

@JS('getLuaLikeEditorValue')
external JSString _getLuaLikeEditorValue();

@JS('setLuaLikeEditorValue')
external JSAny? _setLuaLikeEditorValue(JSString value);

@JS('focusLuaLikeEditor')
external JSAny? _focusLuaLikeEditor();

void main() {
  web.document.body?.dataset['dartLoaded'] = 'true';
  final app = LuaLikeWebApp();
  app.initialize();
}

class LuaLikeWebApp {
  static final String _starterSnippet =
      LuaExamples.getExample('hello') ??
      '''-- Enter your lualike code here
print("Hello from lualike!")
''';

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
  late final web.HTMLUListElement examplesList =
      web.document.querySelector('#examplesList') as web.HTMLUListElement;
  late final web.HTMLSpanElement currentExampleName =
      web.document.querySelector('#currentExampleName') as web.HTMLSpanElement;
  late final web.HTMLSpanElement runStatus =
      web.document.querySelector('#runStatus') as web.HTMLSpanElement;
  late final web.HTMLElement sidebar =
      web.document.querySelector('.sidebar') as web.HTMLElement;
  late final web.HTMLButtonElement menuToggle =
      web.document.querySelector('#menuToggle') as web.HTMLButtonElement;
  late final LuaLike luaLike;
  bool _plainEditorFallback = false;

  void initialize() {
    // Initialize LuaLike interpreter
    luaLike = LuaLike();

    // Set up in-memory file system for web (so file I/O works properly)
    IOLib.fileSystemProvider.setIODeviceFactory(
      createInMemoryIODevice,
      providerName: 'WebInMemoryFileSystem',
    );

    // Set up virtual devices for web I/O (similar to interactive REPL)
    final stdinDevice = VirtualIODevice();
    final stdoutDevice = WebOutputDevice(output);
    IOLib.defaultInput = createLuaFile(stdinDevice);
    IOLib.defaultOutput = createLuaFile(stdoutDevice);

    // Populate examples
    populateExamplesList();
    unawaited(_mountEditor(_starterSnippet));
    _bindEditorEvents();
    _setRunStatus('Ready', 'ready');
    _updateActiveExample('hello');

    runBtn.onClick.listen((_) => runCode());
    clearBtn.onClick.listen((_) => clearCode());
    clearOutputBtn.onClick.listen((_) => clearOutput());
    menuToggle.onClick.listen((_) => _toggleMenu());

    // Show welcome message
    showWelcomeMessage();
  }

  void populateExamplesList() {
    examplesList.textContent = '';

    // Add options for each example
    for (final entry in LuaExamples.allExamples) {
      final li = web.document.createElement('li') as web.HTMLLIElement;
      li.className = 'example-item';
      li.setAttribute('data-key', entry.key);
      li.textContent = LuaExamples.getDisplayName(entry.key) ?? entry.key;
      li.onClick.listen((_) {
        loadExample(entry.key);
      });
      examplesList.appendChild(li);
    }
  }

  void showWelcomeMessage() {
    appendOutput('🌙 Welcome to LuaLike Web REPL!', 'info');
    appendOutput(
      'Press Ctrl/Cmd+Enter to run code, or click the Run button.',
      'info',
    );
    appendOutput(
      'Explore the examples in the sidebar to get started.\n',
      'info',
    );
  }

  void runCode() async {
    final code = _editorValue().trim();

    if (code.isEmpty) {
      appendOutput('No code to run!', 'error');
      _setRunStatus('Editor empty', 'error');
      return;
    }

    // Clear previous output and show running indicator
    clearOutput();
    _setRunStatus('Running', 'running');
    appendOutput('⚡ Running code...\n', 'info');

    try {
      // Execute the code - print statements will automatically go to our WebOutputDevice
      await luaLike.execute(code);

      appendOutput('\n✅ Code executed successfully!', 'success');
      _setRunStatus('Completed', 'success');
    } catch (e) {
      appendOutput('\n❌ Error: $e', 'error');
      _setRunStatus('Execution error', 'error');
    }
  }

  void clearCode() {
    _setEditorValue('');
    _focusEditor();
    _setRunStatus('Ready', 'ready');
    _updateActiveExample('');
  }

  void clearOutput() {
    output.textContent = '';
  }

  void appendOutput(String text, String type) {
    final line = web.document.createElement('div') as web.HTMLDivElement;
    line.className = 'output-line $type';
    line.textContent = text;
    output.appendChild(line);

    // Auto-scroll to bottom
    output.scrollTop = output.scrollHeight;
  }

  void loadExample(String key) {
    final example = LuaExamples.getExample(key);
    if (example != null) {
      _setEditorValue(example);
      _focusEditor();
      _setRunStatus('Ready', 'ready');
      _updateActiveExample(key);
      _closeMenu();
    }
  }

  void _toggleMenu() {
    sidebar.classList.toggle('open');
  }

  void _closeMenu() {
    sidebar.classList.remove('open');
  }

  void _updateActiveExample(String key) {
    currentExampleName.textContent = key.isEmpty
        ? 'New Script'
        : (LuaExamples.getDisplayName(key) ?? key);

    final items = examplesList.querySelectorAll('.example-item');
    for (var i = 0; i < items.length; i++) {
      final item = items.item(i) as web.HTMLElement;
      if (item.getAttribute('data-key') == key) {
        item.classList.add('active');
      } else {
        item.classList.remove('active');
      }
    }
  }

  void _bindEditorEvents() {
    web.window.addEventListener(
      'lualike-run-request',
      ((web.Event _) {
        runCode();
      }).toJS,
    );
  }

  Future<void> _mountEditor(String initialValue) async {
    sourceCode.setAttribute('data-ready', 'false');
    try {
      await _mountLuaLikeEditor(initialValue.toJS).toDart;
      _plainEditorFallback = false;
    } catch (error) {
      _activatePlainEditorFallback(initialValue, error);
    }
  }

  String _editorValue() {
    if (_plainEditorFallback) {
      return sourceCode.textContent ?? '';
    }
    return _getLuaLikeEditorValue().toDart;
  }

  void _setEditorValue(String value) {
    if (_plainEditorFallback) {
      sourceCode.textContent = value;
      return;
    }
    _setLuaLikeEditorValue(value.toJS);
  }

  void _focusEditor() {
    if (_plainEditorFallback) {
      sourceCode.focus();
      return;
    }
    _focusLuaLikeEditor();
  }

  void _activatePlainEditorFallback(String initialValue, Object error) {
    _plainEditorFallback = true;
    sourceCode.setAttribute('data-ready', 'true');
    sourceCode.setAttribute('data-mode', 'plain');
    sourceCode.contentEditable = 'true';
    sourceCode.tabIndex = 0;
    sourceCode.textContent = initialValue;
    appendOutput(
      '⚠️ Interactive editor unavailable; using plain text fallback. ($error)',
      'info',
    );
    _setRunStatus('Fallback editor', 'ready');
  }

  void _setRunStatus(String label, String state) {
    runStatus.textContent = label;
    runStatus.className = 'status-pill $state';
  }
}
