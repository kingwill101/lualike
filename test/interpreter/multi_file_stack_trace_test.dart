import 'dart:async';

import 'package:lualike/testing.dart';

void main() {
  group('Stack trace across files', () {
    test('reports correct file names', () async {
      final bridge = LuaLike();

      bridge.vm.fileManager.registerVirtualFile('mod.lua', '''
local M = {}
function M.trigger()
  assert(false, 'fail')
end
return M
''');

      final mainSource = '''
local mod = require("mod")
local function run()
  mod.trigger()
end
run()
''';

      final buffer = StringBuffer();

      await runZoned(
        () async {
          try {
            await bridge.runCode(mainSource, scriptPath: 'main.lua');
            fail('expected error');
          } catch (_) {}
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, msg) {
            buffer.writeln(msg);
          },
        ),
      );

      final output = buffer.toString();
      expect(output, contains('mod:3'));
      expect(output, contains('main.lua:3'));
    });
  });
}
