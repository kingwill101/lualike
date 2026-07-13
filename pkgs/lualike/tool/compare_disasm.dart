/// Compile a Lua source with both luac55 and lualike, then show both
/// disassemblies so structural differences are easy to spot.
///
/// Usage:
///   dart run tool/compare_disasm.dart `<script.lua>`
///
/// Environment:
///   LUAC55  — path to luac55 binary   (default: ~/Downloads/...)
///   LUALIKE — path to lualike binary  (default: ./lualike)
library;

import 'dart:io';

const _defaultLuac55 =
    '/home/kingwill101/Downloads/lua-5.5.0_Linux68_64_bin/luac55';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run tool/compare_disasm.dart <script.lua>');
    exit(1);
  }

  final sourcePath = args.first;
  final sourceFile = File(sourcePath);
  if (!await sourceFile.exists()) {
    stderr.writeln('File not found: $sourcePath');
    exit(1);
  }

  final shortName = sourcePath.split('/').last;
  final lualikeBin = Platform.environment['LUALIKE'] ?? './lualike';
  final luac55Bin = Platform.environment['LUAC55'] ?? _defaultLuac55;

  print('═══ $shortName ═══════════════════════════════════════════');
  print('');

  // ── luac55 reference ──────────────────────────────────────────
  final luaResult = await Process.run(
    luac55Bin,
    ['-l', '-l', sourcePath],
    runInShell: true,
  );
  print('── luac55 ────────────────────────────────────────────────');
  if (luaResult.exitCode != 0) {
    print('[exit ${luaResult.exitCode}]');
    if ((luaResult.stderr as String).isNotEmpty) print(luaResult.stderr);
  } else {
    print(luaResult.stdout.toString().trimRight());
  }
  print('');

  // ── lualike disassembly ───────────────────────────────────────
  final ourResult = await Process.run(
    lualikeBin,
    ['--disassemble', sourcePath],
    runInShell: true,
  );
  print('── lualike ───────────────────────────────────────────────');
  if (ourResult.exitCode != 0) {
    print('[exit ${ourResult.exitCode}]');
    if ((ourResult.stderr as String).isNotEmpty) print(ourResult.stderr);
  } else {
    print(ourResult.stdout.toString().trimRight());
  }
  print('');
}
