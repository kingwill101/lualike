import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LoveAudioSource timing', () {
    test('tell advances while playing and freezes after pause', () async {
      final backend = _RecordingAudioBackend();
      final source = LoveAudioSource(
        sourceType: 'stream',
        durationSeconds: 2.0,
        sampleRate: 1000,
        backend: backend,
      );

      await source.seek(0.25);
      await source.setVolume(0.4);
      await source.play();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final duringPlayback = source.tell();
      expect(duringPlayback, greaterThan(0.27));
      expect(backend.seeks, isNotEmpty);
      expect(backend.seeks.first, const Duration(milliseconds: 250));
      expect(backend.volumes, isNotEmpty);
      expect(backend.volumes.last, closeTo(0.4, 0.0001));

      await source.pause();
      final pausedAt = source.tell();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(source.tell(), closeTo(pausedAt, 0.01));
      expect(source.isPlayingNow, isFalse);
    });

    test(
      'known durations transition out of playing after completion',
      () async {
        final source = LoveAudioSource(
          sourceType: 'stream',
          durationSeconds: 0.03,
          sampleRate: 1000,
          backend: _RecordingAudioBackend(),
        );

        await source.play();
        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(source.isPlayingNow, isFalse);
        expect(source.tell(), closeTo(0.03, 0.01));
      },
    );
  });
}

final class _RecordingAudioBackend implements LoveAudioSourceBackend {
  final List<Duration> seeks = <Duration>[];
  final List<double> volumes = <double>[];

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> stop() async {}
}
