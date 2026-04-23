import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics object receiver parity', () {
    test(
      'Font type metadata survives release while other methods fail',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        await _expectTypeParity(
          object: font,
          expectedType: 'Font',
          typeOfName: 'Object',
        );

        expect(await luaCallMethod(font, 'release'), isTrue);
        expect(await luaCallMethod(font, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(font, 'getHeight'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(await luaCallMethod(font, 'type'), 'Font');
        expect(
          await luaCallMethod(font, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
      },
    );

    test(
      'Text type metadata survives release while other methods fail',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );
        final text = await luaCall(
          runtime,
          const ['love', 'graphics', 'newText'],
          <Object?>[font, 'hello'],
        );

        await _expectTypeParity(
          object: text,
          expectedType: 'Text',
          typeOfName: 'Object',
        );

        expect(await luaCallMethod(text, 'release'), isTrue);
        expect(await luaCallMethod(text, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(text, 'getWidth'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(await luaCallMethod(text, 'type'), 'Text');
        expect(
          await luaCallMethod(text, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
      },
    );

    test(
      'Canvas type metadata survives release while other methods fail',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final canvas = await luaCall(
          runtime,
          const ['love', 'graphics', 'newCanvas'],
          const <Object?>[4, 4],
        );

        await _expectTypeParity(
          object: canvas,
          expectedType: 'Canvas',
          typeOfName: 'Drawable',
        );

        expect(await luaCallMethod(canvas, 'release'), isTrue);
        expect(await luaCallMethod(canvas, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(canvas, 'getWidth'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(await luaCallMethod(canvas, 'type'), 'Canvas');
        expect(
          await luaCallMethod(canvas, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
      },
    );

    test(
      'ImageData type metadata survives release while other methods fail',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[2, 2],
        );

        await _expectTypeParity(
          object: imageData,
          expectedType: 'ImageData',
          typeOfName: 'Data',
        );

        expect(await luaCallMethod(imageData, 'release'), isTrue);
        expect(await luaCallMethod(imageData, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(imageData, 'getWidth'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(await luaCallMethod(imageData, 'type'), 'ImageData');
        expect(
          await luaCallMethod(imageData, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
      },
    );
  });
}

Future<void> _expectTypeParity({
  required Object? object,
  required String expectedType,
  required String typeOfName,
}) async {
  final typeMethod = luaRawMethod(object, 'type');
  final typeOfMethod = luaRawMethod(object, 'typeOf');

  expect(
    await luaResolveCallResult(typeMethod.call(<Object?>[object])),
    expectedType,
  );
  expect(
    await luaResolveCallResult(
      typeOfMethod.call(<Object?>[object, typeOfName]),
    ),
    isTrue,
  );

  await expectLater(
    () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
    throwsA(
      isA<LuaError>().having(
        (error) => error.message,
        'message',
        "bad argument #1 to 'type' ($expectedType expected, got nil)",
      ),
    ),
  );

  await expectLater(
    () => luaResolveCallResult(typeMethod.call(const <Object?>['oops'])),
    throwsA(
      isA<LuaError>().having(
        (error) => error.message,
        'message',
        "bad argument #1 to 'type' ($expectedType expected, got string)",
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
        "bad argument #1 to 'typeOf' ($expectedType expected, got string)",
      ),
    ),
  );
}
