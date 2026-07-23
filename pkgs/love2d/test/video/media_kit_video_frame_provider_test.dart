import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as package_image;
import 'package:love2d/love2d.dart';

void main() {
  group('LoveMediaKitVideoFrameProvider', () {
    test(
      'snapshotAt seeks and returns a BGRA frame using metadata size',
      () async {
        final seeks = <Duration>[];
        var disposeCount = 0;
        final provider = LoveMediaKitVideoFrameProvider.test(
          metadata: const LoveVideoMetadata(pixelWidth: 4, pixelHeight: 3),
          seekPosition: (position) async {
            seeks.add(position);
          },
          takeScreenshot: () async => Uint8List(4 * 3 * 4),
          disposePlayer: () async {
            disposeCount++;
          },
        );

        final snapshot = await provider.snapshotAt(1.25);

        expect(seeks, <Duration>[const Duration(milliseconds: 1250)]);
        expect(snapshot, isNotNull);
        expect(snapshot!.width, 4);
        expect(snapshot.height, 3);
        expect(snapshot.pixelFormat, LoveVideoFramePixelFormat.bgra8888);
        expect(snapshot.bytes, hasLength(4 * 3 * 4));

        await provider.dispose();
        await provider.dispose();
        expect(disposeCount, 1);
      },
    );

    test('snapshotAt clamps negative positions to zero', () async {
      final seeks = <Duration>[];
      final provider = LoveMediaKitVideoFrameProvider.test(
        metadata: const LoveVideoMetadata(pixelWidth: 2, pixelHeight: 2),
        seekPosition: (position) async {
          seeks.add(position);
        },
        takeScreenshot: () async => Uint8List(2 * 2 * 4),
      );

      final snapshot = await provider.snapshotAt(-5.0);

      expect(seeks, <Duration>[Duration.zero]);
      expect(snapshot, isNotNull);
      expect(snapshot!.width, 2);
      expect(snapshot.height, 2);
    });

    test(
      'snapshotAt can infer a missing height from fallback width and bytes',
      () async {
        final provider = LoveMediaKitVideoFrameProvider.test(
          fallbackWidth: 3,
          takeScreenshot: () async => Uint8List(3 * 5 * 4),
        );

        final snapshot = await provider.snapshotAt(0.0);

        expect(snapshot, isNotNull);
        expect(snapshot!.width, 3);
        expect(snapshot.height, 5);
        expect(snapshot.rowBytes, 12);
      },
    );

    test(
      'snapshotAt preserves padded row bytes when metadata dimensions are known',
      () async {
        final provider = LoveMediaKitVideoFrameProvider.test(
          metadata: const LoveVideoMetadata(pixelWidth: 2, pixelHeight: 2),
          takeScreenshot: () async => Uint8List(2 * 12),
        );

        final snapshot = await provider.snapshotAt(0.0);

        expect(snapshot, isNotNull);
        expect(snapshot!.width, 2);
        expect(snapshot.height, 2);
        expect(snapshot.rowBytes, 12);
        expect(snapshot.bytes, hasLength(24));
      },
    );

    test(
      'snapshotAt reuses the cached frame while playback stays in the same frame slot',
      () async {
        var screenshotCount = 0;
        final provider = LoveMediaKitVideoFrameProvider.test(
          metadata: const LoveVideoMetadata(pixelWidth: 2, pixelHeight: 2),
          frameRate: 30.0,
          takeScreenshot: () async {
            screenshotCount++;
            return Uint8List(2 * 2 * 4);
          },
          settleDelay: Duration.zero,
        );

        final first = await provider.snapshotAt(1.000);
        final second = await provider.snapshotAt(1.010);

        expect(first, isNotNull);
        expect(second, same(first));
        expect(screenshotCount, 1);
      },
    );

    test(
      'snapshotAt captures a new frame after advancing into the next frame slot',
      () async {
        var screenshotCount = 0;
        final provider = LoveMediaKitVideoFrameProvider.test(
          metadata: const LoveVideoMetadata(pixelWidth: 2, pixelHeight: 2),
          frameRate: 30.0,
          takeScreenshot: () async {
            screenshotCount++;
            return Uint8List(2 * 2 * 4);
          },
          settleDelay: Duration.zero,
        );

        final first = await provider.snapshotAt(1.000);
        final second = await provider.snapshotAt(1.040);

        expect(first, isNotNull);
        expect(second, isNotNull);
        expect(second, isNot(same(first)));
        expect(screenshotCount, 2);
      },
    );

    test(
      'snapshotAt returns null when the byte length cannot resolve dimensions',
      () async {
        final provider = LoveMediaKitVideoFrameProvider.test(
          metadata: const LoveVideoMetadata(pixelWidth: 4, pixelHeight: 3),
          takeScreenshot: () async => Uint8List(7),
        );

        expect(await provider.snapshotAt(0.0), isNull);
      },
    );

    test(
      'snapshotAt decodes encoded screenshots when raw layout cannot be inferred',
      () async {
        final image = package_image.Image(width: 2, height: 1, numChannels: 4);
        image.setPixelRgba(0, 0, 0x11, 0x22, 0x33, 0x44);
        image.setPixelRgba(1, 0, 0x55, 0x66, 0x77, 0x88);
        final provider = LoveMediaKitVideoFrameProvider.test(
          takeScreenshot: () async =>
              Uint8List.fromList(package_image.encodePng(image)),
        );

        final snapshot = await provider.snapshotAt(0.0);

        expect(snapshot, isNotNull);
        expect(snapshot!.width, 2);
        expect(snapshot.height, 1);
        expect(snapshot.rowBytes, 8);
        expect(snapshot.pixelFormat, LoveVideoFramePixelFormat.rgba8888);
        expect(snapshot.bytes, <int>[
          0x11,
          0x22,
          0x33,
          0x44,
          0x55,
          0x66,
          0x77,
          0x88,
        ]);
      },
    );

    test(
      'snapshotAt waits for video output readiness before the first screenshot',
      () async {
        final events = <String>[];
        final readiness = Completer<void>();
        final provider = LoveMediaKitVideoFrameProvider.test(
          metadata: const LoveVideoMetadata(pixelWidth: 2, pixelHeight: 2),
          playPlayer: () async {
            events.add('play');
          },
          waitForVideoOutputReady: () async {
            events.add('wait:start');
            await readiness.future;
            events.add('wait:end');
          },
          takeScreenshot: () async {
            events.add('screenshot');
            return Uint8List(2 * 2 * 4);
          },
          settleDelay: Duration.zero,
        );

        final pending = provider.snapshotAt(0.0);
        await Future<void>.delayed(Duration.zero);
        expect(events, <String>['play', 'wait:start']);

        readiness.complete();
        final snapshot = await pending;

        expect(snapshot, isNotNull);
        expect(events, <String>[
          'play',
          'wait:start',
          'wait:end',
          'screenshot',
        ]);
      },
    );

    test(
      'snapshotAt pauses and reuses the cached frame for tiny deltas when frame rate is unknown',
      () async {
        final events = <String>[];
        final provider = LoveMediaKitVideoFrameProvider.test(
          metadata: const LoveVideoMetadata(pixelWidth: 2, pixelHeight: 2),
          playPlayer: () async {
            events.add('play');
          },
          pausePlayer: () async {
            events.add('pause');
          },
          takeScreenshot: () async {
            events.add('screenshot');
            return Uint8List(2 * 2 * 4);
          },
          settleDelay: Duration.zero,
        );

        final first = await provider.snapshotAt(1.000);
        final second = await provider.snapshotAt(1.001);

        expect(first, isNotNull);
        expect(second, same(first));
        expect(events, <String>['play', 'screenshot', 'pause']);
      },
    );

    test(
      'snapshotAt seeks across large jumps without replaying play when already playing',
      () async {
        final seeks = <Duration>[];
        final events = <String>[];
        final provider = LoveMediaKitVideoFrameProvider.test(
          metadata: const LoveVideoMetadata(pixelWidth: 2, pixelHeight: 2),
          seekPosition: (position) async {
            seeks.add(position);
          },
          playPlayer: () async {
            events.add('play');
          },
          takeScreenshot: () async {
            events.add('screenshot');
            return Uint8List(2 * 2 * 4);
          },
          settleDelay: Duration.zero,
        );

        await provider.snapshotAt(0.0);
        await provider.snapshotAt(1.0);

        expect(seeks, <Duration>[Duration.zero, const Duration(seconds: 1)]);
        expect(events, <String>['play', 'screenshot', 'screenshot']);
      },
    );

    test(
      'playVideo waits for video output readiness before starting playback',
      () async {
        final events = <String>[];
        final readiness = Completer<void>();
        final provider = LoveMediaKitVideoFrameProvider.test(
          metadata: const LoveVideoMetadata(pixelWidth: 2, pixelHeight: 2),
          playPlayer: () async {
            events.add('play');
          },
          waitForVideoOutputReady: () async {
            events.add('wait:start');
            await readiness.future;
            events.add('wait:end');
          },
        );

        final pending = provider.playVideo();
        await Future<void>.delayed(Duration.zero);
        expect(events, <String>['wait:start']);

        readiness.complete();
        await pending;

        expect(events, <String>['wait:start', 'wait:end', 'play']);
      },
    );

    test(
      'seekVideo invalidates the cached frame for the same frame slot',
      () async {
        var screenshotCount = 0;
        final provider = LoveMediaKitVideoFrameProvider.test(
          metadata: const LoveVideoMetadata(pixelWidth: 2, pixelHeight: 2),
          frameRate: 30.0,
          takeScreenshot: () async {
            screenshotCount++;
            return Uint8List(2 * 2 * 4);
          },
          settleDelay: Duration.zero,
        );

        final first = await provider.snapshotAt(1.000);
        await provider.seekVideo(1.000);
        final second = await provider.snapshotAt(1.000);

        expect(first, isNotNull);
        expect(second, isNotNull);
        expect(second, isNot(same(first)));
        expect(screenshotCount, 2);
      },
    );

    test(
      'dispose waits for an in-flight snapshot before tearing down the player',
      () async {
        final events = <String>[];
        final seekGate = Completer<void>();
        final provider = LoveMediaKitVideoFrameProvider.test(
          metadata: const LoveVideoMetadata(pixelWidth: 2, pixelHeight: 2),
          seekPosition: (position) async {
            events.add('seek:start');
            await seekGate.future;
            events.add('seek:end');
          },
          playPlayer: () async {
            events.add('play');
          },
          takeScreenshot: () async {
            events.add('screenshot');
            return Uint8List(2 * 2 * 4);
          },
          disposePlayer: () async {
            events.add('dispose');
          },
          settleDelay: Duration.zero,
        );

        final pendingSnapshot = provider.snapshotAt(0.0);
        await Future<void>.delayed(Duration.zero);
        expect(events, <String>['seek:start']);

        final pendingDispose = provider.dispose();
        await Future<void>.delayed(Duration.zero);
        expect(events, <String>['seek:start']);

        seekGate.complete();
        final snapshot = await pendingSnapshot;
        await pendingDispose;

        expect(snapshot, isNotNull);
        expect(events, <String>[
          'seek:start',
          'seek:end',
          'play',
          'screenshot',
          'dispose',
        ]);
      },
    );

    test('dispose stays idempotent while teardown is in flight', () async {
      final events = <String>[];
      final disposeGate = Completer<void>();
      final provider = LoveMediaKitVideoFrameProvider.test(
        disposePlayer: () async {
          events.add('dispose:start');
          await disposeGate.future;
          events.add('dispose:end');
        },
      );

      final firstDispose = provider.dispose();
      final secondDispose = provider.dispose();

      expect(secondDispose, same(firstDispose));

      await Future<void>.delayed(Duration.zero);
      expect(events, <String>['dispose:start']);

      disposeGate.complete();
      await firstDispose;
      await secondDispose;

      expect(events, <String>['dispose:start', 'dispose:end']);
    });

    test('play, pause, and seek no-op once dispose has started', () async {
      final events = <String>[];
      final disposeGate = Completer<void>();
      final provider = LoveMediaKitVideoFrameProvider.test(
        seekPosition: (position) async {
          events.add('seek:${position.inMilliseconds}');
        },
        playPlayer: () async {
          events.add('play');
        },
        pausePlayer: () async {
          events.add('pause');
        },
        disposePlayer: () async {
          events.add('dispose:start');
          await disposeGate.future;
          events.add('dispose:end');
        },
      );

      final pendingDispose = provider.dispose();
      final pendingPlay = provider.playVideo();
      final pendingPause = provider.pauseVideo();
      final pendingSeek = provider.seekVideo(1.0);

      await Future<void>.delayed(Duration.zero);
      expect(events, <String>['dispose:start']);

      disposeGate.complete();
      await Future.wait<void>(<Future<void>>[
        pendingDispose,
        pendingPlay,
        pendingPause,
        pendingSeek,
      ]);

      expect(events, <String>['dispose:start', 'dispose:end']);
    });
  });
}
