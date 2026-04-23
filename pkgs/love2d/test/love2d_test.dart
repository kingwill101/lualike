import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as package_image;
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:love2d/src/runtime/love_api_bindings.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'test_support/font_test_support.dart';
import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('Generated surface', () {
    test(
      'generated reference metadata includes representative LOVE symbols',
      () {
        expect(loveApiVersion, '11.5');
        expect(
          loveApiModules.any((module) => module.symbol == 'love.graphics'),
          isTrue,
        );
        expect(
          loveApiSymbols.any(
            (symbol) => symbol.symbol == 'love.graphics.newShader',
          ),
          isTrue,
        );
        expect(
          loveApiSymbols.any(
            (symbol) => symbol.symbol == 'Image:replacePixels',
          ),
          isTrue,
        );
        expect(loveApiTypes.any((type) => type.symbol == 'Image'), isTrue);
        expect(
          loveApiEnums.any((enumDoc) => enumDoc.symbol == 'AlignMode'),
          isTrue,
        );
      },
    );

    test(
      'every documented LOVE symbol resolves to either a real binding or a stub',
      () {
        ensureLoveApiRuntimeBindingsLoaded();
        final coveredSymbols = <String>{
          ...loveApiBindingFactories.keys,
          ...loveApiStubImplementations.keys,
          ...loveApiOverrides.keys,
        };

        for (final symbol in loveApiSymbols) {
          expect(
            coveredSymbols,
            contains(symbol.symbol),
            reason: 'Missing implementation entry for ${symbol.symbol}',
          );
        }
      },
    );

    test('installLove2d registers nested LOVE submodules', () {
      final runtime = createLuaLikeTestRuntime();

      installLove2d(runtime: runtime);

      final love = runtime.getCurrentEnv().get('love');
      expect(love, isA<Value>());

      final loveTable = (love! as Value).raw;
      expect(loveTable, isA<Map>());

      final graphics = (loveTable as Map)['graphics'];
      expect(graphics, isA<Value>());

      final graphicsTable = (graphics! as Value).raw;
      expect(graphicsTable, isA<Map>());
      expect((graphicsTable as Map)['newShader'], isA<Value>());
      expect((loveTable)['timer'], isA<Value>());
      expect((loveTable)['window'], isA<Value>());
    });

    test('registered stubs still throw symbol-specific Lua errors', () {
      final runtime = createLuaLikeTestRuntime();

      installLove2d(runtime: runtime);

      expect(
        () => luaRawFunction(runtime, const [
          'love',
          'graphics',
          'validateShader',
        ]).call(const <Object?>[]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('love.graphics.validateShader'),
          ),
        ),
      );
    });

    test('method stubs are generated even before object wrappers exist', () {
      final methodStub = loveApiStubImplementations['Image:replacePixels'];
      expect(methodStub, isNotNull);
      expect(
        () => methodStub!(const <Object?>[]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Image:replacePixels'),
          ),
        ),
      );
    });
  });

  group('Implemented runtime APIs', () {
    test(
      'LoveScriptRuntime executes user LOVE callbacks without calling stubs',
      () async {
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(
            windowMetrics: const LoveWindowMetrics(width: 400, height: 240),
          ),
        );

        await runtime.execute('''
testbed = {
  ticks = 0,
  loaded = false,
}

function love.load()
  testbed.loaded = true
  local width, height = love.graphics.getDimensions()
  testbed.window = width .. "x" .. height
end

function love.update(dt)
  testbed.ticks = testbed.ticks + 1
  testbed.dt = dt
end

function love.draw()
  love.graphics.setColor(1, 0.5, 0.25, 1)
  love.graphics.rectangle("fill", 4, 8, 12, 16)
end
''');

        expect(runtime.userLoveCallback('quit'), isNull);

        await runtime.callLoadIfDefined();
        await runtime.callUpdateIfDefined(0.25);
        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        expect(
          runtime.unwrapGlobalTable('testbed'),
          containsPair('loaded', isTrue),
        );
        expect(
          runtime.unwrapGlobalTable('testbed'),
          containsPair('window', '400x240'),
        );
        expect(runtime.unwrapGlobalTable('testbed'), containsPair('ticks', 1));
        expect(runtime.unwrapGlobalTable('testbed'), containsPair('dt', 0.25));
        expect(runtime.context.graphics.commands, hasLength(1));
        expect(
          runtime.context.graphics.commands.single,
          isA<LoveRectangleCommand>(),
        );
      },
    );

    test(
      'love.getVersion and love.isVersionCompatible follow LOVE 11.5',
      () async {
        final runtime = createLuaLikeTestRuntime();

        installLove2d(runtime: runtime);

        expect(await luaCall(runtime, const ['love', 'getVersion']), <Object?>[
          11,
          5,
          0,
          'Mysterious Mysteries',
        ]);
        expect(
          await luaCall(
            runtime,
            const ['love', 'isVersionCompatible'],
            const <Object?>['11.5'],
          ),
          isTrue,
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'isVersionCompatible'],
            const <Object?>['11.4'],
          ),
          isTrue,
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'isVersionCompatible'],
            const <Object?>['11'],
          ),
          isFalse,
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'isVersionCompatible'],
            const <Object?>[11, 2, 0],
          ),
          isTrue,
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'isVersionCompatible'],
            const <Object?>[12, 0, 0],
          ),
          isFalse,
        );
      },
    );

    test('deprecation output state can be queried and changed', () async {
      final runtime = createLuaLikeTestRuntime();

      installLove2d(runtime: runtime);

      expect(
        await luaCall(runtime, const ['love', 'hasDeprecationOutput']),
        isTrue,
      );

      await luaCall(
        runtime,
        const ['love', 'setDeprecationOutput'],
        const <Object?>[false],
      );

      expect(
        await luaCall(runtime, const ['love', 'hasDeprecationOutput']),
        isFalse,
      );
    });

    test('window and graphics APIs track headless host metrics', () async {
      final runtime = createLuaLikeTestRuntime();
      final host = LoveHeadlessHost(
        windowMetrics: const LoveWindowMetrics(
          width: 320,
          height: 180,
          title: 'Before',
          dpiScale: 2,
          desktopWidth: 1920,
          desktopHeight: 1080,
        ),
      );

      installLove2d(runtime: runtime, host: host);

      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getWidth']),
        320,
      );
      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getDimensions']),
        <Object?>[320, 180],
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'getMode']),
        <Object?>[320, 180, containsPair('vsync', 1)],
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'getTitle']),
        'Before',
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'getDPIScale']),
        2.0,
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'window', 'toPixels'],
          const <Object?>[10],
        ),
        20.0,
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'window', 'fromPixels'],
          const <Object?>[20],
        ),
        10.0,
      );

      expect(
        await luaCall(
          runtime,
          const ['love', 'window', 'setMode'],
          <Object?>[
            640,
            360,
            Value(<String, Object?>{
              'vsync': 0,
              'resizable': true,
              'highdpi': true,
              'fullscreentype': 'normal',
            }),
          ],
        ),
        isTrue,
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'getMode']),
        <Object?>[640, 360, containsPair('vsync', 0)],
      );

      await luaCall(
        runtime,
        const ['love', 'window', 'setTitle'],
        const <Object?>['After'],
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'getTitle']),
        'After',
      );
      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getWidth']),
        640,
      );
      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getDimensions']),
        <Object?>[640, 360],
      );
      expect(host.windowMetrics.title, 'After');
      expect(host.windowMetrics.resizable, isTrue);
      expect(host.windowMetrics.highDpi, isTrue);
      expect(host.windowMetrics.fullscreenType, 'normal');
    });

    test(
      'graphics environment APIs expose LOVE-style metrics and metadata',
      () async {
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(
            width: 320,
            height: 180,
            dpiScale: 2,
          ),
        );

        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/images/test_sheet.png': _encodeSizedTestPng(
                width: 32,
                height: 16,
              ),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getDPIScale']),
          2.0,
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getPixelWidth']),
          640,
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getPixelHeight']),
          360,
        );
        expect(
          await luaCall(runtime, const [
            'love',
            'graphics',
            'getPixelDimensions',
          ]),
          <Object?>[640, 360],
        );
        final imageFormats = await luaCall(runtime, const [
          'love',
          'graphics',
          'getImageFormats',
        ]);
        expect(imageFormats, containsPair('rgba8', true));
        expect(imageFormats, containsPair('depth24', false));
        expect(imageFormats, containsPair('DXT1', true));

        expect(
          await luaCall(runtime, const [
            'love',
            'graphics',
            'getDefaultFilter',
          ]),
          <Object?>['linear', 'linear', 1.0],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setDefaultFilter'],
          const <Object?>['nearest', 'linear', 2],
        );
        expect(
          await luaCall(runtime, const [
            'love',
            'graphics',
            'getDefaultFilter',
          ]),
          <Object?>['nearest', 'linear', 2.0],
        );

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'setNewFont'],
          const <Object?>[18],
        );
        expect(font, isNotNull);
        expect(await luaCallMethod(font!, 'getHeight'), 18.0);
        expect(host.graphics.font.size, 18);
        expect(
          host.graphics.font.filter,
          const LoveGraphicsDefaultFilter(
            min: LoveGraphicsFilterMode.nearest,
            mag: LoveGraphicsFilterMode.linear,
            anisotropy: 2,
          ),
        );

        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getRendererInfo']),
          <Object?>['LuaLike Headless', '11.5', 'LuaLike', 'HeadlessHost'],
        );

        final supported = await luaCall(runtime, const [
          'love',
          'graphics',
          'getSupported',
        ]);
        expect(
          supported,
          allOf(
            isA<Map>(),
            containsPair('lighten', isTrue),
            containsPair('instancing', isTrue),
            containsPair('glsl3', isTrue),
          ),
        );
        final supportedTarget = Value(<String, Object?>{'sentinel': 'ok'});
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'getSupported'],
            <Object?>[supportedTarget],
          ),
          allOf(
            containsPair('sentinel', 'ok'),
            containsPair('pixelshaderhighp', isTrue),
          ),
        );

        final canvasFormats = await luaCall(runtime, const [
          'love',
          'graphics',
          'getCanvasFormats',
        ]);
        expect(
          canvasFormats,
          allOf(
            isA<Map>(),
            containsPair('normal', isTrue),
            containsPair('rgba8', isTrue),
            containsPair('unknown', isFalse),
          ),
        );

        final limits = await luaCall(runtime, const [
          'love',
          'graphics',
          'getSystemLimits',
        ]);
        expect(
          limits,
          allOf(
            isA<Map>(),
            containsPair('texturesize', 4096),
            containsPair('pointsize', 64),
            containsPair('anisotropy', 16),
          ),
        );

        host.graphics.beginFrame();
        final image = await luaCall(
          runtime,
          const ['love', 'graphics', 'newImage'],
          const <Object?>['assets/images/test_sheet.png'],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[image!, 8, 12],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'print'],
          const <Object?>['stats', 24, 32],
        );

        final stats = await luaCall(
          runtime,
          const ['love', 'graphics', 'getStats'],
          <Object?>[
            Value(<String, Object?>{'sentinel': 7}),
          ],
        );
        expect(
          stats,
          allOf(
            isA<Map>(),
            containsPair('sentinel', 7),
            containsPair('drawcalls', 2),
            containsPair('images', 1),
            containsPair('fonts', 2),
            containsPair('texturememory', 0),
          ),
        );

        expect(host.graphics.commands, hasLength(2));
        expect(
          (host.graphics.commands.first as LoveImageCommand).image.filter,
          const LoveGraphicsDefaultFilter(
            min: LoveGraphicsFilterMode.nearest,
            mag: LoveGraphicsFilterMode.linear,
            anisotropy: 2,
          ),
        );
      },
    );

    test('math random uses a deterministic seedable generator', () async {
      final runtimeA = createLuaLikeTestRuntime();
      final runtimeB = createLuaLikeTestRuntime();

      installLove2d(
        runtime: runtimeA,
        host: LoveHeadlessHost(
          random: LoveRandomGenerator(low: 0x11111111, high: 0x22222222),
        ),
      );
      installLove2d(
        runtime: runtimeB,
        host: LoveHeadlessHost(
          random: LoveRandomGenerator(low: 0x11111111, high: 0x22222222),
        ),
      );

      expect(
        await luaCall(runtimeA, const ['love', 'math', 'getRandomSeed']),
        <Object?>[0x11111111, 0x22222222],
      );
      expect(
        await luaCall(runtimeA, const ['love', 'math', 'random']),
        await luaCall(runtimeB, const ['love', 'math', 'random']),
      );
      expect(
        await luaCall(
          runtimeA,
          const ['love', 'math', 'random'],
          const <Object?>[5],
        ),
        inInclusiveRange(1, 5),
      );
      expect(
        await luaCall(
          runtimeA,
          const ['love', 'math', 'random'],
          const <Object?>[10, 20],
        ),
        inInclusiveRange(10, 20),
      );

      await luaCall(
        runtimeA,
        const ['love', 'math', 'setRandomSeed'],
        const <Object?>[5, 6],
      );
      expect(
        await luaCall(runtimeA, const ['love', 'math', 'getRandomSeed']),
        <Object?>[5, 6],
      );
    });

    test(
      'string-driven APIs accept LuaString inputs and LuaString table keys',
      () async {
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost();

        installLove2d(runtime: runtime, host: host);

        expect(
          await luaCall(
            runtime,
            const ['love', 'isVersionCompatible'],
            <Object?>[LuaString.fromDartString('11.4')],
          ),
          isTrue,
        );

        await luaCall(
          runtime,
          const ['love', 'window', 'setTitle'],
          <Object?>[LuaString.fromDartString('LuaString Title')],
        );
        expect(
          await luaCall(runtime, const ['love', 'window', 'getTitle']),
          'LuaString Title',
        );

        await luaCall(
          runtime,
          const ['love', 'window', 'setMode'],
          <Object?>[
            640,
            360,
            Value(<Object?, Object?>{
              LuaString.fromDartString('fullscreentype'):
                  LuaString.fromDartString('normal'),
              LuaString.fromDartString('vsync'): 0,
            }),
          ],
        );
        expect(host.windowMetrics.fullscreenType, 'normal');
        expect(host.windowMetrics.vsync, 0);
      },
    );

    test(
      'graphics font APIs create mutable font objects and affect text',
      () async {
        final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/Body.ttf': veraBytes,
              'assets/fonts/Fallback.ttf': veraBytes,
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime.runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);
        final interpreter = runtime.runtime;
        final imageFontData = await luaCall(
          interpreter,
          const ['love', 'image', 'newImageData'],
          <Object?>[9, 6, 'rgba8', imageFontStripBytes()],
        );
        runtime.runtime.globals.define(
          '__image_font_data',
          imageFontData is Value ? imageFontData : Value(imageFontData),
        );

        await runtime.execute('''
testbed = {}

local heading = love.graphics.newFont(24)
heading:setLineHeight(1.25)

local body = love.graphics.newFont("assets/fonts/Body.ttf", 16, "mono", 2)
local fallback = love.graphics.newFont("assets/fonts/Fallback.ttf", 18, "light", 2)
body:setFallbacks(fallback)
love.graphics.setFont(body)
body:setFilter("nearest", "linear", 2.5)

local current = love.graphics.getFont()
local released_font = love.graphics.newFont(11)
local image_data = __image_font_data
local image_font = love.graphics.newImageFont(image_data, "ABC", 1)
local image_fallback = love.graphics.newImageFont(image_data, "XYZ", 0)
image_font:setFallbacks(image_fallback)
testbed.heading_height = heading:getHeight()
testbed.heading_width = heading:getWidth("LOVE")
testbed.heading_ascent = heading:getAscent()
testbed.heading_descent = heading:getDescent()
testbed.heading_baseline = heading:getBaseline()
testbed.current_line_height = current:getLineHeight()
testbed.current_dpi_scale = current:getDPIScale()
testbed.current_type = current:type()
testbed.current_is_font = current:typeOf("Font")
testbed.current_is_object = current:typeOf("Object")
testbed.current_is_image = current:typeOf("Image")
testbed.current_has_glyphs = current:hasGlyphs("LuaLike")
local filter_min, filter_mag, filter_anisotropy = current:getFilter()
testbed.current_filter = string.format("%s/%s/%.1f", filter_min, filter_mag, filter_anisotropy)
testbed.current_kerning = current:getKerning("L", "O")
testbed.release_first = released_font:release()
testbed.release_second = released_font:release()
testbed.image_font_primary_a_width = image_font:getWidth("A")
testbed.image_fallback_z_width = image_fallback:getWidth("Z")
testbed.image_font_width = image_font:getWidth("AB")
testbed.image_font_fallback_width = image_font:getWidth("AZ")
testbed.image_font_has = image_font:hasGlyphs("AZ")
testbed.image_font_missing = image_font:hasGlyphs("AQ")

local wrap_width, wrap_lines = current:getWrap("LuaLike love wrap example", 90)
testbed.wrap_width = wrap_width
testbed.wrap_count = #wrap_lines

function love.draw()
  love.graphics.print("heading", heading, 12, 18)
  love.graphics.print("body", 24, 42)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['heading_height'], 24.0);
        expect(snapshot['heading_width'], closeTo(57.6, 1e-9));
        expect(snapshot['heading_ascent'], 19.0);
        expect(snapshot['heading_descent'], 5.0);
        expect(snapshot['heading_baseline'], 19.0);
        expect(snapshot['current_line_height'], 1.0);
        expect(snapshot['current_dpi_scale'], 2.0);
        expect(snapshot['current_type'], 'Font');
        expect(snapshot['current_is_font'], isTrue);
        expect(snapshot['current_is_object'], isTrue);
        expect(snapshot['current_is_image'], isFalse);
        expect(snapshot['current_has_glyphs'], isTrue);
        expect(snapshot['current_filter'], 'nearest/linear/2.5');
        expect(snapshot['current_kerning'], 0.0);
        expect(snapshot['release_first'], isTrue);
        expect(snapshot['release_second'], isFalse);
        expect(snapshot['image_font_primary_a_width'], greaterThan(0.0));
        expect(snapshot['image_fallback_z_width'], greaterThan(0.0));
        expect(snapshot['image_font_width'], 5.0);
        final imageFontPrimaryAWidth =
            snapshot['image_font_primary_a_width'] as num;
        final imageFallbackZWidth = snapshot['image_fallback_z_width'] as num;
        expect(
          snapshot['image_font_fallback_width'],
          imageFontPrimaryAWidth + imageFallbackZWidth,
        );
        expect(snapshot['image_font_has'], isTrue);
        expect(snapshot['image_font_missing'], isFalse);
        expect(snapshot['wrap_width'], 80.0);
        expect(snapshot['wrap_count'], 3);

        expect(runtime.context.graphics.commands, hasLength(2));
        final heading = runtime.context.graphics.commands[0] as LoveTextCommand;
        expect(heading.font.size, 24);
        expect(heading.font.lineHeight, 1.25);

        final body = runtime.context.graphics.commands[1] as LoveTextCommand;
        expect(body.font.size, 16);
        expect(body.font.hinting, 'mono');
        expect(body.font.dpiScale, 2.0);
        expect(body.font.source, 'assets/fonts/Body.ttf');
        expect(body.font.fontType, LoveFont.trueTypeFontType);
        expect(body.font.fallbacks, hasLength(1));
        expect(body.font.fallbacks.single.source, 'assets/fonts/Fallback.ttf');
        expect(
          body.font.filter,
          const LoveGraphicsDefaultFilter(
            min: LoveGraphicsFilterMode.nearest,
            mag: LoveGraphicsFilterMode.linear,
            anisotropy: 2.5,
          ),
        );
      },
    );

    test(
      'graphics text APIs create drawable Text objects with LOVE semantics',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}

local font = love.graphics.newFont(20)
local headline = love.graphics.newText(font, {
  {1.0, 0.5, 0.2, 1.0},
  "Lua",
  {0.2, 0.8, 1.0, 1.0},
  "Like",
})
local appended = headline:add(" body", 12, 18)
local wrapped = headline:addf("abcd efgh", 48, "center", 4, 40)

testbed.base_width = headline:getWidth(1)
testbed.base_height = headline:getHeight(1)
testbed.default_width = headline:getWidth()
testbed.appended_width = headline:getWidth(appended)
local wrapped_width, wrapped_height = headline:getDimensions(wrapped)
testbed.wrapped_width = wrapped_width
testbed.wrapped_height = wrapped_height
testbed.headline_font_height = headline:getFont():getHeight()

local status = love.graphics.newText(font)
status:setFont(love.graphics.newFont(10))
testbed.status_font_height = status:getFont():getHeight()
status:setf({{0.9, 1.0, 0.7, 1.0}, "reset demo"}, 30, "left")
local status_width, status_height = status:getDimensions()
testbed.status_width = status_width
testbed.status_height = status_height
status:clear()
testbed.cleared_width = status:getWidth()
status:add({{1.0, 1.0, 1.0, 1.0}, "ok"}, 2, 3)
testbed.status_final_width = status:getWidth()

function love.draw()
  love.graphics.setColor(0.8, 0.9, 1.0, 0.75)
  love.graphics.draw(headline, love.math.newTransform(8, 10, 0.05))
  love.graphics.draw(status, 20, 60)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['base_width'], 84.0);
        expect(snapshot['base_height'], 20.0);
        expect(snapshot['default_width'], 48.0);
        expect(snapshot['appended_width'], 60.0);
        expect(snapshot['wrapped_width'], 48.0);
        expect(snapshot['wrapped_height'], 40.0);
        expect(snapshot['headline_font_height'], 20.0);
        expect(snapshot['status_font_height'], 10.0);
        expect(snapshot['status_width'], 30.0);
        expect(snapshot['status_height'], 20.0);
        expect(snapshot['cleared_width'], 0.0);
        expect(snapshot['status_final_width'], 12.0);

        expect(runtime.context.graphics.commands, hasLength(2));
        final headline =
            runtime.context.graphics.commands[0] as LoveTextObjectCommand;
        expect(headline.textObject.font.size, 20.0);
        expect(headline.textObject.entries, hasLength(3));
        expect(headline.textObject.entries.first.plainText, 'LuaLike');
        expect(headline.textObject.entries.first.spans, hasLength(2));
        expect(
          headline.textObject.entries.first.spans.first.color,
          const LoveColor(1.0, 0.5, 0.2, 1.0),
        );
        expect(headline.textObject.entries[1].plainText, ' body');
        expect(headline.textObject.entries[2].align, 'center');
        expect(headline.textObject.entries[2].wrapLimit, 48.0);

        final status =
            runtime.context.graphics.commands[1] as LoveTextObjectCommand;
        expect(status.textObject.font.size, 10.0);
        expect(status.textObject.entries, hasLength(1));
        expect(status.textObject.entries.single.plainText, 'ok');
      },
    );

    test('audio source APIs create playable LOVE Source objects', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());
      final sourceDir = await Directory.systemTemp.createTemp('love2d-audio-');
      addTearDown(() => sourceDir.delete(recursive: true));

      final filesystem = LoveFilesystemState.of(runtime.runtime);
      expect(filesystem.setSource(sourceDir.path), isTrue);

      await File(
        '${sourceDir.path}${Platform.pathSeparator}sounds${Platform.pathSeparator}theme.mp3',
      ).create(recursive: true);
      await File(
        '${sourceDir.path}${Platform.pathSeparator}sounds${Platform.pathSeparator}theme.mp3',
      ).writeAsBytes(const <int>[0x49, 0x44, 0x33, 0x04, 0x00, 0x00]);
      await File(
        '${sourceDir.path}${Platform.pathSeparator}sounds${Platform.pathSeparator}wall.mp3',
      ).writeAsBytes(const <int>[0x49, 0x44, 0x33, 0x04, 0x00, 0x00]);

      await runtime.execute('''
testbed = {}

local theme = love.audio.newSource("sounds/theme.mp3", "stream")
local wall = love.audio.newSource("sounds/wall.mp3", "static")

theme:setLooping(true)
theme:setVolume(0.4)
theme:setPitch(1.25)
theme:setPosition(10, 20, 0)
theme:setVelocity(3, 4, 0)
theme:setRelative(true)
theme:seek(2.5)
love.audio.setVolume(0.8)

wall:play()
love.audio.play(theme)
testbed.active_after_play = love.audio.getActiveSourceCount()
testbed.theme_playing = theme:isPlaying()
testbed.wall_playing = wall:isPlaying()
testbed.theme_looping = theme:isLooping()
testbed.theme_type = theme:getType()
testbed.theme_volume = theme:getVolume()
testbed.theme_pitch = theme:getPitch()
testbed.theme_tell = theme:tell()
local px, py, pz = theme:getPosition()
testbed.theme_position = string.format("%.1f/%.1f/%.1f", px, py, pz)
local vx, vy, vz = theme:getVelocity()
testbed.theme_velocity = string.format("%.1f/%.1f/%.1f", vx, vy, vz)
testbed.theme_relative = theme:isRelative()
testbed.master_volume = love.audio.getVolume()

love.audio.pause(theme)
testbed.theme_after_pause = theme:isPlaying()
testbed.active_after_pause = love.audio.getActiveSourceCount()

wall:stop()
testbed.wall_after_stop = wall:isPlaying()
testbed.active_after_stop = love.audio.getActiveSourceCount()

local clone = theme:clone()
testbed.clone_type = clone:getType()
testbed.clone_looping = clone:isLooping()
testbed.clone_volume = clone:getVolume()
testbed.clone_pitch = clone:getPitch()
''');

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['active_after_play'], 2);
      expect(snapshot['theme_playing'], isTrue);
      expect(snapshot['wall_playing'], isTrue);
      expect(snapshot['theme_looping'], isTrue);
      expect(snapshot['theme_type'], 'stream');
      expect(snapshot['theme_volume'], 0.4);
      expect(snapshot['theme_pitch'], 1.25);
      expect(snapshot['theme_tell'], 2.5);
      expect(snapshot['theme_position'], '10.0/20.0/0.0');
      expect(snapshot['theme_velocity'], '3.0/4.0/0.0');
      expect(snapshot['theme_relative'], isTrue);
      expect(snapshot['master_volume'], 0.8);
      expect(snapshot['theme_after_pause'], isFalse);
      expect(snapshot['active_after_pause'], 1);
      expect(snapshot['wall_after_stop'], isFalse);
      expect(snapshot['active_after_stop'], 0);
      expect(snapshot['clone_type'], 'stream');
      expect(snapshot['clone_looping'], isTrue);
      expect(snapshot['clone_volume'], 0.4);
      expect(snapshot['clone_pitch'], 1.25);
    });

    test('audio newSource accepts SoundData and FileData inputs', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
testbed = {}

local pcm = love.sound.newSoundData(8, 22050, 16, 2)
local filedata = love.filesystem.newFileData("abc", "effect.ogg")

local source_from_data = love.audio.newSource(pcm, "static")
local source_from_filedata = love.audio.newSource(filedata, "stream")

testbed.data_type = source_from_data:type()
testbed.data_source_type = source_from_data:getType()
testbed.data_duration = source_from_data:getDuration()
testbed.data_channels = source_from_data:getChannelCount()
testbed.file_type = source_from_filedata:type()
testbed.file_source_type = source_from_filedata:getType()
''');

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['data_type'], 'Source');
      expect(snapshot['data_source_type'], 'static');
      expect(snapshot['data_duration'], closeTo(8 / 22050, 1e-12));
      expect(snapshot['data_channels'], 2);
      expect(snapshot['file_type'], 'Source');
      expect(snapshot['file_source_type'], 'stream');
    });

    test('joystick APIs expose connected gamepads', () async {
      final runtime = LoveScriptRuntime(
        host: LoveHeadlessHost(
          joysticks: LoveJoystickManager(
            devices: <LoveJoystickDevice>[
              LoveJoystickDevice(
                id: 1,
                name: 'Pad 1',
                gamepadButtons: const <String>{'dpup', 'a'},
              ),
            ],
          ),
        ),
      );

      await runtime.execute('''
testbed = {}

local sticks = love.joystick.getJoysticks()
local pad = sticks[1]

testbed.present = pad ~= nil
testbed.type = pad:type()
testbed.name = pad:getName()
testbed.gamepad = pad:isGamepad()
testbed.up = pad:isGamepadDown("dpup")
testbed.down = pad:isGamepadDown("dpdown")
testbed.any = pad:isGamepadDown("start", "a")
''');

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['present'], isTrue);
      expect(snapshot['type'], 'Joystick');
      expect(snapshot['name'], 'Pad 1');
      expect(snapshot['gamepad'], isTrue);
      expect(snapshot['up'], isTrue);
      expect(snapshot['down'], isFalse);
      expect(snapshot['any'], isTrue);
    });

    test(
      'graphics mesh APIs build drawable geometry from LOVE vertex tables',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}

local mesh = love.graphics.newMesh({
  {1, 2, 0, 0, 1, 0, 0, 1},
  {5, 2, 0, 0, 0, 1, 0, 1},
  {5, 6, 0, 0, 0, 0, 1, 1},
}, "fan", "static")

mesh:setVertices({
  {10, 20, 0, 0, 0.25, 0.50, 0.75, 1},
  {30, 20, 0, 0, 0.50, 0.25, 0.75, 1},
  {30, 40, 0, 0, 0.75, 0.50, 0.25, 1},
  {10, 40, 0, 0, 1, 1, 1, 1},
})

local r1, g1, b1, a1 = mesh:getVertexAttribute(1, 3)
testbed.color1 = string.format("%.2f/%.2f/%.2f/%.2f", r1, g1, b1, a1)

mesh:setVertexAttribute(2, 3, 0.1, 0.2, 0.3, 0.4)
local r2, g2, b2, a2 = mesh:getVertexAttribute(2, 3)
testbed.color2 = string.format("%.2f/%.2f/%.2f/%.2f", r2, g2, b2, a2)

testbed.type = mesh:type()
testbed.mesh = mesh:typeOf("Mesh")
testbed.object = mesh:typeOf("Object")

love.graphics.draw(mesh, 4, 6)
''');

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['type'], 'Mesh');
        expect(snapshot['mesh'], isTrue);
        expect(snapshot['object'], isTrue);
        expect(snapshot['color1'], '0.25/0.50/0.75/1.00');
        expect(snapshot['color2'], '0.10/0.20/0.30/0.40');

        expect(runtime.context.graphics.commands, hasLength(1));
        final command =
            runtime.context.graphics.commands.single as LoveMeshCommand;
        expect(command.mesh.drawMode, LoveMeshDrawMode.fan);
        expect(command.mesh.usage, LoveMeshUsage.staticUsage);
        expect(command.mesh.vertices, hasLength(4));

        final first = command.mesh.vertices[0];
        expect(first.x, 10);
        expect(first.y, 20);
        expect(first.color, const LoveColor(0.25, 0.5, 0.75, 1.0));

        final second = command.mesh.vertices[1];
        expect(second.x, 30);
        expect(second.y, 20);
        expect(second.color, const LoveColor(0.1, 0.2, 0.3, 0.4));

        final origin = _transformPoint(command.drawTransform, 0, 0);
        expect(origin.x, 4);
        expect(origin.y, 6);
      },
    );

    test(
      'graphics image APIs create drawable objects and record draw commands',
      () async {
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/images/test_sheet.png': _encodeSizedTestPng(
                width: 32,
                height: 16,
              ),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime.runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        await runtime.execute('''
testbed = {}

local sprite = love.graphics.newImage("assets/images/test_sheet.png")
local quad = love.graphics.newQuad(8, 0, 8, 8, sprite)
sprite:setFilter("nearest")
sprite:setWrap("repeat", "mirroredrepeat", "clampzero")

local width, height = sprite:getDimensions()
testbed.image_dimensions = string.format("%dx%d", width, height)
testbed.image_width = sprite:getWidth()
testbed.image_height = sprite:getHeight()
testbed.image_dpi_scale = sprite:getDPIScale()
testbed.image_format = sprite:getFormat()
testbed.image_depth = sprite:getDepth()
testbed.image_layers = sprite:getLayerCount()
testbed.image_mipmaps = sprite:getMipmapCount()
local image_mipmap_filter, image_mipmap_sharpness = sprite:getMipmapFilter()
testbed.image_mipmap_filter = string.format("%s/%.1f", tostring(image_mipmap_filter), image_mipmap_sharpness)
testbed.image_depth_sample = tostring(sprite:getDepthSampleMode())
testbed.image_type = sprite:getTextureType()
testbed.image_pixel_width = sprite:getPixelWidth()
testbed.image_pixel_height = sprite:getPixelHeight()
local pixel_width, pixel_height = sprite:getPixelDimensions()
testbed.image_pixel_dimensions = string.format("%dx%d", pixel_width, pixel_height)
local filter_min, filter_mag, filter_anisotropy = sprite:getFilter()
testbed.image_filter = string.format("%s/%s/%.1f", filter_min, filter_mag, filter_anisotropy)
local wrap_s, wrap_t, wrap_r = sprite:getWrap()
testbed.image_wrap = string.format("%s/%s/%s", wrap_s, wrap_t, wrap_r)
testbed.image_compressed = sprite:isCompressed()
testbed.image_linear = sprite:isFormatLinear()
testbed.image_readable = sprite:isReadable()

local qx, qy, qw, qh = quad:getViewport()
testbed.quad_before = string.format("%.0f,%.0f,%.0f,%.0f", qx, qy, qw, qh)

quad:setViewport(16, 0, 8, 8)

local nx, ny, nw, nh = quad:getViewport()
testbed.quad_after = string.format("%.0f,%.0f,%.0f,%.0f", nx, ny, nw, nh)

local tw, th = quad:getTextureDimensions()
testbed.quad_texture = string.format("%.0f,%.0f", tw, th)

function love.draw()
  love.graphics.translate(5, 6)
  love.graphics.setColor(0.75, 0.5, 1.0, 0.8)
  love.graphics.draw(sprite, 10, 20, 0.25, 2, 3, 4, 5, 0.1, -0.2)
  love.graphics.draw(sprite, quad, 30, 40, -0.5, 1.5, 1.25, 2, 3, -0.15, 0.05)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['image_dimensions'], '32x16');
        expect(snapshot['image_width'], 32);
        expect(snapshot['image_height'], 16);
        expect(snapshot['image_dpi_scale'], 1.0);
        expect(snapshot['image_format'], 'normal');
        expect(snapshot['image_depth'], 1);
        expect(snapshot['image_layers'], 1);
        expect(snapshot['image_mipmaps'], 1);
        expect(snapshot['image_mipmap_filter'], 'nil/0.0');
        expect(snapshot['image_depth_sample'], 'nil');
        expect(snapshot['image_type'], '2d');
        expect(snapshot['image_pixel_width'], 32);
        expect(snapshot['image_pixel_height'], 16);
        expect(snapshot['image_pixel_dimensions'], '32x16');
        expect(snapshot['image_filter'], 'nearest/nearest/1.0');
        expect(snapshot['image_wrap'], 'repeat/mirroredrepeat/clampzero');
        expect(snapshot['image_compressed'], isFalse);
        expect(snapshot['image_linear'], isFalse);
        expect(snapshot['image_readable'], isTrue);
        expect(snapshot['quad_before'], '8,0,8,8');
        expect(snapshot['quad_after'], '16,0,8,8');
        expect(snapshot['quad_texture'], '32,16');

        expect(runtime.context.graphics.commands, hasLength(2));

        final first = runtime.context.graphics.commands[0] as LoveImageCommand;
        expect(first.image.source, 'assets/images/test_sheet.png');
        expect(first.image.width, 32);
        expect(first.image.height, 16);
        expect(
          first.image.filter,
          const LoveGraphicsDefaultFilter(
            min: LoveGraphicsFilterMode.nearest,
            mag: LoveGraphicsFilterMode.nearest,
            anisotropy: 1.0,
          ),
        );
        expect(
          first.image.wrap,
          const LoveGraphicsWrap(
            horizontal: LoveGraphicsWrapMode.repeat,
            vertical: LoveGraphicsWrapMode.mirroredRepeat,
            depth: LoveGraphicsWrapMode.clampZero,
          ),
        );
        expect(first.quad, isNull);
        expect(first.color, const LoveColor(0.75, 0.5, 1.0, 0.8));
        final firstLocalOrigin = _transformPoint(first.drawTransform, 4, 5);
        expect(firstLocalOrigin.x, closeTo(10, 1e-9));
        expect(firstLocalOrigin.y, closeTo(20, 1e-9));
        final firstWorldOrigin = _transformPoint(
          _combineImageTransform(first),
          4,
          5,
        );
        expect(firstWorldOrigin.x, closeTo(15, 1e-9));
        expect(firstWorldOrigin.y, closeTo(26, 1e-9));

        final second = runtime.context.graphics.commands[1] as LoveImageCommand;
        expect(second.quad, isNotNull);
        expect(second.quad!.x, 16);
        expect(second.quad!.y, 0);
        expect(second.quad!.width, 8);
        expect(second.quad!.height, 8);
        expect(second.quad!.textureWidth, 32);
        expect(second.quad!.textureHeight, 16);
        final secondLocalOrigin = _transformPoint(second.drawTransform, 2, 3);
        expect(secondLocalOrigin.x, closeTo(30, 1e-9));
        expect(secondLocalOrigin.y, closeTo(40, 1e-9));
        final secondWorldOrigin = _transformPoint(
          _combineImageTransform(second),
          2,
          3,
        );
        expect(secondWorldOrigin.x, closeTo(35, 1e-9));
        expect(secondWorldOrigin.y, closeTo(46, 1e-9));
      },
    );

    test(
      'loaded images keep decoded pixels and switch to image-data rendering after replacePixels',
      () async {
        final sourcePixels = LoveImageData(width: 8, height: 8);
        sourcePixels.setPixel(4, 4, const LoveColor(0.1, 0.2, 0.3, 1.0));

        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/images/test_sheet.png': sourcePixels.encode('png'),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime.runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        await runtime.execute('''
testbed = {}

local sprite = love.graphics.newImage("assets/images/test_sheet.png")
local patch = love.image.newImageData(2, 2)
patch:setPixel(0, 0, 1.0, 0.25, 0.15, 1.0)
patch:setPixel(1, 0, 0.10, 0.92, 0.88, 1.0)
patch:setPixel(0, 1, 1.0, 0.96, 0.24, 1.0)
patch:setPixel(1, 1, 0.62, 0.42, 1.0, 1.0)
sprite:replacePixels(patch, 1, 1, 4, 4)

testbed.image_format = sprite:getFormat()

function love.draw()
  love.graphics.draw(sprite, 20, 24)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['image_format'], 'normal');

        final draw =
            runtime.context.graphics.commands.single as LoveImageCommand;
        expect(draw.image.preferImageDataRendering, isTrue);
        expect(
          draw.image.imageData!.getPixel(4, 4),
          const LoveColor(1.0, 0.25, 0.15, 1.0),
        );
        expect(
          draw.image.imageData!.getPixel(5, 5),
          const LoveColor(0.62, 0.42, 1.0, 1.0),
        );
      },
    );

    test(
      'graphics canvas APIs record offscreen surfaces and replay snapshots',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}

local canvas = love.graphics.newCanvas(64, 32, {
  msaa = 0,
  readable = true,
  dpiscale = 2,
  mipmaps = "manual",
})
canvas:setFilter("nearest", "linear", 2)
canvas:setMipmapFilter("nearest", 0.5)
canvas:setWrap("repeat", "mirroredrepeat", "clampzero")
local quad = love.graphics.newQuad(8, 4, 24, 12, canvas)
local depth_canvas = love.graphics.newCanvas(16, 16, {
  format = "depth24",
  readable = true,
})
depth_canvas:setDepthSampleMode("lequal")

testbed.canvas_dimensions = string.format("%dx%d", canvas:getDimensions())
testbed.canvas_pixels = string.format("%dx%d", canvas:getPixelDimensions())
testbed.canvas_dpi_scale = canvas:getDPIScale()
testbed.canvas_format = canvas:getFormat()
testbed.canvas_depth = canvas:getDepth()
testbed.canvas_layers = canvas:getLayerCount()
testbed.canvas_mipmaps = canvas:getMipmapCount()
testbed.canvas_type = canvas:getTextureType()
testbed.canvas_filter = string.format("%s/%s/%.1f", canvas:getFilter())
local canvas_mipmap_filter, canvas_mipmap_sharpness = canvas:getMipmapFilter()
testbed.canvas_mipmap_filter = string.format("%s/%.1f", tostring(canvas_mipmap_filter), canvas_mipmap_sharpness)
testbed.canvas_wrap = string.format("%s/%s/%s", canvas:getWrap())
testbed.canvas_msaa = canvas:getMSAA()
testbed.canvas_readable = canvas:isReadable()
testbed.canvas_mipmap_mode = canvas:getMipmapMode()
testbed.canvas_depth_compare = tostring(canvas:getDepthSampleMode())
testbed.depth_canvas_compare = depth_canvas:getDepthSampleMode()
testbed.depth_canvas_format = depth_canvas:getFormat()
testbed.depth_canvas_readable = depth_canvas:isReadable()
canvas:generateMipmaps()

function love.draw()
  love.graphics.setCanvas(canvas)
  local current = love.graphics.getCanvas()
  testbed.canvas_active_inside = current ~= nil
  love.graphics.clear(0.1, 0.2, 0.3, 0.4)
  love.graphics.setColor(1, 0, 0, 1)
  love.graphics.rectangle("fill", 2, 3, 10, 11)
  love.graphics.setCanvas()
  testbed.canvas_active_after = love.graphics.getCanvas() == nil

  canvas:renderTo(function()
    local current = love.graphics.getCanvas()
    testbed.canvas_active_render_to = current ~= nil
    love.graphics.setColor(0, 1, 0, 1)
    love.graphics.circle("fill", 20, 12, 6)
  end)

  local stats = love.graphics.getStats()
  testbed.canvas_switches = stats.canvasswitches
  testbed.canvas_count = stats.canvases

  love.graphics.draw(canvas, 10, 20)
  love.graphics.draw(canvas, quad, 40, 50)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['canvas_dimensions'], '64x32');
        expect(snapshot['canvas_pixels'], '128x64');
        expect(snapshot['canvas_dpi_scale'], 2.0);
        expect(snapshot['canvas_format'], 'normal');
        expect(snapshot['canvas_depth'], 1);
        expect(snapshot['canvas_layers'], 1);
        expect(snapshot['canvas_mipmaps'], 8);
        expect(snapshot['canvas_type'], '2d');
        expect(snapshot['canvas_filter'], 'nearest/linear/2.0');
        expect(snapshot['canvas_mipmap_filter'], 'nearest/0.5');
        expect(snapshot['canvas_wrap'], 'repeat/mirroredrepeat/clampzero');
        expect(snapshot['canvas_msaa'], 0);
        expect(snapshot['canvas_readable'], isTrue);
        expect(snapshot['canvas_mipmap_mode'], 'manual');
        expect(snapshot['canvas_depth_compare'], 'nil');
        expect(snapshot['depth_canvas_compare'], 'lequal');
        expect(snapshot['depth_canvas_format'], 'depth24');
        expect(snapshot['depth_canvas_readable'], isTrue);
        expect(snapshot['canvas_active_inside'], isTrue);
        expect(snapshot['canvas_active_after'], isTrue);
        expect(snapshot['canvas_active_render_to'], isTrue);
        expect(snapshot['canvas_switches'], 4);
        expect(snapshot['canvas_count'], 2);

        expect(runtime.context.graphics.commands, hasLength(2));
        final first = runtime.context.graphics.commands[0] as LoveImageCommand;
        final second = runtime.context.graphics.commands[1] as LoveImageCommand;
        expect(first.image, isA<LoveCanvasSnapshot>());
        expect(second.image, isA<LoveCanvasSnapshot>());

        final firstSnapshot = first.image as LoveCanvasSnapshot;
        expect(firstSnapshot.width, 64);
        expect(firstSnapshot.height, 32);
        expect(firstSnapshot.pixelWidth, 128);
        expect(firstSnapshot.pixelHeight, 64);
        expect(firstSnapshot.dpiScale, 2.0);
        expect(firstSnapshot.msaa, 0);
        expect(firstSnapshot.readable, isTrue);
        expect(firstSnapshot.format, 'normal');
        expect(firstSnapshot.depth, 1);
        expect(firstSnapshot.layerCount, 1);
        expect(firstSnapshot.mipmapCount, 8);
        expect(firstSnapshot.textureType, '2d');
        expect(firstSnapshot.mipmapMode, LoveCanvasMipmapMode.manual);
        expect(
          firstSnapshot.filter,
          const LoveGraphicsDefaultFilter(
            min: LoveGraphicsFilterMode.nearest,
            mag: LoveGraphicsFilterMode.linear,
            anisotropy: 2.0,
          ),
        );
        expect(firstSnapshot.mipmapFilter, LoveGraphicsFilterMode.nearest);
        expect(firstSnapshot.mipmapSharpness, 0.5);
        expect(
          firstSnapshot.wrap,
          const LoveGraphicsWrap(
            horizontal: LoveGraphicsWrapMode.repeat,
            vertical: LoveGraphicsWrapMode.mirroredRepeat,
            depth: LoveGraphicsWrapMode.clampZero,
          ),
        );
        expect(firstSnapshot.depthSampleMode, isNull);
        expect(
          firstSnapshot.surface.clearColor,
          const LoveColor(0.1, 0.2, 0.3, 0.4),
        );
        expect(firstSnapshot.surface.commands, hasLength(2));
        expect(
          firstSnapshot.surface.commands.first,
          isA<LoveRectangleCommand>(),
        );
        expect(firstSnapshot.surface.commands.last, isA<LoveCircleCommand>());

        expect(second.quad, isNotNull);
        expect(second.quad!.x, 8);
        expect(second.quad!.y, 4);
        expect(second.quad!.width, 24);
        expect(second.quad!.height, 12);
        expect(second.quad!.textureWidth, 64);
        expect(second.quad!.textureHeight, 32);
      },
    );

    test('texture sampling APIs enforce LOVE validation rules', () async {
      final runtime = createLuaLikeTestRuntime();

      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'assets/images/test_sheet.png': _encodeSizedTestPng(
              width: 32,
              height: 16,
            ),
          }),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime);
      expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

      final image = await luaCall(
        runtime,
        const ['love', 'graphics', 'newImage'],
        const <Object?>['assets/images/test_sheet.png'],
      );
      expect(await luaCallMethod(image!, 'getMipmapFilter'), <Object?>[
        null,
        0.0,
      ]);
      await expectLater(
        luaCallMethod(image, 'setMipmapFilter', const <Object?>['nearest']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('non-mipmapped texture'),
          ),
        ),
      );
      await expectLater(
        luaCallMethod(image, 'setDepthSampleMode', const <Object?>['lequal']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('readable depth textures'),
          ),
        ),
      );

      final canvas = await luaCall(
        runtime,
        const ['love', 'graphics', 'newCanvas'],
        <Object?>[
          32,
          16,
          Value(<Object?, Object?>{'mipmaps': 'manual'}),
        ],
      );
      expect(await luaCallMethod(canvas!, 'getMipmapFilter'), <Object?>[
        'linear',
        0.0,
      ]);
      await luaCallMethod(canvas, 'setMipmapFilter', const <Object?>[
        'nearest',
        0.25,
      ]);
      expect(await luaCallMethod(canvas, 'getMipmapFilter'), <Object?>[
        'nearest',
        0.25,
      ]);

      final depthCanvas = await luaCall(
        runtime,
        const ['love', 'graphics', 'newCanvas'],
        <Object?>[
          16,
          16,
          Value(<Object?, Object?>{'format': 'depth24', 'readable': true}),
        ],
      );
      expect(await luaCallMethod(depthCanvas!, 'getDepthSampleMode'), isNull);
      await luaCallMethod(depthCanvas, 'setDepthSampleMode', const <Object?>[
        'lequal',
      ]);
      expect(await luaCallMethod(depthCanvas, 'getDepthSampleMode'), 'lequal');
    });

    test(
      'image data APIs expose mutable buffers and canvas readback',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}

local data = love.image.newImageData(4, 3)
data:setPixel(1, 1, 0.25, 0.5, 0.75, 1.0)
testbed.blank_dimensions = string.format("%dx%d", data:getDimensions())
local r, g, b, a = data:getPixel(1, 1)
testbed.blank_pixel = string.format("%.2f/%.2f/%.2f/%.2f", r, g, b, a)

local canvas = love.graphics.newCanvas(8, 6, { readable = true })

function love.draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0.2, 0.3, 0.4, 0.5)
  love.graphics.setColor(1.0, 0.0, 0.0, 1.0)
  love.graphics.rectangle("fill", 2, 1, 3, 2)
  love.graphics.setColor(0.0, 1.0, 0.0, 1.0)
  love.graphics.rectangle("fill", 6, 4, 2, 2)
  love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  testbed.canvas_dimensions = string.format("%dx%d", snapshot:getDimensions())
  local sr, sg, sb, sa = snapshot:getPixel(0, 0)
  testbed.canvas_pixel = string.format("%.2f/%.2f/%.2f/%.2f", sr, sg, sb, sa)
  local dr, dg, db, da = snapshot:getPixel(3, 2)
  testbed.canvas_drawn_pixel = string.format("%.2f/%.2f/%.2f/%.2f", dr, dg, db, da)

  local region = canvas:newImageData(1, 2, 3, 4, 2)
  testbed.region_dimensions = string.format("%dx%d", region:getDimensions())

  local mip = canvas:newImageData(2)
  testbed.mipmap_dimensions = string.format("%dx%d", mip:getDimensions())
  local mr, mg, mb, ma = mip:getPixel(3, 2)
  testbed.mipmap_pixel = string.format("%.2f/%.2f/%.2f/%.2f", mr, mg, mb, ma)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['blank_dimensions'], '4x3');
        expect(snapshot['blank_pixel'], '0.25/0.50/0.75/1.00');
        expect(snapshot['canvas_dimensions'], '8x6');
        expect(snapshot['canvas_pixel'], '0.20/0.30/0.40/0.50');
        expect(snapshot['canvas_drawn_pixel'], '1.00/0.00/0.00/1.00');
        expect(snapshot['region_dimensions'], '4x2');
        expect(snapshot['mipmap_dimensions'], '4x3');
        expect(snapshot['mipmap_pixel'], '0.00/1.00/0.00/1.00');
      },
    );

    test(
      'love.image.newImageData decodes filename, FileData, and raw byte inputs',
      () async {
        final encodedPng = _encodeTestPng();
        final runtime = createLuaLikeTestRuntime();

        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/images/checker.png': encodedPng,
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final fromFilename = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[LuaString.fromDartString('assets/images/checker.png')],
        );
        expect(await luaCallMethod(fromFilename!, 'getDimensions'), <Object?>[
          2,
          2,
        ]);
        expect(
          await luaCallMethod(fromFilename, 'getPixel', const <Object?>[0, 0]),
          <Object?>[1.0, 0.0, 64 / 255, 1.0],
        );
        await luaCallMethod(fromFilename, 'setPixel', const <Object?>[
          0,
          0,
          0.0,
          0.0,
          0.0,
          1.0,
        ]);

        final fromFilenameAgain = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>['assets/images/checker.png'],
        );
        expect(
          await luaCallMethod(fromFilenameAgain!, 'getPixel', const <Object?>[
            0,
            0,
          ]),
          <Object?>[1.0, 0.0, 64 / 255, 1.0],
        );

        final fileData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[LuaString.fromBytes(encodedPng), 'checker.png'],
        );
        final fromFileData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[fileData],
        );
        expect(
          await luaCallMethod(fromFileData!, 'getPixel', const <Object?>[1, 0]),
          <Object?>[0.0, 0.0, 1.0, 1.0],
        );

        final rawPixelData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[
            Uint8List.fromList(<int>[255, 128, 64, 255]),
            'pixel.rgba',
          ],
        );
        final fromRawBytes = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[1, 1, 'rgba8', rawPixelData],
        );
        expect(
          await luaCallMethod(fromRawBytes!, 'getPixel', const <Object?>[0, 0]),
          <Object?>[1.0, 128 / 255, 64 / 255, 1.0],
        );
      },
    );

    test(
      'headless image APIs report LOVE filesystem missing-file errors for string sources',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute(r'''
local ok_image, err_image = pcall(function()
  return love.graphics.newImage("assets/images/missing.png")
end)
local ok_imagedata, err_imagedata = pcall(function()
  return love.image.newImageData("assets/images/missing.png")
end)

image_ok = ok_image
image_error = tostring(err_image)
imagedata_ok = ok_imagedata
imagedata_error = tostring(err_imagedata)
''');

        expect(runtime.unwrapGlobal('image_ok'), isFalse);
        expect(
          runtime.unwrapGlobal('image_error'),
          contains(
            'Could not open file assets/images/missing.png. Does not exist.',
          ),
        );
        expect(runtime.unwrapGlobal('imagedata_ok'), isFalse);
        expect(
          runtime.unwrapGlobal('imagedata_error'),
          contains(
            'Could not open file assets/images/missing.png. Does not exist.',
          ),
        );
      },
    );

    test('love.graphics.newImage accepts FileData inputs', () async {
      final encodedPng = _encodeTestPng();
      final runtime = createLuaLikeTestRuntime();

      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final fileData = await luaCall(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[Uint8List.fromList(encodedPng), 'checker.png'],
      );

      final image = await luaCall(
        runtime,
        const ['love', 'graphics', 'newImage'],
        <Object?>[fileData],
      );

      expect(await luaCallMethod(image!, 'getDimensions'), <Object?>[2, 2]);
      expect(await luaCallMethod(image, 'getFilter'), <Object?>[
        'linear',
        'linear',
        1.0,
      ]);
      expect(await luaCallMethod(image, 'isCompressed'), isFalse);
    });

    test(
      'love.image.isCompressed detects LOVE compressed image containers',
      () async {
        final runtime = createLuaLikeTestRuntime();

        installLove2d(runtime: runtime);

        final sourceDir = await Directory.systemTemp.createTemp(
          'love2d-image-compressed-',
        );
        addTearDown(() => sourceDir.delete(recursive: true));

        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(sourceDir.path), isTrue);

        await File(
          '${sourceDir.path}${Platform.pathSeparator}sample.ktx',
        ).writeAsBytes(_ktxCompressedBytes());
        await File(
          '${sourceDir.path}${Platform.pathSeparator}sample.png',
        ).writeAsBytes(_encodeTestPng());

        expect(
          await luaCall(
            runtime,
            const ['love', 'image', 'isCompressed'],
            [LuaString.fromDartString('sample.ktx')],
          ),
          isTrue,
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'image', 'isCompressed'],
            [LuaString.fromDartString('sample.png')],
          ),
          isFalse,
        );

        final compressedFixtures = <String, Uint8List>{
          'sample.dds': _ddsCompressedBytes(),
          'sample.ktx': _ktxCompressedBytes(),
          'sample.pkm': _pkmCompressedBytes(),
          'sample.astc': _astcCompressedBytes(),
          'sample.pvr': _pvrCompressedBytes(),
        };

        for (final entry in compressedFixtures.entries) {
          final fileData = await luaCall(
            runtime,
            const ['love', 'filesystem', 'newFileData'],
            <Object?>[entry.value, entry.key],
          );

          expect(
            await luaCall(
              runtime,
              const ['love', 'image', 'isCompressed'],
              [fileData],
            ),
            isTrue,
            reason: 'Expected ${entry.key} to be recognized as compressed',
          );
        }

        final pngFileData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_encodeTestPng(), 'sample.png'],
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'image', 'isCompressed'],
            [pngFileData],
          ),
          isFalse,
        );
      },
    );

    test(
      'love.graphics.newImage applies common LOVE settings for dpi, linear, and mipmaps',
      () async {
        final runtime = createLuaLikeTestRuntime();

        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final fileData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_encodeSizedTestPng(width: 8, height: 4), 'sprite@2x.png'],
        );
        final image = await luaCall(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[
            fileData,
            Value(<Object?, Object?>{'mipmaps': true, 'linear': true}),
          ],
        );

        expect(await luaCallMethod(image!, 'getWidth'), 4);
        expect(await luaCallMethod(image, 'getHeight'), 2);
        expect(await luaCallMethod(image, 'getPixelWidth'), 8);
        expect(await luaCallMethod(image, 'getPixelHeight'), 4);
        expect(await luaCallMethod(image, 'getDimensions'), <Object?>[4, 2]);
        expect(await luaCallMethod(image, 'getPixelDimensions'), <Object?>[
          8,
          4,
        ]);
        expect(await luaCallMethod(image, 'getDPIScale'), 2.0);
        expect(await luaCallMethod(image, 'getMipmapCount'), 4);
        expect(await luaCallMethod(image, 'isFormatLinear'), isTrue);

        await luaCallMethod(image, 'setMipmapFilter', const <Object?>[
          'linear',
          0.25,
        ]);
        expect(await luaCallMethod(image, 'getMipmapFilter'), <Object?>[
          'linear',
          0.25,
        ]);

        final patch = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[1, 1],
        );
        await luaCallMethod(patch!, 'setPixel', const <Object?>[
          0,
          0,
          1.0,
          0.5,
          0.25,
          1.0,
        ]);
        await luaCallMethod(image, 'replacePixels', <Object?>[
          patch,
          1,
          2,
          1,
          0,
          false,
        ]);
      },
    );

    test(
      'love.image.newCompressedData parses metadata and newImage accepts it',
      () async {
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost();

        installLove2d(runtime: runtime, host: host);

        final sourceDir = await Directory.systemTemp.createTemp(
          'love2d-new-compressed-data-',
        );
        addTearDown(() => sourceDir.delete(recursive: true));

        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(sourceDir.path), isTrue);

        final fixtures = <String, ({Uint8List bytes, String format})>{
          'sample.dds': (bytes: _ddsCompressedBytes(), format: 'DXT1'),
          'sample.ktx': (bytes: _ktxCompressedBytes(), format: 'DXT1'),
          'sample.pkm': (bytes: _pkmCompressedBytes(), format: 'ETC1'),
          'sample.astc': (bytes: _astcCompressedBytes(), format: 'ASTC4x4'),
          'sample.pvr': (bytes: _pvrCompressedBytes(), format: 'DXT1'),
        };

        for (final entry in fixtures.entries) {
          final fileData = await luaCall(
            runtime,
            const ['love', 'filesystem', 'newFileData'],
            <Object?>[entry.value.bytes, entry.key],
          );
          final compressed = await luaCall(
            runtime,
            const ['love', 'image', 'newCompressedData'],
            <Object?>[fileData],
          );

          expect(
            await luaCallMethod(compressed!, 'getFormat'),
            entry.value.format,
          );
          expect(await luaCallMethod(compressed, 'getWidth'), 16);
          expect(await luaCallMethod(compressed, 'getHeight'), 8);
          expect(await luaCallMethod(compressed, 'getDimensions'), <Object?>[
            16,
            8,
          ]);
          expect(
            await luaCallMethod(compressed, 'getMipmapCount'),
            entry.key == 'sample.pkm' || entry.key == 'sample.astc' ? 1 : 2,
          );
        }

        expect(
          await File(
            '${sourceDir.path}${Platform.pathSeparator}sample.ktx',
          ).writeAsBytes(_ktxCompressedBytes()),
          isA<File>(),
        );

        final compressedFromFilename = await luaCall(
          runtime,
          const ['love', 'image', 'newCompressedData'],
          <Object?>[LuaString.fromDartString('sample.ktx')],
        );
        expect(
          await luaCallMethod(compressedFromFilename!, 'getFormat'),
          'DXT1',
        );
        expect(
          await luaCallMethod(compressedFromFilename, 'getMipmapCount'),
          2,
        );
        expect(
          await luaCallMethod(compressedFromFilename, 'getWidth', <Object?>[2]),
          8,
        );
        expect(
          await luaCallMethod(
            compressedFromFilename,
            'getDimensions',
            <Object?>[2],
          ),
          <Object?>[8, 4],
        );

        final image = await luaCall(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[compressedFromFilename],
        );
        expect(await luaCallMethod(image!, 'isCompressed'), isTrue);
        expect(await luaCallMethod(image, 'getFormat'), 'DXT1');
        expect(await luaCallMethod(image, 'getMipmapCount'), 2);
        expect(await luaCallMethod(image, 'isReadable'), isFalse);
        expect(await luaCallMethod(image, 'isFormatLinear'), isTrue);

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCall(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[image, 24, 36],
        );
        expect(host.graphics.commands, hasLength(1));
        final draw = host.graphics.commands.single as LoveImageCommand;
        expect(draw.image.compressed, isTrue);
        expect(draw.image.width, 16);
        expect(draw.image.height, 8);
      },
    );

    test('bundled example script exercises compressed image support', () async {
      final runtime = LoveScriptRuntime(
        host: LoveHeadlessHost(
          imageLoader: (source, {bytes, settings, assetKey}) async {
            final resolvedBytes =
                bytes ??
                await File(
                  'example${Platform.pathSeparator}$source',
                ).readAsBytes();
            final imageData = LoveImageData.decodeEncodedBytes(
              bytes: resolvedBytes,
              source: source,
            );
            return LoveImage(
              source: source,
              width: imageData.width,
              height: imageData.height,
              imageData: imageData,
              preferImageDataRendering: true,
            );
          },
        ),
      );

      final filesystem = LoveFilesystemState.of(runtime.runtime);
      expect(filesystem.setSource('example'), isTrue);

      await runtime.execute(
        await File(
          'example${Platform.pathSeparator}assets${Platform.pathSeparator}scripts${Platform.pathSeparator}test_bed.lua',
        ).readAsString(),
        scriptPath: 'assets/scripts/test_bed.lua',
      );
      await runtime.callLoadIfDefined();
      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['status'], 'love.load complete');
      expect(
        '${snapshot['compressed_detection']}',
        contains('synthetic_ktx=true'),
      );
      expect('${snapshot['compressed_summary']}', contains('DXT1 16x8'));
      expect('${snapshot['compressed_summary']}', contains('compressed=true'));
      expect('${snapshot['compressed_summary']}', contains('linear=true'));
      expect('${snapshot['generated_sprite']}', contains('dpi=2.00'));
      expect('${snapshot['generated_sprite']}', contains('mips=4'));
      expect('${snapshot['generated_sprite']}', contains('linear=true'));
      expect('${snapshot['spritebatch_summary']}', contains('count=3'));
      expect('${snapshot['spritebatch_summary']}', contains('buffer=4'));
      expect('${snapshot['particle_summary']}', contains('count='));
      expect('${snapshot['particle_summary']}', contains('mode=bottom'));
      expect('${snapshot['mapped_pixel']}', isNotEmpty);
      expect('${snapshot['encoded_image']}', contains('Image.png png bytes='));
      expect('${snapshot['encoded_image']}', contains('data=true'));
      expect('${snapshot['encoded_roundtrip']}', isNotEmpty);
      expect(runtime.context.graphics.commands, isNotEmpty);
    });

    test('data-backed images render and support replacePixels', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
testbed = {}

local base = love.image.newImageData(4, 4)
local patch = love.image.newImageData(2, 2)
patch:setPixel(0, 0, 1.0, 0.0, 0.0, 1.0)
patch:setPixel(1, 0, 0.0, 1.0, 0.0, 1.0)
patch:setPixel(0, 1, 0.0, 0.0, 1.0, 1.0)
patch:setPixel(1, 1, 1.0, 1.0, 0.0, 1.0)
base:paste(patch, 1, 1)

local image = love.graphics.newImage(base)
local replace = love.image.newImageData(1, 2, base:getFormat())
replace:setPixel(0, 0, 1.0, 0.5, 0.0, 1.0)
replace:setPixel(0, 1, 0.5, 0.0, 1.0, 1.0)
image:replacePixels(replace, 1, 1, 3, 1)

testbed.base_format = base:getFormat()
local a1, a2, a3, a4 = base:getPixel(1, 1)
testbed.base_center = string.format("%.2f/%.2f/%.2f/%.2f", a1, a2, a3, a4)
local b1, b2, b3, b4 = base:getPixel(3, 1)
testbed.base_edge = string.format("%.2f/%.2f/%.2f/%.2f", b1, b2, b3, b4)

function love.draw()
  love.graphics.draw(image, 12, 18)
end
''');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['base_format'], 'rgba8');
      expect(snapshot['base_center'], '1.00/0.00/0.00/1.00');
      expect(snapshot['base_edge'], '1.00/0.50/0.00/1.00');

      expect(runtime.context.graphics.commands, hasLength(1));
      final draw = runtime.context.graphics.commands.single as LoveImageCommand;
      expect(draw.image.imageData, isNotNull);
      expect(draw.image.width, 4);
      expect(draw.image.height, 4);
      expect(
        draw.image.imageData!.getPixel(3, 1),
        const LoveColor(1.0, 0.5, 0.0, 1.0),
      );
    });

    test('ImageData mapPixel and encode round-trip through FileData', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());
      final filesystem = LoveFilesystemState.of(runtime.runtime);
      final identity =
          'love2d-image-encode-${DateTime.now().microsecondsSinceEpoch}';
      expect(filesystem.setIdentity(identity), isTrue);
      final saveDirectory = filesystem.getSaveDirectory();
      addTearDown(() async {
        final directory = Directory(saveDirectory);
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      await runtime.execute('''
testbed = {}

local image = love.image.newImageData(2, 2)
image:setPixel(0, 0, 0.10, 0.20, 0.30, 0.40)
image:setPixel(1, 0, 0.40, 0.50, 0.60, 0.70)
image:setPixel(0, 1, 0.80, 0.10, 0.20, 0.30)
image:setPixel(1, 1, 0.90, 0.20, 0.30, 0.40)

image:mapPixel(function(x, y, r, g, b, a)
  if x == 1 and y == 0 then
    return g, b, r
  end

  return 1.0 - r, g + 0.25, b, a
end, 0, 0, 2, 1)

local filedata = image:encode("png", "mapped.png")
local decoded = love.image.newImageData(filedata)

local r1, g1, b1, a1 = image:getPixel(0, 0)
local r2, g2, b2, a2 = image:getPixel(1, 0)
local d1, d2, d3, d4 = decoded:getPixel(1, 0)

testbed.map_left = string.format("%.2f/%.2f/%.2f/%.2f", r1, g1, b1, a1)
testbed.map_right = string.format("%.2f/%.2f/%.2f/%.2f", r2, g2, b2, a2)
testbed.decoded_right = string.format("%.2f/%.2f/%.2f/%.2f", d1, d2, d3, d4)
testbed.encoded_name = filedata:getFilename()
testbed.encoded_ext = filedata:getExtension()
testbed.encoded_size = filedata:getSize()
testbed.encoded_is_data = filedata:typeOf("Data")
''');

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['map_left'], '0.90/0.45/0.30/0.40');
      expect(snapshot['map_right'], '0.50/0.60/0.40/1.00');
      expect(snapshot['decoded_right'], '0.50/0.60/0.40/1.00');
      expect(snapshot['encoded_name'], 'mapped.png');
      expect(snapshot['encoded_ext'], 'png');
      expect(snapshot['encoded_size'], greaterThan(0));
      expect(snapshot['encoded_is_data'], isTrue);

      final encodedFile = await filesystem.readFileData(
        'mapped.png',
        filename: 'mapped.png',
      );
      expect(encodedFile, isNotNull);
      expect(encodedFile!.bytes, isNotEmpty);
    });

    test(
      'ImageData:encode reports LOVE filesystem write errors when a filename is provided',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute(r'''
testbed = {}

local image = love.image.newImageData(1, 1)
local ok, err = pcall(function()
  return image:encode("png", "mapped.png")
end)

testbed.ok = ok
testbed.err = tostring(err)
''');

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['ok'], isFalse);
        expect(snapshot['err'], contains('Could not set write directory.'));
        expect(
          snapshot['err'],
          isNot(contains('ImageData:encode could not write')),
        );
      },
    );

    test(
      'Transform objects support LOVE matrix semantics and graphics application',
      () async {
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost();

        installLove2d(runtime: runtime, host: host);

        final transform = await luaCall(
          runtime,
          const ['love', 'math', 'newTransform'],
          const <Object?>[10, 20, 0.25, 2, 3, 4, 5, 0.1, -0.2],
        );

        final matrix = await luaCallMethod(transform!, 'getMatrix');
        expect(
          matrix,
          _matrixRowMajor(
            x: 10,
            y: 20,
            angle: 0.25,
            scaleX: 2,
            scaleY: 3,
            originX: 4,
            originY: 5,
            shearX: 0.1,
            shearY: -0.2,
          ),
        );

        expect(
          await luaCallMethod(transform, 'transformPoint', const <Object?>[
            4,
            5,
          ]),
          <Object?>[10.0, 20.0],
        );
        expect(
          await luaCallMethod(
            transform,
            'inverseTransformPoint',
            const <Object?>[10, 20],
          ),
          <Object?>[4.0, 5.0],
        );
        expect(await luaCallMethod(transform, 'isAffine2DTransform'), isTrue);

        final clone = await luaCallMethod(transform, 'clone');
        await luaCallMethod(clone!, 'reset');
        await luaCallMethod(clone, 'translate', const <Object?>[7, 8]);
        expect(
          await luaCallMethod(clone, 'transformPoint', const <Object?>[4, 5]),
          <Object?>[11.0, 13.0],
        );
        expect(
          await luaCallMethod(transform, 'transformPoint', const <Object?>[
            4,
            5,
          ]),
          <Object?>[10.0, 20.0],
        );

        final inverse = await luaCallMethod(transform, 'inverse');
        expect(
          await luaCallMethod(inverse!, 'transformPoint', const <Object?>[
            10,
            20,
          ]),
          <Object?>[4.0, 5.0],
        );

        await luaCallMethod(transform, 'setMatrix', const <Object?>[
          1,
          0,
          0,
          30,
          0,
          1,
          0,
          40,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          1,
        ]);
        expect(
          await luaCallMethod(transform, 'transformPoint', const <Object?>[
            5,
            6,
          ]),
          <Object?>[35.0, 46.0],
        );

        await luaCallMethod(transform, 'setMatrix', <Object?>[
          'column',
          Value(<Object?, Object?>{
            1: 1,
            2: 0,
            3: 0,
            4: 0,
            5: 0,
            6: 1,
            7: 0,
            8: 0,
            9: 0,
            10: 0,
            11: 1,
            12: 0,
            13: 12,
            14: 18,
            15: 0,
            16: 1,
          }),
        ]);
        expect(
          await luaCallMethod(transform, 'transformPoint', const <Object?>[
            5,
            6,
          ]),
          <Object?>[17.0, 24.0],
        );

        await luaCallMethod(transform, 'setMatrix', <Object?>[
          Value(<Object?, Object?>{
            1: Value(<Object?, Object?>{1: 1, 2: 0, 3: 0, 4: 3}),
            2: Value(<Object?, Object?>{1: 0, 2: 1, 3: 0, 4: 4}),
            3: Value(<Object?, Object?>{1: 0, 2: 0, 3: 1, 4: 0}),
            4: Value(<Object?, Object?>{1: 0, 2: 0, 3: 0, 4: 1}),
          }),
        ]);
        expect(
          await luaCallMethod(transform, 'transformPoint', const <Object?>[
            5,
            6,
          ]),
          <Object?>[8.0, 10.0],
        );

        await luaCallMethod(transform, 'setMatrix', const <Object?>[
          1,
          0,
          1,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          1,
        ]);
        expect(await luaCallMethod(transform, 'isAffine2DTransform'), isFalse);

        await luaCallMethod(transform, 'reset');
        await luaCallMethod(transform, 'setTransformation', const <Object?>[
          15,
          25,
          0.0,
          2,
          2,
          1,
          1,
        ]);
        expect(
          await luaCallMethod(transform, 'transformPoint', const <Object?>[
            1,
            1,
          ]),
          <Object?>[15.0, 25.0],
        );

        await luaCall(
          runtime,
          const ['love', 'graphics', 'replaceTransform'],
          <Object?>[transform],
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 1],
          ),
          <Object?>[15.0, 25.0],
        );

        final offset = await luaCall(
          runtime,
          const ['love', 'math', 'newTransform'],
          const <Object?>[3, 4],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'applyTransform'],
          <Object?>[offset],
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 1],
          ),
          <Object?>[21.0, 33.0],
        );

        await luaCall(
          runtime,
          const ['love', 'graphics', 'push'],
          <Object?>['all', offset],
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 1],
          ),
          <Object?>[27.0, 41.0],
        );
        await luaCall(runtime, const ['love', 'graphics', 'pop']);
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 1],
          ),
          <Object?>[21.0, 33.0],
        );
      },
    );

    test(
      'graphics draw and text APIs accept Transform object overloads',
      () async {
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost();

        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/images/test_sheet.png': _encodeSizedTestPng(
                width: 32,
                height: 16,
              ),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final sprite = await luaCall(
          runtime,
          const ['love', 'graphics', 'newImage'],
          const <Object?>['assets/images/test_sheet.png'],
        );
        final quad = await luaCall(
          runtime,
          const ['love', 'graphics', 'newQuad'],
          <Object?>[8, 0, 8, 8, sprite],
        );
        final drawTransform = await luaCall(
          runtime,
          const ['love', 'math', 'newTransform'],
          const <Object?>[30, 40, 0.25, 2, 3, 4, 5, 0.1, -0.2],
        );
        final quadTransform = await luaCall(
          runtime,
          const ['love', 'math', 'newTransform'],
          const <Object?>[70, 80, -0.5, 1.5, 1.25, 2, 3, -0.15, 0.05],
        );
        final printTransform = await luaCall(
          runtime,
          const ['love', 'math', 'newTransform'],
          const <Object?>[110, 120, 0.1, 1, 1, 6, 7],
        );
        final printfTransform = await luaCall(
          runtime,
          const ['love', 'math', 'newTransform'],
          const <Object?>[150, 160, -0.2, 1.1, 0.9, 3, 4, 0.12, -0.06],
        );

        host.graphics.beginFrame();
        await luaCall(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[sprite, drawTransform],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[sprite, quad, quadTransform],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'print'],
          <Object?>['hello', printTransform],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'printf'],
          <Object?>['world', printfTransform, 96, 'center'],
        );

        expect(host.graphics.commands, hasLength(4));

        final first = host.graphics.commands[0] as LoveImageCommand;
        expect(_transformPoint(first.drawTransform, 4, 5).x, closeTo(30, 1e-9));
        expect(_transformPoint(first.drawTransform, 4, 5).y, closeTo(40, 1e-9));

        final second = host.graphics.commands[1] as LoveImageCommand;
        expect(second.quad, isNotNull);
        expect(
          _transformPoint(second.drawTransform, 2, 3).x,
          closeTo(70, 1e-9),
        );
        expect(
          _transformPoint(second.drawTransform, 2, 3).y,
          closeTo(80, 1e-9),
        );

        final print = host.graphics.commands[2] as LoveTextCommand;
        expect(print.x, 0);
        expect(print.y, 0);
        expect(
          _transformPoint(print.textTransform, 6, 7).x,
          closeTo(110, 1e-9),
        );
        expect(
          _transformPoint(print.textTransform, 6, 7).y,
          closeTo(120, 1e-9),
        );

        final printf = host.graphics.commands[3] as LoveTextCommand;
        expect(printf.limit, 96);
        expect(printf.align, 'center');
        expect(
          _transformPoint(printf.textTransform, 3, 4).x,
          closeTo(150, 1e-9),
        );
        expect(
          _transformPoint(printf.textTransform, 3, 4).y,
          closeTo(160, 1e-9),
        );
      },
    );

    test(
      'graphics scissor APIs track state, stack behavior, and command snapshots',
      () async {
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost();

        installLove2d(runtime: runtime, host: host);

        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getScissor']),
          isNull,
        );

        await luaCall(
          runtime,
          const ['love', 'graphics', 'setScissor'],
          const <Object?>[10, 20, 30, 40],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getScissor']),
          <Object?>[10.0, 20.0, 30.0, 40.0],
        );

        await luaCall(runtime, const ['love', 'graphics', 'push']);
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setScissor'],
          const <Object?>[1, 2, 3, 4],
        );
        await luaCall(runtime, const ['love', 'graphics', 'pop']);
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getScissor']),
          <Object?>[1.0, 2.0, 3.0, 4.0],
        );

        await luaCall(
          runtime,
          const ['love', 'graphics', 'push'],
          const <Object?>['all'],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'intersectScissor'],
          const <Object?>[2, 3, 5, 6],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getScissor']),
          <Object?>[2.0, 3.0, 2.0, 3.0],
        );
        await luaCall(runtime, const ['love', 'graphics', 'pop']);
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getScissor']),
          <Object?>[1.0, 2.0, 3.0, 4.0],
        );

        host.graphics.beginFrame();
        await luaCall(
          runtime,
          const ['love', 'graphics', 'rectangle'],
          const <Object?>['fill', 5, 6, 7, 8],
        );
        final rectangle = host.graphics.commands.single as LoveRectangleCommand;
        expect(
          rectangle.scissor,
          const LoveScissorRect(x: 1, y: 2, width: 3, height: 4),
        );

        await luaCall(
          runtime,
          const ['love', 'graphics', 'clear'],
          const <Object?>[0.2, 0.3, 0.4, 1.0],
        );
        expect(host.graphics.clearColor, const LoveColor(0.2, 0.3, 0.4, 1.0));
        expect(
          host.graphics.clearScissor,
          const LoveScissorRect(x: 1, y: 2, width: 3, height: 4),
        );

        await luaCall(runtime, const ['love', 'graphics', 'setScissor']);
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getScissor']),
          isNull,
        );

        await luaCall(
          runtime,
          const ['love', 'graphics', 'intersectScissor'],
          const <Object?>[12, 14, 16, 18],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getScissor']),
          <Object?>[12.0, 14.0, 16.0, 18.0],
        );
      },
    );

    test('graphics APIs record color state and draw commands', () async {
      final runtime = createLuaLikeTestRuntime();
      final host = LoveHeadlessHost();

      installLove2d(runtime: runtime, host: host);
      LoveRuntimeContext.of(runtime).beginDrawFrame();

      await luaCall(
        runtime,
        const ['love', 'graphics', 'setColor'],
        const <Object?>[0.25, 0.5, 0.75, 0.5],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'setBackgroundColor'],
        const <Object?>[0.1, 0.2, 0.3, 1.0],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'setLineWidth'],
        const <Object?>[2.5],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'setLineStyle'],
        const <Object?>['rough'],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'setLineJoin'],
        const <Object?>['bevel'],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'setPointSize'],
        const <Object?>[3.5],
      );

      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getColor']),
        <Object?>[0.25, 0.5, 0.75, 0.5],
      );
      expect(
        await luaCall(runtime, const [
          'love',
          'graphics',
          'getBackgroundColor',
        ]),
        <Object?>[0.1, 0.2, 0.3, 1.0],
      );
      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getLineWidth']),
        2.5,
      );
      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getLineStyle']),
        'rough',
      );
      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getLineJoin']),
        'bevel',
      );
      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getPointSize']),
        3.5,
      );

      await luaCall(
        runtime,
        const ['love', 'graphics', 'rectangle'],
        const <Object?>['line', 10, 20, 30, 40, 4, 5],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'print'],
        const <Object?>['hello', 50, 60, 0.5, 1.5, 0.75, 4, 5, 0.2, -0.1],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'printf'],
        const <Object?>[
          'world',
          80,
          90,
          120,
          'center',
          -0.25,
          1.25,
          1.5,
          6,
          7,
          -0.2,
          0.4,
        ],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'line'],
        const <Object?>[0, 0, 4, 5, 8, 9],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'ellipse'],
        const <Object?>['fill', 25, 35, 12, 6],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'arc'],
        const <Object?>['line', 'open', 40, 50, 20, 0, 1.5],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'polygon'],
        const <Object?>['line', 0, 0, 10, 0, 8, 6],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'points'],
        const <Object?>[2, 3, 6, 7],
      );

      expect(host.graphics.commands, hasLength(8));

      final rectangle = host.graphics.commands[0] as LoveRectangleCommand;
      expect(rectangle.mode, LoveGraphicsDrawMode.line);
      expect(rectangle.x, 10);
      expect(rectangle.y, 20);
      expect(rectangle.width, 30);
      expect(rectangle.height, 40);
      expect(rectangle.cornerRadiusX, 4);
      expect(rectangle.cornerRadiusY, 5);
      expect(rectangle.color, const LoveColor(0.25, 0.5, 0.75, 0.5));
      expect(rectangle.lineWidth, 2.5);
      expect(rectangle.lineStyle, LoveGraphicsLineStyle.rough);
      expect(rectangle.lineJoin, LoveGraphicsLineJoin.bevel);

      final print = host.graphics.commands[1] as LoveTextCommand;
      expect(print.text, 'hello');
      expect(print.x, 50);
      expect(print.y, 60);
      expect(print.limit, isNull);
      expect(print.lineWidth, 2.5);
      final printOrigin = _transformPoint(print.textTransform, 4, 5);
      expect(printOrigin.x, closeTo(50, 1e-9));
      expect(printOrigin.y, closeTo(60, 1e-9));

      final printf = host.graphics.commands[2] as LoveTextCommand;
      expect(printf.text, 'world');
      expect(printf.x, 80);
      expect(printf.y, 90);
      expect(printf.limit, 120);
      expect(printf.align, 'center');
      final printfOrigin = _transformPoint(printf.textTransform, 6, 7);
      expect(printfOrigin.x, closeTo(80, 1e-9));
      expect(printfOrigin.y, closeTo(90, 1e-9));

      final line = host.graphics.commands[3] as LoveLineCommand;
      expect(line.lineWidth, 2.5);
      expect(line.lineStyle, LoveGraphicsLineStyle.rough);
      expect(line.lineJoin, LoveGraphicsLineJoin.bevel);
      expect(line.points, hasLength(3));
      expect(line.points[1], (x: 4.0, y: 5.0));

      final ellipse = host.graphics.commands[4] as LoveEllipseCommand;
      expect(ellipse.mode, LoveGraphicsDrawMode.fill);
      expect(ellipse.x, 25);
      expect(ellipse.y, 35);
      expect(ellipse.radiusX, 12);
      expect(ellipse.radiusY, 6);

      final arc = host.graphics.commands[5] as LoveArcCommand;
      expect(arc.drawMode, LoveGraphicsDrawMode.line);
      expect(arc.arcMode, LoveGraphicsArcMode.open);
      expect(arc.radius, 20);
      expect(arc.angle2, 1.5);

      final polygon = host.graphics.commands[6] as LovePolygonCommand;
      expect(polygon.mode, LoveGraphicsDrawMode.line);
      expect(polygon.points, hasLength(3));
      expect(polygon.points.last, (x: 8.0, y: 6.0));

      final points = host.graphics.commands[7] as LovePointsCommand;
      expect(points.pointSize, 3.5);
      expect(points.points, hasLength(2));
      expect(points.points.first, (x: 2.0, y: 3.0, color: null));

      await luaCall(
        runtime,
        const ['love', 'graphics', 'clear'],
        const <Object?>[0.9, 0.1, 0.2, 1.0],
      );
      expect(host.graphics.commands, isEmpty);
      expect(host.graphics.clearColor, const LoveColor(0.9, 0.1, 0.2, 1.0));
    });

    test(
      'graphics advanced state APIs snapshot blend mode, color mask, wireframe, and reset',
      () async {
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost();

        installLove2d(runtime: runtime, host: host);
        LoveRuntimeContext.of(runtime).beginDrawFrame();

        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getBlendMode']),
          <Object?>['alpha', 'alphamultiply'],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getColorMask']),
          <Object?>[true, true, true, true],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'isWireframe']),
          isFalse,
        );

        await luaCall(
          runtime,
          const ['love', 'graphics', 'setColor'],
          const <Object?>[0.3, 0.4, 0.5, 0.6],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setBackgroundColor'],
          const <Object?>[0.05, 0.06, 0.07, 0.8],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setLineWidth'],
          const <Object?>[5],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setPointSize'],
          const <Object?>[6],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setLineStyle'],
          const <Object?>['rough'],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setLineJoin'],
          const <Object?>['bevel'],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setScissor'],
          const <Object?>[9, 10, 11, 12],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'translate'],
          const <Object?>[13, 14],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setBlendMode'],
          const <Object?>['screen', 'premultiplied'],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setColorMask'],
          const <Object?>[false, true, false, true],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setWireframe'],
          const <Object?>[true],
        );

        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getBlendMode']),
          <Object?>['screen', 'premultiplied'],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getColorMask']),
          <Object?>[false, true, false, true],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'isWireframe']),
          isTrue,
        );

        await luaCall(
          runtime,
          const ['love', 'graphics', 'rectangle'],
          const <Object?>['fill', 1, 2, 3, 4],
        );

        final rectangle = host.graphics.commands.single as LoveRectangleCommand;
        expect(rectangle.blendMode, LoveGraphicsBlendMode.screen);
        expect(
          rectangle.blendAlphaMode,
          LoveGraphicsBlendAlphaMode.premultiplied,
        );
        expect(
          rectangle.colorMask,
          const LoveGraphicsColorMask(
            red: false,
            green: true,
            blue: false,
            alpha: true,
          ),
        );
        expect(rectangle.wireframe, isTrue);

        await luaCall(
          runtime,
          const ['love', 'graphics', 'clear'],
          const <Object?>[0.7, 0.2, 0.1, 0.9],
        );
        expect(host.graphics.clearColor, const LoveColor(0.7, 0.2, 0.1, 0.9));
        expect(
          host.graphics.clearColorMask,
          const LoveGraphicsColorMask(
            red: false,
            green: true,
            blue: false,
            alpha: true,
          ),
        );

        await luaCall(runtime, const ['love', 'graphics', 'reset']);
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getColor']),
          <Object?>[1.0, 1.0, 1.0, 1.0],
        );
        expect(
          await luaCall(runtime, const [
            'love',
            'graphics',
            'getBackgroundColor',
          ]),
          <Object?>[0.0, 0.0, 0.0, 1.0],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getLineWidth']),
          1.0,
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getPointSize']),
          1.0,
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getLineStyle']),
          'smooth',
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getLineJoin']),
          'miter',
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getBlendMode']),
          <Object?>['alpha', 'alphamultiply'],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getColorMask']),
          <Object?>[true, true, true, true],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'isWireframe']),
          isFalse,
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getScissor']),
          isNull,
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 2],
          ),
          <Object?>[1.0, 2.0],
        );
      },
    );

    test(
      'graphics depth, stencil, and mesh culling state round-trip and affect canvas rasterization',
      () async {
        final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

        await runtime.execute('''
testbed = {}

local canvas = love.graphics.newCanvas(4, 4, { readable = true })
local mesh = love.graphics.newMesh({
  {0, 0, 0, 0, 1, 1, 1, 1},
  {3, 0, 0, 0, 1, 1, 1, 1},
  {0, 3, 0, 0, 1, 1, 1, 1},
}, "triangles", "static")

function love.draw()
  love.graphics.setDepthMode("less", true)
  love.graphics.setStencilTest("greater", 5)
  love.graphics.setFrontFaceWinding("cw")
  love.graphics.setMeshCullMode("back")

  local depth_mode, depth_write = love.graphics.getDepthMode()
  testbed.depth_state = string.format("%s/%s", depth_mode, tostring(depth_write))
  local stencil_mode, stencil_value = love.graphics.getStencilTest()
  testbed.stencil_state = string.format("%s/%d", stencil_mode, stencil_value)
  testbed.front_face = love.graphics.getFrontFaceWinding()
  testbed.cull_mode = love.graphics.getMeshCullMode()

  love.graphics.push("all")
  love.graphics.setFrontFaceWinding("ccw")
  love.graphics.setMeshCullMode("none")
  testbed.front_face_inside_push = love.graphics.getFrontFaceWinding()
  testbed.cull_inside_push = love.graphics.getMeshCullMode()
  love.graphics.pop()

  testbed.front_face_after_pop = love.graphics.getFrontFaceWinding()
  testbed.cull_after_pop = love.graphics.getMeshCullMode()

  love.graphics.draw(mesh)

  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.draw(mesh)
  love.graphics.setCanvas()

  local snapshot = canvas:newImageData()
  local r, g, b, a = snapshot:getPixel(1, 1)
  testbed.canvas_pixel = string.format("%.1f/%.1f/%.1f/%.1f", r, g, b, a)

  love.graphics.reset()
  local reset_depth_mode, reset_depth_write = love.graphics.getDepthMode()
  testbed.depth_after_reset = string.format("%s/%s", reset_depth_mode, tostring(reset_depth_write))
  local reset_stencil_mode, reset_stencil_value = love.graphics.getStencilTest()
  testbed.stencil_after_reset = string.format("%s/%d", reset_stencil_mode, reset_stencil_value)
  testbed.front_face_after_reset = love.graphics.getFrontFaceWinding()
  testbed.cull_after_reset = love.graphics.getMeshCullMode()
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['depth_state'], 'less/true');
        expect(snapshot['stencil_state'], 'greater/5');
        expect(snapshot['front_face'], 'cw');
        expect(snapshot['cull_mode'], 'back');
        expect(snapshot['front_face_inside_push'], 'ccw');
        expect(snapshot['cull_inside_push'], 'none');
        expect(snapshot['front_face_after_pop'], 'cw');
        expect(snapshot['cull_after_pop'], 'back');
        expect(snapshot['canvas_pixel'], '0.0/0.0/0.0/0.0');
        expect(snapshot['depth_after_reset'], 'always/false');
        expect(snapshot['stencil_after_reset'], 'always/0');
        expect(snapshot['front_face_after_reset'], 'ccw');
        expect(snapshot['cull_after_reset'], 'none');

        expect(runtime.context.graphics.commands, hasLength(1));
        final command =
            runtime.context.graphics.commands.single as LoveMeshCommand;
        expect(command.frontFaceWinding, LoveGraphicsVertexWinding.cw);
        expect(command.cullMode, LoveGraphicsCullMode.back);
      },
    );

    test(
      'graphics misc APIs expose shims and explicit unsupported errors',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        expect(
          await luaCall(runtime, const ['love', 'graphics', 'present']),
          isNull,
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'flushBatch']),
          isNull,
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'discard'],
            const <Object?>[true, true],
          ),
          isNull,
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'isActive']),
          isTrue,
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'isGammaCorrect']),
          isFalse,
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getTextureTypes']),
          <Object?, Object?>{
            '2d': true,
            'array': true,
            'cube': false,
            'volume': false,
          },
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'validateShader'],
            <Object?>[
              false,
              '''
extern number innerRadius;
extern number outerRadius;
extern vec2 center;
extern vec4 colorInner;
extern vec4 colorOuter;
vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  number dist = distance(screen_coords, center);
  number t = smoothstep(innerRadius, outerRadius, dist);
  return mix(colorInner, colorOuter, t) * Texel(texture, texture_coords);
}
''',
            ],
          ),
          isTrue,
        );

        expect(
          () => luaRawFunction(runtime, const [
            'love',
            'graphics',
            'captureScreenshot',
          ]).call(const <Object?>[]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('function, string, or Channel'),
            ),
          ),
        );
        expect(
          () => luaRawFunction(runtime, const [
            'love',
            'graphics',
            'drawInstanced',
          ]).call(const <Object?>[]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('expected a Mesh'),
            ),
          ),
        );
        expect(
          () => luaRawFunction(runtime, const [
            'love',
            'graphics',
            'stencil',
          ]).call(const <Object?>[]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('expected a callable at argument 1'),
            ),
          ),
        );
      },
    );

    test(
      'graphics transform stack follows LOVE push and pop semantics',
      () async {
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost();

        installLove2d(runtime: runtime, host: host);

        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getStackDepth']),
          0,
        );

        await luaCall(
          runtime,
          const ['love', 'graphics', 'translate'],
          const <Object?>[10, 20],
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 2],
          ),
          <Object?>[11.0, 22.0],
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'inverseTransformPoint'],
            const <Object?>[11, 22],
          ),
          <Object?>[1.0, 2.0],
        );

        await luaCall(runtime, const ['love', 'graphics', 'push']);
        await luaCall(
          runtime,
          const ['love', 'graphics', 'scale'],
          const <Object?>[2, 3],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setColor'],
          const <Object?>[0.2, 0.3, 0.4, 1.0],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setLineWidth'],
          const <Object?>[4],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setLineStyle'],
          const <Object?>['smooth'],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setLineJoin'],
          const <Object?>['miter'],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getStackDepth']),
          1,
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 2],
          ),
          <Object?>[12.0, 26.0],
        );

        await luaCall(runtime, const ['love', 'graphics', 'pop']);
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getStackDepth']),
          0,
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 2],
          ),
          <Object?>[11.0, 22.0],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getColor']),
          <Object?>[0.2, 0.3, 0.4, 1.0],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getLineWidth']),
          4.0,
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getLineStyle']),
          'smooth',
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getLineJoin']),
          'miter',
        );

        await luaCall(
          runtime,
          const ['love', 'graphics', 'push'],
          const <Object?>['all'],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'translate'],
          const <Object?>[5, 6],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setColor'],
          const <Object?>[0.9, 0.1, 0.2, 1.0],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setLineWidth'],
          const <Object?>[7],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setLineStyle'],
          const <Object?>['rough'],
        );
        await luaCall(
          runtime,
          const ['love', 'graphics', 'setLineJoin'],
          const <Object?>['bevel'],
        );
        await luaCall(runtime, const ['love', 'graphics', 'pop']);
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 2],
          ),
          <Object?>[11.0, 22.0],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getColor']),
          <Object?>[0.2, 0.3, 0.4, 1.0],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getLineWidth']),
          4.0,
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getLineStyle']),
          'smooth',
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getLineJoin']),
          'miter',
        );

        host.graphics.beginFrame();
        await luaCall(
          runtime,
          const ['love', 'graphics', 'circle'],
          const <Object?>['line', 4, 5, 6],
        );
        expect(host.graphics.commands.single, isA<LoveCircleCommand>());

        host.graphics.beginFrame();
        await luaCall(
          runtime,
          const ['love', 'graphics', 'line'],
          <Object?>[
            Value(<Object?, Object?>{1: 1, 2: 2, 3: 3, 4: 4}),
          ],
        );
        final tableLine = host.graphics.commands.single as LoveLineCommand;
        expect(tableLine.points, [(x: 1.0, y: 2.0), (x: 3.0, y: 4.0)]);

        host.graphics.beginFrame();
        await luaCall(
          runtime,
          const ['love', 'graphics', 'polygon'],
          <Object?>[
            'fill',
            Value(<Object?, Object?>{1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6}),
          ],
        );
        final tablePolygon =
            host.graphics.commands.single as LovePolygonCommand;
        expect(tablePolygon.mode, LoveGraphicsDrawMode.fill);
        expect(tablePolygon.points, [
          (x: 1.0, y: 2.0),
          (x: 3.0, y: 4.0),
          (x: 5.0, y: 6.0),
        ]);

        host.graphics.beginFrame();
        await luaCall(
          runtime,
          const ['love', 'graphics', 'points'],
          <Object?>[
            Value(<Object?, Object?>{1: 1, 2: 2, 3: 3, 4: 4}),
          ],
        );
        final tablePoints = host.graphics.commands.single as LovePointsCommand;
        expect(tablePoints.points, [
          (x: 1.0, y: 2.0, color: null),
          (x: 3.0, y: 4.0, color: null),
        ]);

        host.graphics.beginFrame();
        await luaCall(
          runtime,
          const ['love', 'graphics', 'points'],
          <Object?>[
            Value(<Object?, Object?>{
              1: Value(<Object?, Object?>{
                1: 8,
                2: 9,
                3: 1.0,
                4: 0.5,
                5: 0.25,
                6: 1.0,
              }),
              2: Value(<Object?, Object?>{1: 10, 2: 11}),
            }),
          ],
        );
        final coloredPoints =
            host.graphics.commands.single as LovePointsCommand;
        expect(coloredPoints.points, hasLength(2));
        expect(coloredPoints.points.first.x, 8.0);
        expect(
          coloredPoints.points.first.color,
          const LoveColor(0.2, 0.15, 0.1, 1.0),
        );
        expect(
          coloredPoints.points.last.color,
          const LoveColor(0.2, 0.3, 0.4, 1.0),
        );

        host.graphics.beginFrame();
        await luaCall(
          runtime,
          const ['love', 'graphics', 'print'],
          const <Object?>['stacked', 30, 40],
        );
        final stackedText = host.graphics.commands.single as LoveTextCommand;
        final graphicsOrigin = _transformPoint(stackedText.transform, 0, 0);
        expect(graphicsOrigin.x, closeTo(10, 1e-9));
        expect(graphicsOrigin.y, closeTo(20, 1e-9));
        final worldTextOrigin = _transformPoint(
          _combineTextTransform(stackedText),
          0,
          0,
        );
        expect(worldTextOrigin.x, closeTo(40, 1e-9));
        expect(worldTextOrigin.y, closeTo(60, 1e-9));
      },
    );
  });

  testWithFlameGame(
    'LoveFlameHost reports Flame canvas size through LOVE APIs',
    (game) async {
      game.onGameResize(Vector2(512, 288));

      final runtime = createLuaLikeTestRuntime();
      installLove2d(
        runtime: runtime,
        host: LoveFlameHost(game: game),
      );

      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getWidth']),
        512,
      );
      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getHeight']),
        288,
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'getMode']),
        <Object?>[512, 288, containsPair('vsync', 1)],
      );
    },
  );
}

Uint8List _encodeTestPng() {
  return _encodeSizedTestPng(width: 2, height: 2);
}

Uint8List _encodeSizedTestPng({required int width, required int height}) {
  final image = package_image.Image(
    width: width,
    height: height,
    numChannels: 4,
  );
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final isWarm = (x + y).isEven;
      image.setPixelRgba(
        x,
        y,
        isWarm ? 255 : 0,
        (y * 255 ~/ math.max(1, height - 1)).clamp(0, 255),
        isWarm ? 64 : 255,
        255,
      );
    }
  }
  return package_image.encodePng(image);
}

Uint8List _ddsCompressedBytes() {
  const width = 16;
  const height = 8;
  const mip0Size = 64;
  const mip1Size = 16;
  final bytes = Uint8List(128 + mip0Size + mip1Size);
  bytes.setAll(0, const <int>[0x44, 0x44, 0x53, 0x20]);
  _writeUint32Le(bytes, 4, 124);
  _writeUint32Le(bytes, 12, height);
  _writeUint32Le(bytes, 16, width);
  _writeUint32Le(bytes, 20, mip0Size);
  _writeUint32Le(bytes, 28, 2);
  _writeUint32Le(bytes, 76, 32);
  _writeUint32Le(bytes, 80, 0x000004);
  _writeUint32Le(bytes, 84, _fourCc('DXT1'));
  return bytes;
}

Uint8List _ktxCompressedBytes() {
  final bytes = Uint8List(64 + 4 + 64 + 4 + 16);
  bytes.setAll(0, const <int>[
    0xAB,
    0x4B,
    0x54,
    0x58,
    0x20,
    0x31,
    0x31,
    0xBB,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x01,
    0x02,
    0x03,
    0x04,
  ]);
  _writeUint32Le(bytes, 16, 0);
  _writeUint32Le(bytes, 20, 1);
  _writeUint32Le(bytes, 24, 0);
  _writeUint32Le(bytes, 28, 0x83F0);
  _writeUint32Le(bytes, 32, 0x1907);
  _writeUint32Le(bytes, 36, 16);
  _writeUint32Le(bytes, 40, 8);
  _writeUint32Le(bytes, 44, 0);
  _writeUint32Le(bytes, 48, 0);
  _writeUint32Le(bytes, 52, 1);
  _writeUint32Le(bytes, 56, 2);
  _writeUint32Le(bytes, 60, 0);
  _writeUint32Le(bytes, 64, 64);
  _writeUint32Le(bytes, 132, 16);
  return bytes;
}

Uint8List _pkmCompressedBytes() {
  final bytes = Uint8List(16 + 64);
  bytes.setAll(0, const <int>[0x50, 0x4B, 0x4D, 0x20, 0x32, 0x30]);
  _writeUint16Be(bytes, 6, 0);
  _writeUint16Be(bytes, 8, 16);
  _writeUint16Be(bytes, 10, 8);
  _writeUint16Be(bytes, 12, 16);
  _writeUint16Be(bytes, 14, 8);
  return bytes;
}

Uint8List _astcCompressedBytes() {
  final bytes = Uint8List(16 + 128);
  bytes.setAll(0, const <int>[
    0x13,
    0xAB,
    0xA1,
    0x5C,
    0x04,
    0x04,
    0x01,
    0x10,
    0x00,
    0x00,
    0x08,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
  ]);
  return bytes;
}

Uint8List _pvrCompressedBytes() {
  final bytes = Uint8List(52 + 64 + 16);
  bytes.setAll(0, const <int>[0x50, 0x56, 0x52, 0x03]);
  _writeUint32Le(bytes, 4, 0);
  _writeUint64Le(bytes, 8, 7);
  _writeUint32Le(bytes, 16, 0);
  _writeUint32Le(bytes, 20, 0);
  _writeUint32Le(bytes, 24, 8);
  _writeUint32Le(bytes, 28, 16);
  _writeUint32Le(bytes, 32, 1);
  _writeUint32Le(bytes, 36, 1);
  _writeUint32Le(bytes, 40, 1);
  _writeUint32Le(bytes, 44, 2);
  _writeUint32Le(bytes, 48, 0);
  return bytes;
}

void _writeUint32Le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
  bytes[offset + 2] = (value >> 16) & 0xFF;
  bytes[offset + 3] = (value >> 24) & 0xFF;
}

void _writeUint64Le(Uint8List bytes, int offset, int value) {
  _writeUint32Le(bytes, offset, value & 0xFFFFFFFF);
  _writeUint32Le(bytes, offset + 4, value >> 32);
}

void _writeUint16Be(Uint8List bytes, int offset, int value) {
  bytes[offset] = (value >> 8) & 0xFF;
  bytes[offset + 1] = value & 0xFF;
}

int _fourCc(String value) {
  return value.codeUnitAt(0) |
      (value.codeUnitAt(1) << 8) |
      (value.codeUnitAt(2) << 16) |
      (value.codeUnitAt(3) << 24);
}

({double x, double y}) _transformPoint(vm.Matrix4 matrix, double x, double y) {
  final point = matrix.transformed3(vm.Vector3(x, y, 0));
  return (x: point.x, y: point.y);
}

vm.Matrix4 _combineTextTransform(LoveTextCommand command) {
  final combined = vm.Matrix4.copy(command.transform);
  combined.multiply(command.textTransform);
  return combined;
}

vm.Matrix4 _combineImageTransform(LoveImageCommand command) {
  final combined = vm.Matrix4.copy(command.transform);
  combined.multiply(command.drawTransform);
  return combined;
}

List<Object?> _matrixRowMajor({
  required double x,
  required double y,
  required double angle,
  required double scaleX,
  required double scaleY,
  required double originX,
  required double originY,
  required double shearX,
  required double shearY,
}) {
  final cosAngle = math.cos(angle);
  final sinAngle = math.sin(angle);
  final a = cosAngle * scaleX - shearY * sinAngle * scaleY;
  final b = sinAngle * scaleX + shearY * cosAngle * scaleY;
  final c = shearX * cosAngle * scaleX - sinAngle * scaleY;
  final d = shearX * sinAngle * scaleX + cosAngle * scaleY;
  final tx = x - (originX * a) - (originY * c);
  final ty = y - (originX * b) - (originY * d);

  return <Object?>[
    a,
    c,
    0.0,
    tx,
    b,
    d,
    0.0,
    ty,
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0,
  ];
}
