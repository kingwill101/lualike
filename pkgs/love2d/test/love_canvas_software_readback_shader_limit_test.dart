import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

const String _flutterFragmentAssetShaderSource = '''
// LOVE2D_FLUTTER_FRAGMENT_ASSET: packages/love2d/test_assets/shaders/runtime_effect_solid_color.frag
extern vec4 uColor;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  return color;
}
''';

void main() {
  group('Canvas software readback shader limits', () {
    test(
      'Canvas:newImageData rejects Flutter fragment-asset shaders with an explicit LuaError',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
canvas = love.graphics.newCanvas(2, 2, { readable = true })
shader = love.graphics.newShader([[
$_flutterFragmentAssetShaderSource
]])

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setShader(shader)
  love.graphics.rectangle("fill", 0, 0, 2, 2)
  love.graphics.setShader()
  love.graphics.setCanvas()
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final canvas = runtime.unwrapGlobal('canvas');
        expect(
          () => _callMethod(canvas, 'newImageData'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Canvas:newImageData does not yet support software readback of Flutter fragment-asset shaders',
              ),
            ),
          ),
        );
      },
    );

    test(
      'Canvas:newImageData rejects nested canvas snapshots that depend on Flutter fragment-asset shaders',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
source = love.graphics.newCanvas(2, 2, { readable = true })
target = love.graphics.newCanvas(2, 2, { readable = true })
shader = love.graphics.newShader([[
$_flutterFragmentAssetShaderSource
]])

function love.draw()
  love.graphics.setCanvas(source)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setShader(shader)
  love.graphics.rectangle("fill", 0, 0, 2, 2)
  love.graphics.setShader()
  love.graphics.setCanvas()

  love.graphics.setCanvas(target)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.draw(source, 0, 0)
  love.graphics.setCanvas()
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final target = runtime.unwrapGlobal('target');
        expect(
          () => _callMethod(target, 'newImageData'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Canvas:newImageData does not yet support software readback of Flutter fragment-asset shaders',
              ),
            ),
          ),
        );
      },
    );
  });
}

Future<Object?> _callMethod(
  Object? receiver,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(
    _rawMethod(receiver, method).call(<Object?>[receiver, ...args]),
  );
}

BuiltinFunction _rawMethod(Object? receiver, String method) {
  final table = receiver is Value ? receiver.raw : receiver;
  expect(table, isA<Map>());
  final entry = (table! as Map)[method];
  return switch (entry) {
    final Value wrapped when wrapped.raw is BuiltinFunction =>
      wrapped.raw as BuiltinFunction,
    final BuiltinFunction function => function,
    _ => throw TestFailure('Expected $method to be a callable Lua method'),
  };
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved is List<Object?>) {
    return resolved.map(_unwrap).toList(growable: false);
  }
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
