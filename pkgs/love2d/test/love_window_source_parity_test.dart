import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('LOVE window source parity', () {
    test(
      'getNativeDPIScale mirrors the upstream source-backed API in main and thread runtimes',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(
            windowMetrics: const LoveWindowMetrics(dpiScale: 2.5),
          ),
        );

        expect(
          await luaCallList(runtime, const [
            'love',
            'window',
            'getNativeDPIScale',
          ]),
          2.5,
        );
        expect(
          await luaCallList(runtime, const ['love', 'window', 'getDPIScale']),
          2.5,
        );

        final output = await luaCallList(runtime, const [
          'love',
          'thread',
          'newChannel',
        ]);
        final thread = await luaCallList(
          runtime,
          const ['love', 'thread', 'newThread'],
          <Object?>[
            '''
local output = ...
output:push(love.window.getNativeDPIScale())
output:push(love.window.getDPIScale())
output:push(love.window.getNativeDPIScale() == love.window.getDPIScale())
''',
          ],
        );

        expect(
          await luaCallMethodList(thread!, 'start', <Object?>[output]),
          isTrue,
        );
        await luaCallMethodList(thread, 'wait');
        expect(await luaCallMethodList(thread, 'getError'), isNull);
        expect(await luaCallMethodList(output!, 'pop'), 2.5);
        expect(await luaCallMethodList(output, 'pop'), 2.5);
        expect(await luaCallMethodList(output, 'pop'), isTrue);
      },
    );
  });
}
