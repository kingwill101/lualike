// Benchmark: compares compiled vs no-fold timing
import 'dart:io';
import 'dart:math';

void main(List<String> args) {
  final dir = args.isNotEmpty ? args.first : '../luascripts/folding';
  final scripts = [
    '01_literals', '04_logic', '05_tables', '07_functions',
    '08_dead_branches', '10_builtins',
  ];
  
  print('Script              Compiled  No-fold   Speedup');
  print('──────────────────  ────────  ────────  ───────');
  
  for (final name in scripts) {
    final lua = '$dir/${name}.lua';
    final lub = '/tmp/${name}.lub';
    
    // Compile
    Process.runSync('/tmp/lualike_bin', ['--compile', lua, '-o', lub]);
    
    // Time compiled (median of 3)
    final ctimes = <int>[];
    for (var i = 0; i < 3; i++) {
      final sw = Stopwatch()..start();
      Process.runSync('/tmp/lualike_bin', ['--lua-bytecode', lub]);
      sw.stop();
      ctimes.add(sw.elapsedMilliseconds);
    }
    ctimes.sort();
    final ct = ctimes[1];
    
    // Time no-fold (median of 3)
    final ntimes = <int>[];
    for (var i = 0; i < 3; i++) {
      final sw = Stopwatch()..start();
      Process.runSync('/tmp/lualike_bin', ['--lua-bytecode', '--no-fold', lua]);
      sw.stop();
      ntimes.add(sw.elapsedMilliseconds);
    }
    ntimes.sort();
    final nt = ntimes[1];
    
    final pct = ((nt - ct) * 100 / max(nt, 1)).round();
    final sign = pct >= 0 ? '+' : '';
    print('  ${name.padRight(16)}  ${ct.toString().padLeft(4)}ms   ${nt.toString().padLeft(4)}ms   $sign${pct}%');
  }
}
