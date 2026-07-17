import 'dart:io';

import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  final config = LuaLikeConfig();
  late bool originalAllowFfi;

  setUp(() {
    originalAllowFfi = config.allowFfi;
  });

  tearDown(() {
    config.allowFfi = originalAllowFfi;
  });

  for (final mode in EngineMode.values) {
    test(
      'ffi binds shared-library functions in ${mode.name}',
      () async {
        config.allowFfi = true;
        final lua = LuaLike(engineMode: mode);
        await lua.execute(r'''
          local ffi = require("ffi")
          local libc = ffi.load("libc.so.6")
          local abs = libc:func("abs", "i32", {"i32"})
          ffi_result = abs(-42)
          libc:close()
        ''');

        expect((lua.getGlobal('ffi_result') as Value).raw, 42);
      },
      skip: Platform.isLinux ? false : 'Linux bridge prototype',
    );

    test(
      'ffi supports definition tables in ${mode.name}',
      () async {
        config.allowFfi = true;
        final lua = LuaLike(engineMode: mode);
        await lua.execute(r'''
          local ffi = require("ffi")
          local libc = ffi.open("libc.so.6", {
            strlen = {
              arguments = {"string"},
              result = "u64",
            },
          })
          ffi_result = libc.functions.strlen("lualike")
          libc:close()
        ''');

        expect((lua.getGlobal('ffi_result') as Value).raw, 7);
      },
      skip: Platform.isLinux ? false : 'Linux bridge prototype',
    );
  }

  test('ffi rejects native loading unless explicitly enabled', () async {
    config.allowFfi = false;
    final lua = LuaLike();
    await lua.execute(r'''
      local ffi = require("ffi")
      local ok, message = pcall(function()
        ffi.load("libc.so.6")
      end)
      ffi_rejected = not ok and string.find(message, "disabled") ~= nil
    ''');

    expect((lua.getGlobal('ffi_rejected') as Value).raw, isTrue);
  });

  test(
    'ffi reports missing symbols and rejects calls after close',
    () async {
      config.allowFfi = true;
      final lua = LuaLike();
      await lua.execute(r'''
        local ffi = require("ffi")
        local libc = ffi.load("libc.so.6")
        local missing_ok, missing_message = pcall(function()
          libc:func("lualike_symbol_that_does_not_exist", "void", {})
        end)
        local abs = libc:func("abs", "i32", {"i32"})
        libc:close()
        local closed_ok, closed_message = pcall(function()
          abs(-1)
        end)
        ffi_errors_ok = not missing_ok
          and string.find(missing_message, "lualike_symbol") ~= nil
          and not closed_ok
          and string.find(closed_message, "closed") ~= nil
      ''');

      expect((lua.getGlobal('ffi_errors_ok') as Value).raw, isTrue);
    },
    skip: Platform.isLinux ? false : 'Linux bridge prototype',
  );
}
