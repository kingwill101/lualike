import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import '../test_support/lua_api_test_helpers.dart';

void main() {
  test('curve commands retain optional LOVE point counts', () async {
    final host = LoveHeadlessHost();
    final runtime = LuaLike().vm;
    installLove2d(runtime: runtime, host: host);

    await luaCall(
      runtime,
      const ['love', 'graphics', 'rectangle'],
      const <Object?>['line', 10, 20, 80, 50, 12, 8, 20],
    );
    expect(
      (host.graphics.commands.single as LoveRectangleCommand).pointCount,
      20,
    );

    host.graphics.beginFrame();
    await luaCall(
      runtime,
      const ['love', 'graphics', 'circle'],
      const <Object?>['line', 10, 20, 30, 28],
    );
    expect((host.graphics.commands.single as LoveCircleCommand).pointCount, 28);

    host.graphics.beginFrame();
    await luaCall(
      runtime,
      const ['love', 'graphics', 'ellipse'],
      const <Object?>['fill', 10, 20, 30, null, 29],
    );
    final ellipse = host.graphics.commands.single as LoveEllipseCommand;
    expect(ellipse.radiusY, 30);
    expect(ellipse.pointCount, 29);

    host.graphics.beginFrame();
    await luaCall(
      runtime,
      const ['love', 'graphics', 'arc'],
      const <Object?>['line', 'open', 10, 20, 30, 0, 1.5, 31],
    );
    expect((host.graphics.commands.single as LoveArcCommand).pointCount, 31);
  });

  test('curve commands keep automatic tessellation distinguishable', () async {
    final host = LoveHeadlessHost();
    final runtime = LuaLike().vm;
    installLove2d(runtime: runtime, host: host);

    await luaCall(
      runtime,
      const ['love', 'graphics', 'rectangle'],
      const <Object?>['line', 10, 20, 80, 50, null, 8, 20],
    );
    final rectangle = host.graphics.commands.single as LoveRectangleCommand;
    expect(rectangle.cornerRadiusX, 0);
    expect(rectangle.cornerRadiusY, 0);
    expect(rectangle.pointCount, isNull);

    host.graphics.beginFrame();
    await luaCall(
      runtime,
      const ['love', 'graphics', 'circle'],
      const <Object?>['line', 10, 20, 30],
    );
    expect(
      (host.graphics.commands.single as LoveCircleCommand).pointCount,
      isNull,
    );

    host.graphics.beginFrame();
    await luaCall(
      runtime,
      const ['love', 'graphics', 'arc'],
      const <Object?>['line', 10, 20, 30, 0, 1.5],
    );
    expect(
      (host.graphics.commands.single as LoveArcCommand).pointCount,
      isNull,
    );
  });
}
