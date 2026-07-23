import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/src/runtime/flame/love_flame_media_kit_audio.dart';

void main() {
  group('LoveFlameMediaKitAudioSourceBackend', () {
    test('delegates playback operations before disposal', () async {
      final events = <String>[];
      final backend = LoveFlameMediaKitAudioSourceBackend.test(
        play: () async {
          events.add('play');
        },
        pause: () async {
          events.add('pause');
        },
        stop: () async {
          events.add('stop');
        },
        seek: (position) async {
          events.add('seek:${position.inMilliseconds}');
        },
        setLooping: (looping) async {
          events.add('loop:$looping');
        },
        setVolume: (volume) async {
          events.add('volume:${volume.toStringAsFixed(2)}');
        },
      );

      await backend.play();
      await backend.pause();
      await backend.seek(const Duration(milliseconds: 250));
      await backend.setLooping(true);
      await backend.setVolume(0.4);
      await backend.stop();

      expect(events, <String>[
        'play',
        'pause',
        'seek:250',
        'loop:true',
        'volume:0.40',
        'stop',
      ]);
    });

    test('dispose stays idempotent while teardown is in flight', () async {
      final events = <String>[];
      final disposeGate = Completer<void>();
      final backend = LoveFlameMediaKitAudioSourceBackend.test(
        dispose: () async {
          events.add('dispose:start');
          await disposeGate.future;
          events.add('dispose:end');
        },
      );

      final firstDispose = backend.dispose();
      final secondDispose = backend.dispose();

      expect(secondDispose, same(firstDispose));

      await Future<void>.delayed(Duration.zero);
      expect(events, <String>['dispose:start']);

      disposeGate.complete();
      await firstDispose;
      await secondDispose;

      expect(events, <String>['dispose:start', 'dispose:end']);
    });

    test('playback operations no-op once disposal has started', () async {
      final events = <String>[];
      final disposeGate = Completer<void>();
      final backend = LoveFlameMediaKitAudioSourceBackend.test(
        play: () async {
          events.add('play');
        },
        pause: () async {
          events.add('pause');
        },
        stop: () async {
          events.add('stop');
        },
        seek: (position) async {
          events.add('seek:${position.inMilliseconds}');
        },
        setLooping: (looping) async {
          events.add('loop:$looping');
        },
        setVolume: (volume) async {
          events.add('volume:$volume');
        },
        dispose: () async {
          events.add('dispose:start');
          await disposeGate.future;
          events.add('dispose:end');
        },
      );

      final pendingDispose = backend.dispose();
      final pendingCalls = <Future<void>>[
        backend.play(),
        backend.pause(),
        backend.stop(),
        backend.seek(const Duration(seconds: 1)),
        backend.setLooping(true),
        backend.setVolume(0.75),
      ];

      await Future<void>.delayed(Duration.zero);
      expect(events, <String>['dispose:start']);

      disposeGate.complete();
      await Future.wait<void>(<Future<void>>[pendingDispose, ...pendingCalls]);

      expect(events, <String>['dispose:start', 'dispose:end']);
    });
  });
}
