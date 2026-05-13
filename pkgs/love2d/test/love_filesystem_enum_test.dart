import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.filesystem enum tables', () {
    test('are exposed globally and in the module namespace', () {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      final globals = runtime.runtime.globals;
      final love = globals.get('love');
      expect(love, isA<Value>());
      final loveTable = (love! as Value).raw as Map;

      final filesystem = loveTable['filesystem'];
      expect(filesystem, isA<Value>());
      final filesystemTable = (filesystem! as Value).raw as Map;

      final expectedEnums = <String, List<String>>{
        'BufferMode': <String>['none', 'line', 'full'],
        'FileDecoder': <String>['file', 'base64'],
        'FileMode': <String>['r', 'w', 'a', 'c'],
        'FileType': <String>['file', 'directory', 'symlink', 'other'],
      };

      for (final entry in expectedEnums.entries) {
        final globalEnum = globals.get(entry.key);
        expect(globalEnum, isA<Value>(), reason: 'Missing global ${entry.key}');
        final globalTable = (globalEnum! as Value).raw as Map;

        final moduleEnum = filesystemTable[entry.key];
        expect(
          moduleEnum,
          isA<Value>(),
          reason: 'Missing love.filesystem.${entry.key}',
        );
        final moduleTable = (moduleEnum! as Value).raw as Map;

        expect(identical(globalTable, moduleTable), isTrue);
        expect(globalTable.length, entry.value.length);

        for (final constant in entry.value) {
          expect(globalTable[constant], constant);
          expect(moduleTable[constant], constant);
        }
      }
    });

    test('can be used as LOVE string constants in Lua code', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
testbed = {}

love.filesystem.setIdentity("filesystem-enum-tests")

local file = love.filesystem.newFile("enum-check.txt")
testbed.global_mode = FileMode.w
testbed.module_mode = love.filesystem.FileMode.r
testbed.global_buffer = BufferMode.full
testbed.module_buffer = love.filesystem.BufferMode.line
testbed.global_decoder = FileDecoder.base64
testbed.module_decoder = love.filesystem.FileDecoder.file
testbed.global_type = FileType.file
testbed.module_type = love.filesystem.FileType.directory

testbed.opened = file:open(FileMode.w)
testbed.buffered = file:setBuffer(BufferMode.full, 32)
testbed.buffer_mode, testbed.buffer_size = file:getBuffer()
testbed.written = file:write("filesystem enum payload")
testbed.closed = file:close()

local info = love.filesystem.getInfo("enum-check.txt", FileType.file)
testbed.info_type = info.type
''');

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['global_mode'], 'w');
      expect(snapshot['module_mode'], 'r');
      expect(snapshot['global_buffer'], 'full');
      expect(snapshot['module_buffer'], 'line');
      expect(snapshot['global_decoder'], 'base64');
      expect(snapshot['module_decoder'], 'file');
      expect(snapshot['global_type'], 'file');
      expect(snapshot['module_type'], 'directory');
      expect(snapshot['opened'], isTrue);
      expect(snapshot['buffered'], isTrue);
      expect(snapshot['buffer_mode'], 'full');
      expect(snapshot['buffer_size'], 32);
      expect(snapshot['written'], isTrue);
      expect(snapshot['closed'], isTrue);
      expect(snapshot['info_type'], 'file');
    });
  });
}
