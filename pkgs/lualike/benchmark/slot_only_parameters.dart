import 'dart:convert';

import 'package:lualike/lualike.dart';

Future<void> main(List<String> arguments) async {
  final iterations = arguments.isEmpty ? 20000 : int.parse(arguments.first);
  final lua = LuaLike();
  Box.resetBindingDiagnostics();
  Interpreter.resetAstLocalFrameDiagnostics();

  final stopwatch = Stopwatch()..start();
  final result = await lua.execute('''
    local function mutate(value)
      value = value + 1
      value = value * 2
      return value
    end

    local checksum = 0
    for i = 1, $iterations do
      checksum = checksum + mutate(i % 100)
    end
    return checksum
  ''');
  stopwatch.stop();

  print(
    jsonEncode(<String, Object?>{
      'iterations': iterations,
      'checksum': result.unwrap(),
      'elapsedMicros': stopwatch.elapsedMicroseconds,
      'bindings': Box.bindingDiagnostics(),
      'localFrames': Interpreter.astLocalFrameDiagnostics(),
      'slotOnlyParametersEnabled': const bool.fromEnvironment(
        'LUALIKE_AST_SLOT_ONLY_PARAMETERS',
        defaultValue: true,
      ),
    }),
  );
}
