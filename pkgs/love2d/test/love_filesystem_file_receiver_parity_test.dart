import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/lua_api_test_helpers.dart';
import 'test_support/memory_filesystem_test_support.dart';

void main() {
  group('love.filesystem File receiver parity', () {
    test(
      'File type metadata survives release and wrong receivers use Lua arg errors',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'test.txt': 'hello'.codeUnits,
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final file = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFile'],
          const <Object?>['test.txt'],
        );

        final typeMethod = luaRawMethod(file, 'type');
        final typeOfMethod = luaRawMethod(file, 'typeOf');

        expect(
          await luaResolveCallResult(typeMethod.call(<Object?>[file])),
          'File',
        );
        expect(
          await luaResolveCallResult(
            typeOfMethod.call(<Object?>[file, 'Object']),
          ),
          isTrue,
        );

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (File expected, got nil)",
            ),
          ),
        );

        await expectLater(
          () => luaResolveCallResult(
            typeOfMethod.call(const <Object?>['oops', 'Object']),
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'typeOf' (File expected, got string)",
            ),
          ),
        );

        expect(await luaCallMethod(file, 'release'), isTrue);
        expect(await luaCallMethod(file, 'release'), isFalse);
        expect(await luaCallMethod(file, 'type'), 'File');
        expect(
          await luaCallMethod(file, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
      },
    );
  });
}
