import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  test(
    'love.filedropped provides mountable DroppedFile objects through callback and queued events',
    () async {
      final adapter = MemoryLoveFilesystemAdapter(
        files: <String, List<int>>{
          '/drop/mod.zip': _encodeZip(<String, String>{
            'pkg/init.lua': 'return { dropped = true }',
            'readme.txt': 'from callback drop',
          }),
        },
      );
      final runtime = LoveScriptRuntime(filesystemAdapter: adapter);
      final interpreter = runtime.runtime;

      await runtime.execute('''
testbed = {}

function love.filedropped(file)
  local poll = love.event.poll()
  local name, queuedFile = poll()

  testbed.event_name = name
  testbed.arg_type = file:type()
  testbed.arg_typeof = tostring(file:typeOf("DroppedFile"))
  testbed.arg_filename = file:getFilename()
  testbed.queued_type = queuedFile:type()
  testbed.queued_filename = queuedFile:getFilename()

  testbed.arg_mount = tostring(love.filesystem.mount(file, "argmods", true))
  local argInfo = love.filesystem.getInfo("argmods/readme.txt")
  testbed.arg_info_type = argInfo and argInfo.type or "nil"
  testbed.queued_mount = tostring(love.filesystem.mount(queuedFile, "argmods", true))
  local queuedInfo = love.filesystem.getInfo("argmods/readme.txt")
  testbed.queued_info_type = queuedInfo and queuedInfo.type or "nil"
end
''');

      await runtime.dispatchFileDropped('/drop/mod.zip');

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['event_name'], 'filedropped');
      expect(snapshot['arg_type'], 'DroppedFile');
      expect(snapshot['arg_typeof'], 'true');
      expect(snapshot['arg_filename'], '/drop/mod.zip');
      expect(snapshot['queued_type'], 'DroppedFile');
      expect(snapshot['queued_filename'], '/drop/mod.zip');
      expect(snapshot['arg_mount'], 'true');
      expect(snapshot['arg_info_type'], 'file');
      expect(snapshot['queued_mount'], 'true');
      expect(snapshot['queued_info_type'], 'file');
      expect(
        await luaCall(
          interpreter,
          const ['love', 'filesystem', 'read'],
          const <Object?>['argmods/readme.txt'],
        ),
        <Object?>['from callback drop', 18],
      );
      expect(
        await luaCall(
          interpreter,
          const ['love', 'filesystem', 'getRealDirectory'],
          const <Object?>['argmods/readme.txt'],
        ),
        '/drop/mod.zip',
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
