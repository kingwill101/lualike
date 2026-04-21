part of '../love_runtime.dart';

abstract interface class LoveVideoFrameSync {
  FutureOr<void> play();
  FutureOr<void> pause();
  FutureOr<void> seek(double offset);
  double tell();
  bool isPlaying();
}

final class LoveVideoDeltaSync implements LoveVideoFrameSync {
  final Stopwatch _clock = Stopwatch();
  double _position = 0.0;
  bool _playing = false;

  @override
  Future<void> play() async {
    if (_playing) {
      return;
    }

    _playing = true;
    _clock.start();
  }

  @override
  Future<void> pause() async {
    if (!_playing) {
      return;
    }

    _position = tell();
    _playing = false;
    _clock
      ..stop()
      ..reset();
  }

  @override
  Future<void> seek(double offset) async {
    _position = offset;
    if (_playing) {
      _clock
        ..reset()
        ..start();
    } else {
      _clock.reset();
    }
  }

  @override
  double tell() {
    if (!_playing) {
      return _position;
    }

    return _position + _clock.elapsedMicroseconds / Duration.microsecondsPerSecond;
  }

  @override
  bool isPlaying() => _playing;

  Future<void> copyStateFrom(LoveVideoFrameSync other) async {
    await seek(other.tell());
    if (other.isPlaying()) {
      await play();
    } else {
      await pause();
    }
  }
}

final class LoveVideoSourceSync implements LoveVideoFrameSync {
  LoveVideoSourceSync(this.source);

  final LoveAudioSource source;

  @override
  Future<void> play() => source.play().then((_) => null);

  @override
  Future<void> pause() => source.pause();

  @override
  Future<void> seek(double offset) async {
    source.seek(offset, unit: 'seconds');
  }

  @override
  double tell() => source.tell('seconds');

  @override
  bool isPlaying() => source.playing;
}

final class LoveVideoStream {
  LoveVideoStream({
    required this.filename,
    Uint8List? bytes,
    LoveVideoFrameSync? sync,
  }) : bytes = bytes == null ? null : Uint8List.fromList(bytes),
       _sync = sync ?? LoveVideoDeltaSync();

  final String filename;
  final Uint8List? bytes;
  LoveVideoFrameSync _sync;

  Future<void> play() async {
    await _sync.play();
  }

  Future<void> pause() async {
    await _sync.pause();
  }

  Future<void> seek(double offset) async {
    await _sync.seek(offset);
  }

  Future<void> rewind() => seek(0.0);

  double tell() => _sync.tell();

  bool isPlaying() => _sync.isPlaying();

  void setSyncFromSource(LoveAudioSource source) {
    _sync = LoveVideoSourceSync(source);
  }

  void setSyncFromStream(LoveVideoStream other) {
    _sync = other._sync;
  }

  Future<void> setIndependentSync() async {
    final sync = LoveVideoDeltaSync();
    await sync.copyStateFrom(_sync);
    _sync = sync;
  }
}
