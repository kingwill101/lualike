import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

const String _source = r'''
local function build()
  local buttons = {
    {text = "PLAY", action = function() end, y = 320},
    {text = "CONTROLS", action = function() end, y = 380},
    {text = "QUIT", action = function() end, y = 440},
  }
  return #buttons, buttons[1] and buttons[1].text, buttons[2] and buttons[2].text, buttons[3] and buttons[3].text
end
return build()
''';

Future<Map<String, Object?>> _run(EngineMode mode) async {
  final runtime = LoveScriptRuntime(engineMode: mode, host: LoveHeadlessHost());
  await runtime.execute(_source, scriptPath: '=[table literal repro]');
  return runtime.unwrapGlobalTable('testbed')?.cast<String, Object?>() ?? {};
}

void main() {
  test('table literal with nested function fields', () async {
    for (final mode in [EngineMode.ast, EngineMode.luaBytecode]) {
      final runtime = LoveScriptRuntime(engineMode: mode, host: LoveHeadlessHost());
      final value = await runtime.execute(_source, scriptPath: '=[table literal repro]');
      // ignore: avoid_print
      print('$mode => $value');
    }
  });
}
