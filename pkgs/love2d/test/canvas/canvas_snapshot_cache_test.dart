import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'drawing the same canvas twice in one frame reuses the same snapshot until the surface changes',
    () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute(r'''
local canvas = love.graphics.newCanvas(4, 4, {readable = true})

function love.draw()
  canvas:renderTo(function()
    love.graphics.clear(1, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 4, 4)
  end)

  love.graphics.draw(canvas, 0, 0)
  love.graphics.draw(canvas, 8, 0)
end
''');

      runtime.context.beginDrawFrame();
      runtime.context.graphics.origin();
      await runtime.callDrawIfDefined();

      final firstFrameSnapshots = runtime.context.graphics.commands
          .whereType<LoveImageCommand>()
          .map((command) => command.image)
          .whereType<LoveCanvasSnapshot>()
          .toList(growable: false);
      expect(firstFrameSnapshots, hasLength(2));
      expect(firstFrameSnapshots.first, same(firstFrameSnapshots.last));
      final firstFrameSnapshot = firstFrameSnapshots.first;

      runtime.context.beginDrawFrame();
      runtime.context.graphics.origin();
      await runtime.callDrawIfDefined();

      final secondFrameSnapshots = runtime.context.graphics.commands
          .whereType<LoveImageCommand>()
          .map((command) => command.image)
          .whereType<LoveCanvasSnapshot>()
          .toList(growable: false);
      expect(secondFrameSnapshots, hasLength(2));
      expect(secondFrameSnapshots.first, same(secondFrameSnapshots.last));
      expect(secondFrameSnapshots.first, isNot(same(firstFrameSnapshot)));
    },
  );
}
