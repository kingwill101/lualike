part of '../love_runtime.dart';

const Set<String> loveAudioSourceTypes = <String>{'static', 'stream', 'queue'};
const Set<String> loveAudioTimeUnits = <String>{'seconds', 'samples'};
const Set<String> loveAudioDistanceModels = <String>{
  'none',
  'inverse',
  'inverseclamped',
  'linear',
  'linearclamped',
  'exponent',
  'exponentclamped',
};
const double loveAudioMaxAttenuationDistance = 1000000.0;
const int loveAudioDefaultQueueBufferCount = 8;
const int loveAudioMaxQueueBufferCount = 64;

typedef LoveAudioBackendFactory =
    Future<LoveAudioSourceBackend> Function(
      String source, {
      required String sourceType,
      Uint8List? bytes,
      String? mimeType,
    });

abstract interface class LoveAudioSourceBackend {
  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> setLooping(bool looping);

  Future<void> dispose();
}

class LoveNoopAudioSourceBackend implements LoveAudioSourceBackend {
  const LoveNoopAudioSourceBackend();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> stop() async {}
}

class LoveAudioSource {
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

  final String sourceType;
  final String? source;
  final String? filename;
  final Uint8List? bytes;
  final String? mimeType;

  final LoveAudioSourceBackend _backend;
  final LoveAudioSourceEffectState effectState;

  double durationSeconds;
  int durationSamples;
  int sampleRate;
  int bitDepth;
  int channelCount;
  int queueBufferCount;
  double volume;
  double pitch;
  double minVolume;
  double maxVolume;
  double referenceDistance;
  double maxDistance;
  double airAbsorption;
  double rolloff;
  bool relative;
  bool looping;
  double coneInnerAngle;
  double coneOuterAngle;
  double coneOuterVolume;
  double coneOuterHighGain;
  bool playing = false;
  bool paused = false;
  double offsetSeconds = 0.0;
  int offsetSamples = 0;
  Vector3 position;
  Vector3 velocity;
  Vector3 direction;
  final ListQueue<LoveSoundData> _queuedBuffers = ListQueue<LoveSoundData>();

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

  Future<bool> play() async {
    await _backend.setLooping(looping);
    await _backend.play();
    playing = true;
    paused = false;
    return true;
  }

  Future<void> pause() async {
    if (!playing) {
      return;
    }

    await _backend.pause();
    playing = false;
    paused = true;
  }

  Future<void> stop() async {
    await _backend.stop();
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

  Future<void> setLooping(bool value) async {
    if (sourceType == 'queue' && value) {
      throw ArgumentError('Queueable Sources can not be looped.');
    }
    looping = value;
    await _backend.setLooping(value);
  }

  Future<void> dispose() => _backend.dispose();

  double tell([String unit = 'seconds']) {
    return switch (unit) {
      'samples' => offsetSamples.toDouble(),
      _ => offsetSeconds,
    };
  }

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

  void seek(double offset, {String unit = 'seconds'}) {
    if (offset < 0.0) {
      throw ArgumentError("can't seek to a negative position");
    }

    if (unit == 'samples') {
      offsetSamples = offset.floor();
      if (durationSamples >= 0) {
        offsetSamples = offsetSamples.clamp(0, durationSamples);
      }
      if (sampleRate > 0) {
        offsetSeconds = offsetSamples / sampleRate;
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
  }

  int get freeBufferCount {
    if (sourceType != 'queue') {
      return 0;
    }
    return math.max(0, queueBufferCount - _queuedBuffers.length);
  }

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
}

class LoveAudioState {
  double volume = 1.0;
  String distanceModel = 'inverseclamped';
  double dopplerScale = 1.0;
  bool mixWithSystem = false;
  Vector3 position = Vector3.zero();
  Vector3 velocity = Vector3.zero();
  Vector3 orientationForward = Vector3(0, 0, -1);
  Vector3 orientationUp = Vector3(0, 1, 0);
  final LoveAudioSceneEffectState effects = LoveAudioSceneEffectState();
  final Set<LoveAudioSource> _sources = <LoveAudioSource>{};
  final List<LoveRecordingDevice> recordingDevices = <LoveRecordingDevice>[];

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

  int get activeSourceCount =>
      _sources.where((source) => source.playing).length;

  Future<List<LoveAudioSource>> pause([
    Iterable<LoveAudioSource>? sources,
  ]) async {
    final targets = (sources ?? _sources.where((source) => source.playing))
        .toList(growable: false);
    for (final source in targets) {
      await source.pause();
    }
    return targets;
  }

  Future<List<LoveAudioSource>> play(Iterable<LoveAudioSource> sources) async {
    final targets = sources.toList(growable: false);
    for (final source in targets) {
      _sources.add(source);
      await source.play();
    }
    return targets;
  }

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
