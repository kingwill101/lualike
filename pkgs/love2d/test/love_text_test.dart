import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics Text bindings', () {
    test(
      'text methods follow LOVE replacement and indexing semantics',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[20],
        );
        final text = await luaCall(
          runtime,
          const ['love', 'graphics', 'newText'],
          <Object?>[font, 'Lua'],
        );

        expect(await luaCallMethod(text, 'getWidth', const <Object?>[1]), 36.0);
        expect(
          await luaCallMethod(text, 'getHeight', const <Object?>[1]),
          20.0,
        );
        expect(await luaCallMethod(text, 'getWidth'), 36.0);

        final appended = await luaCallMethod(text, 'add', const <Object?>[
          'body',
        ]);
        expect(appended, 2);
        expect(await luaCallMethod(text, 'getWidth', const <Object?>[2]), 48.0);
        expect(await luaCallMethod(text, 'getWidth'), 48.0);

        final wrapped = await luaCallMethod(text, 'addf', const <Object?>[
          'ab cd',
          24.0,
          'center',
        ]);
        expect(wrapped, 3);
        expect(
          await luaCallMethod(text, 'getDimensions', const <Object?>[3]),
          <Object?>[24.0, 40.0],
        );
        expect(await luaCallMethod(text, 'getWidth'), 24.0);
        expect(await luaCallMethod(text, 'getHeight'), 40.0);

        await luaCallMethod(text, 'set', const <Object?>['x']);
        expect(await luaCallMethod(text, 'getWidth', const <Object?>[1]), 12.0);
        expect(await luaCallMethod(text, 'getWidth', const <Object?>[2]), 0.0);

        final smallFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[10],
        );
        await luaCallMethod(text, 'setFont', <Object?>[smallFont]);
        final currentFont = await luaCallMethod(text, 'getFont');
        expect(await luaCallMethod(currentFont, 'getHeight'), 10.0);

        await luaCallMethod(text, 'setf', const <Object?>[
          'ab cd',
          12.0,
          'left',
        ]);
        expect(await luaCallMethod(text, 'getDimensions'), <Object?>[
          12.0,
          20.0,
        ]);

        await luaCallMethod(text, 'clear');
        expect(await luaCallMethod(text, 'getDimensions'), <Object?>[0.0, 0.0]);

        final afterClear = await luaCallMethod(text, 'add', const <Object?>[
          'ok',
        ]);
        expect(afterClear, 1);
      },
    );

    test(
      'text set and constructor only clear for empty input or a single empty string',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        final constructedWithEmptySpans = await luaCall(
          runtime,
          const ['love', 'graphics', 'newText'],
          <Object?>[
            font,
            <Object?, Object?>{1: '', 2: ''},
          ],
        );
        expect(
          await luaCallMethod(constructedWithEmptySpans, 'add', const <Object?>[
            'x',
          ]),
          2,
        );

        final text = await luaCall(
          runtime,
          const ['love', 'graphics', 'newText'],
          <Object?>[font, 'seed'],
        );

        await luaCallMethod(text, 'set', <Object?>[
          <Object?, Object?>{1: '', 2: ''},
        ]);
        expect(await luaCallMethod(text, 'getDimensions'), <Object?>[0.0, 0.0]);
        expect(await luaCallMethod(text, 'add', const <Object?>['x']), 2);

        await luaCallMethod(text, 'set', const <Object?>['']);
        expect(await luaCallMethod(text, 'add', const <Object?>['y']), 1);

        await luaCallMethod(text, 'setf', <Object?>[
          <Object?, Object?>{1: '', 2: ''},
          12.0,
          'left',
        ]);
        expect(
          await luaCallMethod(text, 'addf', const <Object?>['z', 12.0, 'left']),
          2,
        );

        await luaCallMethod(text, 'setf', const <Object?>['', 12.0, 'left']);
        expect(
          await luaCallMethod(text, 'addf', const <Object?>['w', 12.0, 'left']),
          1,
        );
      },
    );
  });
}
