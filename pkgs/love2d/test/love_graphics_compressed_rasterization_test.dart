import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics compressed rasterization', () {
    test(
      'software screenshot rasterizes DXT1 images created from CompressedImageData',
      () async {
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final compressed = await _newCompressedData(
          runtime,
          'solid_red.dds',
          _ddsBytes(_dxt1SolidBlock(paletteIndex: 0)),
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[compressed],
        );

        LoveImageData? captured;
        host.graphics.captureScreenshot((imageData) {
          captured = imageData;
        });

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[image, 0, 0],
        );
        await host.graphics.dispatchPendingScreenshots(
          snapshot: host.graphics.snapshotScreenSurface(),
          pixelWidth: 4,
          pixelHeight: 4,
        );

        expect(captured, isNotNull);
        expect(captured!.getPixel(0, 0).r, closeTo(1.0, 0.001));
        expect(captured!.getPixel(0, 0).g, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).b, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).a, closeTo(1.0, 0.001));
      },
    );

    test(
      'software screenshot rasterizes DXT3 images with explicit alpha',
      () async {
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final compressed = await _newCompressedData(
          runtime,
          'solid_green_dxt3.dds',
          _ddsBytes(
            _dxt3SolidBlock(colorPaletteIndex: 1, alphaNibble: 8),
            fourCc: 'DXT3',
          ),
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[compressed],
        );

        LoveImageData? captured;
        host.graphics.captureScreenshot((imageData) {
          captured = imageData;
        });

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'setBlendMode'],
          const <Object?>['replace'],
        );
        await _call(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[image, 0, 0],
        );
        await host.graphics.dispatchPendingScreenshots(
          snapshot: host.graphics.snapshotScreenSurface(),
          pixelWidth: 4,
          pixelHeight: 4,
        );

        expect(captured, isNotNull);
        expect(captured!.getPixel(0, 0).r, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).g, closeTo(1.0, 0.001));
        expect(captured!.getPixel(0, 0).b, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).a, closeTo(8 / 15, 0.001));
      },
    );

    test(
      'software screenshot rasterizes DXT1 array slices drawn through drawLayer',
      () async {
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final red = await _newCompressedData(
          runtime,
          'red.dds',
          _ddsBytes(_dxt1SolidBlock(paletteIndex: 0)),
        );
        final green = await _newCompressedData(
          runtime,
          'green.ktx',
          _ktxBytes(_dxt1SolidBlock(paletteIndex: 1)),
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newArrayImage'],
          <Object?>[
            _luaSeq(<Object?>[red, green]),
          ],
        );

        LoveImageData? captured;
        host.graphics.captureScreenshot((imageData) {
          captured = imageData;
        });

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'drawLayer'],
          <Object?>[image, 2, 0, 0],
        );
        await host.graphics.dispatchPendingScreenshots(
          snapshot: host.graphics.snapshotScreenSurface(),
          pixelWidth: 4,
          pixelHeight: 4,
        );

        expect(captured, isNotNull);
        expect(captured!.getPixel(0, 0).r, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).g, closeTo(1.0, 0.001));
        expect(captured!.getPixel(0, 0).b, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).a, closeTo(1.0, 0.001));
      },
    );

    test(
      'software screenshot rasterizes DXT5 array slices with interpolated alpha',
      () async {
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final red = await _newCompressedData(
          runtime,
          'red.dds',
          _ddsBytes(
            _dxt5SolidBlock(
              colorPaletteIndex: 0,
              alpha0: 255,
              alpha1: 0,
              alphaIndex: 0,
            ),
            fourCc: 'DXT5',
          ),
        );
        final green = await _newCompressedData(
          runtime,
          'green_dxt5.ktx',
          _ktxBytes(
            _dxt5SolidBlock(
              colorPaletteIndex: 1,
              alpha0: 128,
              alpha1: 0,
              alphaIndex: 0,
            ),
            internalFormat: 0x83F3,
          ),
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newArrayImage'],
          <Object?>[
            _luaSeq(<Object?>[red, green]),
          ],
        );

        LoveImageData? captured;
        host.graphics.captureScreenshot((imageData) {
          captured = imageData;
        });

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'setBlendMode'],
          const <Object?>['replace'],
        );
        await _call(
          runtime,
          const ['love', 'graphics', 'drawLayer'],
          <Object?>[image, 2, 0, 0],
        );
        await host.graphics.dispatchPendingScreenshots(
          snapshot: host.graphics.snapshotScreenSurface(),
          pixelWidth: 4,
          pixelHeight: 4,
        );

        expect(captured, isNotNull);
        expect(captured!.getPixel(0, 0).r, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).g, closeTo(1.0, 0.001));
        expect(captured!.getPixel(0, 0).b, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).a, closeTo(128 / 255, 0.001));
      },
    );

    test('software screenshot rasterizes ETC1 PKM images', () async {
      final host = LoveHeadlessHost(
        windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
      );
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: host);

      final compressed = await _newCompressedData(
        runtime,
        'solid_etc1.pkm',
        _pkmBytes(_etc1SolidBlock(redNibble: 1, greenNibble: 2, blueNibble: 3)),
      );
      final image = await _call(
        runtime,
        const ['love', 'graphics', 'newImage'],
        <Object?>[compressed],
      );

      LoveImageData? captured;
      host.graphics.captureScreenshot((imageData) {
        captured = imageData;
      });

      LoveRuntimeContext.of(runtime).beginDrawFrame();
      await _call(
        runtime,
        const ['love', 'graphics', 'draw'],
        <Object?>[image, 0, 0],
      );
      await host.graphics.dispatchPendingScreenshots(
        snapshot: host.graphics.snapshotScreenSurface(),
        pixelWidth: 4,
        pixelHeight: 4,
      );

      expect(captured, isNotNull);
      expect(captured!.getPixel(0, 0).r, closeTo(19 / 255, 0.001));
      expect(captured!.getPixel(0, 0).g, closeTo(36 / 255, 0.001));
      expect(captured!.getPixel(0, 0).b, closeTo(53 / 255, 0.001));
      expect(captured!.getPixel(0, 0).a, closeTo(1.0, 0.001));
    });

    test(
      'software screenshot rasterizes ETC2rgb PKM images through T mode',
      () async {
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final compressed = await _newCompressedData(
          runtime,
          'solid_etc2rgb.pkm',
          _pkmBytes(
            _etc2TModeBlock(
              red1Nibble: 11,
              green1Nibble: 4,
              blue1Nibble: 5,
              red2Nibble: 1,
              green2Nibble: 2,
              blue2Nibble: 3,
              distanceIndex: 0,
              selector: 0,
              modeBit: 1,
            ),
            format: 1,
          ),
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[compressed],
        );

        LoveImageData? captured;
        host.graphics.captureScreenshot((imageData) {
          captured = imageData;
        });

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[image, 0, 0],
        );
        await host.graphics.dispatchPendingScreenshots(
          snapshot: host.graphics.snapshotScreenSurface(),
          pixelWidth: 4,
          pixelHeight: 4,
        );

        expect(captured, isNotNull);
        expect(captured!.getPixel(0, 0).r, closeTo(187 / 255, 0.001));
        expect(captured!.getPixel(0, 0).g, closeTo(68 / 255, 0.001));
        expect(captured!.getPixel(0, 0).b, closeTo(85 / 255, 0.001));
        expect(captured!.getPixel(0, 0).a, closeTo(1.0, 0.001));
      },
    );

    test(
      'software screenshot rasterizes ETC2rgba images with separate alpha blocks',
      () async {
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final block = Uint8List(16)
          ..setAll(
            0,
            _etc2AlphaBlock(
              baseCodeword: 128,
              multiplier: 0,
              tableIndex: 13,
              selector: 4,
            ),
          )
          ..setAll(
            8,
            _etc1SolidBlock(redNibble: 1, greenNibble: 2, blueNibble: 3),
          );
        final compressed = await _newCompressedData(
          runtime,
          'solid_etc2rgba.ktx',
          _ktxBytes(block, internalFormat: 0x9278),
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[compressed],
        );

        LoveImageData? captured;
        host.graphics.captureScreenshot((imageData) {
          captured = imageData;
        });

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'setBlendMode'],
          const <Object?>['replace'],
        );
        await _call(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[image, 0, 0],
        );
        await host.graphics.dispatchPendingScreenshots(
          snapshot: host.graphics.snapshotScreenSurface(),
          pixelWidth: 4,
          pixelHeight: 4,
        );

        expect(captured, isNotNull);
        expect(captured!.getPixel(0, 0).r, closeTo(19 / 255, 0.001));
        expect(captured!.getPixel(0, 0).g, closeTo(36 / 255, 0.001));
        expect(captured!.getPixel(0, 0).b, closeTo(53 / 255, 0.001));
        expect(captured!.getPixel(0, 0).a, closeTo(128 / 255, 0.001));
      },
    );

    test(
      'software screenshot rasterizes EACr PKM images as red-only data',
      () async {
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final compressed = await _newCompressedData(
          runtime,
          'solid_red_eacr.pkm',
          _pkmBytes(
            _eacChannelBlock(
              baseCodeword: 128,
              multiplier: 0,
              tableIndex: 13,
              selector: 4,
            ),
            format: 5,
          ),
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[compressed],
        );

        LoveImageData? captured;
        host.graphics.captureScreenshot((imageData) {
          captured = imageData;
        });

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[image, 0, 0],
        );
        await host.graphics.dispatchPendingScreenshots(
          snapshot: host.graphics.snapshotScreenSurface(),
          pixelWidth: 4,
          pixelHeight: 4,
        );

        expect(captured, isNotNull);
        expect(captured!.getPixel(0, 0).r, closeTo(1028 / 2047, 0.001));
        expect(captured!.getPixel(0, 0).g, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).b, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).a, closeTo(1.0, 0.001));
      },
    );

    test(
      'software screenshot rasterizes BC4 images as red-only data',
      () async {
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final compressed = await _newCompressedData(
          runtime,
          'solid_red_bc4.dds',
          _ddsBytes(
            _bc4SolidBlock(endpoint0: 255, endpoint1: 0, paletteIndex: 0),
            fourCc: 'BC4U',
          ),
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[compressed],
        );

        LoveImageData? captured;
        host.graphics.captureScreenshot((imageData) {
          captured = imageData;
        });

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[image, 0, 0],
        );
        await host.graphics.dispatchPendingScreenshots(
          snapshot: host.graphics.snapshotScreenSurface(),
          pixelWidth: 4,
          pixelHeight: 4,
        );

        expect(captured, isNotNull);
        expect(captured!.getPixel(0, 0).r, closeTo(1.0, 0.001));
        expect(captured!.getPixel(0, 0).g, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).b, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).a, closeTo(1.0, 0.001));
      },
    );

    test(
      'software screenshot rasterizes ETC1 array slices drawn through drawLayer',
      () async {
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final first = await _newCompressedData(
          runtime,
          'first_etc1.pkm',
          _pkmBytes(
            _etc1SolidBlock(redNibble: 1, greenNibble: 2, blueNibble: 3),
          ),
        );
        final second = await _newCompressedData(
          runtime,
          'second_etc1.ktx',
          _ktxBytes(
            _etc1SolidBlock(redNibble: 6, greenNibble: 5, blueNibble: 4),
            internalFormat: 0x8D64,
          ),
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newArrayImage'],
          <Object?>[
            _luaSeq(<Object?>[first, second]),
          ],
        );

        LoveImageData? captured;
        host.graphics.captureScreenshot((imageData) {
          captured = imageData;
        });

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'drawLayer'],
          <Object?>[image, 2, 0, 0],
        );
        await host.graphics.dispatchPendingScreenshots(
          snapshot: host.graphics.snapshotScreenSurface(),
          pixelWidth: 4,
          pixelHeight: 4,
        );

        expect(captured, isNotNull);
        expect(captured!.getPixel(0, 0).r, closeTo(104 / 255, 0.001));
        expect(captured!.getPixel(0, 0).g, closeTo(87 / 255, 0.001));
        expect(captured!.getPixel(0, 0).b, closeTo(70 / 255, 0.001));
        expect(captured!.getPixel(0, 0).a, closeTo(1.0, 0.001));
      },
    );

    test(
      'software screenshot applies ETC2rgba1 punchthrough alpha transparency',
      () async {
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final compressed = await _newCompressedData(
          runtime,
          'transparent_etc2rgba1.ktx',
          _ktxBytes(
            _etc2TModeBlock(
              red1Nibble: 11,
              green1Nibble: 4,
              blue1Nibble: 5,
              red2Nibble: 1,
              green2Nibble: 2,
              blue2Nibble: 3,
              distanceIndex: 0,
              selector: 2,
              modeBit: 0,
            ),
            internalFormat: 0x9276,
          ),
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[compressed],
        );

        LoveImageData? captured;
        host.graphics.captureScreenshot((imageData) {
          captured = imageData;
        });

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'setBlendMode'],
          const <Object?>['replace'],
        );
        await _call(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[image, 0, 0],
        );
        await host.graphics.dispatchPendingScreenshots(
          snapshot: host.graphics.snapshotScreenSurface(),
          pixelWidth: 4,
          pixelHeight: 4,
        );

        expect(captured, isNotNull);
        expect(captured!.getPixel(0, 0).r, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).g, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).b, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).a, closeTo(0.0, 0.001));
      },
    );

    test(
      'software screenshot rasterizes EACrg array slices drawn through drawLayer',
      () async {
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final first = await _newCompressedData(
          runtime,
          'first_eacrg.pkm',
          _pkmBytes(
            _eacRgBlock(
              redBaseCodeword: 200,
              redMultiplier: 0,
              redTableIndex: 13,
              redSelector: 4,
              greenBaseCodeword: 32,
              greenMultiplier: 0,
              greenTableIndex: 13,
              greenSelector: 4,
            ),
            format: 6,
          ),
        );
        final second = await _newCompressedData(
          runtime,
          'second_eacrg.ktx',
          _ktxBytes(
            _eacRgBlock(
              redBaseCodeword: 48,
              redMultiplier: 0,
              redTableIndex: 13,
              redSelector: 4,
              greenBaseCodeword: 160,
              greenMultiplier: 0,
              greenTableIndex: 13,
              greenSelector: 4,
            ),
            internalFormat: 0x9272,
          ),
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newArrayImage'],
          <Object?>[
            _luaSeq(<Object?>[first, second]),
          ],
        );

        LoveImageData? captured;
        host.graphics.captureScreenshot((imageData) {
          captured = imageData;
        });

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'drawLayer'],
          <Object?>[image, 2, 0, 0],
        );
        await host.graphics.dispatchPendingScreenshots(
          snapshot: host.graphics.snapshotScreenSurface(),
          pixelWidth: 4,
          pixelHeight: 4,
        );

        expect(captured, isNotNull);
        expect(captured!.getPixel(0, 0).r, closeTo(388 / 2047, 0.001));
        expect(captured!.getPixel(0, 0).g, closeTo(1284 / 2047, 0.001));
        expect(captured!.getPixel(0, 0).b, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).a, closeTo(1.0, 0.001));
      },
    );

    test(
      'software screenshot rasterizes BC5 array slices drawn through drawLayer',
      () async {
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final red = await _newCompressedData(
          runtime,
          'red_bc5.dds',
          _ddsBytes(
            _bc5SolidBlock(
              redEndpoint0: 255,
              redEndpoint1: 0,
              redPaletteIndex: 0,
              greenEndpoint0: 0,
              greenEndpoint1: 0,
              greenPaletteIndex: 0,
            ),
            fourCc: 'BC5U',
          ),
        );
        final green = await _newCompressedData(
          runtime,
          'green_bc5.ktx',
          _ktxBytes(
            _bc5SolidBlock(
              redEndpoint0: 0,
              redEndpoint1: 0,
              redPaletteIndex: 0,
              greenEndpoint0: 255,
              greenEndpoint1: 0,
              greenPaletteIndex: 0,
            ),
            internalFormat: 0x8DBD,
          ),
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newArrayImage'],
          <Object?>[
            _luaSeq(<Object?>[red, green]),
          ],
        );

        LoveImageData? captured;
        host.graphics.captureScreenshot((imageData) {
          captured = imageData;
        });

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'drawLayer'],
          <Object?>[image, 2, 0, 0],
        );
        await host.graphics.dispatchPendingScreenshots(
          snapshot: host.graphics.snapshotScreenSurface(),
          pixelWidth: 4,
          pixelHeight: 4,
        );

        expect(captured, isNotNull);
        expect(captured!.getPixel(0, 0).r, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).g, closeTo(1.0, 0.001));
        expect(captured!.getPixel(0, 0).b, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).a, closeTo(1.0, 0.001));
      },
    );

    test(
      'software screenshot clamps signed EACrgs samples into the output color range',
      () async {
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final compressed = await _newCompressedData(
          runtime,
          'signed_eacrgs.ktx',
          _ktxBytes(
            _eacRgBlock(
              redBaseCodeword: 64,
              redMultiplier: 0,
              redTableIndex: 13,
              redSelector: 4,
              greenBaseCodeword: -64,
              greenMultiplier: 0,
              greenTableIndex: 13,
              greenSelector: 4,
            ),
            internalFormat: 0x9273,
          ),
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[compressed],
        );

        LoveImageData? captured;
        host.graphics.captureScreenshot((imageData) {
          captured = imageData;
        });

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'setBlendMode'],
          const <Object?>['replace'],
        );
        await _call(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[image, 0, 0],
        );
        await host.graphics.dispatchPendingScreenshots(
          snapshot: host.graphics.snapshotScreenSurface(),
          pixelWidth: 4,
          pixelHeight: 4,
        );

        expect(captured, isNotNull);
        expect(captured!.getPixel(0, 0).r, closeTo(512 / 1023, 0.001));
        expect(captured!.getPixel(0, 0).g, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).b, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).a, closeTo(1.0, 0.001));
      },
    );

    test(
      'software screenshot clamps signed BC5s samples into the output color range',
      () async {
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(width: 4, height: 4),
        );
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final compressed = await _newCompressedData(
          runtime,
          'signed_bc5.ktx',
          _ktxBytes(
            _bc5SolidBlock(
              redEndpoint0: 64,
              redEndpoint1: 64,
              redPaletteIndex: 0,
              greenEndpoint0: -64,
              greenEndpoint1: -64,
              greenPaletteIndex: 0,
            ),
            internalFormat: 0x8DBE,
          ),
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[compressed],
        );

        LoveImageData? captured;
        host.graphics.captureScreenshot((imageData) {
          captured = imageData;
        });

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'setBlendMode'],
          const <Object?>['replace'],
        );
        await _call(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[image, 0, 0],
        );
        await host.graphics.dispatchPendingScreenshots(
          snapshot: host.graphics.snapshotScreenSurface(),
          pixelWidth: 4,
          pixelHeight: 4,
        );

        expect(captured, isNotNull);
        expect(captured!.getPixel(0, 0).r, closeTo(64 / 127, 0.001));
        expect(captured!.getPixel(0, 0).g, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).b, closeTo(0.0, 0.001));
        expect(captured!.getPixel(0, 0).a, closeTo(1.0, 0.001));
      },
    );
  });
}

Future<Object?> _newCompressedData(
  Interpreter runtime,
  String filename,
  Uint8List bytes,
) async {
  final fileData = await _call(
    runtime,
    const ['love', 'filesystem', 'newFileData'],
    <Object?>[bytes, filename],
  );
  return _call(
    runtime,
    const ['love', 'image', 'newCompressedData'],
    <Object?>[fileData],
  );
}

Uint8List _ddsBytes(Uint8List blockBytes, {String fourCc = 'DXT1'}) {
  final bytes = Uint8List(128 + blockBytes.length);
  bytes.setAll(0, const <int>[0x44, 0x44, 0x53, 0x20]);
  _writeUint32Le(bytes, 4, 124);
  _writeUint32Le(bytes, 12, 4);
  _writeUint32Le(bytes, 16, 4);
  _writeUint32Le(bytes, 20, blockBytes.length);
  _writeUint32Le(bytes, 28, 1);
  _writeUint32Le(bytes, 76, 32);
  _writeUint32Le(bytes, 80, 0x000004);
  _writeUint32Le(bytes, 84, _fourCc(fourCc));
  bytes.setAll(128, blockBytes);
  return bytes;
}

Uint8List _ktxBytes(Uint8List blockBytes, {int internalFormat = 0x83F0}) {
  final bytes = Uint8List(64 + 4 + blockBytes.length);
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
  _writeUint32Le(bytes, 28, internalFormat);
  _writeUint32Le(bytes, 32, 0x1907);
  _writeUint32Le(bytes, 36, 4);
  _writeUint32Le(bytes, 40, 4);
  _writeUint32Le(bytes, 44, 0);
  _writeUint32Le(bytes, 48, 0);
  _writeUint32Le(bytes, 52, 1);
  _writeUint32Le(bytes, 56, 1);
  _writeUint32Le(bytes, 60, 0);
  _writeUint32Le(bytes, 64, blockBytes.length);
  bytes.setAll(68, blockBytes);
  return bytes;
}

Uint8List _pkmBytes(Uint8List blockBytes, {int format = 0}) {
  final bytes = Uint8List(16 + blockBytes.length);
  bytes.setAll(0, const <int>[0x50, 0x4B, 0x4D, 0x20, 0x32, 0x30]);
  _writeUint16Be(bytes, 6, format);
  _writeUint16Be(bytes, 8, 4);
  _writeUint16Be(bytes, 10, 4);
  _writeUint16Be(bytes, 12, 4);
  _writeUint16Be(bytes, 14, 4);
  bytes.setAll(16, blockBytes);
  return bytes;
}

Uint8List _dxt1SolidBlock({required int paletteIndex}) {
  final bytes = Uint8List(8);
  bytes.setAll(0, _dxtColorBlock(colorPaletteIndex: paletteIndex));
  return bytes;
}

Uint8List _dxt3SolidBlock({
  required int colorPaletteIndex,
  required int alphaNibble,
}) {
  final bytes = Uint8List(16);
  var alphaBits = 0;
  for (var index = 0; index < 16; index++) {
    alphaBits |= (alphaNibble & 0xf) << (index * 4);
  }
  _writeUint64Le(bytes, 0, alphaBits);
  bytes.setAll(8, _dxtColorBlock(colorPaletteIndex: colorPaletteIndex));
  return bytes;
}

Uint8List _dxt5SolidBlock({
  required int colorPaletteIndex,
  required int alpha0,
  required int alpha1,
  required int alphaIndex,
}) {
  final bytes = Uint8List(16);
  bytes[0] = alpha0 & 0xFF;
  bytes[1] = alpha1 & 0xFF;
  var alphaBits = 0;
  for (var index = 0; index < 16; index++) {
    alphaBits |= (alphaIndex & 0x7) << (index * 3);
  }
  _writeUint48Le(bytes, 2, alphaBits);
  bytes.setAll(8, _dxtColorBlock(colorPaletteIndex: colorPaletteIndex));
  return bytes;
}

Uint8List _etc1SolidBlock({
  required int redNibble,
  required int greenNibble,
  required int blueNibble,
}) {
  final bytes = Uint8List(8);
  final high =
      ((redNibble & 0xf) << 28) |
      ((redNibble & 0xf) << 24) |
      ((greenNibble & 0xf) << 20) |
      ((greenNibble & 0xf) << 16) |
      ((blueNibble & 0xf) << 12) |
      ((blueNibble & 0xf) << 8);
  _writeUint32Be(bytes, 0, high);
  _writeUint32Be(bytes, 4, 0);
  return bytes;
}

Uint8List _etc2AlphaBlock({
  required int baseCodeword,
  required int multiplier,
  required int tableIndex,
  required int selector,
}) {
  return _eacChannelBlock(
    baseCodeword: baseCodeword,
    multiplier: multiplier,
    tableIndex: tableIndex,
    selector: selector,
  );
}

Uint8List _etc2TModeBlock({
  required int red1Nibble,
  required int green1Nibble,
  required int blue1Nibble,
  required int red2Nibble,
  required int green2Nibble,
  required int blue2Nibble,
  required int distanceIndex,
  required int selector,
  required int modeBit,
}) {
  final bytes = Uint8List(8);
  final red1a = (red1Nibble >> 2) & 0x3;
  final red1b = red1Nibble & 0x3;
  bytes[0] = red1b | (red1a << 3) | (0x7 << 5);
  bytes[1] = (blue1Nibble & 0xF) | ((green1Nibble & 0xF) << 4);
  bytes[2] = (green2Nibble & 0xF) | ((red2Nibble & 0xF) << 4);
  bytes[3] =
      (distanceIndex & 0x1) |
      ((modeBit & 0x1) << 1) |
      (((distanceIndex >> 1) & 0x3) << 2) |
      ((blue2Nibble & 0xF) << 4);
  _writeUint32Be(bytes, 4, _etcSelectorWord(selector));
  return bytes;
}

Uint8List _eacChannelBlock({
  required int baseCodeword,
  required int multiplier,
  required int tableIndex,
  required int selector,
}) {
  final bytes = Uint8List(8);
  bytes[0] = baseCodeword & 0xFF;
  bytes[1] = ((multiplier & 0xF) << 4) | (tableIndex & 0xF);
  var selectors = 0;
  for (var index = 0; index < 16; index++) {
    selectors |= (selector & 0x7) << ((15 - index) * 3);
  }
  _writeUint48Be(bytes, 2, selectors);
  return bytes;
}

Uint8List _eacRgBlock({
  required int redBaseCodeword,
  required int redMultiplier,
  required int redTableIndex,
  required int redSelector,
  required int greenBaseCodeword,
  required int greenMultiplier,
  required int greenTableIndex,
  required int greenSelector,
}) {
  final bytes = Uint8List(16);
  bytes.setAll(
    0,
    _eacChannelBlock(
      baseCodeword: redBaseCodeword,
      multiplier: redMultiplier,
      tableIndex: redTableIndex,
      selector: redSelector,
    ),
  );
  bytes.setAll(
    8,
    _eacChannelBlock(
      baseCodeword: greenBaseCodeword,
      multiplier: greenMultiplier,
      tableIndex: greenTableIndex,
      selector: greenSelector,
    ),
  );
  return bytes;
}

Uint8List _bc4SolidBlock({
  required int endpoint0,
  required int endpoint1,
  required int paletteIndex,
}) {
  final bytes = Uint8List(8);
  bytes[0] = endpoint0 & 0xFF;
  bytes[1] = endpoint1 & 0xFF;
  var lookup = 0;
  for (var index = 0; index < 16; index++) {
    lookup |= (paletteIndex & 0x7) << (index * 3);
  }
  _writeUint48Le(bytes, 2, lookup);
  return bytes;
}

Uint8List _bc5SolidBlock({
  required int redEndpoint0,
  required int redEndpoint1,
  required int redPaletteIndex,
  required int greenEndpoint0,
  required int greenEndpoint1,
  required int greenPaletteIndex,
}) {
  final bytes = Uint8List(16);
  bytes.setAll(
    0,
    _bc4SolidBlock(
      endpoint0: redEndpoint0,
      endpoint1: redEndpoint1,
      paletteIndex: redPaletteIndex,
    ),
  );
  bytes.setAll(
    8,
    _bc4SolidBlock(
      endpoint0: greenEndpoint0,
      endpoint1: greenEndpoint1,
      paletteIndex: greenPaletteIndex,
    ),
  );
  return bytes;
}

Uint8List _dxtColorBlock({required int colorPaletteIndex}) {
  final bytes = Uint8List(8);
  _writeUint16Le(bytes, 0, 0xF800);
  _writeUint16Le(bytes, 2, 0x07E0);
  var lookup = 0;
  for (var index = 0; index < 16; index++) {
    lookup |= (colorPaletteIndex & 0x3) << (index * 2);
  }
  _writeUint32Le(bytes, 4, lookup);
  return bytes;
}

int _etcSelectorWord(int selector) {
  var word = 0;
  for (var index = 0; index < 16; index++) {
    word |= (selector & 0x1) << index;
    word |= ((selector >> 1) & 0x1) << (index + 16);
  }
  return word;
}

void _writeUint16Le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
}

void _writeUint32Le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
  bytes[offset + 2] = (value >> 16) & 0xFF;
  bytes[offset + 3] = (value >> 24) & 0xFF;
}

void _writeUint16Be(Uint8List bytes, int offset, int value) {
  bytes[offset] = (value >> 8) & 0xFF;
  bytes[offset + 1] = value & 0xFF;
}

void _writeUint32Be(Uint8List bytes, int offset, int value) {
  bytes[offset] = (value >> 24) & 0xFF;
  bytes[offset + 1] = (value >> 16) & 0xFF;
  bytes[offset + 2] = (value >> 8) & 0xFF;
  bytes[offset + 3] = value & 0xFF;
}

void _writeUint48Le(Uint8List bytes, int offset, int value) {
  for (var index = 0; index < 6; index++) {
    bytes[offset + index] = (value >> (index * 8)) & 0xFF;
  }
}

void _writeUint48Be(Uint8List bytes, int offset, int value) {
  for (var index = 0; index < 6; index++) {
    bytes[offset + index] = (value >> ((5 - index) * 8)) & 0xFF;
  }
}

void _writeUint64Le(Uint8List bytes, int offset, int value) {
  for (var index = 0; index < 8; index++) {
    bytes[offset + index] = (value >> (index * 8)) & 0xFF;
  }
}

int _fourCc(String value) {
  return value.codeUnitAt(0) |
      (value.codeUnitAt(1) << 8) |
      (value.codeUnitAt(2) << 16) |
      (value.codeUnitAt(3) << 24);
}

Map<Object?, Object?> _luaSeq(List<Object?> values) {
  return <Object?, Object?>{
    for (var index = 0; index < values.length; index++)
      index + 1: values[index],
  };
}

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
}

BuiltinFunction _rawFunction(Interpreter runtime, List<String> path) {
  var current = runtime.getCurrentEnv().get(path.first);
  for (final segment in path.skip(1)) {
    final table = current is Value ? current.raw : current;
    expect(
      table,
      isA<Map>(),
      reason: 'Expected ${path.join('.')} to traverse a Lua table',
    );
    current = (table as Map)[segment];
  }

  expect(current, isA<Value>());
  final raw = (current! as Value).raw;
  expect(raw, isA<BuiltinFunction>());
  return raw as BuiltinFunction;
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
