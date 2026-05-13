import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/src/runtime/love_runtime.dart';
import 'package:love2d/src/runtime/love_script_runtime.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('LoveScriptRuntime callback helpers', () {
    test(
      'call callback helpers invoke dropped-file, directory, display, text-edited, and thread-error callbacks',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}

function love.directorydropped(path)
  testbed.directorydropped = path
end

function love.displayrotated(index, orientation)
  testbed.displayrotated = string.format("%d/%s", index, orientation)
end

function love.filedropped(file)
  testbed.filedropped_type = file:type()
  testbed.filedropped_typeof = tostring(file:typeOf("DroppedFile"))
  testbed.filedropped_filename = file:getFilename()
end

function love.textedited(text, start, length)
  testbed.textedited = string.format("%s/%d/%d", text, start, length)
end

function love.threaderror(thread, err)
  testbed.threaderror = string.format("%s/%s", tostring(thread), err)
end
''');

        await runtime.callDirectoryDroppedIfDefined('/tmp/save-dir');
        await runtime.callDisplayRotatedIfDefined(2, 'landscape');
        await runtime.callFileDroppedIfDefined('/tmp/dropped.txt');
        await runtime.callTextEditedIfDefined('compose', 1, 4);
        await runtime.callThreadErrorIfDefined('worker-1', 'boom');

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['directorydropped'], '/tmp/save-dir');
        expect(snapshot['displayrotated'], '2/landscape');
        expect(snapshot['filedropped_type'], 'DroppedFile');
        expect(snapshot['filedropped_typeof'], 'true');
        expect(snapshot['filedropped_filename'], '/tmp/dropped.txt');
        expect(snapshot['textedited'], 'compose/1/4');
        expect(snapshot['threaderror'], 'worker-1/boom');
      },
    );

    test(
      'dispatch helpers queue LOVE events and invoke callbacks with matching payloads',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}

function love.resize(width, height)
  local poll = love.event.poll()
  local name, queuedWidth, queuedHeight = poll()
  testbed.resize = string.format("%s|%d|%d|%d|%d", name, queuedWidth, queuedHeight, width, height)
end

function love.visible(visible)
  local poll = love.event.poll()
  local name, queuedVisible = poll()
  testbed.visible = string.format("%s|%s|%s", name, tostring(queuedVisible), tostring(visible))
end

function love.lowmemory()
  local poll = love.event.poll()
  testbed.lowmemory = poll()
end

function love.directorydropped(path)
  local poll = love.event.poll()
  local name, queuedPath = poll()
  testbed.directorydropped = string.format("%s|%s|%s", name, queuedPath, path)
end

function love.displayrotated(index, orientation)
  local poll = love.event.poll()
  local name, queuedIndex, queuedOrientation = poll()
  testbed.displayrotated = string.format("%s|%d|%s|%d|%s", name, queuedIndex, queuedOrientation, index, orientation)
end

function love.filedropped(file)
  local poll = love.event.poll()
  local name, queuedFile = poll()
  testbed.filedropped = string.format("%s|%s|%s|%s", name, file:type(), queuedFile:type(), queuedFile:getFilename())
end

function love.textedited(text, start, length)
  local poll = love.event.poll()
  local name, queuedText, queuedStart, queuedLength = poll()
  testbed.textedited = string.format("%s|%s|%d|%d|%s|%d|%d", name, queuedText, queuedStart, queuedLength, text, start, length)
end

function love.threaderror(thread, err)
  local poll = love.event.poll()
  local name, queuedThread, queuedErr = poll()
  testbed.threaderror = string.format("%s|%s|%s|%s|%s", name, tostring(queuedThread), queuedErr, tostring(thread), err)
end
''');

        await runtime.dispatchResize(1280, 720);
        await runtime.dispatchVisible(false);
        await runtime.dispatchLowMemory();
        await runtime.dispatchDirectoryDropped('/tmp/save-dir');
        await runtime.dispatchDisplayRotated(2, 'landscape');
        await runtime.dispatchFileDropped('/tmp/dropped.txt');
        await runtime.dispatchTextEdited('compose', 1, 4);
        await runtime.dispatchThreadError('worker-1', 'boom');

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['resize'], 'resize|1280|720|1280|720');
        expect(snapshot['visible'], 'visible|false|false');
        expect(snapshot['lowmemory'], 'lowmemory');
        expect(
          snapshot['directorydropped'],
          'directorydropped|/tmp/save-dir|/tmp/save-dir',
        );
        expect(
          snapshot['displayrotated'],
          'displayrotated|2|landscape|2|landscape',
        );
        expect(
          snapshot['filedropped'],
          'filedropped|DroppedFile|DroppedFile|/tmp/dropped.txt',
        );
        expect(snapshot['textedited'], 'textedited|compose|1|4|compose|1|4');
        expect(
          snapshot['threaderror'],
          'threaderror|worker-1|boom|worker-1|boom',
        );
      },
    );

    test(
      'dispatch helpers still queue events when callbacks are undefined',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.dispatchResize(1280, 720);
        await runtime.dispatchVisible(false);
        await runtime.dispatchLowMemory();
        await runtime.dispatchDirectoryDropped('/tmp/save-dir');
        await runtime.dispatchDisplayRotated(2, 'landscape');
        await runtime.dispatchTextEdited('compose', 1, 4);
        await runtime.dispatchThreadError('worker-1', 'boom');

        final iterator = await luaCall(runtime, const [
          'love',
          'event',
          'poll',
        ]);
        expect(iterator, isA<BuiltinFunction>());
        final poll = iterator! as BuiltinFunction;

        expect(await luaCallCallable(poll), <Object?>['resize', 1280, 720]);
        expect(await luaCallCallable(poll), <Object?>['visible', false]);
        expect(await luaCallCallable(poll), <Object?>['lowmemory']);
        expect(await luaCallCallable(poll), <Object?>[
          'directorydropped',
          '/tmp/save-dir',
        ]);
        expect(await luaCallCallable(poll), <Object?>[
          'displayrotated',
          2,
          'landscape',
        ]);
        expect(await luaCallCallable(poll), <Object?>[
          'textedited',
          'compose',
          1,
          4,
        ]);
        expect(await luaCallCallable(poll), <Object?>[
          'threaderror',
          'worker-1',
          'boom',
        ]);
        expect(await luaCallCallable(poll), isNull);
      },
    );

    test('return null when optional callbacks are undefined', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      expect(
        await runtime.callDirectoryDroppedIfDefined('/tmp/save-dir'),
        isNull,
      );
      expect(await runtime.callDisplayRotatedIfDefined(1, 'portrait'), isNull);
      expect(
        await runtime.callFileDroppedIfDefined('/tmp/dropped.txt'),
        isNull,
      );
      expect(await runtime.callTextEditedIfDefined('compose', 0, 0), isNull);
      expect(
        await runtime.callThreadErrorIfDefined('worker-1', 'boom'),
        isNull,
      );
    });

    test(
      'key callback helpers preserve nil scancode argument positions',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}

function love.keypressed(key, scancode, isrepeat)
  testbed.keypressed = string.format("%s|%s|%s|%d", key, tostring(scancode), tostring(isrepeat), select('#', key, scancode, isrepeat))
end

function love.keyreleased(key, scancode)
  testbed.keyreleased = string.format("%s|%s|%d", key, tostring(scancode), select('#', key, scancode))
end
''');

        await runtime.callKeyPressedIfDefined('unknown', isRepeat: true);
        await runtime.callKeyReleasedIfDefined('unknown');

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['keypressed'], 'unknown|nil|true|3');
        expect(snapshot['keyreleased'], 'unknown|nil|2');
      },
    );
  });
}
