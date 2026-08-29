import 'dart:convert';

import 'package:lualike/lualike.dart';

double _median(List<int> samples) {
  final sorted = List<int>.from(samples)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle].toDouble()
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

Future<void> main(List<String> arguments) async {
  final iterations = arguments.isEmpty ? 1200 : int.parse(arguments.first);
  final sampleCount = arguments.length < 2 ? 7 : int.parse(arguments[1]);
  final elapsedSamples = <int>[];
  final boxSamples = <int>[];
  final localBindSamples = <int>[];
  final identityLocalBindSamples = <int>[];
  Object? checksum;

  for (var sample = 0; sample < sampleCount + 1; sample++) {
    final lua = LuaLike();
    Box.resetBindingDiagnostics();
    Interpreter.resetAstLocalFrameDiagnostics();
    final stopwatch = Stopwatch()..start();
    final result = await lua.execute('''
      local function transform(seed)
        local state = {value = seed}
        local label = "relay"
        local operation = math.abs
        local total = 0
        for i = 1, 16 do
          state.value = state.value + 1
          total = total + operation(-state.value) + #label
        end
        return total
      end

      local checksum = 0
      for i = 1, $iterations do
        checksum = checksum + transform(i % 100)
      end
      return checksum
    ''');
    stopwatch.stop();

    final rawChecksum = result.unwrap();
    checksum ??= rawChecksum;
    if (rawChecksum != checksum) {
      throw StateError('unexpected checksum: $rawChecksum != $checksum');
    }
    if (sample == 0) continue;

    elapsedSamples.add(stopwatch.elapsedMicroseconds);
    boxSamples.add(Box.bindingDiagnostics()['created']! as int);
    final diagnostics = Interpreter.astLocalFrameDiagnostics();
    localBindSamples.add(diagnostics['slotOnlyLocalBinds']! as int);
    identityLocalBindSamples.add(
      diagnostics['slotOnlyIdentityLocalBinds']! as int,
    );
  }

  print(
    jsonEncode(<String, Object?>{
      'iterations': iterations,
      'samples': sampleCount,
      'checksum': checksum,
      'medianElapsedMicros': _median(elapsedSamples),
      'medianCreatedBoxes': _median(boxSamples),
      'medianSlotOnlyLocalBinds': _median(localBindSamples),
      'medianSlotOnlyIdentityLocalBinds': _median(identityLocalBindSamples),
      'slotOnlyIdentityLocalsEnabled': const bool.fromEnvironment(
        'LUALIKE_AST_SLOT_ONLY_IDENTITY_LOCALS',
        defaultValue: true,
      ),
    }),
  );
}
