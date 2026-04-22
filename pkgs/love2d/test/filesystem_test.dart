import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/io/io_device.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_bindings.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:path/path.dart' as p;

void main() {
  test('filesystem adapter uses upstream Linux appdata fallbacks', () {
    final fallbackAdapter = LoveLualikeFilesystemAdapter(
      environment: const <String, String>{'HOME': '/users/tester'},
      isWindows: false,
      isLinux: true,
      isMacOS: false,
      workingDirectoryProvider: () => '/work',
    );
    final xdgAdapter = LoveLualikeFilesystemAdapter(
      environment: const <String, String>{
        'HOME': '/users/tester',
        'XDG_DATA_HOME': '/xdg/data',
      },
      isWindows: false,
      isLinux: true,
      isMacOS: false,
      workingDirectoryProvider: () => '/work',
    );

    expect(fallbackAdapter.userDirectory, '/users/tester');
    expect(fallbackAdapter.appdataDirectory, '/users/tester/.local/share');
    expect(xdgAdapter.appdataDirectory, '/xdg/data');
  });

  test(
    'filesystem save directory naming follows the active adapter platform',
    () async {
      final adapter = _TestLoveFilesystemAdapter(
        isWindows: true,
        isLinux: false,
        isMacOS: false,
      );
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'setIdentity'],
          const <Object?>['game'],
        ),
        isNull,
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'getSaveDirectory']),
        '/appdata/LOVE/game',
      );
    },
  );

  test(
    'filesystem setIdentity accepts empty identities like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'setIdentity'],
          const <Object?>[''],
        ),
        isNull,
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'getIdentity']),
        '',
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'getSaveDirectory']),
        '/appdata/love',
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['empty-identity.txt', 'alpha'],
        ),
        isTrue,
      );
      expect(
        String.fromCharCodes(
          adapter.fileBytes('/appdata/love/empty-identity.txt'),
        ),
        'alpha',
      );
    },
  );

  test(
    'filesystem failed setIdentity calls leave identity and save directory unchanged',
    () async {
      final adapter = _TestLoveFilesystemAdapter(appdataDirectory: null);
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);

      await expectLater(
        () => _call(
          runtime,
          const ['love', 'filesystem', 'setIdentity'],
          const <Object?>['game'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'Could not set write directory.',
          ),
        ),
      );

      expect(
        await _call(runtime, const ['love', 'filesystem', 'getIdentity']),
        '',
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'getSaveDirectory']),
        '',
      );
    },
  );

  test('filesystem module resolves source, mounts, and loads chunks', () async {
    final adapter = _TestLoveFilesystemAdapter();
    adapter.addFile('/source/scripts/loaded.lua', 'return 123');
    adapter.addFile('/mods/extra/bonus.lua', 'return 456');

    final runtime = LoveScriptRuntime(filesystemAdapter: adapter);

    final interpreter = runtime.runtime as Interpreter;
    await _call(
      interpreter,
      const ['love', 'filesystem', 'setIdentity'],
      const <Object?>['game'],
    );
    await _call(
      interpreter,
      const ['love', 'filesystem', 'setSource'],
      const <Object?>['/source'],
    );
    _allowStringMount(interpreter, '/mods/extra');
    await _call(
      interpreter,
      const ['love', 'filesystem', 'mount'],
      const <Object?>['/mods/extra', 'mods', true],
    );

    final sourceRead = await _call(
      interpreter,
      const ['love', 'filesystem', 'read'],
      const <Object?>['scripts/loaded.lua'],
    );
    final modInfo = await _call(
      interpreter,
      const ['love', 'filesystem', 'getInfo'],
      const <Object?>['mods'],
    );
    final modItems = await _call(
      interpreter,
      const ['love', 'filesystem', 'getDirectoryItems'],
      const <Object?>['mods'],
    );
    final rootItems = await _call(
      interpreter,
      const ['love', 'filesystem', 'getDirectoryItems'],
      const <Object?>[''],
    );
    final chunk = await _callRawPath(
      interpreter,
      const ['love', 'filesystem', 'load'],
      const <Object?>['scripts/loaded.lua'],
    );
    final loadedValue = await interpreter.callFunction(
      chunk! as Value,
      const [],
    );

    expect(sourceRead, <Object?>['return 123', 10]);
    expect(
      await _call(interpreter, const [
        'love',
        'filesystem',
        'getSourceBaseDirectory',
      ]),
      '/',
    );
    expect(
      await _call(
        interpreter,
        const ['love', 'filesystem', 'getRealDirectory'],
        const <Object?>['scripts/loaded.lua'],
      ),
      '/source',
    );
    expect(
      await _call(
        interpreter,
        const ['love', 'filesystem', 'getRealDirectory'],
        const <Object?>['mods/bonus.lua'],
      ),
      '/mods/extra',
    );
    expect(modInfo, isA<Map>());
    expect((modInfo! as Map)['type'], 'directory');
    expect((modItems as Map)[1], 'bonus.lua');
    expect((rootItems as Map).containsValue('mods'), isTrue);
    expect(_unwrap(loadedValue), 123);

    final saveDir = await _call(runtime.runtime as Interpreter, const [
      'love',
      'filesystem',
      'getSaveDirectory',
    ]);
    expect(saveDir, isA<String>());
    expect(saveDir as String, contains('game'));
  });

  test(
    'filesystem getSourceBaseDirectory returns empty for single-segment relative sources like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('game/main.lua', 'return true');

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['game'],
      );

      expect(
        await _call(interpreter, const ['love', 'filesystem', 'getSource']),
        'game',
      );
      expect(
        await _call(interpreter, const [
          'love',
          'filesystem',
          'getSourceBaseDirectory',
        ]),
        '',
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['main.lua'],
        ),
        'game',
      );
    },
  );

  test(
    'filesystem setSource mounts zipped .love files as source roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/main.lua', 'return "directory"');
      adapter.addFileBytes(
        '/source/game.love',
        _encodeZip(<String, String>{
          'main.lua': 'return "archive"',
          'lib/tool.lua': 'return { answer = 99, label = "archive" }',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source/game.love'],
      );

      final sourceRead = await _call(
        interpreter,
        const ['love', 'filesystem', 'read'],
        const <Object?>['main.lua'],
      );
      final rootItems = await _call(
        interpreter,
        const ['love', 'filesystem', 'getDirectoryItems'],
        const <Object?>[''],
      );
      final toolResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('lib.tool')],
        ),
      );
      final tool = (toolResult.first as Value).unwrap() as Map;

      expect(
        await _call(interpreter, const ['love', 'filesystem', 'getSource']),
        '/source/game.love',
      );
      expect(
        await _call(interpreter, const [
          'love',
          'filesystem',
          'getSourceBaseDirectory',
        ]),
        '/source',
      );
      expect(sourceRead, <Object?>['return "archive"', 16]);
      expect(rootItems, <Object?, Object?>{1: 'lib', 2: 'main.lua'});
      expect(tool['answer'], 99);
      expect(tool['label'], 'archive');
      expect(_unwrap(toolResult[1]), 'lib/tool.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['main.lua'],
        ),
        '/source/game.love',
      );
    },
  );

  test(
    'filesystem setSource mounts fused executable-style zip sources',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/bin/lualike-test',
        _encodePrefixedZip(<String, String>{
          'main.lua': 'return "prefixed archive"',
          'lib/tool.lua': 'return { answer = 123 }',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/bin/lualike-test'],
      );

      expect(
        await _call(interpreter, const ['love', 'filesystem', 'getSource']),
        '/bin/lualike-test',
      );
      expect(
        await _call(interpreter, const [
          'love',
          'filesystem',
          'getSourceBaseDirectory',
        ]),
        '/bin',
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['main.lua'],
        ),
        <Object?>['return "prefixed archive"', 25],
      );

      final toolResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('lib.tool')],
        ),
      );
      final tool = (toolResult.first as Value).unwrap() as Map;
      expect(tool['answer'], 123);
      expect(_unwrap(toolResult[1]), 'lib/tool.lua');
    },
  );

  test(
    'filesystem fused mode can mount getSourceBaseDirectory like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/bin/lualike-test',
        _encodePrefixedZip(<String, String>{
          'main.lua': 'return "prefixed archive"',
        }),
      );
      adapter.addFile('/bin/sidecar.lua', 'return "sidecar"');

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'setFused'],
          const <Object?>[true],
        ),
        isNull,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/bin/lualike-test'],
      );

      final sourceBase = await _call(interpreter, const [
        'love',
        'filesystem',
        'getSourceBaseDirectory',
      ]);

      expect(sourceBase, '/bin');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[sourceBase, 'fusedbase', true],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['fusedbase/sidecar.lua'],
        ),
        <Object?>['return "sidecar"', 16],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['fusedbase/sidecar.lua'],
        ),
        '/bin',
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          <Object?>[sourceBase],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['fusedbase/sidecar.lua'],
        ),
        isNull,
      );
    },
  );

  test(
    'filesystem direct setSource reuses cached archive source roots on the same adapter',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/main.lua', 'return "directory"');
      adapter.addFileBytes(
        '/source/game.love',
        _encodeZip(<String, String>{
          'main.lua': 'return "archive"',
          'lib/tool.lua': 'return { answer = 77 }',
        }),
      );

      final firstRuntime = LoveScriptRuntime(filesystemAdapter: adapter);
      final firstInterpreter = firstRuntime.runtime as Interpreter;

      await _call(
        firstInterpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source/game.love'],
      );

      final secondRuntime = LoveScriptRuntime(filesystemAdapter: adapter);
      final secondFilesystem = LoveFilesystemState.of(secondRuntime.runtime);

      expect(secondFilesystem.setSource('/source/game.love'), isTrue);
      expect(
        String.fromCharCodes(
          (await secondFilesystem.readAllBytes('main.lua'))!,
        ),
        'return "archive"',
      );
      expect(
        await secondFilesystem.getRealDirectory('main.lua'),
        '/source/game.love',
      );
    },
  );

  test(
    'filesystem direct setSource rejects unresolved archive-looking paths',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/source/game.love',
        _encodeZip(<String, String>{'main.lua': 'return "archive"'}),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final filesystem = LoveFilesystemState.of(runtime.runtime);

      expect(filesystem.setSource('/source/game.love'), isFalse);
      expect(await filesystem.readAllBytes('main.lua'), isNull);
    },
  );

  test(
    'filesystem direct setSource treats .7z paths as archive-like and rejects parent fallback',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes('/source/game.7z', _fake7zBytes());

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final filesystem = LoveFilesystemState.of(runtime.runtime);

      expect(filesystem.setSource('/source/game.7z'), isFalse);
      expect(await filesystem.readAllBytes('main.lua'), isNull);
    },
  );

  test(
    'filesystem setSource rejects invalid existing .love archives',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/game.love', 'not an archive');

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await expectLater(
        () => _call(
          interpreter,
          const ['love', 'filesystem', 'setSource'],
          const <Object?>['/source/game.love'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Could not set source.'),
          ),
        ),
      );

      expect(
        await _call(interpreter, const ['love', 'filesystem', 'getSource']),
        '',
      );
    },
  );

  test('filesystem setSource rejects invalid existing .7z archives', () async {
    final adapter = _TestLoveFilesystemAdapter();
    adapter.addFileBytes('/source/game.7z', _fake7zBytes());

    final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
    final interpreter = runtime.runtime as Interpreter;

    await expectLater(
      () => _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source/game.7z'],
      ),
      throwsA(
        isA<LuaError>().having(
          (error) => error.message,
          'message',
          contains('Could not set source.'),
        ),
      ),
    );

    expect(
      await _call(interpreter, const ['love', 'filesystem', 'getSource']),
      '',
    );
  });

  test(
    'filesystem setSource mounts existing .7z archives',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/source/game.7z',
        _encode7z(<String, String>{
          'main.lua': 'return "archive-7z"',
          'lib/tool.lua': 'return { answer = 77, label = "archive-7z" }',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'setSource'],
          const <Object?>['/source/game.7z'],
        ),
        isNull,
      );
      expect(
        await _call(interpreter, const ['love', 'filesystem', 'getSource']),
        '/source/game.7z',
      );

      final sourceRead = await _call(
        interpreter,
        const ['love', 'filesystem', 'read'],
        const <Object?>['main.lua'],
      );
      expect(sourceRead, <Object?>['return "archive-7z"', 19]);

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['?.lua;?/init.lua'],
      );
      final toolResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('lib.tool')],
        ),
      );
      expect(_unwrap(toolResult[1]), 'lib/tool.lua');
      final tool = (toolResult.first as Value).unwrap() as Map;
      expect(tool['answer'], 77);
      expect(tool['label'], 'archive-7z');
    },
    skip: _sevenZipSupportSkipReason,
  );

  test(
    'filesystem setSource rejects missing archive-looking source paths',
    () async {
      final runtime = LoveScriptRuntime(
        filesystemAdapter: _TestLoveFilesystemAdapter(),
      );
      final interpreter = runtime.runtime as Interpreter;

      await expectLater(
        () => _call(
          interpreter,
          const ['love', 'filesystem', 'setSource'],
          const <Object?>['/source/missing.love'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Could not set source.'),
          ),
        ),
      );

      expect(
        await _call(interpreter, const ['love', 'filesystem', 'getSource']),
        '',
      );
    },
  );

  test(
    'filesystem setSource rejects non-mountable file paths instead of using their parent directory',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/main.lua', 'return "not a source root"');

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await expectLater(
        () => _call(
          interpreter,
          const ['love', 'filesystem', 'setSource'],
          const <Object?>['/source/main.lua'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Could not set source.'),
          ),
        ),
      );

      expect(
        await _call(interpreter, const ['love', 'filesystem', 'getSource']),
        '',
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['main.lua'],
        ),
        <Object?>[null, 'Could not open file main.lua. Does not exist.'],
      );
    },
  );

  test(
    'filesystem does not fall back to unmounted direct filesystem paths',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('loose.txt', 'payload');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      final filesystem = LoveFilesystemState.of(runtime);

      expect(await filesystem.readAllBytes('loose.txt'), isNull);
      expect(await filesystem.getInfo('loose.txt'), isNull);
      expect(await filesystem.getRealDirectory('loose.txt'), isNull);

      final readResult = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['loose.txt'],
        ),
      );
      expect(readResult[0], isNull);
      expect(
        _unwrap(readResult[1]),
        'Could not open file loose.txt. Does not exist.',
      );

      final realDirectoryResult = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['loose.txt'],
        ),
      );
      expect(realDirectoryResult[0], isNull);
      expect(_unwrap(realDirectoryResult[1]), 'File does not exist on disk.');
    },
  );

  test(
    'filesystem integrates with require through package.searchers',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile(
        '/source/lib/tool.lua',
        'return { answer = 42, label = "source" }',
      );
      adapter.addFile(
        '/mods/extra/custom/init.lua',
        'return { answer = 7, label = "mounted" }',
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final toolResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('lib.tool')],
        ),
      );
      _allowStringMount(interpreter, '/mods/extra');
      await _call(
        interpreter,
        const ['love', 'filesystem', 'mount'],
        const <Object?>['/mods/extra', 'mods', true],
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['mods/?.lua;mods/?/init.lua;?.lua;?/init.lua'],
      );
      final customResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('custom')],
        ),
      );
      final toolAgainResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('lib.tool')],
        ),
      );

      final tool = (toolResult.first as Value).unwrap() as Map;
      final custom = (customResult.first as Value).unwrap() as Map;

      expect(
        await _call(interpreter, const [
          'love',
          'filesystem',
          'getRequirePath',
        ]),
        'mods/?.lua;mods/?/init.lua;?.lua;?/init.lua',
      );
      expect(tool['answer'], 42);
      expect(tool['label'], 'source');
      expect(_unwrap(toolResult[1]), 'lib/tool.lua');
      expect(identical(toolResult.first, toolAgainResult.first), isTrue);
      expect(custom['answer'], 7);
      expect(custom['label'], 'mounted');
      expect(_unwrap(customResult[1]), 'mods/custom/init.lua');
    },
  );

  test(
    'filesystem package searcher coerces numeric module names like upstream',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/123.lua', 'return "numeric-module"');

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final requireResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          const <Object?>[123],
        ),
      );

      expect(_unwrap(requireResult.first), 'numeric-module');
      expect(_unwrap(requireResult[1]), '123.lua');
    },
  );

  test(
    'filesystem package searcher preserves LOVE missing-module and open-error messages',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/broken.lua', 'return true');
      adapter.failOpen('/source/broken.lua', 'permission denied');

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      await expectLater(
        () => _callRawPath(
          interpreter,
          const ['require'],
          const <Object?>['missing.module'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains("no 'missing/module' in LOVE game directories."),
          ),
        ),
      );

      await expectLater(
        () => _callRawPath(interpreter, const ['require'], const <Object?>['']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains("no '' in LOVE game directories."),
          ),
        ),
      );

      await expectLater(
        () => _callRawPath(
          interpreter,
          const ['require'],
          const <Object?>['broken'],
        ),
        throwsA(isA<LuaError>()),
      );

      final luaSearcherResult = _rawResults(
        await _callHostFunction(
          _packageSearchers(interpreter)[1] as Value,
          const <Object?>['broken'],
        ),
      );
      expect(_unwrap(luaSearcherResult[1]), 'broken.lua');

      await expectLater(
        () => _callHostFunction(
          luaSearcherResult.first! as Value,
          const <Object?>['broken', 'broken.lua'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains("error loading module 'broken' from file 'broken.lua'"),
              contains('permission denied'),
            ),
          ),
        ),
      );
    },
  );

  test(
    'filesystem package searcher preserves LOVE syntax-error formatting',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/broken.lua', 'local =');

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final luaSearcherResult = _rawResults(
        await _callHostFunction(
          _packageSearchers(interpreter)[1] as Value,
          const <Object?>['broken'],
        ),
      );
      expect(_unwrap(luaSearcherResult[1]), 'broken.lua');

      await expectLater(
        () => _callHostFunction(
          luaSearcherResult.first! as Value,
          const <Object?>['broken', 'broken.lua'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains("error loading module 'broken' from file 'broken.lua'"),
              contains('Syntax error: '),
            ),
          ),
        ),
      );
    },
  );

  test(
    'filesystem package interop installs LOVE lua and C searchers in order',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/main.lua', 'return true');
      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setCRequirePath'],
        const <Object?>['native/??;mods/?'],
      );

      final packageTable = _packageTable(interpreter);
      final searchers = _packageSearchers(interpreter);
      final loadersValue = packageTable['loaders'];

      expect(_unwrap(packageTable['path']), '?.lua;?/init.lua');
      expect(_unwrap(packageTable['cpath']), 'native/??;mods/?');
      expect(loadersValue, same(packageTable['searchers']));
      expect(searchers.length, greaterThanOrEqualTo(4));

      final luaSearcherResult = await _callHostFunction(
        searchers[1] as Value,
        const <Object?>['missing.module'],
      );
      final extSearcherResult = await _callHostFunction(
        searchers[2] as Value,
        const <Object?>['missing.module'],
      );

      expect(
        _unwrap(luaSearcherResult),
        "\n\tno 'missing/module' in LOVE game directories.",
      );
      expect(
        _unwrap(extSearcherResult),
        "\n\tno file 'missing/module' in LOVE paths.",
      );
    },
  );

  test(
    'filesystem getDirectoryItems ignores extra args like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/main.lua', 'return true');
      adapter.addFile('/source/states/menu.lua', 'return {}');
      adapter.addFileBytes('/source/sprites/logo.png', const <int>[1, 2, 3, 4]);

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      final seen = <Object?>[];

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final items = await _call(
        interpreter,
        const ['love', 'filesystem', 'getDirectoryItems'],
        <Object?>[
          '',
          Value(
            _TestBuiltinFunction((args) {
              seen.add(_unwrap(args.isNotEmpty ? args.first : null));
              return null;
            }),
            functionName: 'directoryItemsCallback',
          ),
        ],
      );

      expect(items, <Object?, Object?>{
        1: 'main.lua',
        2: 'sprites',
        3: 'states',
      });
      expect(
        seen,
        isEmpty,
        reason: 'LOVE 11.5 ignores extra args in the C++ wrapper',
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getDirectoryItems'],
          const <Object?>['', 123],
        ),
        <Object?, Object?>{1: 'main.lua', 2: 'sprites', 3: 'states'},
      );
    },
  );

  test(
    'filesystem C-module searcher resolves cpath candidates without native loading',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes('/source/native/mod.so', const <int>[1, 2, 3, 4]);

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final searchers = _packageSearchers(interpreter);
      final extSearcherResult = _rawResults(
        await _callHostFunction(searchers[2] as Value, const <Object?>[
          'native.mod',
        ]),
      );

      expect(_unwrap(extSearcherResult[1]), 'native/mod.so');
      await expectLater(
        () => _callHostFunction(
          extSearcherResult.first! as Value,
          const <Object?>['native.mod', 'native/mod.so'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains("C library 'native/mod' is incompatible."),
          ),
        ),
      );
    },
  );

  test(
    'filesystem File and FileData wrappers expose LOVE-style methods',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game'],
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['notes.txt'],
      );
      expect(file, isA<Map>());

      final closedFile = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['notes-closed.txt', false],
      );
      expect(closedFile, isA<Map>());
      expect(
        await _callMethod(closedFile!, 'isOpen'),
        isFalse,
        reason: 'LOVE ignores non-string optional mode arguments here',
      );

      expect(await _callMethod(file!, 'type'), 'File');
      expect(
        await _callMethod(file, 'typeOf', const <Object?>['Object']),
        isTrue,
      );
      expect(await _callMethod(file, 'getExtension'), 'txt');
      expect(await _callMethod(file, 'open', const <Object?>['w']), isTrue);
      expect(
        await _callMethod(file, 'setBuffer', const <Object?>['full', 64]),
        isTrue,
      );
      expect(await _callMethod(file, 'getBuffer'), <Object?>['full', 64]);
      expect(
        await _callMethod(file, 'write', const <Object?>['alpha\nbeta\n']),
        isTrue,
      );
      expect(await _callMethod(file, 'tell'), 11);
      expect(await _callMethod(file, 'close'), isTrue);

      expect(await _callMethod(file, 'open', const <Object?>['r']), isTrue);
      expect(await _callMethod(file, 'getMode'), 'r');
      expect(await _callMethod(file, 'getSize'), 11);
      expect(await _callMethod(file, 'read'), <Object?>['alpha\nbeta\n', 11]);
      expect(await _callMethod(file, 'seek', const <Object?>[0]), isTrue);

      final iterator = await _callMethod(file, 'lines');
      expect(await _callBuiltin(iterator!), 'alpha');
      expect(await _callMethod(file, 'tell'), 0);
      expect(await _callBuiltin(iterator), 'beta');
      expect(await _callMethod(file, 'tell'), 0);
      expect(await _callBuiltin(iterator), isNull);
      expect(await _callMethod(file, 'isOpen'), isFalse);

      final fileData = await _call(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        const <Object?>['notes.txt'],
      );
      expect(fileData, isA<Map>());
      expect(await _callMethod(fileData!, 'type'), 'FileData');
      expect(
        await _callMethod(fileData, 'typeOf', const <Object?>['Data']),
        isTrue,
      );
      expect(await _callMethod(fileData, 'getFilename'), 'notes.txt');
      expect(await _callMethod(fileData, 'getSize'), 11);
      expect(await _callMethod(fileData, 'getString'), 'alpha\nbeta\n');

      final clone = await _callMethod(fileData, 'clone');
      expect(await _callMethod(clone!, 'getString'), 'alpha\nbeta\n');

      expect(await _callMethod(file, 'release'), isTrue);
      expect(await _callMethod(file, 'release'), isFalse);
    },
  );

  test(
    'filesystem string arguments follow upstream Lua coercion rules',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game'],
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>[123, 'alpha'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>[123, 2],
        ),
        <Object?>['al', 2],
        reason:
            'love.filesystem.read only treats exact strings as container-type overloads',
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>[123],
        ),
        isA<Map>(),
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'setRequirePath'],
          const <Object?>[456],
        ),
        isNull,
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'getRequirePath']),
        '456',
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'append'],
          const <Object?>[123, 45],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>[123],
        ),
        <Object?>['alpha45', 7],
      );
      final numericFileData = await _call(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        const <Object?>[67, 'digits.txt'],
      );
      expect(numericFileData, isA<Map>());
      expect(await _callMethod(numericFileData!, 'getString'), '67');
      expect(await _callMethod(numericFileData, 'getFilename'), 'digits.txt');

      await expectLater(
        () => _call(
          runtime,
          const ['love', 'filesystem', 'newFile'],
          const <Object?>['notes.txt', 789],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'love.filesystem.newFile invalid file mode "789"',
          ),
        ),
      );
    },
  );

  test(
    'filesystem supports write, append, info filters, data reads, and removal',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game'],
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'createDirectory'],
          const <Object?>['saves/slot1'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['saves/slot1/note.txt', 'alpha\r\n'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'append'],
          const <Object?>['saves/slot1/note.txt', 'beta'],
        ),
        isTrue,
      );

      final reusedInfoTable = <Object?, Object?>{'stale': true};
      final info = await _call(
        runtime,
        const ['love', 'filesystem', 'getInfo'],
        <Object?>['saves/slot1/note.txt', 'file', reusedInfoTable],
      );
      expect(info, isA<Map>());
      expect(reusedInfoTable['type'], 'file');
      expect(reusedInfoTable['size'], 11);
      expect(reusedInfoTable['modtime'], 0);

      final reusedDirectoryInfoTable = <Object?, Object?>{
        'type': 'stale',
        'size': 123,
        'modtime': 456,
      };
      final directoryInfo = await _call(
        runtime,
        const ['love', 'filesystem', 'getInfo'],
        <Object?>['saves', reusedDirectoryInfoTable],
      );
      expect(directoryInfo, same(reusedDirectoryInfoTable));
      expect(reusedDirectoryInfoTable['type'], 'directory');
      expect(
        reusedDirectoryInfoTable['size'],
        123,
        reason: 'LOVE leaves existing size fields intact on reused tables',
      );
      expect(reusedDirectoryInfoTable['modtime'], 0);

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['saves/slot1/note.txt', 'directory'],
        ),
        isNull,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getInfo'],
          <Object?>['saves/slot1/note.txt', null, reusedInfoTable],
        ),
        isA<Map>(),
        reason:
            'LOVE ignores a nil filter slot and does not reuse argument 3 as the table',
      );
      expect(reusedInfoTable['stale'], isTrue);
      await expectLater(
        () => _call(
          runtime,
          const ['love', 'filesystem', 'getInfo'],
          <Object?>['saves/slot1/note.txt', 123, reusedInfoTable],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'love.filesystem.getInfo invalid file type "123"',
          ),
        ),
      );
      final ignoredThirdTable = <Object?, Object?>{'ignored': true};
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getInfo'],
          <Object?>['saves/slot1/note.txt', reusedInfoTable, ignoredThirdTable],
        ),
        same(reusedInfoTable),
        reason:
            'LOVE only treats argument 3 as the table when argument 2 is a filter string',
      );

      final readData = await _call(
        runtime,
        const ['love', 'filesystem', 'read'],
        const <Object?>['data', 'saves/slot1/note.txt'],
      );
      expect(readData, isA<List<Object?>>());
      final readTuple = readData! as List<Object?>;
      expect(readTuple[0], isA<Map>());
      expect(readTuple[1], 11);
      expect(await _callMethod(readTuple[0]!, 'getString'), 'alpha\r\nbeta');
      expect(await _callMethod(readTuple[0]!, 'getExtension'), 'txt');

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'remove'],
          const <Object?>['saves/slot1/note.txt'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['saves/slot1/note.txt'],
        ),
        isNull,
      );
    },
  );

  test(
    'filesystem remove only deletes files and empty directories like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game'],
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'createDirectory'],
          const <Object?>['kept/nested'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['kept/nested/file.txt', 'payload'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'createDirectory'],
          const <Object?>['emptydir'],
        ),
        isTrue,
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'remove'],
          const <Object?>['kept'],
        ),
        isFalse,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['kept'],
        ),
        isA<Map>(),
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['kept/nested/file.txt'],
        ),
        <Object?>['payload', 7],
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'remove'],
          const <Object?>['emptydir'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['emptydir'],
        ),
        isNull,
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'remove'],
          const <Object?>['kept/nested/file.txt'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'remove'],
          const <Object?>['kept/nested'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'remove'],
          const <Object?>['kept'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['kept'],
        ),
        isNull,
      );
    },
  );

  test(
    'filesystem remove fails for files with an open File handle like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game'],
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['busy.txt', 'payload'],
        ),
        isTrue,
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['busy.txt'],
      );
      expect(file, isA<Map>());
      expect(await _callMethod(file!, 'open', const <Object?>['r']), isTrue);

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'remove'],
          const <Object?>['busy.txt'],
        ),
        isFalse,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['busy.txt'],
        ),
        isA<Map>(),
      );

      expect(await _callMethod(file, 'close'), isTrue);
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'remove'],
          const <Object?>['busy.txt'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['busy.txt'],
        ),
        isNull,
      );
    },
  );

  test(
    'filesystem createDirectory returns false for existing paths like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['dir-tests'],
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'createDirectory'],
          const <Object?>['nested'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'createDirectory'],
          const <Object?>['nested'],
        ),
        isFalse,
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['file.txt', 'payload'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'createDirectory'],
          const <Object?>['file.txt'],
        ),
        isFalse,
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'createDirectory'],
          const <Object?>['file.txt/nested'],
        ),
        isFalse,
      );
    },
  );

  test(
    'filesystem line iterators trim CRLF and follow LOVE file cursor semantics',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/lines.txt', 'alpha\r\nbeta\r\ngamma\r\n');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final moduleIterator = await _call(
        runtime,
        const ['love', 'filesystem', 'lines'],
        const <Object?>['lines.txt'],
      );
      expect(await _callBuiltin(moduleIterator!), 'alpha');
      expect(await _callBuiltin(moduleIterator), 'beta');
      expect(await _callBuiltin(moduleIterator), 'gamma');
      expect(await _callBuiltin(moduleIterator), isNull);

      final closedFile = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['lines.txt'],
      );
      final closedFileIterator = await _callMethod(closedFile!, 'lines');
      expect(await _callBuiltin(closedFileIterator!), 'alpha');
      expect(await _callMethod(closedFile, 'tell'), 7);
      expect(await _callBuiltin(closedFileIterator), 'beta');
      expect(await _callMethod(closedFile, 'tell'), 13);
      expect(await _callBuiltin(closedFileIterator), 'gamma');
      expect(await _callMethod(closedFile, 'tell'), 20);
      expect(await _callBuiltin(closedFileIterator), isNull);
      expect(await _callMethod(closedFile, 'isOpen'), isFalse);

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['lines.txt'],
      );
      expect(await _callMethod(file!, 'open', const <Object?>['r']), isTrue);
      expect(await _callMethod(file, 'seek', const <Object?>[7]), isTrue);

      final fileIterator = await _callMethod(file, 'lines');
      expect(await _callBuiltin(fileIterator!), 'alpha');
      expect(await _callMethod(file, 'tell'), 7);
      expect(await _callBuiltin(fileIterator), 'beta');
      expect(await _callMethod(file, 'tell'), 7);
      expect(await _callBuiltin(fileIterator), 'gamma');
      expect(await _callMethod(file, 'tell'), 7);
      expect(await _callBuiltin(fileIterator), isNull);
      expect(await _callMethod(file, 'isOpen'), isFalse);

      final movedFile = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['lines.txt'],
      );
      expect(
        await _callMethod(movedFile!, 'open', const <Object?>['r']),
        isTrue,
      );
      expect(await _callMethod(movedFile, 'seek', const <Object?>[7]), isTrue);

      final movedIterator = await _callMethod(movedFile, 'lines');
      expect(await _callBuiltin(movedIterator!), 'alpha');
      expect(await _callMethod(movedFile, 'tell'), 7);

      expect(await _callMethod(movedFile, 'seek', const <Object?>[2]), isTrue);
      expect(await _callBuiltin(movedIterator), 'beta');
      expect(await _callMethod(movedFile, 'tell'), 2);

      expect(await _callMethod(movedFile, 'seek', const <Object?>[4]), isTrue);
      expect(await _callBuiltin(movedIterator), 'gamma');
      expect(await _callMethod(movedFile, 'tell'), 4);

      expect(await _callBuiltin(movedIterator), isNull);
      expect(await _callMethod(movedFile, 'isOpen'), isFalse);
    },
  );

  test(
    'filesystem read, load, and string newFileData report LOVE-style missing file errors',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/main.lua', 'return true');
      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final readResult = _rawResults(
        await _callRawPath(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['missing.txt'],
        ),
      );
      expect(readResult[0], isNull);
      expect(
        _unwrap(readResult[1]),
        'Could not open file missing.txt. Does not exist.',
      );

      final loadResult = _rawResults(
        await _callRawPath(
          runtime,
          const ['love', 'filesystem', 'load'],
          const <Object?>['missing.lua'],
        ),
      );
      expect(loadResult[0], isNull);
      expect(
        _unwrap(loadResult[1]),
        'Could not open file missing.lua. Does not exist.',
      );

      final fileDataResult = _rawResults(
        await _callRawPath(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>['missing.bin'],
        ),
      );
      expect(fileDataResult[0], isNull);
      expect(
        _unwrap(fileDataResult[1]),
        'Could not open file missing.bin. Does not exist.',
      );

      final openedFileResult = _rawResults(
        await _callRawPath(
          runtime,
          const ['love', 'filesystem', 'newFile'],
          const <Object?>['missing.open.txt', 'r'],
        ),
      );
      expect(openedFileResult[0], isNull);
      expect(
        _unwrap(openedFileResult[1]),
        'Could not open file missing.open.txt. Does not exist.',
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['missing.file.txt'],
      );
      expect(file, isA<Map>());

      final fileOpenResult = _rawResults(
        await _callMethod(file!, 'open', const <Object?>['r']),
      );
      expect(fileOpenResult[0], isNull);
      expect(
        _unwrap(fileOpenResult[1]),
        'Could not open file missing.file.txt. Does not exist.',
      );

      final fileReadResult = _rawResults(await _callMethod(file, 'read'));
      expect(fileReadResult[0], isNull);
      expect(
        _unwrap(fileReadResult[1]),
        'Could not open file missing.file.txt. Does not exist.',
      );
    },
  );

  test(
    'filesystem newFileData follows upstream File cursor and open-state semantics',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/cursor.txt', 'abcdef');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final closedFile = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['cursor.txt'],
      );
      expect(closedFile, isA<Map>());
      expect(await _callMethod(closedFile!, 'isOpen'), isFalse);

      final closedFileData = await _call(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[closedFile],
      );
      expect(closedFileData, isA<Map>());
      expect(await _callMethod(closedFileData!, 'getString'), 'abcdef');
      expect(await _callMethod(closedFile, 'isOpen'), isFalse);

      final openFile = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['cursor.txt'],
      );
      expect(openFile, isA<Map>());
      expect(
        await _callMethod(openFile!, 'open', const <Object?>['r']),
        isTrue,
      );
      expect(await _callMethod(openFile, 'read', const <Object?>[2]), <Object?>[
        'ab',
        2,
      ]);
      expect(await _callMethod(openFile, 'tell'), 2);

      final openFileData = await _call(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[openFile],
      );
      expect(openFileData, isA<Map>());
      expect(await _callMethod(openFileData!, 'getString'), 'cdef');
      expect(await _callMethod(openFile, 'isOpen'), isTrue);
      expect(await _callMethod(openFile, 'getMode'), 'r');
      expect(await _callMethod(openFile, 'tell'), 6);
    },
  );

  test(
    'filesystem runtime loadChunk preserves low-level open errors',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/locked.lua', 'return true');
      adapter.failOpen('/source/locked.lua', 'permission denied');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final filesystem = LoveFilesystemState.of(runtime);

      await expectLater(
        () => filesystem.loadChunk(runtime, 'locked.lua'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Could not open file locked.lua (permission denied)',
          ),
        ),
      );
    },
  );

  test('filesystem runtime loadChunk preserves missing-file errors', () async {
    final runtime = Interpreter();
    installLove2d(
      runtime: runtime,
      filesystemAdapter: _TestLoveFilesystemAdapter(),
    );

    final filesystem = LoveFilesystemState.of(runtime);

    await expectLater(
      () => filesystem.loadChunk(runtime, 'missing-runtime.lua'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Could not open file missing-runtime.lua. Does not exist.',
        ),
      ),
    );
  });

  test(
    'filesystem runtime loadChunk preserves syntax-error formatting',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/broken-runtime.lua', 'local =');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final filesystem = LoveFilesystemState.of(runtime);

      await expectLater(
        () => filesystem.loadChunk(runtime, 'broken-runtime.lua'),
        throwsA(
          isA<LuaError>()
              .having(
                (error) => error.message,
                'message',
                startsWith('Syntax error: '),
              )
              .having((error) => error.message, 'message', endsWith('\n')),
        ),
      );
    },
  );

  test('filesystem load preserves upstream syntax-error formatting', () async {
    final adapter = _TestLoveFilesystemAdapter();
    adapter.addFile('/source/broken.lua', 'local =');

    final runtime = Interpreter();
    installLove2d(runtime: runtime, filesystemAdapter: adapter);
    await _call(
      runtime,
      const ['love', 'filesystem', 'setSource'],
      const <Object?>['/source'],
    );

    await expectLater(
      () => _callRawPath(
        runtime,
        const ['love', 'filesystem', 'load'],
        const <Object?>['broken.lua'],
      ),
      throwsA(
        isA<LuaError>()
            .having(
              (error) => error.message,
              'message',
              startsWith('Syntax error: '),
            )
            .having((error) => error.message, 'message', endsWith('\n')),
      ),
    );
  });

  test(
    'filesystem runtime readFileData preserves low-level open errors',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/locked.bin', 'payload');
      adapter.failOpen('/source/locked.bin', 'permission denied');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final filesystem = LoveFilesystemState.of(runtime);

      await expectLater(
        () => filesystem.readFileData('locked.bin'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Could not open file locked.bin (permission denied)',
          ),
        ),
      );
    },
  );

  test(
    'filesystem runtime readAllBytes preserves first-root open errors instead of falling through',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/shared.lua', 'source copy');
      adapter.failOpen('/source/shared.lua', 'permission denied');
      adapter.addFile('/mods/shared.lua', 'mounted copy');

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final filesystem = LoveFilesystemState.of(runtime.runtime);

      expect(filesystem.setSource('/source'), isTrue);
      filesystem.allowMountingForPath('/mods');
      expect(
        await filesystem.mount('/mods', mountpoint: '', appendToPath: true),
        isTrue,
      );

      await expectLater(
        () => filesystem.readAllBytes('shared.lua'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Could not open file shared.lua (permission denied)',
          ),
        ),
      );
    },
  );

  test(
    'filesystem write and append preserve LOVE write-directory errors',
    () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime);

      final writeResult = _rawResults(
        await _callRawPath(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['state.txt', 'payload'],
        ),
      );
      expect(writeResult[0], isNull);
      expect(_unwrap(writeResult[1]), 'Could not set write directory.');

      final appendResult = _rawResults(
        await _callRawPath(
          runtime,
          const ['love', 'filesystem', 'append'],
          const <Object?>['state.txt', 'payload'],
        ),
      );
      expect(appendResult[0], isNull);
      expect(_unwrap(appendResult[1]), 'Could not set write directory.');
    },
  );

  test(
    'filesystem file writes return false on short writes while module writes return an error',
    () async {
      final adapter = _TestLoveFilesystemAdapter()
        ..failWritesWithoutError = true;
      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['write-tests'],
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['state.txt'],
      );
      expect(file, isA<Map>());
      expect(await _callMethod(file!, 'open', const <Object?>['w']), isTrue);
      expect(
        await _callMethod(file, 'write', const <Object?>['payload']),
        isFalse,
      );

      final writeResult = _rawResults(
        await _callRawPath(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['state.txt', 'payload'],
        ),
      );
      expect(writeResult[0], isNull);
      expect(_unwrap(writeResult[1]), 'Data could not be written.');
    },
  );

  test(
    'filesystem writes do not auto-create subdirectories beyond the save root like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['write-subdirs'],
      );

      final moduleWrite = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['nested/state.txt', 'payload'],
        ),
      );
      expect(moduleWrite[0], isNull);
      expect(_unwrap(moduleWrite[1]), 'Could not open file nested/state.txt.');

      final moduleAppend = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'append'],
          const <Object?>['nested/state.txt', 'payload'],
        ),
      );
      expect(moduleAppend[0], isNull);
      expect(_unwrap(moduleAppend[1]), 'Could not open file nested/state.txt.');

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['nested/state.txt'],
      );
      expect(file, isA<Map>());
      final openResult = _rawResults(
        await _callMethod(file!, 'open', const <Object?>['w']),
      );
      expect(openResult[0], isNull);
      expect(_unwrap(openResult[1]), 'Could not open file nested/state.txt.');

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'createDirectory'],
          const <Object?>['nested'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['nested/state.txt', 'payload'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['nested/state.txt'],
        ),
        <Object?>['payload', 7],
      );
    },
  );

  test(
    'filesystem File:open preserves LOVE write-directory errors for write modes',
    () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime);

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['state.txt'],
      );
      expect(file, isA<Map>());

      final openResult = _rawResults(
        await _callMethod(file!, 'open', const <Object?>['w']),
      );
      expect(openResult[0], isNull);
      expect(_unwrap(openResult[1]), 'Could not set write directory.');
    },
  );

  test(
    'filesystem File:read preserves upstream read-mode errors when already opened for writing',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['read-mode-test'],
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['state.txt'],
      );
      expect(file, isA<Map>());
      expect(await _callMethod(file!, 'open', const <Object?>['w']), isTrue);

      final readResult = _rawResults(await _callMethod(file, 'read'));
      expect(readResult[0], isNull);
      expect(_unwrap(readResult[1]), 'File is not opened for reading.');
    },
  );

  test(
    'filesystem newFileData preserves upstream File read-mode errors and argerror wording',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['newfiledata-file-test'],
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['state.txt'],
      );
      expect(file, isA<Map>());
      expect(await _callMethod(file!, 'open', const <Object?>['w']), isTrue);

      final fileResult = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[file],
        ),
      );
      expect(fileResult[0], isNull);
      expect(_unwrap(fileResult[1]), 'File is not opened for reading.');

      await expectLater(
        () => _call(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>[true],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'love.filesystem.newFileData expected filename or File at argument 1',
          ),
        ),
      );

      await expectLater(
        () => _call(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>[true, 'payload.bin'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'love.filesystem.newFileData expected string or Data at argument 1',
          ),
        ),
      );
    },
  );

  test(
    'filesystem File:getSize preserves upstream missing-file open errors',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['missing.txt'],
      );
      expect(file, isA<Map>());

      final getSizeResult = _rawResults(await _callMethod(file!, 'getSize'));
      expect(getSizeResult[0], isNull);
      expect(
        _unwrap(getSizeResult[1]),
        'Could not open file missing.txt. Does not exist.',
      );
    },
  );

  test('filesystem read APIs preserve LOVE low-level open errors', () async {
    final adapter = _TestLoveFilesystemAdapter();
    adapter.addFile('/source/locked.txt', 'payload');
    adapter.failOpen('/source/locked.txt', 'permission denied');

    final runtime = Interpreter();
    installLove2d(runtime: runtime, filesystemAdapter: adapter);
    await _call(
      runtime,
      const ['love', 'filesystem', 'setSource'],
      const <Object?>['/source'],
    );

    final readResult = _rawResults(
      await _call(
        runtime,
        const ['love', 'filesystem', 'read'],
        const <Object?>['locked.txt'],
      ),
    );
    expect(readResult[0], isNull);
    expect(
      _unwrap(readResult[1]),
      'Could not open file locked.txt (permission denied)',
    );

    final fileDataResult = _rawResults(
      await _call(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        const <Object?>['locked.txt'],
      ),
    );
    expect(fileDataResult[0], isNull);
    expect(
      _unwrap(fileDataResult[1]),
      'Could not open file locked.txt (permission denied)',
    );

    final file = await _call(
      runtime,
      const ['love', 'filesystem', 'newFile'],
      const <Object?>['locked.txt'],
    );
    final openResult = _rawResults(
      await _callMethod(file!, 'open', const <Object?>['r']),
    );
    expect(openResult[0], isNull);
    expect(
      _unwrap(openResult[1]),
      'Could not open file locked.txt (permission denied)',
    );
  });

  test(
    'filesystem getRealDirectory preserves LOVE missing-file errors',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/main.lua', 'return true');
      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final result = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['missing.txt'],
        ),
      );
      expect(result[0], isNull);
      expect(_unwrap(result[1]), 'File does not exist on disk.');
    },
  );

  test(
    'filesystem deprecated helper APIs preserve LOVE missing and unknown-info errors',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/unknown-size.txt', 'abcdef');
      adapter.overrideUnknownSize('/source/unknown-size.txt');
      adapter.addFile('/source/unknown-modtime.txt', 'abcdef');
      adapter.overrideModified('/source/unknown-modtime.txt', null);

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final missingSize = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getSize'],
          const <Object?>['missing.txt'],
        ),
      );
      expect(missingSize[0], isNull);
      expect(_unwrap(missingSize[1]), 'File does not exist');

      final unknownSize = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getSize'],
          const <Object?>['unknown-size.txt'],
        ),
      );
      expect(unknownSize[0], isNull);
      expect(_unwrap(unknownSize[1]), 'Could not determine file size.');

      final missingModtime = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getLastModified'],
          const <Object?>['missing.txt'],
        ),
      );
      expect(missingModtime[0], isNull);
      expect(_unwrap(missingModtime[1]), 'File does not exist');

      final unknownModtime = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getLastModified'],
          const <Object?>['unknown-modtime.txt'],
        ),
      );
      expect(unknownModtime[0], isNull);
      expect(
        _unwrap(unknownModtime[1]),
        'Could not determine file modification date.',
      );
    },
  );

  test(
    'filesystem treats negative size and modtime info as upstream unknown sentinels',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/sentinel-info.txt', 'abcdef');
      adapter.overrideSize('/source/sentinel-info.txt', -1);
      adapter.overrideModified(
        '/source/sentinel-info.txt',
        DateTime.fromMillisecondsSinceEpoch(-1000, isUtc: true),
      );

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final info = await _call(
        runtime,
        const ['love', 'filesystem', 'getInfo'],
        const <Object?>['sentinel-info.txt'],
      );
      expect(info, isA<Map>());
      final infoTable = info! as Map<dynamic, dynamic>;
      expect(infoTable['type'], 'file');
      expect(infoTable.containsKey('size'), isFalse);
      expect(infoTable.containsKey('modtime'), isFalse);

      final reusedInfoTable = <Object?, Object?>{'size': 123, 'modtime': 456};
      final reusedInfo = await _call(
        runtime,
        const ['love', 'filesystem', 'getInfo'],
        <Object?>['sentinel-info.txt', reusedInfoTable],
      );
      expect(reusedInfo, same(reusedInfoTable));
      expect(reusedInfoTable['type'], 'file');
      expect(
        reusedInfoTable['size'],
        123,
        reason: 'LOVE leaves existing size fields intact when size is unknown',
      );
      expect(
        reusedInfoTable['modtime'],
        456,
        reason:
            'LOVE leaves existing modtime fields intact when modtime is unknown',
      );

      final deprecatedSize = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getSize'],
          const <Object?>['sentinel-info.txt'],
        ),
      );
      expect(deprecatedSize[0], isNull);
      expect(_unwrap(deprecatedSize[1]), 'Could not determine file size.');

      final deprecatedModtime = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getLastModified'],
          const <Object?>['sentinel-info.txt'],
        ),
      );
      expect(deprecatedModtime[0], isNull);
      expect(
        _unwrap(deprecatedModtime[1]),
        'Could not determine file modification date.',
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['sentinel-info.txt'],
      );
      expect(file, isA<Map>());

      final fileSize = _rawResults(await _callMethod(file!, 'getSize'));
      expect(fileSize[0], isNull);
      expect(_unwrap(fileSize[1]), 'Could not determine file size.');
    },
  );

  test(
    'filesystem numeric file APIs preserve LOVE safe-number limits',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/oversized.txt', 'abcdef');
      adapter.overrideSize('/source/oversized.txt', 0x20000000000000);
      adapter.overridePosition('/source/oversized.txt', 0x20000000000000);

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final info = await _call(
        runtime,
        const ['love', 'filesystem', 'getInfo'],
        const <Object?>['oversized.txt'],
      );
      expect(info, isA<Map>());
      expect((info! as Map)['size'], 0x20000000000000);

      final deprecatedSize = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getSize'],
          const <Object?>['oversized.txt'],
        ),
      );
      expect(deprecatedSize[0], isNull);
      expect(
        _unwrap(deprecatedSize[1]),
        'Size too large to fit into a Lua number!',
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['oversized.txt'],
      );
      expect(await _callMethod(file!, 'open', const <Object?>['r']), isTrue);

      final fileSize = _rawResults(await _callMethod(file, 'getSize'));
      expect(fileSize[0], isNull);
      expect(_unwrap(fileSize[1]), 'Size is too large.');

      final tell = _rawResults(await _callMethod(file, 'tell'));
      expect(tell[0], isNull);
      expect(_unwrap(tell[1]), 'Number is too large.');
    },
  );

  test(
    'filesystem File:seek truncates Lua numbers and rejects unsafe positions',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/seek.txt', 'abcdef');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['seek.txt'],
      );
      expect(await _callMethod(file!, 'open', const <Object?>['r']), isTrue);
      expect(await _callMethod(file, 'seek', const <Object?>[1.9]), isTrue);
      expect(await _callMethod(file, 'tell'), 1);
      expect(
        await _callMethod(file, 'seek', const <Object?>[9007199254740992.0]),
        isFalse,
      );
    },
  );

  test(
    'filesystem read and buffer sizes truncate Lua numbers like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/fractional.txt', 'abcdef');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['fractional.txt', 1.9],
        ),
        <Object?>['a', 1],
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['fractional.txt'],
      );
      expect(await _callMethod(file!, 'open', const <Object?>['r']), isTrue);
      expect(adapter.lastOpenedDevice, isNotNull);
      expect(adapter.lastOpenedDevice!.bufferMode, BufferMode.none);
      expect(adapter.lastOpenedDevice!.bufferSize, 0);
      expect(await _callMethod(file, 'read', const <Object?>[2.9]), <Object?>[
        'ab',
        2,
      ]);
      expect(
        await _callMethod(file, 'setBuffer', const <Object?>['full', 3.9]),
        isTrue,
      );
      expect(await _callMethod(file, 'getBuffer'), <Object?>['full', 3]);
      expect(adapter.lastOpenedDevice!.bufferMode, BufferMode.full);
      expect(adapter.lastOpenedDevice!.bufferSize, 3);

      expect(
        await _callMethod(file, 'setBuffer', const <Object?>['none', 7.9]),
        isTrue,
      );
      expect(await _callMethod(file, 'getBuffer'), <Object?>['none', 0]);
      expect(adapter.lastOpenedDevice!.bufferMode, BufferMode.none);
      expect(adapter.lastOpenedDevice!.bufferSize, 0);

      expect(await _callMethod(file, 'close'), isTrue);
      expect(
        await _callMethod(file, 'setBuffer', const <Object?>['none', 9.9]),
        isTrue,
      );
      expect(await _callMethod(file, 'getBuffer'), <Object?>['none', 9]);
      expect(await _callMethod(file, 'open', const <Object?>['r']), isTrue);
      expect(await _callMethod(file, 'getBuffer'), <Object?>['none', 0]);
      expect(adapter.lastOpenedDevice!.bufferMode, BufferMode.none);
      expect(adapter.lastOpenedDevice!.bufferSize, 0);
    },
  );

  test(
    'filesystem File buffer failures preserve upstream fallback and false-return semantics',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/fractional.txt', 'abcdef');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['fractional.txt'],
      );
      expect(file, isA<Map>());

      expect(
        await _callMethod(file!, 'setBuffer', const <Object?>['full', 12]),
        isTrue,
      );
      expect(await _callMethod(file, 'getBuffer'), <Object?>['full', 12]);

      adapter.setBufferingFailureError = 'buffer apply failed';
      expect(await _callMethod(file, 'open', const <Object?>['r']), isTrue);
      expect(await _callMethod(file, 'getBuffer'), <Object?>['none', 0]);

      expect(
        await _callMethod(file, 'setBuffer', const <Object?>['line', 7]),
        isFalse,
      );
      expect(await _callMethod(file, 'getBuffer'), <Object?>['none', 0]);
    },
  );

  test(
    'filesystem File flush and close return false on backend failures like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['close-failure-test'],
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['state.txt'],
      );
      expect(file, isA<Map>());
      expect(await _callMethod(file!, 'open', const <Object?>['w']), isTrue);

      adapter.flushFailureError = 'flush failed';
      expect(await _callMethod(file, 'flush'), isFalse);
      expect(await _callMethod(file, 'isOpen'), isTrue);
      expect(await _callMethod(file, 'getMode'), 'w');

      adapter.closeFailureError = 'close failed';
      expect(await _callMethod(file, 'close'), isFalse);
      expect(await _callMethod(file, 'isOpen'), isTrue);
      expect(await _callMethod(file, 'getMode'), 'w');
    },
  );

  test(
    'filesystem read APIs reject explicit negative sizes like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/fractional.txt', 'abcdef');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final moduleRead = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['fractional.txt', -1],
        ),
      );
      expect(moduleRead[0], isNull);
      expect(_unwrap(moduleRead[1]), 'Invalid read size.');

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['fractional.txt'],
      );
      expect(await _callMethod(file!, 'open', const <Object?>['r']), isTrue);

      final fileRead = _rawResults(
        await _callMethod(file, 'read', const <Object?>[-2]),
      );
      expect(fileRead[0], isNull);
      expect(_unwrap(fileRead[1]), 'Invalid read size.');
    },
  );

  test(
    'filesystem File:read treats lone string args as container selectors like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/fractional.txt', 'abcdef');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['fractional.txt'],
      );
      expect(await _callMethod(file!, 'open', const <Object?>['r']), isTrue);

      final fileRead = _rawResults(
        await _callMethod(file, 'read', const <Object?>['3.9']),
      );
      expect(fileRead[0], isNull);
      expect(_unwrap(fileRead[1]), 'File:read invalid container type "3.9"');
    },
  );

  test(
    'filesystem File:read returns an empty string for zero-byte EOF reads like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/fractional.txt', 'abcdef');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['fractional.txt'],
      );
      expect(await _callMethod(file!, 'open', const <Object?>['r']), isTrue);
      expect(await _callMethod(file, 'seek', const <Object?>[6]), isTrue);

      expect(await _callMethod(file, 'read', const <Object?>[0]), <Object?>[
        '',
        0,
      ]);
    },
  );

  test(
    'filesystem write APIs reject explicit negative sizes like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['write-size-test'],
      );

      final moduleWrite = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['state.txt', 'payload', -1],
        ),
      );
      expect(moduleWrite[0], isNull);
      expect(_unwrap(moduleWrite[1]), 'Invalid write size.');

      final moduleAppend = _rawResults(
        await _call(
          runtime,
          const ['love', 'filesystem', 'append'],
          const <Object?>['state.txt', 'payload', -2],
        ),
      );
      expect(moduleAppend[0], isNull);
      expect(_unwrap(moduleAppend[1]), 'Invalid write size.');

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['state.txt'],
      );
      expect(file, isA<Map>());
      expect(await _callMethod(file!, 'open', const <Object?>['w']), isTrue);

      final fileWrite = _rawResults(
        await _callMethod(file, 'write', const <Object?>['payload', -3]),
      );
      expect(fileWrite[0], isNull);
      expect(_unwrap(fileWrite[1]), 'Invalid write size.');
    },
  );

  test(
    'filesystem File:write preserves upstream lowercase data type errors',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['write-type-test'],
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['state.txt'],
      );
      expect(file, isA<Map>());
      expect(await _callMethod(file!, 'open', const <Object?>['w']), isTrue);

      await expectLater(
        () => _callMethod(file, 'write', const <Object?>[true]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'File:write expected string or data at argument 2',
          ),
        ),
      );
    },
  );

  test(
    'filesystem module write APIs preserve upstream Data type-name errors',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['write-module-type-test'],
      );

      await expectLater(
        () => _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['state.txt', true],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'love.filesystem.write expected string or Data at argument 2',
          ),
        ),
      );

      await expectLater(
        () => _call(
          runtime,
          const ['love', 'filesystem', 'append'],
          const <Object?>['state.txt', true],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'love.filesystem.append expected string or Data at argument 2',
          ),
        ),
      );
    },
  );

  test(
    'filesystem numeric string arguments coerce through LOVE number checks',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/numeric-strings.txt', 'abcdef');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game'],
      );

      final readData = await _call(
        runtime,
        const ['love', 'filesystem', 'read'],
        const <Object?>['data', 'numeric-strings.txt', '2.9'],
      );
      expect(readData, isA<List<Object?>>());
      final readTuple = readData! as List<Object?>;
      expect(await _callMethod(readTuple[0]!, 'getString'), 'ab');
      expect(readTuple[1], 2);

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['numeric-strings.txt'],
      );
      expect(await _callMethod(file!, 'open', const <Object?>['r']), isTrue);
      final fileRead = await _callMethod(file, 'read', const <Object?>[
        'data',
        '3.9',
      ]);
      expect(fileRead, isA<List<Object?>>());
      final fileReadTuple = fileRead! as List<Object?>;
      expect(await _callMethod(fileReadTuple[0]!, 'getString'), 'abc');
      expect(fileReadTuple[1], 3);
      expect(
        await _callMethod(file, 'setBuffer', const <Object?>['full', '4.9']),
        isTrue,
      );
      expect(await _callMethod(file, 'getBuffer'), <Object?>['full', 4]);
      expect(await _callMethod(file, 'seek', const <Object?>['1.9']), isTrue);
      expect(await _callMethod(file, 'tell'), 1);

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['numeric-write.txt', 'abcdef', '2.9'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'append'],
          const <Object?>['numeric-write.txt', 'XYZ', '1.9'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['numeric-write.txt'],
        ),
        <Object?>['abX', 3],
      );
    },
  );

  test(
    'filesystem write lengths truncate Lua numbers like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game'],
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['fractional-write.txt', 'abcdef', 2.9],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'append'],
          const <Object?>['fractional-write.txt', 'XYZ', 1.9],
        ),
        isTrue,
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['fractional-write.txt'],
      );
      expect(await _callMethod(file!, 'open', const <Object?>['a']), isTrue);
      expect(
        await _callMethod(file, 'write', const <Object?>['1234', 2.9]),
        isTrue,
      );
      expect(await _callMethod(file, 'close'), isTrue);

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['fractional-write.txt'],
        ),
        <Object?>['abX12', 5],
      );
    },
  );

  test('filesystem write APIs preserve LOVE low-level open errors', () async {
    final adapter = _TestLoveFilesystemAdapter();

    final runtime = Interpreter();
    installLove2d(runtime: runtime, filesystemAdapter: adapter);
    await _call(
      runtime,
      const ['love', 'filesystem', 'setIdentity'],
      const <Object?>['game'],
    );
    final saveDirectory = await _call(runtime, const [
      'love',
      'filesystem',
      'getSaveDirectory',
    ]);
    adapter.failOpen(
      p.posix.join(saveDirectory! as String, 'blocked.txt'),
      'device busy',
    );

    final writeResult = _rawResults(
      await _call(
        runtime,
        const ['love', 'filesystem', 'write'],
        const <Object?>['blocked.txt', 'payload'],
      ),
    );
    expect(writeResult[0], isNull);
    expect(
      _unwrap(writeResult[1]),
      'Could not open file blocked.txt (device busy)',
    );

    final file = await _call(
      runtime,
      const ['love', 'filesystem', 'newFile'],
      const <Object?>['blocked.txt'],
    );
    final openResult = _rawResults(
      await _callMethod(file!, 'open', const <Object?>['w']),
    );
    expect(openResult[0], isNull);
    expect(
      _unwrap(openResult[1]),
      'Could not open file blocked.txt (device busy)',
    );
  });

  test(
    'filesystem init and setSymlinksEnabled require LOVE argument types',
    () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime);

      await expectLater(
        () => _call(runtime, const ['love', 'filesystem', 'init']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'love.filesystem.init expected a string at argument 1',
          ),
        ),
      );

      await expectLater(
        () => _call(
          runtime,
          const ['love', 'filesystem', 'setSymlinksEnabled'],
          const <Object?>['yes'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'love.filesystem.setSymlinksEnabled expected a boolean at argument 1',
          ),
        ),
      );
    },
  );

  test(
    'filesystem module getters expose adapter paths and init resets symlink state',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/main.lua', 'return true');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);

      expect(
        await _call(runtime, const [
          'love',
          'filesystem',
          'getWorkingDirectory',
        ]),
        '/work',
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'getUserDirectory']),
        '/users/tester',
      );
      expect(
        await _call(runtime, const [
          'love',
          'filesystem',
          'getAppdataDirectory',
        ]),
        '/appdata',
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'getIdentity']),
        '',
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'getSource']),
        '',
      );
      expect(
        await _call(runtime, const [
          'love',
          'filesystem',
          'areSymlinksEnabled',
        ]),
        isTrue,
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'isFused']),
        isFalse,
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'setSymlinksEnabled'],
          const <Object?>[false],
        ),
        isNull,
      );
      expect(
        await _call(runtime, const [
          'love',
          'filesystem',
          'areSymlinksEnabled',
        ]),
        isFalse,
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'init'],
          const <Object?>['lualike'],
        ),
        isNull,
      );
      expect(
        await _call(runtime, const [
          'love',
          'filesystem',
          'areSymlinksEnabled',
        ]),
        isTrue,
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'setIdentity'],
          const <Object?>['game'],
        ),
        isNull,
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'getIdentity']),
        'game',
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'setSource'],
          const <Object?>['/source'],
        ),
        isNull,
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'getSource']),
        '/source',
      );
    },
  );

  test(
    'filesystem require path setters match upstream semicolon splitting',
    () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime);

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'setRequirePath'],
          const <Object?>[' ;?.lua;;?/init.lua; '],
        ),
        isNull,
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'getRequirePath']),
        ' ;?.lua;;?/init.lua; ',
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'setRequirePath'],
          const <Object?>['mods/?.lua;mods/?/init.lua;'],
        ),
        isNull,
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'getRequirePath']),
        'mods/?.lua;mods/?/init.lua',
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'setCRequirePath'],
          const <Object?>[';;lib/??; ? '],
        ),
        isNull,
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'getCRequirePath']),
        ';;lib/??; ? ',
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'setCRequirePath'],
          const <Object?>[';;lib/??;;'],
        ),
        isNull,
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'getCRequirePath']),
        ';;lib/??;',
      );
    },
  );

  test(
    'filesystem optional boolean args default instead of using generic truthiness',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/main.lua', 'return "source"');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game', 'yes'],
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['main.lua', 'save'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['main.lua'],
        ),
        <Object?>['save', 4],
        reason:
            'A non-boolean appendToPath arg should fall back to false and prepend the save root',
      );
    },
  );

  test(
    'filesystem adapter replacement rebinds the mounted save root to the new adapter',
    () async {
      final initialAdapter = _TestLoveFilesystemAdapter(
        appdataDirectory: '/appdata-initial',
      );
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: initialAdapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game'],
      );

      expect(
        await _call(runtime, const ['love', 'filesystem', 'getSaveDirectory']),
        '/appdata-initial/love/game',
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['state.txt', 'initial'],
        ),
        isTrue,
      );

      final replacementAdapter = _TestLoveFilesystemAdapter(
        appdataDirectory: '/appdata-replacement',
      );
      LoveFilesystemState.attach(runtime, adapter: replacementAdapter);

      expect(
        await _call(runtime, const ['love', 'filesystem', 'getSaveDirectory']),
        '/appdata-replacement/love/game',
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['state.txt', 'replacement'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['state.txt'],
        ),
        <Object?>['replacement', 11],
      );

      expect(
        String.fromCharCodes(
          replacementAdapter.fileBytes(
            '/appdata-replacement/love/game/state.txt',
          ),
        ),
        'replacement',
      );
      expect(
        String.fromCharCodes(
          initialAdapter.fileBytes('/appdata-initial/love/game/state.txt'),
        ),
        'initial',
      );
    },
  );

  test(
    'filesystem adapter replacement rebinds archive-backed source roots to the new adapter',
    () async {
      final initialAdapter = _TestLoveFilesystemAdapter();
      initialAdapter.addFileBytes(
        '/source/game.love',
        _encodeZip(<String, String>{'main.lua': 'return 1'}),
      );
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: initialAdapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source/game.love'],
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['main.lua'],
        ),
        <Object?>['return 1', 8],
      );

      final replacementAdapter = _TestLoveFilesystemAdapter();
      replacementAdapter.addFileBytes(
        '/source/game.love',
        _encodeZip(<String, String>{'main.lua': 'return 2'}),
      );
      LoveFilesystemState.attach(runtime, adapter: replacementAdapter);

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['main.lua'],
        ),
        <Object?>['return 2', 8],
      );
    },
  );

  test(
    'filesystem adapter replacement rebinds save-relative string archive mounts to the new adapter',
    () async {
      final initialAdapter = _TestLoveFilesystemAdapter(
        appdataDirectory: '/appdata-initial',
      );
      initialAdapter.addFileBytes(
        '/appdata-initial/love/game/mods.zip',
        _encodeZip(<String, String>{'main.lua': 'return 1'}),
      );
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: initialAdapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game'],
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['mods.zip', 'mods'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['mods/main.lua'],
        ),
        <Object?>['return 1', 8],
      );

      final replacementAdapter = _TestLoveFilesystemAdapter(
        appdataDirectory: '/appdata-replacement',
      );
      replacementAdapter.addFileBytes(
        '/appdata-replacement/love/game/mods.zip',
        _encodeZip(<String, String>{'main.lua': 'return 2'}),
      );
      LoveFilesystemState.attach(runtime, adapter: replacementAdapter);

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['mods/main.lua'],
        ),
        <Object?>['return 2', 8],
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'unmount'],
          const <Object?>['mods.zip'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['mods/main.lua'],
        ),
        isNull,
      );
    },
  );

  test(
    'filesystem adapter replacement rebinds save-relative string directory mounts to the new adapter',
    () async {
      final initialAdapter = _TestLoveFilesystemAdapter(
        appdataDirectory: '/appdata-initial',
      );
      initialAdapter.addFile(
        '/appdata-initial/love/game/mods/main.lua',
        'return "initial"',
      );
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: initialAdapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game'],
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['mods', 'mountedmods'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['mountedmods/main.lua'],
        ),
        <Object?>['return "initial"', 16],
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['mountedmods/main.lua'],
        ),
        '/appdata-initial/love/game/mods',
      );

      final replacementAdapter = _TestLoveFilesystemAdapter(
        appdataDirectory: '/appdata-replacement',
      );
      replacementAdapter.addFile(
        '/appdata-replacement/love/game/mods/main.lua',
        'return "replacement"',
      );
      LoveFilesystemState.attach(runtime, adapter: replacementAdapter);

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['mountedmods/main.lua'],
        ),
        <Object?>['return "replacement"', 20],
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['mountedmods/main.lua'],
        ),
        '/appdata-replacement/love/game/mods',
      );
    },
  );

  test(
    'filesystem adapter replacement preserves string mount precedence order',
    () async {
      final initialAdapter = _TestLoveFilesystemAdapter(
        appdataDirectory: '/appdata-initial',
      );
      initialAdapter.addFile(
        '/appdata-initial/love/game/primary/main.lua',
        'return "primary-initial"',
      );
      initialAdapter.addFile(
        '/appdata-initial/love/game/secondary/main.lua',
        'return "secondary-initial"',
      );
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: initialAdapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game'],
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['primary', 'overlay', false],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['secondary', 'overlay', true],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['overlay/main.lua'],
        ),
        <Object?>['return "primary-initial"', 24],
      );

      final replacementAdapter = _TestLoveFilesystemAdapter(
        appdataDirectory: '/appdata-replacement',
      );
      replacementAdapter.addFile(
        '/appdata-replacement/love/game/primary/main.lua',
        'return "primary-replacement"',
      );
      replacementAdapter.addFile(
        '/appdata-replacement/love/game/secondary/main.lua',
        'return "secondary-replacement"',
      );
      LoveFilesystemState.attach(runtime, adapter: replacementAdapter);

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['overlay/main.lua'],
        ),
        <Object?>['return "primary-replacement"', 28],
      );
    },
  );

  test(
    'filesystem adapter replacement lets unmount remove save-relative string mounts even when the current adapter cannot resolve them',
    () async {
      final initialAdapter = _TestLoveFilesystemAdapter(
        appdataDirectory: '/appdata-initial',
      );
      initialAdapter.addFileBytes(
        '/appdata-initial/love/game/mods.zip',
        _encodeZip(<String, String>{'main.lua': 'return 1'}),
      );
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: initialAdapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game'],
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['mods.zip', 'mods'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['mods/main.lua'],
        ),
        <Object?>['return 1', 8],
      );

      LoveFilesystemState.attach(
        runtime,
        adapter: _TestLoveFilesystemAdapter(appdataDirectory: null),
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'unmount'],
          const <Object?>['mods.zip'],
        ),
        isTrue,
      );

      final restoredAdapter = _TestLoveFilesystemAdapter(
        appdataDirectory: '/appdata-restored',
      );
      restoredAdapter.addFileBytes(
        '/appdata-restored/love/game/mods.zip',
        _encodeZip(<String, String>{'main.lua': 'return 2'}),
      );
      LoveFilesystemState.attach(runtime, adapter: restoredAdapter);

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['mods/main.lua'],
        ),
        isNull,
      );
    },
  );

  test(
    'filesystem adapter replacement restores the mounted save root after a temporary unwritable adapter',
    () async {
      final initialAdapter = _TestLoveFilesystemAdapter(
        appdataDirectory: '/appdata-initial',
      );
      final runtime = Interpreter();

      installLove2d(runtime: runtime, filesystemAdapter: initialAdapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game'],
      );

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['state.txt', 'initial'],
        ),
        isTrue,
      );

      LoveFilesystemState.attach(
        runtime,
        adapter: _TestLoveFilesystemAdapter(appdataDirectory: null),
      );

      expect(
        await _call(runtime, const ['love', 'filesystem', 'getSaveDirectory']),
        '',
      );
      final unwritableWrite = _rawResults(
        await _callRawPath(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['state.txt', 'blocked'],
        ),
      );
      expect(unwritableWrite[0], isNull);
      expect(_unwrap(unwritableWrite[1]), 'Could not set write directory.');

      final restoredAdapter = _TestLoveFilesystemAdapter(
        appdataDirectory: '/appdata-restored',
      );
      LoveFilesystemState.attach(runtime, adapter: restoredAdapter);

      expect(
        await _call(runtime, const ['love', 'filesystem', 'getSaveDirectory']),
        '/appdata-restored/love/game',
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'write'],
          const <Object?>['state.txt', 'restored'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'read'],
          const <Object?>['state.txt'],
        ),
        <Object?>['restored', 8],
      );
      expect(
        String.fromCharCodes(
          restoredAdapter.fileBytes('/appdata-restored/love/game/state.txt'),
        ),
        'restored',
      );
    },
  );

  test(
    'filesystem lines, tell, and seek preserve LOVE file-object edge-case behavior',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/main.lua', 'return true');
      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);
      await _call(
        runtime,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      await expectLater(
        () => _call(
          runtime,
          const ['love', 'filesystem', 'lines'],
          const <Object?>['missing-lines.txt'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'Could not open file.',
          ),
        ),
      );

      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['missing-lines.txt'],
      );
      expect(file, isA<Map>());
      final missingFile = file!;

      await expectLater(
        () => _callMethod(missingFile, 'lines'),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'Could not open file.',
          ),
        ),
      );

      final tellResult = _rawResults(await _callMethod(missingFile, 'tell'));
      expect(tellResult[0], isNull);
      expect(_unwrap(tellResult[1]), 'Invalid position.');

      expect(
        await _callMethod(missingFile, 'seek', const <Object?>[-1]),
        isFalse,
      );
    },
  );

  test(
    'filesystem lines preserves upstream filename argerror wording',
    () async {
      final runtime = Interpreter();
      installLove2d(
        runtime: runtime,
        filesystemAdapter: _TestLoveFilesystemAdapter(),
      );

      await expectLater(
        () => _call(
          runtime,
          const ['love', 'filesystem', 'lines'],
          const <Object?>[true],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'love.filesystem.lines expected filename.',
          ),
        ),
      );
    },
  );

  test('filesystem lines APIs preserve LOVE generic open errors', () async {
    final adapter = _TestLoveFilesystemAdapter();
    adapter.addFile('/source/locked-lines.txt', 'alpha\nbeta\n');
    adapter.failOpen('/source/locked-lines.txt', 'permission denied');

    final runtime = Interpreter();
    installLove2d(runtime: runtime, filesystemAdapter: adapter);
    await _call(
      runtime,
      const ['love', 'filesystem', 'setSource'],
      const <Object?>['/source'],
    );

    await expectLater(
      () => _call(
        runtime,
        const ['love', 'filesystem', 'lines'],
        const <Object?>['locked-lines.txt'],
      ),
      throwsA(
        isA<LuaError>().having(
          (error) => error.message,
          'message',
          'Could not open file.',
        ),
      ),
    );

    final file = await _call(
      runtime,
      const ['love', 'filesystem', 'newFile'],
      const <Object?>['locked-lines.txt'],
    );
    expect(file, isA<Map>());

    await expectLater(
      () => _callMethod(file!, 'lines'),
      throwsA(
        isA<LuaError>().having(
          (error) => error.message,
          'message',
          'Could not open file.',
        ),
      ),
    );
  });

  test(
    'filesystem mounts FileData archives as virtual readable roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      final archiveData = await _call(
        interpreter,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[
          _encodeZip(<String, String>{
            'boot.lua': 'return 99',
            'pkg/init.lua': 'return { answer = 5 }',
          }),
          'mods.zip',
        ],
      );
      expect(archiveData, isA<Map>());

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[archiveData, 'packed', true],
        ),
        isTrue,
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['packed/boot.lua'],
        ),
        <Object?>['return 99', 9],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['packed/boot.lua'],
        ),
        <Object?>[null, 'File does not exist on disk.'],
      );

      final packedInfo = await _call(
        interpreter,
        const ['love', 'filesystem', 'getInfo'],
        const <Object?>['packed/pkg'],
      );
      expect(packedInfo, isA<Map>());
      expect((packedInfo! as Map)['type'], 'directory');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getDirectoryItems'],
          const <Object?>['packed'],
        ),
        <Object?, Object?>{1: 'boot.lua', 2: 'pkg'},
      );

      final file = await _call(
        interpreter,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['packed/boot.lua'],
      );
      expect(await _callMethod(file!, 'open', const <Object?>['r']), isTrue);
      expect(await _callMethod(file, 'getSize'), 9);
      expect(await _callMethod(file, 'read'), <Object?>['return 99', 9]);
      expect(await _callMethod(file, 'seek', const <Object?>[0]), isTrue);
      expect(await _callMethod(file, 'tell'), 0);

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['packed/?.lua;packed/?/init.lua'],
      );
      await runtime.execute('''
local mod, modPath = require("pkg")
testbed = {
  answer = mod.answer,
  path = modPath,
}
''');

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['answer'], 5);
      expect(snapshot['path'], 'packed/pkg/init.lua');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          <Object?>[archiveData],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['packed/boot.lua'],
        ),
        isNull,
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[archiveData, 'custom-name.zip', 'alias', false],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['alias/boot.lua'],
        ),
        <Object?>[null, 'File does not exist on disk.'],
      );
    },
  );

  test(
    'filesystem mounts 7z archives from FileData as virtual readable roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      final archiveData = await _call(
        interpreter,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[
          _encode7z(<String, String>{
            'boot.lua': 'return 71',
            'pkg/init.lua': 'return { answer = 17, label = "7z-filedata" }',
          }),
          'mods.7z',
        ],
      );
      expect(archiveData, isA<Map>());

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[archiveData, 'packed7z', true],
        ),
        isTrue,
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['packed7z/boot.lua'],
        ),
        <Object?>['return 71', 9],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['packed7z/boot.lua'],
        ),
        <Object?>[null, 'File does not exist on disk.'],
      );

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['packed7z/?.lua;packed7z/?/init.lua'],
      );
      final pkgResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('pkg')],
        ),
      );
      final pkg = (pkgResult.first as Value).unwrap() as Map;
      expect(pkg['answer'], 17);
      expect(pkg['label'], '7z-filedata');
      expect(_unwrap(pkgResult[1]), 'packed7z/pkg/init.lua');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          <Object?>[archiveData],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['packed7z/boot.lua'],
        ),
        isNull,
      );
    },
    skip: _sevenZipSupportSkipReason,
  );

  test(
    'filesystem mounts zip archives from string paths as virtual roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/mods/extra.zip',
        _encodeZip(<String, String>{
          'mod.lua': 'return 77',
          'nested/init.lua': 'return { label = "zip" }',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      _allowStringMount(interpreter, '/mods/extra.zip');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/mods/extra.zip', 'zipmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['zipmods/?.lua;zipmods/?/init.lua'],
      );

      final nestedResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('nested')],
        ),
      );
      final modRead = await _call(
        interpreter,
        const ['love', 'filesystem', 'read'],
        const <Object?>['zipmods/mod.lua'],
      );
      final nested = (nestedResult.first as Value).unwrap() as Map;

      expect(modRead, <Object?>['return 77', 9]);
      expect(nested['label'], 'zip');
      expect(_unwrap(nestedResult[1]), 'zipmods/nested/init.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['zipmods/mod.lua'],
        ),
        '/mods/extra.zip',
      );
    },
  );

  test(
    'filesystem duplicate string mounts succeed without replacing the original mount',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/mods/extra.zip',
        _encodeZip(<String, String>{'mod.lua': 'return 77'}),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      _allowStringMount(interpreter, '/mods/extra.zip');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/mods/extra.zip', 'zipmods', true],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/mods/extra.zip', 'zipmods_alias', false],
        ),
        isTrue,
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['zipmods/mod.lua'],
        ),
        <Object?>['return 77', 9],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['zipmods_alias/mod.lua'],
        ),
        isNull,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          const <Object?>['/mods/extra.zip'],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['zipmods/mod.lua'],
        ),
        isNull,
      );
    },
  );

  test(
    'filesystem mounts prefixed zip archives from string paths as virtual roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/mods/selfextracting.bin',
        _encodePrefixedZip(<String, String>{
          'mod.lua': 'return 91',
          'nested/init.lua': 'return { label = "prefixed" }',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      _allowStringMount(interpreter, '/mods/selfextracting.bin');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/mods/selfextracting.bin', 'sxmods', true],
        ),
        isTrue,
      );

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['sxmods/?.lua;sxmods/?/init.lua'],
      );

      final modValue = await _call(
        interpreter,
        const ['love', 'filesystem', 'read'],
        const <Object?>['sxmods/mod.lua'],
      );
      final nestedResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('nested')],
        ),
      );
      final nested = (nestedResult.first as Value).unwrap() as Map;

      expect(modValue, <Object?>['return 91', 9]);
      expect(nested['label'], 'prefixed');
      expect(_unwrap(nestedResult[1]), 'sxmods/nested/init.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['sxmods/mod.lua'],
        ),
        '/mods/selfextracting.bin',
      );
    },
  );

  test(
    'filesystem mounts tar archives from string paths as virtual roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/mods/extra.tar',
        _encodeTar(<String, String>{
          'mod.lua': 'return 88',
          'nested/init.lua': 'return { label = "tar" }',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      _allowStringMount(interpreter, '/mods/extra.tar');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/mods/extra.tar', 'tarmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['tarmods/?.lua;tarmods/?/init.lua'],
      );

      final nestedResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('nested')],
        ),
      );
      final modRead = await _call(
        interpreter,
        const ['love', 'filesystem', 'read'],
        const <Object?>['tarmods/mod.lua'],
      );
      final nested = (nestedResult.first as Value).unwrap() as Map;

      expect(modRead, <Object?>['return 88', 9]);
      expect(nested['label'], 'tar');
      expect(_unwrap(nestedResult[1]), 'tarmods/nested/init.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['tarmods/mod.lua'],
        ),
        '/mods/extra.tar',
      );
    },
  );

  test(
    'filesystem mounts tar.bz2 archives from string paths as virtual roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/mods/extra.tbz2',
        _encodeTarBzip2(<String, String>{
          'mod.lua': 'return 89',
          'nested/init.lua': 'return { label = "tbz2" }',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      _allowStringMount(interpreter, '/mods/extra.tbz2');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/mods/extra.tbz2', 'tbzmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['tbzmods/?.lua;tbzmods/?/init.lua'],
      );

      final nestedResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('nested')],
        ),
      );
      final modRead = await _call(
        interpreter,
        const ['love', 'filesystem', 'read'],
        const <Object?>['tbzmods/mod.lua'],
      );
      final nested = (nestedResult.first as Value).unwrap() as Map;

      expect(modRead, <Object?>['return 89', 9]);
      expect(nested['label'], 'tbz2');
      expect(_unwrap(nestedResult[1]), 'tbzmods/nested/init.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['tbzmods/mod.lua'],
        ),
        '/mods/extra.tbz2',
      );
    },
  );

  test(
    'filesystem mounts tar.gz archives from FileData as virtual readable roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      final archiveData = await _call(
        interpreter,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[
          _encodeTarGzip(<String, String>{
            'pkg/init.lua': 'return { value = 42 }',
            'notes.txt': 'hello from tgz',
          }),
          'mods.tgz',
        ],
      );
      expect(archiveData, isA<Map>());

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[archiveData, 'tgzmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['tgzmods/?.lua;tgzmods/?/init.lua'],
      );

      final moduleResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('pkg')],
        ),
      );
      final module = _unwrap(moduleResult.first) as Map;

      expect(module['value'], 42);
      expect(_unwrap(moduleResult[1]), 'tgzmods/pkg/init.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['tgzmods/notes.txt'],
        ),
        <Object?>['hello from tgz', 14],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['tgzmods/notes.txt'],
        ),
        <Object?>[null, 'File does not exist on disk.'],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          <Object?>[archiveData],
        ),
        isTrue,
      );
    },
  );

  test(
    'filesystem mounts tar.xz archives from FileData as virtual readable roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      final archiveData = await _call(
        interpreter,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[
          _encodeTarXz(<String, String>{
            'pkg/init.lua': 'return { value = 43 }',
            'notes.txt': 'hello from txz',
          }),
          'mods.txz',
        ],
      );
      expect(archiveData, isA<Map>());

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[archiveData, 'txzmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['txzmods/?.lua;txzmods/?/init.lua'],
      );

      final moduleResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('pkg')],
        ),
      );
      final module = _unwrap(moduleResult.first) as Map;

      expect(module['value'], 43);
      expect(_unwrap(moduleResult[1]), 'txzmods/pkg/init.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['txzmods/notes.txt'],
        ),
        <Object?>['hello from txz', 14],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['txzmods/notes.txt'],
        ),
        <Object?>[null, 'File does not exist on disk.'],
      );
    },
  );

  test(
    'filesystem mounts wad archives from string paths as virtual roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/mods/extra.wad',
        _encodeWad(<String, String>{
          'mod.lua': 'return 93',
          'readme': 'hello wad',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      _allowStringMount(interpreter, '/mods/extra.wad');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/mods/extra.wad', 'wadmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['wadmods/?.lua'],
      );

      final moduleResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('mod')],
        ),
      );

      expect(_unwrap(moduleResult.first), 93);
      expect(_unwrap(moduleResult[1]), 'wadmods/mod.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['wadmods/readme'],
        ),
        <Object?>['hello wad', 9],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getDirectoryItems'],
          const <Object?>['wadmods'],
        ),
        <Object?, Object?>{1: 'mod.lua', 2: 'readme'},
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['wadmods/mod.lua'],
        ),
        '/mods/extra.wad',
      );
    },
  );

  test(
    'filesystem mounts mvl archives from FileData as virtual readable roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      final archiveData = await _call(
        interpreter,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[
          _encodeMvl(<String, String>{
            'mod.lua': 'return 94',
            'note.txt': 'hello mvl',
          }),
          'mods.mvl',
        ],
      );
      expect(archiveData, isA<Map>());

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[archiveData, 'mvlmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['mvlmods/?.lua'],
      );

      final moduleResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('mod')],
        ),
      );

      expect(_unwrap(moduleResult.first), 94);
      expect(_unwrap(moduleResult[1]), 'mvlmods/mod.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['mvlmods/note.txt'],
        ),
        <Object?>['hello mvl', 9],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['mvlmods/note.txt'],
        ),
        <Object?>[null, 'File does not exist on disk.'],
      );
    },
  );

  test(
    'filesystem mounts hog archives from string paths as virtual roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/mods/extra.hog',
        _encodeHog(<String, String>{
          'mod.lua': 'return 95',
          'note.txt': 'hello hog',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      _allowStringMount(interpreter, '/mods/extra.hog');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/mods/extra.hog', 'hogmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['hogmods/?.lua'],
      );

      final moduleResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('mod')],
        ),
      );

      expect(_unwrap(moduleResult.first), 95);
      expect(_unwrap(moduleResult[1]), 'hogmods/mod.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['hogmods/note.txt'],
        ),
        <Object?>['hello hog', 9],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['hogmods/mod.lua'],
        ),
        '/mods/extra.hog',
      );
    },
  );

  test(
    'filesystem mounts grp archives from string paths as virtual roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/mods/extra.grp',
        _encodeGrp(<String, String>{
          'mod.lua': 'return 96',
          'readme.txt': 'hello grp',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      _allowStringMount(interpreter, '/mods/extra.grp');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/mods/extra.grp', 'grpmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['grpmods/?.lua'],
      );

      final moduleResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('mod')],
        ),
      );

      expect(_unwrap(moduleResult.first), 96);
      expect(_unwrap(moduleResult[1]), 'grpmods/mod.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['grpmods/readme.txt'],
        ),
        <Object?>['hello grp', 9],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['grpmods/mod.lua'],
        ),
        '/mods/extra.grp',
      );
    },
  );

  test(
    'filesystem mounts pak archives from string paths as virtual roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/mods/extra.pak',
        _encodePak(<String, String>{
          'mod.lua': 'return 97',
          'nested/init.lua': 'return { label = "pak" }',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      _allowStringMount(interpreter, '/mods/extra.pak');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/mods/extra.pak', 'pakmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['pakmods/?.lua;pakmods/?/init.lua'],
      );

      final moduleResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('mod')],
        ),
      );
      final nestedResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('nested')],
        ),
      );
      final nested = _unwrap(nestedResult.first) as Map;

      expect(_unwrap(moduleResult.first), 97);
      expect(_unwrap(moduleResult[1]), 'pakmods/mod.lua');
      expect(nested['label'], 'pak');
      expect(_unwrap(nestedResult[1]), 'pakmods/nested/init.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['pakmods/mod.lua'],
        ),
        '/mods/extra.pak',
      );
    },
  );

  test(
    'filesystem mounts slb archives from string paths as virtual roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/mods/extra.slb',
        _encodeSlb(<String, String>{
          'mod.lua': 'return 98',
          'nested/init.lua': 'return { label = "slb" }',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      _allowStringMount(interpreter, '/mods/extra.slb');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/mods/extra.slb', 'slbmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['slbmods/?.lua;slbmods/?/init.lua'],
      );

      final moduleResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('mod')],
        ),
      );
      final nestedResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('nested')],
        ),
      );
      final nested = _unwrap(nestedResult.first) as Map;

      expect(_unwrap(moduleResult.first), 98);
      expect(_unwrap(moduleResult[1]), 'slbmods/mod.lua');
      expect(nested['label'], 'slb');
      expect(_unwrap(nestedResult[1]), 'slbmods/nested/init.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['slbmods/mod.lua'],
        ),
        '/mods/extra.slb',
      );
    },
  );

  test(
    'filesystem mounts vdf archives from FileData as virtual readable roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      final archiveData = await _call(
        interpreter,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[
          _encodeVdf(
            <String, String>{
              'mod.lua': 'return 99',
              'nested/init.lua': 'return { label = "vdf" }',
            },
            directories: <String>['nested'],
          ),
          'mods.vdf',
        ],
      );
      expect(archiveData, isA<Map>());

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[archiveData, 'vdfmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['vdfmods/?.lua;vdfmods/?/init.lua'],
      );

      final moduleResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('mod')],
        ),
      );
      final nestedResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('nested')],
        ),
      );
      final nested = _unwrap(nestedResult.first) as Map;

      expect(_unwrap(moduleResult.first), 99);
      expect(_unwrap(moduleResult[1]), 'vdfmods/mod.lua');
      expect(nested['label'], 'vdf');
      expect(_unwrap(nestedResult[1]), 'vdfmods/nested/init.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['vdfmods/nested/init.lua'],
        ),
        <Object?>['return { label = "vdf" }', 24],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['vdfmods/mod.lua'],
        ),
        <Object?>[null, 'File does not exist on disk.'],
      );
    },
  );

  test(
    'filesystem mounts iso archives from string paths as virtual roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/mods/extra.iso',
        _encodeIso(<String, String>{
          'mod.lua': 'return 100',
          'nested/init.lua': 'return { label = "iso" }',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      _allowStringMount(interpreter, '/mods/extra.iso');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/mods/extra.iso', 'isomods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['isomods/?.lua;isomods/?/init.lua'],
      );

      final moduleResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('mod')],
        ),
      );
      final nestedResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('nested')],
        ),
      );
      final nested = _unwrap(nestedResult.first) as Map;

      expect(_unwrap(moduleResult.first), 100);
      expect(_unwrap(moduleResult[1]), 'isomods/mod.lua');
      expect(nested['label'], 'iso');
      expect(_unwrap(nestedResult[1]), 'isomods/nested/init.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['isomods/mod.lua'],
        ),
        '/mods/extra.iso',
      );
    },
  );

  test('filesystem mount rejects invalid .7z archives cleanly', () async {
    final adapter = _TestLoveFilesystemAdapter();
    adapter.addFileBytes('/mods/extra.7z', _fake7zBytes());

    final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
    final interpreter = runtime.runtime as Interpreter;
    _allowStringMount(interpreter, '/mods/extra.7z');

    expect(
      await _call(
        interpreter,
        const ['love', 'filesystem', 'mount'],
        const <Object?>['/mods/extra.7z', 'sevenmods', true],
      ),
      isFalse,
    );
    expect(
      await _call(
        interpreter,
        const ['love', 'filesystem', 'read'],
        const <Object?>['sevenmods/mod.lua'],
      ),
      <Object?>[null, 'Could not open file sevenmods/mod.lua. Does not exist.'],
    );
  });

  test(
    'filesystem mounts 7z archives from string paths as virtual roots',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/mods/extra.7z',
        _encode7z(<String, String>{
          'mod.lua': 'return 97',
          'nested/init.lua': 'return { label = "7z" }',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      _allowStringMount(interpreter, '/mods/extra.7z');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/mods/extra.7z', 'sevenmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['sevenmods/?.lua;sevenmods/?/init.lua'],
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['sevenmods/mod.lua'],
        ),
        <Object?>['return 97', 9],
      );

      final nestedResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('nested')],
        ),
      );
      final nested = (nestedResult.first as Value).unwrap() as Map;
      expect(nested['label'], '7z');
      expect(_unwrap(nestedResult[1]), 'sevenmods/nested/init.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['sevenmods/mod.lua'],
        ),
        '/mods/extra.7z',
      );
    },
    skip: _sevenZipSupportSkipReason,
  );

  test(
    'filesystem mounts 7z archives with literal dash-prefixed entry names',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/mods/literal.7z',
        _encode7z(<String, String>{
          '-leading.lua': 'return "leading"',
          '[notes].txt': 'literal brackets',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      _allowStringMount(interpreter, '/mods/literal.7z');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/mods/literal.7z', 'literalmods', true],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['literalmods/-leading.lua'],
        ),
        <Object?>['return "leading"', 16],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['literalmods/[notes].txt'],
        ),
        <Object?>['literal brackets', 16],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['literalmods/-leading.lua'],
        ),
        '/mods/literal.7z',
      );
    },
    skip: _sevenZipSupportSkipReason,
  );

  test(
    'filesystem mount falls back to openFile when direct archive byte reads throw',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/mods/fallback.zip',
        _encodeZip(<String, String>{
          'mod.lua': 'return 91',
          'nested/init.lua': 'return { label = "fallback" }',
        }),
      );
      adapter.failReadFileBytes('/mods/fallback.zip', 'direct reads disabled');

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      _allowStringMount(interpreter, '/mods/fallback.zip');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/mods/fallback.zip', 'fallbackmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['fallbackmods/?.lua;fallbackmods/?/init.lua'],
      );

      final nestedResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('nested')],
        ),
      );
      final modRead = await _call(
        interpreter,
        const ['love', 'filesystem', 'read'],
        const <Object?>['fallbackmods/mod.lua'],
      );
      final nested = (nestedResult.first as Value).unwrap() as Map;

      expect(modRead, <Object?>['return 91', 9]);
      expect(nested['label'], 'fallback');
      expect(_unwrap(nestedResult[1]), 'fallbackmods/nested/init.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['fallbackmods/mod.lua'],
        ),
        '/mods/fallback.zip',
      );
    },
  );

  test(
    'filesystem rejects source-relative string mounts and allows save-relative ones',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/source/packs/source_mod.zip',
        _encodeZip(<String, String>{
          'feature.lua': 'return { enabled = false }',
          'notes.txt': 'hello from source zip',
        }),
      );
      adapter.addFileBytes(
        '/appdata/love/game/packs/save_mod.zip',
        _encodeZip(<String, String>{
          'feature.lua': 'return { enabled = true }',
          'notes.txt': 'hello from save zip',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game'],
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['packs/source_mod.zip', 'srczip', true],
        ),
        isFalse,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['packs/save_mod.zip', 'savezip', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['savezip/?.lua;?.lua'],
      );

      final featureResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('feature')],
        ),
      );
      final feature = _unwrap(featureResult.first) as Map;

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['srczip/notes.txt'],
        ),
        isNull,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['savezip/notes.txt'],
        ),
        <Object?>['hello from save zip', 19],
      );
      expect(feature['enabled'], isTrue);
      expect(_unwrap(featureResult[1]), 'savezip/feature.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['savezip/notes.txt'],
        ),
        '/appdata/love/game/packs/save_mod.zip',
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          const <Object?>['packs/save_mod.zip'],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['savezip/notes.txt'],
        ),
        isNull,
      );
    },
  );

  test(
    'filesystem mount and unmount reject unsafe and non-allowlisted full paths like upstream',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/source/packs/source_mod.zip',
        _encodeZip(<String, String>{
          'feature.lua': 'return { enabled = true }',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['packs/../packs/source_mod.zip', 'unsafe', true],
        ),
        isFalse,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/', 'unsafe', true],
        ),
        isFalse,
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/source/packs/source_mod.zip', 'safe', true],
        ),
        isFalse,
      );

      _allowStringMount(interpreter, '/source/packs/source_mod.zip');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/source/packs/source_mod.zip', 'safe', true],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['safe/feature.lua'],
        ),
        <Object?>['return { enabled = true }', 25],
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          const <Object?>['packs/../packs/source_mod.zip'],
        ),
        isFalse,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          const <Object?>['/'],
        ),
        isFalse,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['safe/feature.lua'],
        ),
        <Object?>['return { enabled = true }', 25],
      );
    },
  );

  test(
    'filesystem mount rejects string archive paths containing dot-dot substrings like upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/main.lua', 'return true');
      adapter.addFileBytes(
        '/appdata/love/game/packs/source..mod.zip',
        _encodeZip(<String, String>{
          'feature.lua': 'return { enabled = true }',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setIdentity'],
        const <Object?>['game'],
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['packs/source..mod.zip', 'unsafe', true],
        ),
        isFalse,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          const <Object?>['packs/source..mod.zip'],
        ),
        isFalse,
      );
    },
  );

  test(
    'filesystem string mounts reject archive paths only reachable through another mounted root',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/outside/base/inner.zip',
        _encodeZip(<String, String>{'module.lua': 'return { mounted = true }'}),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      _allowStringMount(interpreter, '/outside/base');

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/outside/base', 'modsbase', true],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['modsbase/inner.zip', 'nestedmods', true],
        ),
        isFalse,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['nestedmods/module.lua'],
        ),
        isNull,
      );
    },
  );

  test(
    'filesystem mounts generic Data wrappers with explicit archive names',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      final archiveData = _genericDataWrapper(
        _encodeZip(<String, String>{'pkg/init.lua': 'return { value = 314 }'}),
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[archiveData, 'generic.zip', 'generic', true],
        ),
        isTrue,
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['generic/pkg/init.lua'],
        ),
        <Object?>['return { value = 314 }', 22],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['generic/pkg/init.lua'],
        ),
        <Object?>[null, 'File does not exist on disk.'],
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          <Object?>[archiveData],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['generic/pkg/init.lua'],
        ),
        isNull,
      );
    },
  );

  test(
    'filesystem mounts generic Data wrappers with explicit 7z archive names',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      final archiveData = _genericDataWrapper(
        _encode7z(<String, String>{
          'pkg/init.lua': 'return { value = 717, kind = "7z" }',
        }),
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[archiveData, 'generic.7z', 'generic7z', true],
        ),
        isTrue,
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['generic7z/pkg/init.lua'],
        ),
        <Object?>['return { value = 717, kind = "7z" }', 35],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['generic7z/pkg/init.lua'],
        ),
        <Object?>[null, 'File does not exist on disk.'],
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          <Object?>[archiveData],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['generic7z/pkg/init.lua'],
        ),
        isNull,
      );
    },
    skip: _sevenZipSupportSkipReason,
  );

  test(
    'filesystem mount overloads preserve upstream FileData and Data argument selection',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      final fileData = await _call(
        interpreter,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[
          _encodeZip(<String, String>{'pkg/init.lua': 'return { value = 12 }'}),
          'mods.zip',
        ],
      );
      expect(fileData, isA<Map>());

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[fileData, 123, true],
        ),
        isTrue,
        reason:
            'FileData + non-string arg3 should use the implicit filename overload like upstream Lua wrappers',
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['123/pkg/init.lua'],
        ),
        <Object?>['return { value = 12 }', 21],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          <Object?>[fileData],
        ),
        isTrue,
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[fileData, 456, 789, true],
        ),
        isTrue,
        reason:
            'FileData + string-like arg3 should use the explicit archive-name overload like upstream Lua wrappers',
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['789/pkg/init.lua'],
        ),
        <Object?>['return { value = 12 }', 21],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          const <Object?>[456],
        ),
        isTrue,
      );

      final archiveData = _genericDataWrapper(
        _encodeZip(<String, String>{'pkg/init.lua': 'return { value = 34 }'}),
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[archiveData, 987, 654, true],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['654/pkg/init.lua'],
        ),
        <Object?>['return { value = 34 }', 21],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          const <Object?>[987],
        ),
        isTrue,
      );
    },
  );

  test(
    'filesystem data mounts support archive-name unmounts and multiple mounts per source',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      final archiveData = await _call(
        interpreter,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[
          _encodeZip(<String, String>{
            'pkg/init.lua': 'return { value = 271 }',
            'readme.txt': 'shared archive',
          }),
          'mods.zip',
        ],
      );
      expect(archiveData, isA<Map>());

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[archiveData, 'firstmods', true],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[archiveData, 'alias.zip', 'secondmods', true],
        ),
        isTrue,
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['firstmods/readme.txt'],
        ),
        <Object?>['shared archive', 14],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['secondmods/readme.txt'],
        ),
        <Object?>['shared archive', 14],
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          const <Object?>['mods.zip'],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['firstmods/readme.txt'],
        ),
        isNull,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['secondmods/readme.txt'],
        ),
        <Object?>['shared archive', 14],
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          <Object?>[archiveData],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['secondmods/readme.txt'],
        ),
        isNull,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          const <Object?>['alias.zip'],
        ),
        isFalse,
      );
    },
  );

  test(
    'filesystem duplicate data mount archive names preserve the first mount but update unmount ownership like upstream',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      final firstArchive = _genericDataWrapper(
        _encodeZip(<String, String>{'pkg/init.lua': 'return { value = 1 }'}),
      );
      final secondArchive = _genericDataWrapper(
        _encodeZip(<String, String>{'pkg/init.lua': 'return { value = 2 }'}),
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[firstArchive, 'shared.zip', 'mods1', true],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[secondArchive, 'shared.zip', 'mods2', true],
        ),
        isTrue,
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['mods1/pkg/init.lua'],
        ),
        <Object?>['return { value = 1 }', 20],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['mods2/pkg/init.lua'],
        ),
        isNull,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          <Object?>[firstArchive],
        ),
        isFalse,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          <Object?>[secondArchive],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['mods1/pkg/init.lua'],
        ),
        isNull,
      );
    },
  );

  test(
    'filesystem wraps DroppedFile objects and mounts dropped archives',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/drop/mod.zip',
        _encodeZip(<String, String>{
          'dropped.lua': 'return { dropped = true }',
          'readme.txt': 'from dropped zip',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      final dropped = await wrapLoveFilesystemDroppedFileForRuntime(
        interpreter,
        LoveFilesystemDroppedFile(
          state: LoveFilesystemState.attach(interpreter),
          filename: '/drop/mod.zip',
        ),
      );

      expect(await _callMethod(dropped, 'type'), 'DroppedFile');
      expect(
        await _callMethod(dropped, 'typeOf', const <Object?>['DroppedFile']),
        isTrue,
      );
      expect(
        await _callMethod(dropped, 'typeOf', const <Object?>['File']),
        isTrue,
      );
      expect(await _callMethod(dropped, 'getExtension'), 'zip');
      expect(await _callMethod(dropped, 'getFilename'), '/drop/mod.zip');
      expect(await _callMethod(dropped, 'open', const <Object?>['r']), isTrue);
      expect(await _callMethod(dropped, 'getSize'), greaterThan(0));
      expect(await _callMethod(dropped, 'close'), isTrue);

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[dropped, 'droppedmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['droppedmods/?.lua;?.lua'],
      );

      final droppedResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('dropped')],
        ),
      );
      final module = _unwrap(droppedResult.first) as Map;

      expect(module['dropped'], isTrue);
      expect(_unwrap(droppedResult[1]), 'droppedmods/dropped.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['droppedmods/readme.txt'],
        ),
        <Object?>['from dropped zip', 16],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['droppedmods/readme.txt'],
        ),
        '/drop/mod.zip',
      );
    },
  );

  test(
    'filesystem wraps DroppedFile objects and mounts dropped 7z archives',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/drop/mod.7z',
        _encode7z(<String, String>{
          'dropped.lua': 'return { dropped = "7z" }',
          'readme.txt': 'from dropped 7z',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      final dropped = await wrapLoveFilesystemDroppedFileForRuntime(
        interpreter,
        LoveFilesystemDroppedFile(
          state: LoveFilesystemState.attach(interpreter),
          filename: '/drop/mod.7z',
        ),
      );

      expect(await _callMethod(dropped, 'type'), 'DroppedFile');
      expect(await _callMethod(dropped, 'getExtension'), '7z');
      expect(await _callMethod(dropped, 'getFilename'), '/drop/mod.7z');
      expect(await _callMethod(dropped, 'open', const <Object?>['r']), isTrue);
      expect(await _callMethod(dropped, 'getSize'), greaterThan(0));
      expect(await _callMethod(dropped, 'close'), isTrue);

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          <Object?>[dropped, 'dropped7zmods', true],
        ),
        isTrue,
      );
      await _call(
        interpreter,
        const ['love', 'filesystem', 'setRequirePath'],
        const <Object?>['dropped7zmods/?.lua;?.lua'],
      );

      final droppedResult = _rawResults(
        await _callRawPath(
          interpreter,
          const ['require'],
          <Object?>[Value('dropped')],
        ),
      );
      final module = _unwrap(droppedResult.first) as Map;

      expect(module['dropped'], '7z');
      expect(_unwrap(droppedResult[1]), 'dropped7zmods/dropped.lua');
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['dropped7zmods/readme.txt'],
        ),
        <Object?>['from dropped 7z', 15],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['dropped7zmods/readme.txt'],
        ),
        '/drop/mod.7z',
      );
    },
    skip: _sevenZipSupportSkipReason,
  );

  test(
    'filesystem dropped file wrappers allow later string mounts of the dropped filename',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/drop/mod.zip',
        _encodeZip(<String, String>{
          'dropped.lua': 'return { dropped = true }',
          'readme.txt': 'from dropped zip',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await wrapLoveFilesystemDroppedFileForRuntime(
        interpreter,
        LoveFilesystemDroppedFile(
          state: LoveFilesystemState.attach(interpreter),
          filename: '/drop/mod.zip',
        ),
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/drop/mod.zip', 'namedmods', true],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['namedmods/readme.txt'],
        ),
        <Object?>['from dropped zip', 16],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          const <Object?>['/drop/mod.zip'],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['namedmods/readme.txt'],
        ),
        isNull,
      );
    },
  );

  test(
    'filesystem dropped 7z file wrappers allow later string mounts of the dropped filename',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFileBytes(
        '/drop/mod.7z',
        _encode7z(<String, String>{
          'dropped.lua': 'return { dropped = "7z" }',
          'readme.txt': 'from dropped 7z',
        }),
      );

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await wrapLoveFilesystemDroppedFileForRuntime(
        interpreter,
        LoveFilesystemDroppedFile(
          state: LoveFilesystemState.attach(interpreter),
          filename: '/drop/mod.7z',
        ),
      );

      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'mount'],
          const <Object?>['/drop/mod.7z', 'named7zmods', true],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['named7zmods/readme.txt'],
        ),
        <Object?>['from dropped 7z', 15],
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'unmount'],
          const <Object?>['/drop/mod.7z'],
        ),
        isTrue,
      );
      expect(
        await _call(
          interpreter,
          const ['love', 'filesystem', 'getInfo'],
          const <Object?>['named7zmods/readme.txt'],
        ),
        isNull,
      );
    },
    skip: _sevenZipSupportSkipReason,
  );

  test(
    'filesystem File:lines reads dropped files through the file object',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/drop/notes.txt', 'alpha\nbeta\n');

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      final dropped = await wrapLoveFilesystemDroppedFileForRuntime(
        interpreter,
        LoveFilesystemDroppedFile(
          state: LoveFilesystemState.attach(interpreter),
          filename: '/drop/notes.txt',
        ),
      );

      final iterator = await _callMethod(dropped, 'lines');
      expect(await _callBuiltin(iterator!), 'alpha');
      expect(await _callMethod(dropped, 'tell'), 6);
      expect(await _callBuiltin(iterator), 'beta');
      expect(await _callMethod(dropped, 'tell'), 11);
      expect(await _callBuiltin(iterator), isNull);
      expect(await _callMethod(dropped, 'isOpen'), isFalse);
    },
  );

  test(
    'filesystem DroppedFile buffer sizing preserves upstream BUFFER_NONE normalization',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/drop/notes.txt', 'alpha\nbeta\n');

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      final dropped = await wrapLoveFilesystemDroppedFileForRuntime(
        interpreter,
        LoveFilesystemDroppedFile(
          state: LoveFilesystemState.attach(interpreter),
          filename: '/drop/notes.txt',
        ),
      );

      expect(
        await _callMethod(dropped, 'setBuffer', const <Object?>['none', 9.9]),
        isTrue,
      );
      expect(await _callMethod(dropped, 'getBuffer'), <Object?>['none', 0]);

      expect(await _callMethod(dropped, 'open', const <Object?>['r']), isTrue);
      expect(adapter.lastOpenedDevice, isNotNull);
      expect(adapter.lastOpenedDevice!.bufferMode, BufferMode.none);
      expect(adapter.lastOpenedDevice!.bufferSize, 0);
      expect(await _callMethod(dropped, 'getBuffer'), <Object?>['none', 0]);
    },
  );

  test(
    'filesystem DroppedFile buffer failures preserve upstream fallback and false-return semantics',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/drop/notes.txt', 'alpha\nbeta\n');

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      final dropped = await wrapLoveFilesystemDroppedFileForRuntime(
        interpreter,
        LoveFilesystemDroppedFile(
          state: LoveFilesystemState.attach(interpreter),
          filename: '/drop/notes.txt',
        ),
      );

      expect(
        await _callMethod(dropped, 'setBuffer', const <Object?>['full', 12]),
        isTrue,
      );
      expect(await _callMethod(dropped, 'getBuffer'), <Object?>['full', 12]);

      adapter.setBufferingFailureError = 'buffer apply failed';
      expect(await _callMethod(dropped, 'open', const <Object?>['r']), isTrue);
      expect(await _callMethod(dropped, 'getBuffer'), <Object?>['none', 0]);

      expect(
        await _callMethod(dropped, 'setBuffer', const <Object?>['line', 7]),
        isFalse,
      );
      expect(await _callMethod(dropped, 'getBuffer'), <Object?>['none', 0]);
    },
  );

  test(
    'filesystem DroppedFile open failure semantics match upstream LOVE',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/drop/blocked.txt', 'payload');
      adapter.failOpen('/drop/blocked.txt', 'permission denied');

      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;
      final dropped = await wrapLoveFilesystemDroppedFileForRuntime(
        interpreter,
        LoveFilesystemDroppedFile(
          state: LoveFilesystemState.attach(interpreter),
          filename: '/drop/blocked.txt',
        ),
      );

      final readResult = _rawResults(
        await _callMethod(dropped, 'open', const <Object?>['r']),
      );
      expect(readResult[0], isNull);
      expect(
        _unwrap(readResult[1]),
        'Could not open file /drop/blocked.txt. Does not exist.',
      );
      expect(await _callMethod(dropped, 'getMode'), 'c');

      final writeResult = _rawResults(
        await _callMethod(dropped, 'open', const <Object?>['w']),
      );
      expect(writeResult, <Object?>[false]);
      expect(await _callMethod(dropped, 'isOpen'), isFalse);
      expect(await _callMethod(dropped, 'getMode'), 'w');
    },
  );

  test(
    'filesystem installs source-compatible helper functions from upstream',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/main.lua', 'return true');

      final runtime = Interpreter();
      installLove2d(runtime: runtime, filesystemAdapter: adapter);

      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'setFused'],
          const <Object?>[true],
        ),
        isNull,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', '_setAndroidSaveExternal'],
          const <Object?>[true],
        ),
        isNull,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'setIdentity'],
          const <Object?>['game'],
        ),
        isNull,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'setSource'],
          const <Object?>['/source'],
        ),
        isNull,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'createDirectory'],
          const <Object?>['saves'],
        ),
        isTrue,
      );

      expect(
        await _call(runtime, const ['love', 'filesystem', 'getExecutablePath']),
        '/bin/lualike-test',
      );
      expect(
        await _call(runtime, const ['love', 'filesystem', 'getSaveDirectory']),
        '/appdata/game',
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'exists'],
          const <Object?>['main.lua'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'isFile'],
          const <Object?>['main.lua'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'isDirectory'],
          const <Object?>['saves'],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'isSymlink'],
          const <Object?>['main.lua'],
        ),
        isFalse,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getLastModified'],
          const <Object?>['main.lua'],
        ),
        0,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'filesystem', 'getSize'],
          const <Object?>['main.lua'],
        ),
        11,
      );
    },
  );

  test(
    'filesystem File and FileData wrappers expose LOVE object semantics',
    () async {
      final adapter = _TestLoveFilesystemAdapter();
      adapter.addFile('/source/objects.txt', 'hello');
      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime as Interpreter;

      await _call(
        interpreter,
        const ['love', 'filesystem', 'setSource'],
        const <Object?>['/source'],
      );

      final file = await _call(
        interpreter,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['objects.txt'],
      );
      expect(await _callMethod(file!, 'type'), 'File');
      expect(
        await _callMethod(file, 'typeOf', const <Object?>['File']),
        isTrue,
      );
      expect(
        await _callMethod(file, 'typeOf', const <Object?>['Object']),
        isTrue,
      );
      expect(await _callMethod(file, 'open', const <Object?>['r']), isTrue);
      expect(await _callMethod(file, 'release'), isTrue);
      expect(await _callMethod(file, 'isOpen'), isFalse);
      expect(await _callMethod(file, 'release'), isFalse);

      final fileData = await _call(
        interpreter,
        const ['love', 'filesystem', 'newFileData'],
        const <Object?>['payload', 'payload.bin'],
      );
      expect(await _callMethod(fileData!, 'type'), 'FileData');
      expect(
        await _callMethod(fileData, 'typeOf', const <Object?>['FileData']),
        isTrue,
      );
      expect(
        await _callMethod(fileData, 'typeOf', const <Object?>['Data']),
        isTrue,
      );
      expect(
        await _callMethod(fileData, 'typeOf', const <Object?>['Object']),
        isTrue,
      );
      expect(await _callMethod(fileData, 'getSize'), 7);
      expect(await _callMethod(fileData, 'release'), isTrue);
      expect(await _callMethod(fileData, 'release'), isFalse);
    },
  );

  test(
    'filesystem setFused only honors the first upstream-compatible call',
    () async {
      final firstRuntime = Interpreter();
      installLove2d(
        runtime: firstRuntime,
        filesystemAdapter: _TestLoveFilesystemAdapter(),
      );

      expect(
        await _call(firstRuntime, const ['love', 'filesystem', 'isFused']),
        isFalse,
      );
      expect(
        await _call(
          firstRuntime,
          const ['love', 'filesystem', 'setFused'],
          const <Object?>[false],
        ),
        isNull,
      );
      expect(
        await _call(firstRuntime, const ['love', 'filesystem', 'isFused']),
        isFalse,
      );
      expect(
        await _call(
          firstRuntime,
          const ['love', 'filesystem', 'setFused'],
          const <Object?>[true],
        ),
        isNull,
      );
      expect(
        await _call(firstRuntime, const ['love', 'filesystem', 'isFused']),
        isFalse,
      );

      final secondRuntime = Interpreter();
      installLove2d(
        runtime: secondRuntime,
        filesystemAdapter: _TestLoveFilesystemAdapter(),
      );

      expect(
        await _call(
          secondRuntime,
          const ['love', 'filesystem', 'setFused'],
          const <Object?>[true],
        ),
        isNull,
      );
      expect(
        await _call(secondRuntime, const ['love', 'filesystem', 'isFused']),
        isTrue,
      );
      expect(
        await _call(
          secondRuntime,
          const ['love', 'filesystem', 'setFused'],
          const <Object?>[false],
        ),
        isNull,
      );
      expect(
        await _call(secondRuntime, const ['love', 'filesystem', 'isFused']),
        isTrue,
      );
    },
  );
}

List<int> _encodeZip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.add(ArchiveFile.string(entry.key, entry.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

List<int> _encodePrefixedZip(Map<String, String> files) {
  return <int>[
    0x4d,
    0x5a,
    0x90,
    0x00,
    0x03,
    0x00,
    0x00,
    0x00,
    ..._encodeZip(files),
    0x00,
    0x00,
    0x00,
    0x00,
  ];
}

List<int> _encodeTar(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.add(ArchiveFile.string(entry.key, entry.value));
  }
  return TarEncoder().encodeBytes(archive);
}

List<int> _encodeTarGzip(Map<String, String> files) {
  return GZipEncoder().encodeBytes(_encodeTar(files));
}

List<int> _encodeTarBzip2(Map<String, String> files) {
  return BZip2Encoder().encodeBytes(_encodeTar(files));
}

List<int> _encodeTarXz(Map<String, String> files) {
  return XZEncoder().encodeBytes(_encodeTar(files));
}

List<int> _encodeWad(Map<String, String> files) {
  final data = <int>[];
  final directory = <int>[];
  var fileOffset = 12;
  for (final entry in files.entries) {
    final List<int> bytes = ascii.encode(entry.value);
    directory
      ..addAll(_u32le(fileOffset))
      ..addAll(_u32le(bytes.length))
      ..addAll(_fixedAsciiBytes(entry.key, 8));
    data.addAll(bytes);
    fileOffset += bytes.length;
  }

  return <int>[
    ...ascii.encode('PWAD'),
    ..._u32le(files.length),
    ..._u32le(12 + data.length),
    ...data,
    ...directory,
  ];
}

List<int> _encodeMvl(Map<String, String> files) {
  final directory = <int>[];
  final data = <int>[];
  for (final entry in files.entries) {
    final List<int> bytes = ascii.encode(entry.value);
    directory
      ..addAll(_fixedAsciiBytes(entry.key, 13))
      ..addAll(_u32le(bytes.length));
    data.addAll(bytes);
  }

  return <int>[
    ...ascii.encode('DMVL'),
    ..._u32le(files.length),
    ...directory,
    ...data,
  ];
}

List<int> _encodeHog(Map<String, String> files) {
  final archive = <int>[...ascii.encode('DHF')];
  for (final entry in files.entries) {
    final List<int> bytes = ascii.encode(entry.value);
    archive
      ..addAll(_fixedAsciiBytes(entry.key, 13))
      ..addAll(_u32le(bytes.length))
      ..addAll(bytes);
  }

  return archive;
}

List<int> _encodeGrp(Map<String, String> files) {
  final directory = <int>[];
  final data = <int>[];
  for (final entry in files.entries) {
    final List<int> bytes = ascii.encode(entry.value);
    directory
      ..addAll(_fixedSpacePaddedAsciiBytes(entry.key, 12))
      ..addAll(_u32le(bytes.length));
    data.addAll(bytes);
  }

  return <int>[
    ...ascii.encode('KenSilverman'),
    ..._u32le(files.length),
    ...directory,
    ...data,
  ];
}

List<int> _encodePak(Map<String, String> files) {
  final data = <int>[];
  final directory = <int>[];
  var fileOffset = 12;
  for (final entry in files.entries) {
    final List<int> bytes = ascii.encode(entry.value);
    directory
      ..addAll(_fixedAsciiBytes(entry.key, 56))
      ..addAll(_u32le(fileOffset))
      ..addAll(_u32le(bytes.length));
    data.addAll(bytes);
    fileOffset += bytes.length;
  }

  return <int>[
    ...ascii.encode('PACK'),
    ..._u32le(12 + data.length),
    ..._u32le(directory.length),
    ...data,
    ...directory,
  ];
}

List<int> _encodeIso(Map<String, String> files) {
  const sectorSize = 2048;
  final root = _buildIsoDirectoryTree(files);
  _computeIsoDirectorySizes(root);

  final directories = <_IsoDirectoryNode>[];
  _collectIsoDirectories(root, directories);

  var nextSector = 18;
  for (final directory in directories) {
    directory.extent = nextSector;
    nextSector += (directory.size + sectorSize - 1) ~/ sectorSize;
  }

  final fileEntries = <_IsoFileEntry>[];
  _collectIsoFiles(root, fileEntries);
  for (final file in fileEntries) {
    file.extent = nextSector;
    nextSector += (file.bytes.length + sectorSize - 1) ~/ sectorSize;
  }

  final image = List<int>.filled(nextSector * sectorSize, 0);
  _writeIsoPrimaryVolumeDescriptor(
    image,
    rootExtent: root.extent,
    rootSize: root.size,
    volumeSectors: nextSector,
  );
  _writeIsoVolumeDescriptorTerminator(image);

  for (final directory in directories) {
    final parent = directory.parent ?? root;
    final data = _buildIsoDirectoryData(directory, parent);
    final offset = directory.extent * sectorSize;
    image.setRange(offset, offset + data.length, data);
  }

  for (final file in fileEntries) {
    final offset = file.extent * sectorSize;
    image.setRange(offset, offset + file.bytes.length, file.bytes);
  }

  return image;
}

List<int> _encodeSlb(Map<String, String> files) {
  final data = <int>[];
  final directory = <int>[];
  var fileOffset = 12;
  for (final entry in files.entries) {
    final List<int> bytes = ascii.encode(entry.value);
    final archivePath = entry.key.replaceAll('/', '\\');
    directory
      ..add(0x5c)
      ..addAll(_fixedAsciiBytes(archivePath, 63))
      ..addAll(_u32le(fileOffset))
      ..addAll(_u32le(bytes.length));
    data.addAll(bytes);
    fileOffset += bytes.length;
  }

  return <int>[
    ..._u32le(0),
    ..._u32le(files.length),
    ..._u32le(12 + data.length),
    ...data,
    ...directory,
  ];
}

List<int> _encodeVdf(
  Map<String, String> files, {
  Iterable<String> directories = const <String>[],
}) {
  const headerSize = 256 + 16 + 24;
  final data = <int>[];
  final directory = <int>[];
  var fileOffset = headerSize;

  for (final name in directories) {
    directory
      ..addAll(_fixedSpacePaddedAsciiBytes(name, 64))
      ..addAll(_u32le(0))
      ..addAll(_u32le(0))
      ..addAll(_u32le(0x80000000))
      ..addAll(_u32le(0));
  }

  for (final entry in files.entries) {
    final List<int> bytes = ascii.encode(entry.value);
    directory
      ..addAll(_fixedSpacePaddedAsciiBytes(entry.key, 64))
      ..addAll(_u32le(fileOffset))
      ..addAll(_u32le(bytes.length))
      ..addAll(_u32le(0))
      ..addAll(_u32le(0));
    data.addAll(bytes);
    fileOffset += bytes.length;
  }

  return <int>[
    ...List<int>.filled(256, 0),
    ...ascii.encode('PSVDSC_V2.00\r\n\r\n'),
    ..._u32le(directories.length + files.length),
    ..._u32le(files.length),
    ..._u32le(_dosDateTime(DateTime(2024, 1, 2, 3, 4, 6))),
    ..._u32le(data.length),
    ..._u32le(headerSize + data.length),
    ..._u32le(0x50),
    ...data,
    ...directory,
  ];
}

List<int> _fixedAsciiBytes(String value, int length) {
  final List<int> bytes = ascii.encode(value);
  if (bytes.length > length) {
    throw ArgumentError.value(value, 'value', 'must be at most $length bytes');
  }

  return <int>[...bytes, ...List<int>.filled(length - bytes.length, 0)];
}

List<int> _fixedSpacePaddedAsciiBytes(String value, int length) {
  final List<int> bytes = ascii.encode(value);
  if (bytes.length > length) {
    throw ArgumentError.value(value, 'value', 'must be at most $length bytes');
  }

  return <int>[...bytes, ...List<int>.filled(length - bytes.length, 0x20)];
}

List<int> _u32le(int value) {
  return <int>[
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ];
}

int _dosDateTime(DateTime value) {
  return ((value.year - 1980) << 25) |
      (value.month << 21) |
      (value.day << 16) |
      (value.hour << 11) |
      (value.minute << 5) |
      (value.second ~/ 2);
}

final String? _sevenZipExecutable = _findSevenZipExecutable();
final String? _sevenZipSupportSkipReason = _sevenZipExecutable == null
    ? '7z executable not available in PATH.'
    : null;

List<int> _encode7z(Map<String, String> files) {
  final executable = _sevenZipExecutable;
  if (executable == null) {
    throw StateError('7z executable not available in PATH.');
  }

  final tempDirectory = Directory.systemTemp.createTempSync('love2d-test-7z-');
  try {
    final inputDirectory = Directory(p.join(tempDirectory.path, 'input'))
      ..createSync();
    for (final entry in files.entries) {
      File(p.join(inputDirectory.path, p.posix.normalize(entry.key)))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(entry.value);
    }

    final archivePath = p.join(tempDirectory.path, 'archive.7z');
    final roots =
        files.keys
            .map((key) => p.posix.normalize(key).split('/').first)
            .toSet()
            .toList()
          ..sort();
    final result = Process.runSync(
      executable,
      <String>['a', '-spd', '-t7z', archivePath, '--', ...roots],
      workingDirectory: inputDirectory.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'Failed to create test 7z archive: ${result.stderr ?? result.stdout}',
      );
    }

    return File(archivePath).readAsBytesSync();
  } finally {
    tempDirectory.deleteSync(recursive: true);
  }
}

String? _findSevenZipExecutable() {
  for (final candidate in const <String>['7z', '7za', '7zr']) {
    try {
      final result = Process.runSync(
        candidate,
        const <String>['i'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode == 0) {
        return candidate;
      }
    } on ProcessException {
      continue;
    }
  }

  return null;
}

List<int> _fake7zBytes() => <int>[0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0, 4];

_IsoDirectoryNode _buildIsoDirectoryTree(Map<String, String> files) {
  final root = _IsoDirectoryNode(name: '');
  for (final entry in files.entries) {
    final segments = p.posix.normalize(entry.key).split('/');
    if (segments.any((segment) => segment.isEmpty || segment == '.')) {
      throw ArgumentError.value(
        entry.key,
        'files',
        'must use normalized paths',
      );
    }

    var current = root;
    for (final segment in segments.take(segments.length - 1)) {
      current = current.directories.putIfAbsent(
        segment,
        () => _IsoDirectoryNode(name: segment, parent: current),
      );
    }

    final leaf = segments.last;
    current.files[leaf] = _IsoFileEntry(
      name: leaf,
      bytes: ascii.encode(entry.value),
    );
  }

  return root;
}

void _collectIsoDirectories(
  _IsoDirectoryNode directory,
  List<_IsoDirectoryNode> out,
) {
  out.add(directory);
  final names = directory.directories.keys.toList()..sort();
  for (final name in names) {
    _collectIsoDirectories(directory.directories[name]!, out);
  }
}

void _collectIsoFiles(_IsoDirectoryNode directory, List<_IsoFileEntry> out) {
  final fileNames = directory.files.keys.toList()..sort();
  for (final name in fileNames) {
    out.add(directory.files[name]!);
  }

  final directoryNames = directory.directories.keys.toList()..sort();
  for (final name in directoryNames) {
    _collectIsoFiles(directory.directories[name]!, out);
  }
}

void _computeIsoDirectorySizes(_IsoDirectoryNode directory) {
  for (final child in directory.directories.values) {
    _computeIsoDirectorySizes(child);
  }

  var size = _isoDirectoryRecordLength(1) * 2;
  final childDirectoryNames = directory.directories.keys.toList()..sort();
  for (final name in childDirectoryNames) {
    size += _isoDirectoryRecordLength(ascii.encode(name).length);
  }

  final fileNames = directory.files.keys.toList()..sort();
  for (final name in fileNames) {
    size += _isoDirectoryRecordLength(ascii.encode('$name;1').length);
  }

  directory.size = size;
}

int _isoDirectoryRecordLength(int identifierLength) {
  return 33 + identifierLength + (identifierLength.isEven ? 1 : 0);
}

void _writeIsoPrimaryVolumeDescriptor(
  List<int> image, {
  required int rootExtent,
  required int rootSize,
  required int volumeSectors,
}) {
  const sectorSize = 2048;
  final descriptor = List<int>.filled(sectorSize, 0);
  descriptor[0] = 1;
  descriptor.setRange(1, 6, ascii.encode('CD001'));
  descriptor[6] = 1;
  descriptor.setRange(8, 40, _fixedSpacePaddedAsciiBytes('LUALIKE', 32));
  descriptor.setRange(40, 72, _fixedSpacePaddedAsciiBytes('LOVEFS', 32));
  _writeIsoU32BothEndian(descriptor, 80, volumeSectors);
  _writeIsoU16BothEndian(descriptor, 120, 1);
  _writeIsoU16BothEndian(descriptor, 124, 1);
  _writeIsoU16BothEndian(descriptor, 128, sectorSize);
  final rootRecord = _isoDirectoryRecord(
    specialId: 0,
    isDirectory: true,
    extent: rootExtent,
    length: rootSize,
  );
  descriptor.setRange(156, 156 + rootRecord.length, rootRecord);
  descriptor[881] = 1;
  descriptor[882] = 0;
  image.setRange(16 * sectorSize, 17 * sectorSize, descriptor);
}

void _writeIsoVolumeDescriptorTerminator(List<int> image) {
  const sectorSize = 2048;
  final descriptor = List<int>.filled(sectorSize, 0);
  descriptor[0] = 255;
  descriptor.setRange(1, 6, ascii.encode('CD001'));
  descriptor[6] = 1;
  image.setRange(17 * sectorSize, 18 * sectorSize, descriptor);
}

List<int> _buildIsoDirectoryData(
  _IsoDirectoryNode directory,
  _IsoDirectoryNode parent,
) {
  const sectorSize = 2048;
  final bytes = <int>[
    ..._isoDirectoryRecord(
      specialId: 0,
      isDirectory: true,
      extent: directory.extent,
      length: directory.size,
    ),
    ..._isoDirectoryRecord(
      specialId: 1,
      isDirectory: true,
      extent: parent.extent,
      length: parent.size,
    ),
  ];

  final directoryNames = directory.directories.keys.toList()..sort();
  for (final name in directoryNames) {
    final child = directory.directories[name]!;
    bytes.addAll(
      _isoDirectoryRecord(
        name: child.name,
        isDirectory: true,
        extent: child.extent,
        length: child.size,
      ),
    );
  }

  final fileNames = directory.files.keys.toList()..sort();
  for (final name in fileNames) {
    final file = directory.files[name]!;
    bytes.addAll(
      _isoDirectoryRecord(
        name: '${file.name};1',
        isDirectory: false,
        extent: file.extent,
        length: file.bytes.length,
      ),
    );
  }

  final sectorCount = (directory.size + sectorSize - 1) ~/ sectorSize;
  return <int>[
    ...bytes,
    ...List<int>.filled((sectorCount * sectorSize) - bytes.length, 0),
  ];
}

List<int> _isoDirectoryRecord({
  String? name,
  int? specialId,
  required bool isDirectory,
  required int extent,
  required int length,
}) {
  final identifier = specialId != null ? <int>[specialId] : ascii.encode(name!);
  final recordLength = _isoDirectoryRecordLength(identifier.length);
  final record = List<int>.filled(recordLength, 0);
  record[0] = recordLength;
  record[1] = 0;
  _writeIsoU32BothEndian(record, 2, extent);
  _writeIsoU32BothEndian(record, 10, length);
  record.setRange(
    18,
    25,
    _isoRecordingTimestamp(DateTime(2024, 1, 2, 3, 4, 6)),
  );
  record[25] = isDirectory ? 0x02 : 0x00;
  record[26] = 0;
  record[27] = 0;
  _writeIsoU16BothEndian(record, 28, 1);
  record[32] = identifier.length;
  record.setRange(33, 33 + identifier.length, identifier);
  return record;
}

List<int> _isoRecordingTimestamp(DateTime value) {
  return <int>[
    value.year - 1900,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
    0,
  ];
}

void _writeIsoU16BothEndian(List<int> target, int offset, int value) {
  target[offset] = value & 0xff;
  target[offset + 1] = (value >> 8) & 0xff;
  target[offset + 2] = (value >> 8) & 0xff;
  target[offset + 3] = value & 0xff;
}

void _writeIsoU32BothEndian(List<int> target, int offset, int value) {
  target[offset] = value & 0xff;
  target[offset + 1] = (value >> 8) & 0xff;
  target[offset + 2] = (value >> 16) & 0xff;
  target[offset + 3] = (value >> 24) & 0xff;
  target[offset + 4] = (value >> 24) & 0xff;
  target[offset + 5] = (value >> 16) & 0xff;
  target[offset + 6] = (value >> 8) & 0xff;
  target[offset + 7] = value & 0xff;
}

final class _IsoDirectoryNode {
  _IsoDirectoryNode({required this.name, this.parent});

  final String name;
  final _IsoDirectoryNode? parent;
  final Map<String, _IsoDirectoryNode> directories =
      <String, _IsoDirectoryNode>{};
  final Map<String, _IsoFileEntry> files = <String, _IsoFileEntry>{};
  int extent = 0;
  int size = 0;
}

final class _IsoFileEntry {
  _IsoFileEntry({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
  int extent = 0;
}

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
}

void _allowStringMount(LuaRuntime runtime, String archivePath) {
  LoveFilesystemState.attach(runtime).allowMountingForPath(archivePath);
}

Future<Object?> _callRawPath(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  final result = _rawFunction(
    runtime,
    path,
  ).call(args.map((arg) => arg is Value ? arg : Value(arg)).toList());
  return result is Future<Object?> ? await result : result;
}

Future<Object?> _callMethod(
  Object object,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  final table = object is Value ? object.raw : object;
  expect(table, isA<Map>());

  final methodValue = (table as Map)[method];
  final callable = switch (methodValue) {
    final Value value => value.raw,
    final BuiltinFunction function => function,
    _ => methodValue,
  };
  expect(callable, isA<BuiltinFunction>());
  return _resolveCallResult(
    (callable as BuiltinFunction).call(<Object?>[object, ...args]),
  );
}

Future<Object?> _callBuiltin(
  Object object, [
  List<Object?> args = const <Object?>[],
]) async {
  final callable = switch (object) {
    final Value value => value.raw,
    final BuiltinFunction function => function,
    _ => object,
  };
  expect(callable, isA<BuiltinFunction>());
  return _resolveCallResult((callable as BuiltinFunction).call(args));
}

Map<dynamic, dynamic> _packageTable(Interpreter runtime) {
  final packageValue = runtime.globals.get('package');
  expect(packageValue, isA<Value>());
  final raw = (packageValue! as Value).raw;
  expect(raw, isA<Map>());
  return raw as Map<dynamic, dynamic>;
}

List<dynamic> _packageSearchers(Interpreter runtime) {
  final packageTable = _packageTable(runtime);
  final searchersValue = packageTable['searchers'];
  expect(searchersValue, isA<Value>());
  final raw = (searchersValue! as Value).raw;
  expect(raw, isA<List>());
  return raw as List<dynamic>;
}

Future<Object?> _callHostFunction(
  Value function, [
  List<Object?> args = const <Object?>[],
]) async {
  final rawFunction = function.raw;
  expect(rawFunction, isA<Function>());
  final result = await (rawFunction! as Function)(args);
  return result;
}

BuiltinFunction _rawFunction(Interpreter runtime, List<String> path) {
  var current = runtime.getCurrentEnv().get(path.first);
  for (final segment in path.skip(1)) {
    final table = current is Value ? current.raw : current;
    expect(
      table,
      isA<Map>(),
      reason: 'Expected ${path.join('.')} to traverse a Lua table',
    );
    current = (table as Map)[segment];
  }

  expect(current, isA<Value>());
  final raw = (current! as Value).raw;
  expect(raw, isA<BuiltinFunction>());
  return raw as BuiltinFunction;
}

List<Object?> _rawResults(Object? result) {
  if (result case final Value value when value.isMulti) {
    return List<Object?>.from(value.raw as List<Object?>, growable: false);
  }
  if (result is List) {
    return List<Object?>.from(result, growable: false);
  }
  return <Object?>[result];
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;

  if (resolved case final Value wrapped when wrapped.isMulti) {
    return (wrapped.raw as List<Object?>).map(_unwrap).toList(growable: false);
  }

  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;

Map<Object?, Object?> _genericDataWrapper(List<int> bytes) {
  Object? unwrapArg(Object? value) => value is Value ? value.unwrap() : value;

  return <Object?, Object?>{
    'type': Value(
      _TestBuiltinFunction((args) => 'ByteData'),
      functionName: 'type',
    ),
    'typeOf': Value(
      _TestBuiltinFunction((args) {
        final queried = unwrapArg(args.length > 1 ? args[1] : null);
        return queried == 'ByteData' ||
            queried == 'Data' ||
            queried == 'Object';
      }),
      functionName: 'typeOf',
    ),
    'getSize': Value(
      _TestBuiltinFunction((args) => bytes.length),
      functionName: 'getSize',
    ),
    'getString': Value(
      _TestBuiltinFunction((args) => LuaString.fromBytes(bytes)),
      functionName: 'getString',
    ),
  };
}

class _TestBuiltinFunction extends BuiltinFunction {
  _TestBuiltinFunction(this._implementation);

  final Object? Function(List<Object?> args) _implementation;

  @override
  Object? call(List<Object?> args) => _implementation(args);
}

class _TestLoveFilesystemAdapter implements LoveFilesystemAdapter {
  _TestLoveFilesystemAdapter({
    this.appdataDirectory = '/appdata',
    this.isWindows = false,
    this.isLinux = true,
    this.isMacOS = false,
  });

  @override
  final String? workingDirectory = '/work';

  @override
  final String? userDirectory = '/users/tester';

  @override
  final String? appdataDirectory;

  @override
  final String? executablePath = '/bin/lualike-test';

  @override
  final bool isWindows;

  @override
  final bool isLinux;

  @override
  final bool isMacOS;

  final Map<String, List<int>> _files = <String, List<int>>{};
  final Set<String> _directories = <String>{};
  final Map<String, DateTime> _modified = <String, DateTime>{};
  final Map<String, int?> _sizeOverrides = <String, int?>{};
  final Map<String, int> _positionOverrides = <String, int>{};
  final Map<String, String> _openFailures = <String, String>{};
  final Map<String, String> _readFileBytesFailures = <String, String>{};
  bool failWritesWithoutError = false;
  String? writeFailureError;
  String? setBufferingFailureError;
  String? flushFailureError;
  String? closeFailureError;
  _TestFilesystemIODevice? lastOpenedDevice;

  void addFile(String filePath, String content) {
    final normalized = _normalize(filePath);
    _ensureParents(normalized);
    _files[normalized] = List<int>.from(content.codeUnits);
    _touch(normalized);
  }

  void addFileBytes(String filePath, List<int> bytes) {
    final normalized = _normalize(filePath);
    _ensureParents(normalized);
    _files[normalized] = List<int>.from(bytes);
    _touch(normalized);
  }

  void failOpen(String filePath, String message) {
    _openFailures[_normalize(filePath)] = message;
  }

  void failReadFileBytes(String filePath, String message) {
    _readFileBytesFailures[_normalize(filePath)] = message;
  }

  void overridePosition(String filePath, int position) {
    _positionOverrides[_normalize(filePath)] = position;
  }

  void overrideSize(String filePath, int size) {
    _sizeOverrides[_normalize(filePath)] = size;
  }

  void overrideUnknownSize(String filePath) {
    _sizeOverrides[_normalize(filePath)] = null;
  }

  void overrideModified(String filePath, DateTime? modified) {
    final normalized = _normalize(filePath);
    if (modified == null) {
      _modified.remove(normalized);
      return;
    }

    _modified[normalized] = modified;
  }

  @override
  Future<IODevice> openFile(String path, String mode) async {
    final normalized = _normalize(path);

    final openFailure = _openFailures[normalized];
    if (openFailure != null) {
      throw UnsupportedError(openFailure);
    }

    if (mode == 'r' && !_files.containsKey(normalized)) {
      throw StateError('File not found: $normalized');
    }

    if (mode == 'w') {
      final parent = p.posix.dirname(normalized);
      if (parent.isNotEmpty &&
          parent != '.' &&
          !_directories.contains(parent)) {
        throw StateError('Directory not found: $parent');
      }
      _files[normalized] = <int>[];
      _touch(normalized);
    } else if (mode == 'a') {
      final parent = p.posix.dirname(normalized);
      if (parent.isNotEmpty &&
          parent != '.' &&
          !_directories.contains(parent)) {
        throw StateError('Directory not found: $parent');
      }
      _files.putIfAbsent(normalized, () => <int>[]);
      _touch(normalized);
    }

    final device = _TestFilesystemIODevice(
      adapter: this,
      filePath: normalized,
      mode: mode,
    );
    lastOpenedDevice = device;
    return device;
  }

  @override
  Future<bool> fileExists(String path) async =>
      _files.containsKey(_normalize(path));

  @override
  Future<bool> directoryExists(String path) async =>
      _directories.contains(_normalize(path));

  @override
  Future<List<int>?> readFileBytes(String path) async {
    final normalized = _normalize(path);
    final readFailure = _readFileBytesFailures[normalized];
    if (readFailure != null) {
      throw UnsupportedError(readFailure);
    }
    if (_openFailures.containsKey(normalized)) {
      return null;
    }

    final bytes = _files[normalized];
    return bytes == null ? null : List<int>.from(bytes);
  }

  @override
  Future<List<String>> listDirectory(String path) async {
    final normalized = _normalize(path);
    final entries = <String>{};

    for (final directory in _directories) {
      if (directory.isEmpty || directory == normalized) {
        continue;
      }
      if (p.posix.dirname(directory) == normalized) {
        entries.add(directory);
      }
    }

    for (final filePath in _files.keys) {
      if (p.posix.dirname(filePath) == normalized) {
        entries.add(filePath);
      }
    }

    final sorted = entries.toList()..sort();
    return sorted;
  }

  @override
  Future<DateTime?> modified(String path) async => _modified[_normalize(path)];

  @override
  Future<int?> fileSize(String path) async {
    final normalized = _normalize(path);
    if (_sizeOverrides.containsKey(normalized)) {
      return _sizeOverrides[normalized];
    }

    return _files[normalized]?.length;
  }

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) async {
    final normalized = _normalize(path);
    if (_files.containsKey(normalized)) {
      return false;
    }

    _ensureDirectory(normalized);
    return true;
  }

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) async {
    final normalized = _normalize(path);
    if (_files.remove(normalized) != null) {
      _modified.remove(normalized);
      return true;
    }

    if (!_directories.contains(normalized)) {
      return false;
    }

    if (!recursive) {
      final hasChildDirectory = _directories.any(
        (directory) =>
            directory != normalized && p.posix.dirname(directory) == normalized,
      );
      if (hasChildDirectory) {
        return false;
      }

      final hasChildFile = _files.keys.any(
        (filePath) => p.posix.dirname(filePath) == normalized,
      );
      if (hasChildFile) {
        return false;
      }
    }

    _directories.removeWhere(
      (directory) =>
          directory == normalized || directory.startsWith('$normalized/'),
    );
    _files.removeWhere(
      (filePath, _) =>
          filePath == normalized || filePath.startsWith('$normalized/'),
    );
    _modified.removeWhere(
      (entryPath, _) =>
          entryPath == normalized || entryPath.startsWith('$normalized/'),
    );
    return true;
  }

  List<int> fileBytes(String path) {
    return List<int>.from(_files[_normalize(path)] ?? const <int>[]);
  }

  void writeBytes(
    String path,
    List<int> bytes, {
    required int offset,
    required bool append,
  }) {
    final normalized = _normalize(path);
    _ensureParents(normalized);
    final existing = List<int>.from(_files[normalized] ?? const <int>[]);

    if (append) {
      existing.addAll(bytes);
      _files[normalized] = existing;
      _touch(normalized);
      return;
    }

    final before = offset.clamp(0, existing.length);
    final afterStart = math.min(before + bytes.length, existing.length);
    final next = <int>[
      ...existing.take(before),
      ...bytes,
      ...existing.skip(afterStart),
    ];
    _files[normalized] = next;
    _touch(normalized);
  }

  String _normalize(String value) {
    if (value.isEmpty) {
      return '';
    }
    return p.posix.normalize(value);
  }

  void _ensureParents(String filePath) {
    _ensureDirectory(p.posix.dirname(filePath));
  }

  void _ensureDirectory(String directoryPath) {
    var current = _normalize(directoryPath);
    if (current.isEmpty || current == '.') {
      return;
    }

    final pending = <String>[];
    while (current.isNotEmpty &&
        current != '.' &&
        !_directories.contains(current)) {
      pending.add(current);
      final parent = p.posix.dirname(current);
      if (parent == current) {
        break;
      }
      current = parent;
    }

    for (final directory in pending.reversed) {
      _directories.add(directory);
      _touch(directory);
    }
  }

  void _touch(String path) {
    _modified[path] = DateTime.fromMillisecondsSinceEpoch(1);
  }
}

class _TestFilesystemIODevice extends BaseIODevice {
  _TestFilesystemIODevice({
    required this.adapter,
    required this.filePath,
    required String mode,
  }) : super(mode) {
    isClosed = false;
    if (mode == 'a') {
      _position = adapter.fileBytes(filePath).length;
    }
  }

  final _TestLoveFilesystemAdapter adapter;
  final String filePath;
  int _position = 0;

  @override
  Future<void> close() async {
    if (adapter.closeFailureError != null) {
      throw StateError(adapter.closeFailureError!);
    }
    isClosed = true;
  }

  @override
  Future<void> flush() async {
    checkOpen();
    if (adapter.flushFailureError != null) {
      throw StateError(adapter.flushFailureError!);
    }
  }

  @override
  Future<ReadResult> read([String format = 'l']) async {
    checkOpen();
    validateReadFormat(format);

    if (mode == 'w' || mode == 'a') {
      return ReadResult(null, 'Cannot read from write-only file', 9);
    }

    final bytes = adapter.fileBytes(filePath);
    final normalized = normalizeReadFormat(format);
    if (normalized == 'a') {
      final result = bytes.sublist(_position.clamp(0, bytes.length));
      _position = bytes.length;
      return ReadResult(LuaString.fromBytes(result));
    }

    if (normalized == 'l' || normalized == 'L') {
      if (_position >= bytes.length) {
        return ReadResult(null);
      }

      var end = _position;
      while (end < bytes.length && bytes[end] != 10) {
        end++;
      }

      final includeTerminator = normalized == 'L' && end < bytes.length;
      final line = bytes.sublist(_position, includeTerminator ? end + 1 : end);
      _position = end < bytes.length ? end + 1 : bytes.length;
      return ReadResult(LuaString.fromBytes(line));
    }

    final count = int.parse(normalized);
    if (_position >= bytes.length) {
      return ReadResult(null);
    }

    final end = math.min(_position + count, bytes.length);
    final chunk = bytes.sublist(_position, end);
    _position = end;
    return ReadResult(LuaString.fromBytes(chunk));
  }

  @override
  Future<WriteResult> write(String data) async {
    return writeBytes(List<int>.from(data.codeUnits));
  }

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async {
    checkOpen();
    if (mode != 'w' && mode != 'a') {
      return WriteResult(false, 'File not open for writing');
    }

    if (adapter.failWritesWithoutError || adapter.writeFailureError != null) {
      return WriteResult(false, adapter.writeFailureError);
    }

    adapter.writeBytes(filePath, bytes, offset: _position, append: mode == 'a');
    _position = mode == 'a'
        ? adapter.fileBytes(filePath).length
        : _position + bytes.length;
    return WriteResult(true);
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    checkOpen();
    final length = adapter.fileBytes(filePath).length;
    switch (whence) {
      case SeekWhence.set:
        _position = offset.clamp(0, length);
      case SeekWhence.cur:
        _position = (_position + offset).clamp(0, length);
      case SeekWhence.end:
        _position = (length + offset).clamp(0, length);
    }
    return _position;
  }

  @override
  Future<int> getPosition() async {
    checkOpen();
    return adapter._positionOverrides[filePath] ?? _position;
  }

  @override
  Future<void> setBuffering(BufferMode mode, [int? size]) async {
    if (adapter.setBufferingFailureError != null) {
      throw StateError(adapter.setBufferingFailureError!);
    }
    await super.setBuffering(mode, size);
  }

  @override
  Future<bool> isEOF() async {
    checkOpen();
    return _position >= adapter.fileBytes(filePath).length;
  }
}
