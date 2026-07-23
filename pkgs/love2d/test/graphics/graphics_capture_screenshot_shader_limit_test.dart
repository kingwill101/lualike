import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

const String _flutterFragmentAssetShaderSource = '''
// LOVE2D_FLUTTER_FRAGMENT_ASSET: packages/love2d/test_assets/shaders/runtime_effect_solid_color.frag
extern vec4 uColor;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  return color;
}
''';

void main() {
  group('love.graphics.captureScreenshot shader limits', () {
    test(
      'dispatchPendingScreenshots rejects Flutter fragment-asset shaders with an explicit error',
      () async {
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(
            windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
          ),
        );

        await runtime.execute('''
captured = false
shader = love.graphics.newShader([[
$_flutterFragmentAssetShaderSource
]])

function love.draw()
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setShader(shader)
  love.graphics.rectangle("fill", 0, 0, 4, 4)
  love.graphics.setShader()
  love.graphics.captureScreenshot(function(data)
    captured = data ~= nil
  end)
end
''');

        runtime.context.beginDrawFrame();
        runtime.context.graphics.origin();
        await runtime.callDrawIfDefined();

        expect(
          () => _dispatchPendingScreenshots(runtime),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'message',
              contains(
                'love.graphics.captureScreenshot does not yet support software readback of Flutter fragment-asset shaders',
              ),
            ),
          ),
        );
        expect(runtime.unwrapGlobal('captured'), isFalse);
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
