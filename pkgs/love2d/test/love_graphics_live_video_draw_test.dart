import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

const String _registeredFragmentVideoFallbackShaderSource = '''
// LOVE2D_FLUTTER_FRAGMENT_ASSET: packages/love2d/test_assets/shaders/runtime_effect_solid_color.frag

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  return vec4(1.0, 0.0, 0.0, 1.0);
}
''';

const String _desaturationVideoFallbackShaderSource = '''
extern vec4 tint;
extern number strength;

vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _)
{
  color = Texel(texture, tc);
  number luma = dot(vec3(0.299f, 0.587f, 0.114f), color.rgb);
  return mix(color, tint * luma, strength);
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('love.graphics draw(Video) live presentation', () {
    test(
      'queues a live video command when a presentation handle is available',
      () async {
        final provider = _FakeLiveVideoFrameProvider();
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false, 'dpiscale': 2.0},
          ],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, 10.0, 20.0],
        );

        expect(host.graphics.commands, hasLength(1));
        final command = host.graphics.commands.single as LoveVideoCommand;
        expect(provider.snapshotCalls, 0);
        expect(command.video.hasLivePresentation, isTrue);
        expect(command.drawTransform.storage[0], closeTo(0.5, 0.0001));
        expect(command.drawTransform.storage[5], closeTo(0.5, 0.0001));
        expect(command.drawTransform.storage[12], closeTo(10.0, 0.0001));
        expect(command.drawTransform.storage[13], closeTo(20.0, 0.0001));
      },
    );

    test('queues a live video command when drawing with a Quad', () async {
      final provider = _FakeLiveVideoFrameProvider();
      final runtime = createLuaLikeTestRuntime();
      final host = LoveHeadlessHost(
        videoFrameProviderFactory: (source, {bytes, metadata}) async {
          return provider;
        },
      );
      installLove2d(
        runtime: runtime,
        host: host,
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
          }),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime);
      expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

      final video = await luaCallRawList(
        runtime,
        const ['love', 'graphics', 'newVideo'],
        const <Object?>[
          'videos/demo.ogv',
          <Object?, Object?>{'audio': false},
        ],
      );
      final quad = await luaCallRawList(
        runtime,
        const ['love', 'graphics', 'newQuad'],
        const <Object?>[2.0, 1.0, 3.0, 2.0, 8.0, 4.0],
      );

      LoveRuntimeContext.of(runtime).beginDrawFrame();
      await luaCallRawList(
        runtime,
        const ['love', 'graphics', 'draw'],
        <Object?>[video, quad, 10.0, 20.0],
      );

      expect(provider.snapshotCalls, 0);
      expect(host.graphics.commands, hasLength(1));
      final command = host.graphics.commands.single as LoveVideoCommand;
      expect(command.quad, isNotNull);
      expect(command.quad!.x, 2.0);
      expect(command.quad!.y, 1.0);
      expect(command.quad!.width, 3.0);
      expect(command.quad!.height, 2.0);
    });

    test(
      'queues a live video command when scissor and tint are active',
      () async {
        final provider = _FakeLiveVideoFrameProvider();
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'setColor'],
          const <Object?>[0.5, 0.75, 1.0, 0.5],
        );
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'setScissor'],
          const <Object?>[1.0, 2.0, 3.0, 4.0],
        );
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, 10.0, 20.0],
        );

        expect(provider.snapshotCalls, 0);
        expect(host.graphics.commands, hasLength(1));
        final command = host.graphics.commands.single as LoveVideoCommand;
        expect(command.scissor, isNotNull);
        expect(command.scissor!.x, 1.0);
        expect(command.scissor!.y, 2.0);
        expect(command.scissor!.width, 3.0);
        expect(command.scissor!.height, 4.0);
        expect(command.color.r, closeTo(0.5, 0.0001));
        expect(command.color.g, closeTo(0.75, 0.0001));
        expect(command.color.b, closeTo(1.0, 0.0001));
        expect(command.color.a, closeTo(0.5, 0.0001));
      },
    );

    test(
      'queues a live video command when alpha blending uses premultiplied mode',
      () async {
        final provider = _FakeLiveVideoFrameProvider();
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'setBlendMode'],
          const <Object?>['alpha', 'premultiplied'],
        );
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, 10.0, 20.0],
        );

        expect(provider.snapshotCalls, 0);
        expect(host.graphics.commands, hasLength(1));
        expect(host.graphics.commands.single, isA<LoveVideoCommand>());
      },
    );

    test(
      'queues a live video command when drawing with a Transform object',
      () async {
        final provider = _FakeLiveVideoFrameProvider();
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false, 'dpiscale': 2.0},
          ],
        );
        final transform = await luaCallRawList(
          runtime,
          const ['love', 'math', 'newTransform'],
          const <Object?>[10.0, 20.0, 0.0, 3.0, 4.0],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, transform],
        );

        expect(provider.snapshotCalls, 0);
        expect(host.graphics.commands, hasLength(1));
        final command = host.graphics.commands.single as LoveVideoCommand;
        expect(command.drawTransform.storage[0], closeTo(1.5, 0.0001));
        expect(command.drawTransform.storage[5], closeTo(2.0, 0.0001));
        expect(command.drawTransform.storage[12], closeTo(10.0, 0.0001));
        expect(command.drawTransform.storage[13], closeTo(20.0, 0.0001));
      },
    );

    test(
      'queues a live video command when replace blending keeps source alpha opaque',
      () async {
        final provider = _FakeLiveVideoFrameProvider();
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'setBlendMode'],
          const <Object?>['replace'],
        );
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, 10.0, 20.0],
        );

        expect(provider.snapshotCalls, 0);
        expect(host.graphics.commands, hasLength(1));
        expect(host.graphics.commands.single, isA<LoveVideoCommand>());
      },
    );

    test(
      'queues a live video command when none blending keeps source alpha opaque',
      () async {
        final provider = _FakeLiveVideoFrameProvider();
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'setBlendMode'],
          const <Object?>['none'],
        );
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, 10.0, 20.0],
        );

        expect(provider.snapshotCalls, 0);
        expect(host.graphics.commands, hasLength(1));
        expect(host.graphics.commands.single, isA<LoveVideoCommand>());
      },
    );

    test(
      'falls back to image snapshots when the draw state cannot stay live',
      () async {
        final provider = _FakeLiveVideoFrameProvider();
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'setBlendMode'],
          const <Object?>['add'],
        );
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, 10.0, 20.0],
        );

        expect(provider.snapshotCalls, 1);
        expect(host.graphics.commands, hasLength(1));
        expect(host.graphics.commands.single, isA<LoveImageCommand>());
      },
    );

    test(
      'falls back to image snapshots when replace blending uses translucent alpha',
      () async {
        final provider = _FakeLiveVideoFrameProvider();
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'setBlendMode'],
          const <Object?>['replace'],
        );
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'setColor'],
          const <Object?>[1.0, 1.0, 1.0, 0.5],
        );
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, 10.0, 20.0],
        );

        expect(provider.snapshotCalls, 1);
        expect(host.graphics.commands, hasLength(1));
        expect(host.graphics.commands.single, isA<LoveImageCommand>());
      },
    );

    test(
      'falls back to image snapshots when none blending uses translucent alpha',
      () async {
        final provider = _FakeLiveVideoFrameProvider();
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'setBlendMode'],
          const <Object?>['none'],
        );
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'setColor'],
          const <Object?>[1.0, 1.0, 1.0, 0.5],
        );
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, 10.0, 20.0],
        );

        expect(provider.snapshotCalls, 1);
        expect(host.graphics.commands, hasLength(1));
        expect(host.graphics.commands.single, isA<LoveImageCommand>());
      },
    );

    test(
      'falls back to image snapshots when colorMask disables channels',
      () async {
        final provider = _FakeLiveVideoFrameProvider();
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'setColorMask'],
          const <Object?>[false, true, true, true],
        );
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, 10.0, 20.0],
        );

        expect(provider.snapshotCalls, 1);
        expect(host.graphics.commands, hasLength(1));
        expect(host.graphics.commands.single, isA<LoveImageCommand>());
      },
    );

    test(
      'falls back to image snapshots when a Quad targets a non-zero layer',
      () async {
        final provider = _FakeLiveVideoFrameProvider();
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        );
        final quad = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newQuad'],
          const <Object?>[2.0, 1.0, 3.0, 2.0, 8.0, 4.0],
        );
        await luaCallMethodRawList(quad, 'setLayer', const <Object?>[2]);

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, quad, 10.0, 20.0],
        );

        expect(provider.snapshotCalls, 1);
        expect(host.graphics.commands, hasLength(1));
        final command = host.graphics.commands.single as LoveImageCommand;
        expect(command.quad, isNotNull);
        expect(command.quad!.layer, 1);
      },
    );

    test(
      'falls back to image snapshots with a Transform object while preserving video scaling',
      () async {
        final provider = _FakeLiveVideoFrameProvider();
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false, 'dpiscale': 2.0},
          ],
        );
        final transform = await luaCallRawList(
          runtime,
          const ['love', 'math', 'newTransform'],
          const <Object?>[10.0, 20.0, 0.0, 3.0, 4.0],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'setBlendMode'],
          const <Object?>['add'],
        );
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, transform],
        );

        expect(provider.snapshotCalls, 1);
        expect(host.graphics.commands, hasLength(1));
        final command = host.graphics.commands.single as LoveImageCommand;
        expect(command.drawTransform.storage[0], closeTo(1.5, 0.0001));
        expect(command.drawTransform.storage[5], closeTo(2.0, 0.0001));
        expect(command.drawTransform.storage[12], closeTo(10.0, 0.0001));
        expect(command.drawTransform.storage[13], closeTo(20.0, 0.0001));
      },
    );

    test(
      'falls back to image snapshots when a registered fragment shader is active',
      () async {
        final provider = _FakeLiveVideoFrameProvider();
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        );
        final shader = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newShader'],
          const <Object?>[_registeredFragmentVideoFallbackShaderSource],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'setShader'],
          <Object?>[shader],
        );
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, 10.0, 20.0],
        );

        expect(provider.snapshotCalls, 1);
        expect(host.graphics.commands, hasLength(1));
        final command = host.graphics.commands.single as LoveImageCommand;
        expect(command.shader, isNotNull);
        expect(
          command.shader!.flutterFragmentAssetKey,
          'packages/love2d/test_assets/shaders/runtime_effect_solid_color.frag',
        );
      },
    );

    test(
      'falls back to image snapshots when a supported LOVE shader subset is active',
      () async {
        final provider = _FakeLiveVideoFrameProvider();
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        );
        final shader = await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'newShader'],
          const <Object?>[_desaturationVideoFallbackShaderSource],
        );
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'setShader'],
          <Object?>[shader],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRawList(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, 10.0, 20.0],
        );

        expect(provider.snapshotCalls, 1);
        expect(host.graphics.commands, hasLength(1));
        final command = host.graphics.commands.single as LoveImageCommand;
        expect(command.shader, isNotNull);
        expect(command.shader!.kind, LoveShaderKind.desaturationTint);
      },
    );
  });
}

final class _FakeLiveVideoFrameProvider
    implements LoveVideoFrameProvider, LoveVideoLivePresentation {
  int snapshotCalls = 0;

  @override
  final Object livePresentationHandle = Object();

  @override
  Future<void> dispose() async {}

  @override
  Future<LoveVideoFrameSnapshot?> snapshotAt(double positionSeconds) async {
    snapshotCalls++;
    return LoveVideoFrameSnapshot(
      width: 8,
      height: 4,
      bytes: Uint8List.fromList(<int>[
        0x30,
        0x20,
        0x10,
        0xff,
        ...List<int>.filled((8 * 4 * 4) - 4, 0),
      ]),
    );
  }
}

List<int> _fakeTheoraOggBytes({required int width, required int height}) {
  final packet = Uint8List(22);
  packet[0] = 0x80;
  const signature = 'theora';
  for (var index = 0; index < signature.length; index++) {
    packet[index + 1] = signature.codeUnitAt(index);
  }

  packet[7] = 3;
  packet[8] = 2;
  packet[9] = 1;

  final macroBlockWidth = ((width + 15) ~/ 16).clamp(0, 0xffff);
  final macroBlockHeight = ((height + 15) ~/ 16).clamp(0, 0xffff);
  packet[10] = (macroBlockWidth >> 8) & 0xff;
  packet[11] = macroBlockWidth & 0xff;
  packet[12] = (macroBlockHeight >> 8) & 0xff;
  packet[13] = macroBlockHeight & 0xff;
  packet[14] = (width >> 16) & 0xff;
  packet[15] = (width >> 8) & 0xff;
  packet[16] = width & 0xff;
  packet[17] = (height >> 16) & 0xff;
  packet[18] = (height >> 8) & 0xff;
  packet[19] = height & 0xff;

  return <int>[
    ...'OggS'.codeUnits,
    0x00,
    0x02,
    ...List<int>.filled(8, 0),
    0x01,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x01,
    packet.length,
    ...packet,
  ];
}
