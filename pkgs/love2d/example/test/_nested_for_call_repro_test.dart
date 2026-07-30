import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

const String _source = r'''
local TILE_SIZE = 16
local function pick_floor_quad(tileX, tileY)
  return { tileX, tileY }
end
local function draw_quad(quad, x, y, options)
  return x + y + #quad
end
local function draw_floor(left, top, right, bottom)
  local floorX = left
  local floorY = top
  local floorRight = right
  local floorBottom = bottom
  local floorW = floorRight - floorX
  local floorH = floorBottom - floorY
  local startTileX = 5
  local endTileX = 31
  local startTileY = 1
  local endTileY = 19
  local firstDetailTileX = 8
  local firstDetailTileY = 4
  for tileY = firstDetailTileY, endTileY, 2 do
    for tileX = firstDetailTileX, endTileX, 2 do
      local x = tileX * TILE_SIZE
      local y = tileY * TILE_SIZE
      local quad = pick_floor_quad(tileX, tileY)
      draw_quad(quad, x, y, {})
    end
  end
end
return draw_floor(81.0666669209798, 28.400000127156574, 497.0666669209798, 304.40000012715655)
''';

Future<void> _run(EngineMode mode) async {
  final runtime = LoveScriptRuntime(engineMode: mode, host: LoveHeadlessHost());
  await runtime.execute(_source, scriptPath: '=[nested for repro]');
}

void main() {
  test('nested for/call repro ast and bytecode', () async {
    await _run(EngineMode.ast);
    await _run(EngineMode.luaBytecode);
  });
}
