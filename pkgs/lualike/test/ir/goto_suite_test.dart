@Tags(['ir'])
library;

import 'dart:io';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/ir/runtime.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

Future<void> _executeGotoSource(String source) async {
  final runtime = LualikeIrRuntime();
  runtime.globals
    ..define('_port', Value(true))
    ..define('_soft', Value(true));

  final lua = LuaLike(runtime: runtime);
  await lua.execute(source);
}

String _gotoPrefix(int lineCount) {
  final lines = File(
    'pkgs/lualike/luascripts/test/goto.lua',
  ).readAsLinesSync();
  return lines.take(lineCount).join('\n');
}

String _gotoPrefixWithSyntheticEnd(int lineCount) {
  return '${_gotoPrefix(lineCount)}\nend';
}

void main() {
  test('executes first 162 lines of goto.lua through lowered IR runtime', () async {
    await _executeGotoSource(_gotoPrefix(162));
  });

  test('executes first 260 lines of goto.lua through lowered IR runtime', () async {
    await _executeGotoSource(_gotoPrefix(260));
  });

  test(
    'executes first 289 lines of goto.lua through lowered IR runtime',
    () async {
      await _executeGotoSource(_gotoPrefix(289));
    },
  );

  test(
    'executes first 300 lines of goto.lua through lowered IR runtime',
    () async {
      await _executeGotoSource(_gotoPrefix(300));
    },
  );

  test(
    'executes first 311 lines of goto.lua with synthetic end through lowered IR runtime',
    () async {
      await _executeGotoSource(_gotoPrefixWithSyntheticEnd(311));
    },
  );

  test(
    'executes first 318 lines of goto.lua with synthetic end through lowered IR runtime',
    () async {
      await _executeGotoSource(_gotoPrefixWithSyntheticEnd(318));
    },
  );

  test(
    'executes first 321 lines of goto.lua with synthetic end through lowered IR runtime',
    () async {
      await _executeGotoSource(_gotoPrefixWithSyntheticEnd(321));
    },
  );

  test(
    'executes first 326 lines of goto.lua with synthetic end through lowered IR runtime',
    () async {
      await _executeGotoSource(_gotoPrefixWithSyntheticEnd(326));
    },
  );

  test(
    'executes first 327 lines of goto.lua with synthetic end through lowered IR runtime',
    () async {
      await _executeGotoSource(_gotoPrefixWithSyntheticEnd(327));
    },
  );

  test(
    'executes first 334 lines of goto.lua with synthetic end through lowered IR runtime',
    () async {
      await _executeGotoSource(_gotoPrefixWithSyntheticEnd(334));
    },
  );

  test(
    'executes first 344 lines of goto.lua with synthetic end through lowered IR runtime',
    () async {
      await _executeGotoSource(_gotoPrefixWithSyntheticEnd(344));
    },
  );

  test(
    'executes first 361 lines of goto.lua with synthetic end through lowered IR runtime',
    () async {
      await _executeGotoSource(_gotoPrefixWithSyntheticEnd(361));
    },
  );

  test(
    'executes first 375 lines of goto.lua with synthetic end through lowered IR runtime',
    () async {
      await _executeGotoSource(_gotoPrefixWithSyntheticEnd(375));
    },
  );

  test('executes first 385 lines of goto.lua through lowered IR runtime', () async {
    await _executeGotoSource(_gotoPrefix(385));
  });

  test('executes first 460 lines of goto.lua through lowered IR runtime', () async {
    await _executeGotoSource(_gotoPrefix(460));
  });

  test('executes goto.lua through lowered IR runtime', () async {
    await _executeGotoSource(
      "package.path = 'pkgs/lualike/luascripts/test/?.lua;' .. package.path; "
      "return dofile('pkgs/lualike/luascripts/test/goto.lua')",
    );
  });
}
