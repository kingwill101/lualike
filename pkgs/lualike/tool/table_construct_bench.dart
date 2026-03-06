import 'dart:io';

import 'package:lualike/lualike.dart';

Future<double> _time(Future<void> Function() action) async {
  final sw = Stopwatch()..start();
  await action();
  sw.stop();
  return sw.elapsedMicroseconds / 1000.0;
}

Future<double> _bench(LuaLike lua, String name, String script) async {
  final millis = await _time(() async {
    await lua.execute(script);
  });
  return millis;
}

String _literalBench(int size, int iterations) {
  final entries = List<String>.generate(
    size,
    (index) => '${index + 1}.1',
  ).join(',');

  return '''
local sink = 0
local chunk = load('return {$entries}')
for iter = 1, $iterations do
  local t = chunk()
  sink = sink + (t[#t] or 0)
end
assert(sink >= 0)
''';
}

String _reverseAssignBench(int n, int outer, int iterations) =>
    '''
for iter = 1, $iterations do
  local t = {}
  local a = nil
  while not a do
    a = 0
    for i = 1, $outer do
      for j = i, 1, -1 do
        a = a + 1
        t[j] = 1
      end
    end
  end
  assert(t[1] and t[$n] and not t[0] and not t[$n + 1])
end
''';

String _varargConstructorBench(int fanout, int iterations) =>
    '''
local function producer(limit)
  local out = {}
  for i = 1, limit do
    out[i] = i
  end
  out.n = limit
  return out
end

for iter = 1, $iterations do
  local src = producer($fanout)
  local t = {table.unpack(src, 1, src.n)}
  assert(#t == src.n)
end
''';

Future<void> main(List<String> args) async {
  final literalSize = args.isNotEmpty ? int.parse(args[0]) : 512;
  final iterations = args.length > 1 ? int.parse(args[1]) : 50;
  final reverseN = args.length > 2 ? int.parse(args[2]) : 120;

  final lua = LuaLike();

  final reverseIterations = iterations.clamp(1, 5);
  final varargIterations = iterations * 2;

  final benches = <String, String>{
    'literal_construct': _literalBench(literalSize, iterations),
    'reverse_assign': _reverseAssignBench(
      reverseN,
      reverseN,
      reverseIterations,
    ),
    'vararg_constructor': _varargConstructorBench(
      literalSize,
      varargIterations,
    ),
  };

  print('Table construction benchmark');
  print('literal size: $literalSize | iterations: $iterations');

  final logPath = 'benchmarks/table_construct_benchmark.log';
  final logFile = File(logPath)..createSync(recursive: true);

  final buffer = StringBuffer()
    ..write(DateTime.now().toIso8601String())
    ..write(' size=$literalSize iterations=$iterations reverseN=$reverseN ');

  for (final entry in benches.entries) {
    final millis = await _bench(lua, entry.key, entry.value);
    print('${entry.key.padRight(18)} : ${millis.toStringAsFixed(2)} ms');
    buffer.write('${entry.key}=${millis.toStringAsFixed(2)} ');
  }

  buffer.write('\n');
  logFile.writeAsStringSync(buffer.toString(), mode: FileMode.append);
  print('Result logged to $logPath');
}
