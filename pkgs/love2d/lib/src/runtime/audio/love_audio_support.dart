part of '../love_runtime.dart';

/// The valid LOVE audio source type names.
const Set<String> loveAudioSourceTypes = <String>{'static', 'stream', 'queue'};

/// The valid LOVE audio time unit names.
const Set<String> loveAudioTimeUnits = <String>{'seconds', 'samples'};

/// The valid LOVE distance model names.
const Set<String> loveAudioDistanceModels = <String>{
  'none',
  'inverse',
  'inverseclamped',
  'linear',
  'linearclamped',
  'exponent',
  'exponentclamped',
};

/// The maximum supported attenuation distance for positional audio.
const double loveAudioMaxAttenuationDistance = 1000000.0;

/// The default number of queued buffers for queueable audio sources.
const int loveAudioDefaultQueueBufferCount = 8;

/// The maximum number of queued buffers for queueable audio sources.
const int loveAudioMaxQueueBufferCount = 64;

/// Creates an audio backend for a resolved source and playback metadata.
typedef LoveAudioBackendFactory =
    Future<LoveAudioSourceBackend> Function(
      String source, {
      required String sourceType,
      Uint8List? bytes,
      String? mimeType,
    });

/// Playback backend contract for one LOVE audio source.
abstract interface class LoveAudioSourceBackend {
  /// Starts or resumes playback.
  Future<void> play();

  /// Pauses playback without discarding backend state.
  Future<void> pause();

  /// Seeks playback to [position].
  Future<void> seek(Duration position);

  /// Stops playback and resets the backend to its stopped state.
  Future<void> stop();

  /// Enables or disables looping playback.
  Future<void> setLooping(bool looping);

  /// Sets the output [volume] in LOVE's normalized range.
  Future<void> setVolume(double volume);

  /// Releases any native resources held by the backend.
  Future<void> dispose();
}

/// Silent fallback backend used when no real audio backend is available.
class LoveNoopAudioSourceBackend implements LoveAudioSourceBackend {
  /// Creates a no-op audio backend.
  const LoveNoopAudioSourceBackend();

  @override
  /// Does nothing because no backend resources are allocated.
  Future<void> dispose() async {}

  @override
  /// Does nothing because playback is never started.
  Future<void> pause() async {}

  @override
  /// Does nothing because no audio is produced.
  Future<void> play() async {}

  @override
  /// Does nothing because no playback position is tracked.
  Future<void> seek(Duration position) async {}

  @override
  /// Does nothing because looping state is not tracked.
  Future<void> setLooping(bool looping) async {}

  @override
  /// Does nothing because output volume is not applied.
  Future<void> setVolume(double volume) async {}

  @override
  /// Does nothing because playback never starts.
  Future<void> stop() async {}
}

/// Mutable LOVE audio source state plus backend playback integration.
class LoveAudioSource {
  /// Creates an audio source with playback metadata, spatial state, and backend
  /// integration.
  LoveAudioSource({
    required this.sourceType,
    this.source,
    this.filename,
    this.durationSeconds = -1.0,
    this.durationSamples = -1,
    this.sampleRate = 0,
    this.bitDepth = 0,
    this.channelCount = 2,
    this.queueBufferCount = 0,
    this.volume = 1.0,
    this.pitch = 1.0,
    this.minVolume = 0.0,
    this.maxVolume = 1.0,
    this.referenceDistance = 1.0,
    this.maxDistance = loveAudioMaxAttenuationDistance,
    this.airAbsorption = 0.0,
    this.rolloff = 1.0,
    this.relative = false,
    this.looping = false,
    this.coneInnerAngle = math.pi * 2.0,
    this.coneOuterAngle = math.pi * 2.0,
    this.coneOuterVolume = 0.0,
    this.coneOuterHighGain = 1.0,
    LoveAudioSourceBackend? backend,
    LoveAudioSourceEffectState? effectState,
    Uint8List? bytes,
    this.mimeType,
    Vector3? position,
    Vector3? velocity,
    Vector3? direction,
  }) : _backend = backend ?? const LoveNoopAudioSourceBackend(),
       effectState = effectState ?? LoveAudioSourceEffectState(),
       bytes = bytes == null ? null : Uint8List.fromList(bytes),
       position = position ?? Vector3.zero(),
       velocity = velocity ?? Vector3.zero(),
       direction = direction ?? Vector3.zero();

  /// The LOVE source type, such as `static`, `stream`, or `queue`.
  final String sourceType;

  /// The logical source identifier passed to the backend, if any.
  final String? source;

  /// The original filename when this source came from the filesystem.
  final String? filename;

  /// The in-memory audio payload, when one was provided directly.
  final Uint8List? bytes;

  /// The detected MIME type for [bytes], when it can be inferred.
  final String? mimeType;

  /// The backend that performs actual playback operations.
  final LoveAudioSourceBackend _backend;

  /// The per-source effect and filter state.
  final LoveAudioSourceEffectState effectState;

  /// The source duration in seconds, or a negative sentinel when unknown.
  double durationSeconds;

  /// The source duration in samples, or a negative sentinel when unknown.
  int durationSamples;

  /// The playback sample rate in hertz.
  int sampleRate;

  /// The source bit depth.
  int bitDepth;

  /// The number of audio channels in the source.
  int channelCount;

  /// The configured queue buffer capacity for queueable sources.
  int queueBufferCount;

  /// The current playback volume.
  double volume;

  /// The requested playback pitch multiplier.
  double pitch;

  /// The minimum volume used by distance attenuation.
  double minVolume;

  /// The maximum volume used by distance attenuation.
  double maxVolume;

  /// The reference distance used by positional attenuation.
  double referenceDistance;

  /// The maximum attenuation distance for positional playback.
  double maxDistance;

  /// The air absorption factor for positional playback.
  double airAbsorption;

  /// The rolloff factor for positional attenuation.
  double rolloff;

  /// Whether the source position is relative to the listener.
  bool relative;

  /// Whether playback should loop automatically.
  bool looping;

  /// The inner cone angle in radians for directional attenuation.
  double coneInnerAngle;

  /// The outer cone angle in radians for directional attenuation.
  double coneOuterAngle;

  /// The outer cone volume multiplier.
  double coneOuterVolume;

  /// The outer cone high-frequency gain multiplier.
  double coneOuterHighGain;

  /// Whether the backend is currently playing this source.
  bool playing = false;

  /// Whether playback is currently paused.
  bool paused = false;

  /// The current playback offset in seconds.
  double offsetSeconds = 0.0;

  /// The current playback offset in samples.
  int offsetSamples = 0;

  /// The current source position in listener space.
  Vector3 position;

  /// The current source velocity in listener space.
  Vector3 velocity;

  /// The current source direction in listener space.
  Vector3 direction;

  /// The queued `SoundData` buffers waiting to be consumed by queue sources.
  final ListQueue<LoveSoundData> _queuedBuffers = ListQueue<LoveSoundData>();

  /// Local playback timer used to estimate current position between backend calls.
  final Stopwatch _playbackClock = Stopwatch();

  /// Whether this source has started disposing its backend.
  bool _disposed = false;

  /// The in-flight dispose action, when teardown has already begun.
  Future<void>? _disposeAction;

  /// A copy of this source with duplicated effect state and spatial metadata.
  LoveAudioSource clone() {
    return LoveAudioSource(
      sourceType: sourceType,
      source: source,
      filename: filename,
      durationSeconds: sourceType == 'queue' ? 0.0 : durationSeconds,
      durationSamples: sourceType == 'queue' ? 0 : durationSamples,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channelCount: channelCount,
      queueBufferCount: queueBufferCount,
      volume: volume,
      pitch: pitch,
      minVolume: minVolume,
      maxVolume: maxVolume,
      referenceDistance: referenceDistance,
      maxDistance: maxDistance,
      airAbsorption: airAbsorption,
      rolloff: rolloff,
      relative: relative,
      looping: looping,
      coneInnerAngle: coneInnerAngle,
      coneOuterAngle: coneOuterAngle,
      coneOuterVolume: coneOuterVolume,
      coneOuterHighGain: coneOuterHighGain,
      effectState: effectState.clone(),
      bytes: bytes,
      mimeType: mimeType,
      position: Vector3.copy(position),
      velocity: Vector3.copy(velocity),
      direction: Vector3.copy(direction),
    );
  }

  /// Starts or resumes playback from the current offset.
  Future<bool> play() async {
    if (_disposed) {
      return false;
    }

    _refreshPlaybackState();
    if (sourceType == 'queue' && _queuedBuffers.isEmpty) {
      playing = false;
      paused = false;
      _playbackClock
        ..stop()
        ..reset();
      return false;
    }

    if (!paused && !_hasPlayableOffset) {
      offsetSeconds = 0.0;
      offsetSamples = 0;
    }

    await _backend.setLooping(looping);
    await _backend.setVolume(volume);
    await _backend.seek(_positionDuration);
    await _backend.play();
    if (_disposed) {
      return false;
    }
    playing = true;
    paused = false;
    _playbackClock
      ..reset()
      ..start();
    return true;
  }

  /// Pauses playback while preserving the current offset.
  Future<void> pause() async {
    if (_disposed) {
      return;
    }

    if (!isPlayingNow) {
      return;
    }

    _syncOffsetsFromClock();
    _playbackClock
      ..stop()
      ..reset();
    await _backend.pause();
    playing = false;
    paused = true;
  }

  /// Stops playback and resets offsets.
  ///
  /// Queueable sources also clear their queued buffers and reset queued
  /// duration metadata.
  Future<void> stop() async {
    if (_disposed) {
      return;
    }

    await _backend.stop();
    _playbackClock
      ..stop()
      ..reset();
    playing = false;
    paused = false;
    offsetSeconds = 0.0;
    offsetSamples = 0;
    if (sourceType == 'queue') {
      _queuedBuffers.clear();
      durationSeconds = 0.0;
      durationSamples = 0;
    }
  }

  /// Updates whether playback should loop.
  Future<void> setLooping(bool value) async {
    if (_disposed) {
      return;
    }

    if (sourceType == 'queue' && value) {
      throw ArgumentError('Queueable Sources can not be looped.');
    }
    looping = value;
    await _backend.setLooping(value);
  }

  /// Updates the playback volume.
  Future<void> setVolume(double value) async {
    if (_disposed) {
      return;
    }

    volume = value;
    await _backend.setVolume(value);
  }

  /// Releases backend resources associated with this source.
  Future<void> dispose() {
    final existingDispose = _disposeAction;
    if (existingDispose != null) {
      return existingDispose;
    }

    if (_disposed) {
      return Future<void>.value();
    }

    _disposed = true;
    if (playing) {
      _syncOffsetsFromClock();
    }
    _playbackClock
      ..stop()
      ..reset();
    playing = false;
    paused = false;

    final action = _backend.dispose();
    _disposeAction = action;
    return action;
  }

  /// The current playback offset in the requested [unit].
  double tell([String unit = 'seconds']) {
    _refreshPlaybackState();
    return switch (unit) {
      'samples' => _currentOffsetSamples.toDouble(),
      _ => _currentOffsetSeconds,
    };
  }

  /// The source duration in the requested [unit], or `-1.0` when unknown.
  double getDuration([String unit = 'seconds']) {
    if (durationSeconds < 0.0 && durationSamples < 0) {
      return -1.0;
    }

    return switch (unit) {
      'samples' =>
        durationSamples >= 0
            ? durationSamples.toDouble()
            : (sampleRate > 0 && durationSeconds >= 0.0
                  ? durationSeconds * sampleRate
                  : -1.0),
      _ => durationSeconds,
    };
  }

  /// Seeks to [offset] in the requested [unit].
  Future<void> seek(double offset, {String unit = 'seconds'}) async {
    if (_disposed) {
      return;
    }

    if (offset < 0.0) {
      throw ArgumentError("can't seek to a negative position");
    }

    _refreshPlaybackState();
    if (unit == 'samples') {
      offsetSamples = offset.floor();
      if (durationSamples >= 0) {
        offsetSamples = offsetSamples.clamp(0, durationSamples);
      }
      if (sampleRate > 0) {
        offsetSeconds = offsetSamples / sampleRate;
      }
      await _backend.seek(_positionDuration);
      if (playing) {
        _playbackClock
          ..reset()
          ..start();
      }
      return;
    }

    offsetSeconds = offset;
    if (durationSeconds >= 0.0) {
      offsetSeconds = offsetSeconds.clamp(0.0, durationSeconds);
    }
    if (sampleRate > 0) {
      offsetSamples = (offsetSeconds * sampleRate).floor();
      if (durationSamples >= 0) {
        offsetSamples = offsetSamples.clamp(0, durationSamples);
      }
    }
    await _backend.seek(_positionDuration);
    if (playing) {
      _playbackClock
        ..reset()
        ..start();
    }
  }

  /// Whether this source is currently playing after refreshing derived state.
  bool get isPlayingNow {
    if (_disposed) {
      return false;
    }

    _refreshPlaybackState();
    return playing;
  }

  /// The number of additional `SoundData` buffers a queue source can accept.
  int get freeBufferCount {
    if (sourceType != 'queue') {
      return 0;
    }
    return math.max(0, queueBufferCount - _queuedBuffers.length);
  }

  /// Queues [data] for playback on a queueable source.
  ///
  /// Returns `false` when no queue slots remain.
  bool queueSoundData(LoveSoundData data) {
    if (sourceType != 'queue') {
      throw ArgumentError(
        'Only queueable Sources can be queued with sound data.',
      );
    }
    if (data.sampleRate != sampleRate ||
        data.bitDepth != bitDepth ||
        data.channels != channelCount) {
      throw ArgumentError(
        'Queued sound data must have same format as sound Source.',
      );
    }
    if (freeBufferCount <= 0) {
      return false;
    }

    final queued = data.clone();
    _queuedBuffers.addLast(queued);
    durationSamples += queued.sampleCount;
    if (sampleRate > 0) {
      durationSeconds = durationSamples / sampleRate;
    }
    return true;
  }

  /// The current playback position as a backend [Duration].
  Duration get _positionDuration => Duration(
    microseconds: (_currentOffsetSeconds * Duration.microsecondsPerSecond)
        .round(),
  );

  /// The effective duration in seconds derived from known metadata.
  double get _effectiveDurationSeconds {
    if (durationSeconds >= 0.0) {
      return durationSeconds;
    }
    if (durationSamples >= 0 && sampleRate > 0) {
      return durationSamples / sampleRate;
    }
    return -1.0;
  }

  /// Whether the current offsets still point at playable content.
  bool get _hasPlayableOffset {
    final duration = _effectiveDurationSeconds;
    if (duration < 0.0) {
      return true;
    }
    return offsetSeconds < duration;
  }

  /// The current playback offset in seconds, including clocked playback time.
  double get _currentOffsetSeconds {
    final duration = _effectiveDurationSeconds;
    final elapsed = playing
        ? _playbackClock.elapsedMicroseconds / Duration.microsecondsPerSecond
        : 0.0;
    final current = offsetSeconds + elapsed;
    if (duration < 0.0) {
      return current;
    }
    if (looping && duration > 0.0) {
      return current % duration;
    }
    return current.clamp(0.0, duration);
  }

  /// The current playback offset in samples.
  int get _currentOffsetSamples {
    if (sampleRate > 0) {
      final current = (_currentOffsetSeconds * sampleRate).floor();
      if (durationSamples >= 0) {
        return current.clamp(0, durationSamples);
      }
      return current;
    }
    return offsetSamples;
  }

  /// Updates derived playback flags when non-looping playback reaches the end.
  void _refreshPlaybackState() {
    if (!playing) {
      return;
    }

    final duration = _effectiveDurationSeconds;
    if (duration < 0.0 || looping) {
      return;
    }
    final current =
        offsetSeconds +
        _playbackClock.elapsedMicroseconds / Duration.microsecondsPerSecond;
    if (current < duration) {
      return;
    }

    offsetSeconds = duration;
    if (sampleRate > 0) {
      offsetSamples = durationSamples >= 0
          ? durationSamples
          : (duration * sampleRate).floor();
    }
    playing = false;
    paused = false;
    _playbackClock
      ..stop()
      ..reset();
  }

  /// Copies the clock-derived playback position back into persisted offsets.
  void _syncOffsetsFromClock() {
    offsetSeconds = _currentOffsetSeconds;
    if (sampleRate > 0) {
      offsetSamples = _currentOffsetSamples;
    }
  }
}

/// Playback state captured before a batched `love.audio.play` attempt.
class _LoveAudioPlaybackSnapshot {
  _LoveAudioPlaybackSnapshot.capture(LoveAudioSource source)
    : wasPlaying = source.isPlayingNow,
      wasPaused = source.paused,
      offsetSeconds = source.tell(),
      offsetSamples = source.tell('samples').round();

  /// Whether the source was already actively playing.
  final bool wasPlaying;

  /// Whether the source was paused before playback was attempted.
  final bool wasPaused;

  /// The persisted offset in seconds before playback was attempted.
  final double offsetSeconds;

  /// The persisted offset in samples before playback was attempted.
  final int offsetSamples;

  /// Restores [source] to the state captured by this snapshot.
  Future<void> restore(LoveAudioSource source) async {
    if (source._disposed || wasPlaying) {
      return;
    }

    await source._backend.stop();
    source._playbackClock
      ..stop()
      ..reset();
    source.playing = false;
    source.paused = wasPaused;
    source.offsetSeconds = offsetSeconds;
    source.offsetSamples = offsetSamples;
    await source._backend.seek(source._positionDuration);
  }
}

/// Global LOVE audio state including listener properties and active sources.
class LoveAudioState {
  /// The global audio volume.
  double volume = 1.0;

  /// The current distance attenuation model.
  String distanceModel = 'inverseclamped';

  /// The Doppler effect scale multiplier.
  double dopplerScale = 1.0;

  /// Whether audio should mix with system output instead of interrupting it.
  bool mixWithSystem = false;

  /// The listener position in world space.
  Vector3 position = Vector3.zero();

  /// The listener velocity in world space.
  Vector3 velocity = Vector3.zero();

  /// The listener forward orientation vector.
  Vector3 orientationForward = Vector3(0, 0, -1);

  /// The listener up orientation vector.
  Vector3 orientationUp = Vector3(0, 1, 0);

  /// The active scene-wide audio effects.
  final LoveAudioSceneEffectState effects = LoveAudioSceneEffectState();

  /// All sources created or tracked by this audio state.
  final Set<LoveAudioSource> _sources = <LoveAudioSource>{};

  /// The recording devices available to this runtime.
  final List<LoveRecordingDevice> recordingDevices = <LoveRecordingDevice>[];

  /// Creates, tracks, and returns a new audio source.
  LoveAudioSource newSource({
    required String sourceType,
    String? source,
    String? filename,
    LoveAudioSourceBackend? backend,
    Uint8List? bytes,
    String? mimeType,
    double durationSeconds = -1.0,
    int durationSamples = -1,
    int sampleRate = 0,
    int bitDepth = 0,
    int channelCount = 2,
    int queueBufferCount = 0,
  }) {
    final resolvedSourceType = loveAudioSourceTypes.contains(sourceType)
        ? sourceType
        : 'static';
    final audioSource = LoveAudioSource(
      sourceType: resolvedSourceType,
      source: source ?? filename,
      filename: filename ?? source,
      durationSeconds: durationSeconds,
      durationSamples: durationSamples,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channelCount: channelCount,
      queueBufferCount: queueBufferCount,
      backend: backend,
      bytes: bytes,
      mimeType: mimeType ?? loveAudioMimeTypeFromFilename(filename ?? source),
    );
    _sources.add(audioSource);
    return audioSource;
  }

  /// The number of currently playing tracked sources.
  int get activeSourceCount =>
      _sources.where((source) => source.isPlayingNow).length;

  /// Pauses the provided [sources], or every currently playing tracked source.
  Future<List<LoveAudioSource>> pause([
    Iterable<LoveAudioSource>? sources,
  ]) async {
    final targets = (sources ?? _sources.where((source) => source.isPlayingNow))
        .toList(growable: false);
    for (final source in targets) {
      await source.pause();
    }
    return targets;
  }

  /// Starts playback for [sources] and tracks them in this state.
  ///
  /// Returns `false` when any requested source can not be started.
  Future<bool> play(Iterable<LoveAudioSource> sources) async {
    final targets = sources.toList(growable: false);
    if (targets.isEmpty) {
      return true;
    }

    final snapshots = targets
        .map(_LoveAudioPlaybackSnapshot.capture)
        .toList(growable: false);
    for (var index = 0; index < targets.length; index++) {
      final source = targets[index];
      _sources.add(source);
      final started = await source.play();
      if (started) {
        continue;
      }

      for (var rollbackIndex = 0; rollbackIndex < index; rollbackIndex++) {
        await snapshots[rollbackIndex].restore(targets[rollbackIndex]);
      }
      return false;
    }
    return true;
  }

  /// Stops the provided [sources], or every tracked source when omitted.
  Future<List<LoveAudioSource>> stop([
    Iterable<LoveAudioSource>? sources,
  ]) async {
    final targets = (sources ?? _sources.toList(growable: false)).toList(
      growable: false,
    );
    for (final source in targets) {
      await source.stop();
    }
    return targets;
  }
}

/// Returns the MIME type implied by [filename], if it is recognized.
String? loveAudioMimeTypeFromFilename(String? filename) {
  if (filename == null || !filename.contains('.')) {
    return null;
  }

  final extension = filename
      .substring(filename.lastIndexOf('.') + 1)
      .toLowerCase();
  return switch (extension) {
    'aac' => 'audio/aac',
    'flac' => 'audio/flac',
    'm4a' => 'audio/mp4',
    'mp3' => 'audio/mpeg',
    'ogg' => 'audio/ogg',
    'wav' => 'audio/wav',
    _ => null,
  };
}
