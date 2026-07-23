import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LoveAudioSource lifecycle', () {
    test(
      'dispose freezes playback state and stays idempotent in flight',
      () async {
        final backend = _HookedAudioBackend();
        final source = LoveAudioSource(
          sourceType: 'stream',
          durationSeconds: 2.0,
          sampleRate: 1000,
          backend: backend,
        );

        await source.play();
        await Future<void>.delayed(const Duration(milliseconds: 30));

        final disposeGate = Completer<void>();
        backend.onDispose = () async {
          backend.events.add('dispose:start');
          await disposeGate.future;
          backend.events.add('dispose:end');
        };

        final firstDispose = source.dispose();
        final secondDispose = source.dispose();
        final disposedAt = source.tell();

        expect(secondDispose, same(firstDispose));
        expect(source.isPlayingNow, isFalse);

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(source.tell(), closeTo(disposedAt, 0.01));
        expect(backend.events, contains('dispose:start'));

        disposeGate.complete();
        await firstDispose;
        await secondDispose;

        expect(
          backend.events
              .where((event) => event.startsWith('dispose:'))
              .toList(),
          <String>['dispose:start', 'dispose:end'],
        );
      },
    );

    test('play and state mutations no-op once disposal has started', () async {
      final backend = _HookedAudioBackend();
      final source = LoveAudioSource(
        sourceType: 'stream',
        durationSeconds: 2.0,
        sampleRate: 1000,
        backend: backend,
      );

      final disposeGate = Completer<void>();
      backend.onDispose = () async {
        backend.events.add('dispose:start');
        await disposeGate.future;
        backend.events.add('dispose:end');
      };

      final pendingDispose = source.dispose();

      expect(await source.play(), isFalse);
      await source.pause();
      await source.stop();
      await source.seek(1.0);
      await source.setLooping(true);
      await source.setVolume(0.5);

      expect(source.isPlayingNow, isFalse);
      expect(source.tell(), 0.0);
      expect(source.looping, isFalse);
      expect(source.volume, 1.0);
      expect(backend.events, <String>['dispose:start']);

      disposeGate.complete();
      await pendingDispose;
      expect(backend.events, <String>['dispose:start', 'dispose:end']);
    });
  });
}

final class _HookedAudioBackend implements LoveAudioSourceBackend {
  final List<String> events = <String>[];

  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onStop;
  Future<void> Function(bool looping)? onSetLooping;
  Future<void> Function(Duration position)? onSeek;
  Future<void> Function(double volume)? onSetVolume;
  Future<void> Function()? onDispose;

  @override
  Future<void> dispose() async {
    await onDispose?.call();
  }

  @override
  Future<void> pause() async {
    events.add('pause');
    await onPause?.call();
  }

  @override
  Future<void> play() async {
    events.add('play');
    await onPlay?.call();
  }

  @override
  Future<void> seek(Duration position) async {
    events.add('seek:${position.inMilliseconds}');
    await onSeek?.call(position);
  }

  @override
  Future<void> setLooping(bool looping) async {
    events.add('loop:$looping');
    await onSetLooping?.call(looping);
  }

  @override
  Future<void> setVolume(double volume) async {
    events.add('volume:$volume');
    await onSetVolume?.call(volume);
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    await onStop?.call();
  }
}
