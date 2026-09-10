import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:path/path.dart' as p;

void main() {
  group('love.graphics.captureScreenshot', () {
    test(
      'callback delivery receives ImageData after the frame is rendered',
      () async {
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(
            windowMetrics: const LoveWindowMetrics(width: 16, height: 12),
          ),
        );

        await runtime.execute('''
capturedWidth = nil
capturedHeight = nil
capturedType = nil
capturedIsImageData = nil
capturedR = nil
capturedG = nil
capturedB = nil
capturedA = nil

function love.draw()
  love.graphics.clear(1, 0.5, 0.25, 1)
  love.graphics.captureScreenshot(function(data)
    capturedWidth, capturedHeight = data:getDimensions()
    capturedType = data:type()
    capturedIsImageData = data:typeOf("ImageData")
    capturedR, capturedG, capturedB, capturedA = data:getPixel(0, 0)
  end)
end
''');

        runtime.context.beginDrawFrame();
        runtime.context.graphics.origin();
        await runtime.callDrawIfDefined();

        expect(runtime.unwrapGlobal('capturedWidth'), isNull);
        expect(runtime.unwrapGlobal('capturedType'), isNull);

        await _dispatchPendingScreenshots(runtime);

        expect(runtime.unwrapGlobal('capturedWidth'), 16);
        expect(runtime.unwrapGlobal('capturedHeight'), 12);
        expect(runtime.unwrapGlobal('capturedType'), 'ImageData');
        expect(runtime.unwrapGlobal('capturedIsImageData'), isTrue);
        expect(
          runtime.unwrapGlobal('capturedR') as double,
          closeTo(1.0, 0.001),
        );
        expect(
          runtime.unwrapGlobal('capturedG') as double,
          closeTo(0.5, 0.001),
        );
        expect(
          runtime.unwrapGlobal('capturedB') as double,
          closeTo(0.25, 0.001),
        );
        expect(
          runtime.unwrapGlobal('capturedA') as double,
          closeTo(1.0, 0.001),
        );
      },
    );

    test('channel delivery exposes the screenshot as ImageData', () async {
      final runtime = LoveScriptRuntime(
        host: LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 10, height: 8),
        ),
      );

      await runtime.execute('''
channel = love.thread.newChannel()

function love.draw()
  love.graphics.clear(0.2, 0.4, 0.6, 1)
  love.graphics.captureScreenshot(channel)
end
''');

      runtime.context.beginDrawFrame();
      runtime.context.graphics.origin();
      await runtime.callDrawIfDefined();
      await _dispatchPendingScreenshots(runtime);

      await runtime.execute('''
queuedCount = channel:getCount()
popped = channel:pop()
if popped ~= nil then
  poppedType = popped:type()
  poppedIsImageData = popped:typeOf("ImageData")
  poppedWidth, poppedHeight = popped:getDimensions()
  poppedR, poppedG, poppedB, poppedA = popped:getPixel(0, 0)
end
''');

      expect(runtime.unwrapGlobal('queuedCount'), 1);
      expect(runtime.unwrapGlobal('poppedType'), 'ImageData');
      expect(runtime.unwrapGlobal('poppedIsImageData'), isTrue);
      expect(runtime.unwrapGlobal('poppedWidth'), 10);
      expect(runtime.unwrapGlobal('poppedHeight'), 8);
      expect(runtime.unwrapGlobal('poppedR') as double, closeTo(0.2, 0.001));
      expect(runtime.unwrapGlobal('poppedG') as double, closeTo(0.4, 0.001));
      expect(runtime.unwrapGlobal('poppedB') as double, closeTo(0.6, 0.001));
      expect(runtime.unwrapGlobal('poppedA') as double, closeTo(1.0, 0.001));
    });

    test(
      'filename delivery writes the rendered screenshot to the save directory',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'love-capture-screenshot-',
        );
        addTearDown(() async {
          if (await tempRoot.exists()) {
            await tempRoot.delete(recursive: true);
          }
        });

        final adapter = LoveLualikeFilesystemAdapter(
          environment: <String, String>{
            'HOME': tempRoot.path,
            'XDG_DATA_HOME': p.join(tempRoot.path, 'appdata'),
          },
          isWindows: false,
          isLinux: true,
          isMacOS: false,
          workingDirectoryProvider: () => tempRoot.path,
        );
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(
            windowMetrics: const LoveWindowMetrics(width: 9, height: 7),
          ),
          filesystemAdapter: adapter,
        );
        final filesystem = LoveFilesystemState.of(runtime.runtime);

        expect(filesystem.setIdentity('capture-screenshot-test'), isTrue);

        await runtime.execute('''
function love.draw()
  love.graphics.clear(0.125, 0.5, 0.875, 1)
  love.graphics.captureScreenshot("frame.png")
end
''');

        runtime.context.beginDrawFrame();
        runtime.context.graphics.origin();
        await runtime.callDrawIfDefined();
        await _dispatchPendingScreenshots(runtime);

        final fileData = await filesystem.readFileData(
          'frame.png',
          filename: 'frame.png',
        );
        expect(fileData, isNotNull);

        final decoded = LoveImageData.decodeEncodedBytes(
          bytes: fileData!.bytes,
          source: fileData.filename,
        );
        final pixel = decoded.getPixel(0, 0);
        expect(decoded.width, 9);
        expect(decoded.height, 7);
        expect(pixel.r, closeTo(0.125, 0.02));
        expect(pixel.g, closeTo(0.5, 0.02));
        expect(pixel.b, closeTo(0.875, 0.02));
        expect(pixel.a, closeTo(1.0, 0.02));
      },
    );
  });
}

Future<void> _dispatchPendingScreenshots(LoveScriptRuntime runtime) {
  final snapshot = runtime.context.graphics.snapshotScreenSurface();
  return runtime.context.graphics.dispatchPendingScreenshots(
    snapshot: snapshot,
    pixelWidth:
        (runtime.context.windowMetrics.width *
                runtime.context.windowMetrics.dpiScale)
            .round(),
    pixelHeight:
        (runtime.context.windowMetrics.height *
                runtime.context.windowMetrics.dpiScale)
            .round(),
  );
}
