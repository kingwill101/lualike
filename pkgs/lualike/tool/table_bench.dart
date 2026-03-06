import 'dart:io';

import 'package:lualike/lualike.dart';

Future<double> _time(Future<void> Function() action) async {
  final stopwatch = Stopwatch()..start();
  await action();
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds / 1000.0;
}

Future<double> _benchmark(LuaLike lua, String label, String template) async {
  final millis = await _time(() async {
    await lua.execute(template);
  });
  return millis;
}

String _codeSequentialAssign(int limit) =>
    '''
local limit = $limit
bench_numeric = {}
for idx = 1, limit do
  bench_numeric[idx] = idx
end
assert(#bench_numeric == limit)
''';

String _codeForwardRead(int limit) =>
    '''
local limit = $limit
local tbl = bench_numeric
local sum = 0
for idx = 1, limit do
  sum = sum + tbl[idx]
end
assert(sum >= 0)
''';

String _codeBackwardRead(int limit) =>
    '''
local limit = $limit
local tbl = bench_numeric
local sum = 0
for idx = limit, 1, -1 do
  sum = sum + tbl[idx]
end
assert(sum >= 0)
''';

String _codeRandomNumeric(int limit) =>
    '''
local limit = $limit
local tbl = bench_numeric
local sum = 0
local idx = 1
for iter = 1, limit do
  idx = ((idx * 37) % limit) + 1
  sum = sum + tbl[idx]
end
assert(sum >= 0)
''';

String _codeStringAssign(int limit) =>
    '''
local limit = $limit
bench_string = {}
for idx = 1, limit do
  bench_string["key" .. idx] = idx
end
''';

String _codeStringLookup(int limit) =>
    '''
local limit = $limit
local tbl = bench_string
local sum = 0
for idx = 1, limit do
  local key = "key" .. idx
  sum = sum + tbl[key]
end
assert(sum >= 0)
''';

String _codeSortAndCheck(int limit) =>
    '''
local limit = $limit
local tbl = {}
for idx = 1, limit do
  tbl[idx] = bench_numeric[idx]
end
table.sort(tbl)
for idx = limit, 2, -1 do
  assert(tbl[idx] >= tbl[idx - 1])
end
''';

Future<Map<String, double>> _runBenchmarks(
  LuaLike lua,
  int limit, {
  int iterations = 5,
}) async {
  final results = <String, List<double>>{
    'seq_assign': [],
    'forward_read': [],
    'backward_read': [],
    'random_read': [],
    'string_assign': [],
    'string_lookup': [],
    'sort_check': [],
  };

  for (var iter = 0; iter < iterations; iter++) {
    results['seq_assign']!.add(
      await _benchmark(lua, 'seq_assign', _codeSequentialAssign(limit)),
    );
    results['forward_read']!.add(
      await _benchmark(lua, 'forward_read', _codeForwardRead(limit)),
    );
    results['backward_read']!.add(
      await _benchmark(lua, 'backward_read', _codeBackwardRead(limit)),
    );
    results['random_read']!.add(
      await _benchmark(lua, 'random_read', _codeRandomNumeric(limit)),
    );
    results['string_assign']!.add(
      await _benchmark(lua, 'string_assign', _codeStringAssign(limit)),
    );
    results['string_lookup']!.add(
      await _benchmark(lua, 'string_lookup', _codeStringLookup(limit)),
    );
    results['sort_check']!.add(
      await _benchmark(lua, 'sort_check', _codeSortAndCheck(limit)),
    );
  }

  final averages = <String, double>{};
  results.forEach((label, timings) {
    final avg =
        timings.reduce((sum, t) => sum + t) / timings.length.clamp(1, 1 << 30);
    averages[label] = avg;
  });
  return averages;
}

Future<void> main(List<String> args) async {
  final size = args.isNotEmpty ? int.parse(args[0]) : 5000;
  final iterations = args.length > 1 ? int.parse(args[1]) : 5;

  print('Lua table benchmark: assignments, lookups, and sort check');
  print('Size: $size elements | iterations: $iterations');

  final lua = LuaLike();
  await lua.execute('bench_numeric = {}\nbench_string = {}');

  final averages = await _runBenchmarks(lua, size, iterations: iterations);

  averages.forEach((label, value) {
    print('${label.padRight(14)} : ${value.toStringAsFixed(2)} ms');
  });

  final logPath = 'benchmarks/table_sort_benchmark.log';
  final file = File(logPath);
  file.createSync(recursive: true);
  file.writeAsStringSync(
    '${DateTime.now().toIso8601String()} size=$size iterations=$iterations '
    'seq_assign=${averages['seq_assign']?.toStringAsFixed(2)} '
    'forward=${averages['forward_read']?.toStringAsFixed(2)} '
    'backward=${averages['backward_read']?.toStringAsFixed(2)} '
    'random=${averages['random_read']?.toStringAsFixed(2)} '
    'str_assign=${averages['string_assign']?.toStringAsFixed(2)} '
    'str_lookup=${averages['string_lookup']?.toStringAsFixed(2)} '
    'sort_check=${averages['sort_check']?.toStringAsFixed(2)}\n',
    mode: FileMode.append,
  );
  print('Result logged to $logPath');
}
