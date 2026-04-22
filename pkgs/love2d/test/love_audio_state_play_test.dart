import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LoveAudioState.play', () {
    test(
      'returns false and rolls back earlier sources when a later source is disposed',
      () async {
        final firstBackend = _RecordingAudioBackend();
        final secondBackend = _RecordingAudioBackend();
        final audio = LoveAudioState();

        final first = audio.newSource(
          sourceType: 'static',
          backend: firstBackend,
          durationSeconds: 1.0,
          durationSamples: 22050,
          sampleRate: 22050,
          bitDepth: 16,
          channelCount: 2,
        );
        final second = audio.newSource(
          sourceType: 'static',
          backend: secondBackend,
          durationSeconds: 1.0,
          durationSamples: 22050,
          sampleRate: 22050,
          bitDepth: 16,
          channelCount: 2,
        );

        await second.dispose();

        expect(await audio.play(<LoveAudioSource>[first, second]), isFalse);
        expect(first.isPlayingNow, isFalse);
        expect(first.paused, isFalse);
        expect(first.tell(), closeTo(0.0, 1e-12));
        expect(firstBackend.playCalls, 1);
        expect(firstBackend.stopCalls, 1);
        expect(firstBackend.seekOffsets, isNotEmpty);
        expect(firstBackend.seekOffsets.last, equals(Duration.zero));
      },
    );
  });
}

final class _RecordingAudioBackend implements LoveAudioSourceBackend {
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  final List<Duration> seekOffsets = <Duration>[];

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> seek(Duration position) async {
    seekOffsets.add(position);
  }

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}
