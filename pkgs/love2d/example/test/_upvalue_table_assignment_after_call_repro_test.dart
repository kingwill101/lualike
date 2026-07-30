import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

const String _source = r'''
local buttons = {}
local function load()
  return 123
end
local function enter()
  local x = load()
  buttons = {
    {text = "PLAY", action = function() end, y = 320},
    {text = "CONTROLS", action = function() end, y = 380},
    {text = "QUIT", action = function() end, y = 440},
  }
  return x
end
local function count()
  return #buttons, buttons[1] and buttons[1].text, buttons[2] and buttons[2].text, buttons[3] and buttons[3].text
end
enter()
return count()
''';

void main() {
  test('upvalue table assignment after call', () async {
    for (final mode in [EngineMode.ast, EngineMode.luaBytecode]) {
      final runtime = LoveScriptRuntime(engineMode: mode, host: LoveHeadlessHost());
      final result = await runtime.execute(_source, scriptPath: '=[upvalue table assignment after call repro]');
      // ignore: avoid_print
      print('$mode => $result');
    }
  });
}
