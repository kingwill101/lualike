import 'package:lualike/lualike.dart';
import 'package:lualike/src/io/lua_file.dart';
import 'package:lualike/src/io/virtual_io_device.dart';
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:web/web.dart' as web;

import 'output_device.dart';

void main() {
  final app = LuaLikeWebApp();
  app.initialize();
}

class LuaLikeWebApp {
  late final web.HTMLTextAreaElement sourceCode =
      web.document.querySelector('#sourceCode') as web.HTMLTextAreaElement;
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
    final code = sourceCode.value.trim();

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
    sourceCode.value = '';
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

    final example = getExampleCode(selectedValue);
    sourceCode.value = example;

    // Reset select to default
    examplesSelect.value = '';

    // Focus on code area
    sourceCode.focus();
  }

  String getExampleCode(String exampleType) {
    switch (exampleType) {
      case 'hello':
        return '''-- Hello World Example
print("Hello, World!")
print("Welcome to LuaLike!")

-- Variables and basic operations
local name = "LuaLike"
local version = 5.4
print("Running " .. name .. " " .. version)''';

      case 'fibonacci':
        return '''-- Fibonacci Sequence
function fibonacci(n)
    if n <= 1 then
        return n
    else
        return fibonacci(n - 1) + fibonacci(n - 2)
    end
end

-- Calculate first 10 fibonacci numbers
print("Fibonacci sequence:")
for i = 0, 9 do
    print("F(" .. i .. ") = " .. fibonacci(i))
end''';

      case 'table':
        return '''-- Table Operations
-- Create a table
local fruits = {"apple", "banana", "cherry"}

-- Add elements
fruits[4] = "date"
fruits["favorite"] = "mango"

-- Iterate through table
print("Fruits list:")
for i, fruit in ipairs(fruits) do
    print(i .. ": " .. fruit)
end

-- Table as a map
local person = {
    name = "Alice",
    age = 30,
    city = "New York"
}

print("\\nPerson info:")
for key, value in pairs(person) do
    print(key .. ": " .. value)
end''';

      case 'functions':
        return '''-- Functions and Closures
-- Function with multiple return values
function divmod(a, b)
    local quotient = math.floor(a / b)
    local remainder = a % b
    return quotient, remainder
end

local q, r = divmod(17, 5)
print("17 ÷ 5 = " .. q .. " remainder " .. r)

-- Closure example
function makeCounter(start)
    local count = start or 0
    return function()
        count = count + 1
        return count
    end
end

local counter = makeCounter(10)
print("Counter: " .. counter()) -- 11
print("Counter: " .. counter()) -- 12
print("Counter: " .. counter()) -- 13''';

      case 'metatable':
        return '''-- Metatables Example
-- Create a vector class
Vector = {}
Vector.__index = Vector

function Vector.new(x, y)
    local v = {x = x or 0, y = y or 0}
    setmetatable(v, Vector)
    return v
end

function Vector:__add(other)
    return Vector.new(self.x + other.x, self.y + other.y)
end

function Vector:__tostring()
    return "(" .. self.x .. ", " .. self.y .. ")"
end

-- Create and use vectors
local v1 = Vector.new(3, 4)
local v2 = Vector.new(1, 2)
local v3 = v1 + v2

print("v1 = " .. tostring(v1))
print("v2 = " .. tostring(v2))
print("v1 + v2 = " .. tostring(v3))''';

      case 'string':
        return '''-- String Manipulation
local text = "  Hello, LuaLike World!  "

-- String functions
print("Original: '" .. text .. "'")
print("Length: " .. #text)
print("Upper: " .. string.upper(text))
print("Lower: " .. string.lower(text))
print("Trimmed: '" .. string.gsub(text, "^%s*(.-)%s*\$", "%1") .. "'")

-- Pattern matching
local sentence = "The quick brown fox jumps over the lazy dog"
print("\\nPattern matching:")
print("Words starting with 't': " .. string.gsub(sentence, "%f[%a][Tt]%w*", "[%0]"))

-- String formatting
local name, age = "Alice", 25
print(string.format("\\nHello, %s! You are %d years old.", name, age))''';

      case 'math':
        return '''-- Math Operations
print("Basic Math:")
print("π = " .. math.pi)
print("e = " .. math.exp(1))
print("sqrt(16) = " .. math.sqrt(16))
print("sin(π/2) = " .. math.sin(math.pi/2))
print("log(e) = " .. math.log(math.exp(1)))

-- Random numbers
math.randomseed(os.time and os.time() or 12345)
print("\\nRandom numbers:")
for i = 1, 5 do
    print("Random " .. i .. ": " .. math.random(1, 100))
end

-- Calculations
local function factorial(n)
    if n <= 1 then
        return 1
    else
        return n * factorial(n - 1)
    end
end

print("\\nFactorials:")
for i = 1, 8 do
    print(i .. "! = " .. factorial(i))
end''';

      default:
        return '-- Choose an example from the dropdown above\nprint("Hello from LuaLike!")';
    }
  }
}
