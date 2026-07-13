/// Quick summary: instruction count and register count for both compilers.
///
/// Usage:  dart run tool/count_profile.dart `<script.lua>`
///         dart run tool/count_profile.dart luascripts/compare/
library;

import 'dart:io';

const _defaultLuac55 =
    '/home/kingwill101/Downloads/lua-5.5.0_Linux68_64_bin/luac55';

Future<void> main(List<String> args) async {
  final target = args.isNotEmpty ? args.first : 'luascripts/compare/';
  final luac55Bin = Platform.environment['LUAC55'] ?? _defaultLuac55;

  if (await Directory(target).exists()) {
    final files = await Directory(target)
        .list()
        .where((e) => e is File && e.path.endsWith('.lua'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    print('${'Script'.padRight(30)} ${'luac55'.padRight(16)}  lualike');
    print(''.padRight(70, '─'));
    for (final f in files) {
      await _showProfile(f, luac55Bin);
    }
  } else if (await File(target).exists()) {
    await _showProfile(File(target), luac55Bin);
  } else {
    stderr.writeln('Not found: $target');
    exit(1);
  }
}

Future<void> _showProfile(File file, String luac55Bin) async {
  final path = file.path;
  final name = path.split('/').last;

  // luac55: instructions on line 1, slots on line 2
  final luaResult = await Process.run(
    luac55Bin,
    ['-l', path],
    runInShell: true,
  );
  String luaLine = '?';
  if (luaResult.exitCode == 0) {
    final lines = (luaResult.stdout as String).split('\n');
    for (var i = 0; i < lines.length - 1; i++) {
      final instrMatch =
          RegExp(r'\((\d+) instructions?').firstMatch(lines[i]);
      final slotMatch =
          RegExp(r'^(\d+)\+? params, (\d+) slots?').firstMatch(lines[i + 1]);
      if (instrMatch != null && slotMatch != null) {
        luaLine = '${instrMatch[1]}i/${slotMatch[2]}s';
        break;
      }
    }
  }

  // lualike: use --disassemble, parse main header
  final ourBin = Platform.environment['LUALIKE'] ?? './lualike';
  final ourResult = await Process.run(
    ourBin,
    ['--disassemble', path],
    runInShell: true,
  );
  String ourLine = '?';
  if (ourResult.exitCode == 0) {
    final lines = (ourResult.stdout as String).split('\n');
    for (var i = 0; i < lines.length - 1; i++) {
      final instrMatch = RegExp(r'\((\d+) instructions?\)').firstMatch(lines[i]);
      if (instrMatch != null) {
        final slotMatch = RegExp(r'(\d+) slots').firstMatch(lines[i + 1]);
        final slots = slotMatch?.group(1) ?? '?';
        ourLine = '${instrMatch[1]}i/$slots';
        break;
      }
    }
  }

  print('${name.padRight(30)} ${luaLine.padRight(16)}  $ourLine');
}
