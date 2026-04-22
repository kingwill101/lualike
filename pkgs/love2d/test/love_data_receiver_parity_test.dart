import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.data receiver parity', () {
    test(
      'ByteData type metadata survives release while other methods fail',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final byteData = await luaCall(
          runtime,
          const ['love', 'data', 'newByteData'],
          const <Object?>['hello'],
        );

        final typeMethod = luaRawMethod(byteData, 'type');
        final typeOfMethod = luaRawMethod(byteData, 'typeOf');

        expect(
          await luaResolveCallResult(typeMethod.call(<Object?>[byteData])),
          'ByteData',
        );
        expect(
          await luaResolveCallResult(
            typeOfMethod.call(<Object?>[byteData, 'Data']),
          ),
          isTrue,
        );

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (ByteData expected, got nil)",
            ),
          ),
        );

        await expectLater(
          () => luaResolveCallResult(
            typeOfMethod.call(const <Object?>['oops', 'Data']),
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'typeOf' (ByteData expected, got string)",
            ),
          ),
        );

        expect(await luaCallMethod(byteData, 'release'), isTrue);
        expect(await luaCallMethod(byteData, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(byteData, 'getString'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(
          await luaResolveCallResult(typeMethod.call(<Object?>[byteData])),
          'ByteData',
        );
        expect(
          await luaResolveCallResult(
            typeOfMethod.call(<Object?>[byteData, 'Object']),
          ),
          isTrue,
        );
      },
    );

    test(
      'FileData type metadata survives release while data methods fail',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final fileData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>['payload', 'payload.bin'],
        );

        final typeMethod = luaRawMethod(fileData, 'type');
        final typeOfMethod = luaRawMethod(fileData, 'typeOf');

        expect(
          await luaResolveCallResult(typeMethod.call(<Object?>[fileData])),
          'FileData',
        );
        expect(
          await luaResolveCallResult(
            typeOfMethod.call(<Object?>[fileData, 'Data']),
          ),
          isTrue,
        );

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (FileData expected, got nil)",
            ),
          ),
        );

        await expectLater(
          () => luaResolveCallResult(
            typeOfMethod.call(const <Object?>['oops', 'Data']),
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'typeOf' (FileData expected, got string)",
            ),
          ),
        );

        expect(await luaCallMethod(fileData, 'release'), isTrue);
        expect(await luaCallMethod(fileData, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(fileData, 'getString'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(
          await luaResolveCallResult(typeMethod.call(<Object?>[fileData])),
          'FileData',
        );
        expect(
          await luaResolveCallResult(
            typeOfMethod.call(<Object?>[fileData, 'Object']),
          ),
          isTrue,
        );
      },
    );
  });
}
