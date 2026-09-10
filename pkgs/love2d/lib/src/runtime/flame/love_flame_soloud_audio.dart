library;

import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import '../love_runtime.dart';

/// Initializes the shared SoLoud engine used by LOVE audio sources.
typedef LoveSoLoudInitializer = Future<void> Function();

Future<void>? _loveSoLoudInitialization;

/// Initializes SoLoud once without disrupting already loaded or playing audio.
Future<void> ensureLoveSoLoudInitialized() {
  final engine = SoLoud.instance;
  if (engine.isInitialized) {
    return Future<void>.value();
  }

  final pending = _loveSoLoudInitialization;
  if (pending != null) {
    return pending;
  }

  final initialization = engine.init();
  _loveSoLoudInitialization = initialization;
  return initialization.whenComplete(() {
    if (identical(_loveSoLoudInitialization, initialization)) {
      _loveSoLoudInitialization = null;
    }
  });
}

/// An audio backend that drives LOVE sources through the shared SoLoud engine.
final class LoveFlameSoLoudAudioSourceBackend
    implements LoveAudioSourceBackend {
  LoveFlameSoLoudAudioSourceBackend._({
    required Future<void> Function() disposeVoice,
    required Future<void> Function() pauseVoice,
    required Future<void> Function() playVoice,
    required Future<void> Function(Duration position) seekVoice,
    required Future<void> Function(bool looping) setLoopingVoice,
    required Future<void> Function(double volume) setVolumeVoice,
    required Future<void> Function() stopVoice,
  }) : _disposeVoice = disposeVoice,
       _pauseVoice = pauseVoice,
       _playVoice = playVoice,
       _seekVoice = seekVoice,
       _setLoopingVoice = setLoopingVoice,
       _setVolumeVoice = setVolumeVoice,
       _stopVoice = stopVoice;

  /// Loads [bytes] into the shared SoLoud engine.
  ///
  /// Static sources are decoded into memory for low-latency playback. Stream
  /// sources retain compressed data and decode it incrementally to reduce their
  /// memory footprint.
  static Future<LoveFlameSoLoudAudioSourceBackend> open({
    required String source,
    required String sourceType,
    required Uint8List bytes,
    LoveSoLoudInitializer? initializer,
  }) async {
    await (initializer ?? ensureLoveSoLoudInitialized)();

    final engine = SoLoud.instance;
    final audioSource = await engine.loadMem(
      source,
      bytes,
      mode: sourceType == 'stream' ? LoadMode.disk : LoadMode.memory,
    );
    final voice = _LoveSoLoudVoice(engine: engine, source: audioSource);
    return LoveFlameSoLoudAudioSourceBackend._(
      disposeVoice: voice.dispose,
      pauseVoice: voice.pause,
      playVoice: voice.play,
      seekVoice: voice.seek,
      setLoopingVoice: voice.setLooping,
      setVolumeVoice: voice.setVolume,
      stopVoice: voice.stop,
    );
  }

  /// Returns a controllable test backend that delegates to supplied hooks.
  static LoveFlameSoLoudAudioSourceBackend test({
    Future<void> Function()? play,
    Future<void> Function()? pause,
    Future<void> Function()? stop,
    Future<void> Function(bool looping)? setLooping,
    Future<void> Function(Duration position)? seek,
    Future<void> Function(double volume)? setVolume,
    Future<void> Function()? dispose,
  }) {
    return LoveFlameSoLoudAudioSourceBackend._(
      disposeVoice: dispose ?? () async {},
      pauseVoice: pause ?? () async {},
      playVoice: play ?? () async {},
      seekVoice: seek ?? (_) async {},
      setLoopingVoice: setLooping ?? (_) async {},
      setVolumeVoice: setVolume ?? (_) async {},
      stopVoice: stop ?? () async {},
    );
  }

  final Future<void> Function() _disposeVoice;
  final Future<void> Function() _pauseVoice;
  final Future<void> Function() _playVoice;
  final Future<void> Function(Duration position) _seekVoice;
  final Future<void> Function(bool looping) _setLoopingVoice;
  final Future<void> Function(double volume) _setVolumeVoice;
  final Future<void> Function() _stopVoice;

  bool _disposed = false;
  Future<void>? _disposeAction;

  @override
  Future<void> dispose() {
    final pending = _disposeAction;
    if (pending != null) {
      return pending;
    }
    if (_disposed) {
      return Future<void>.value();
    }

    _disposed = true;
    final action = _disposeVoice();
    _disposeAction = action;
    return action;
  }

  @override
  Future<void> pause() async {
    if (!_disposed) {
      await _pauseVoice();
    }
  }

  @override
  Future<void> play() async {
    if (!_disposed) {
      await _playVoice();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_disposed) {
      await _seekVoice(position);
    }
  }

  @override
  Future<void> setLooping(bool looping) async {
    if (!_disposed) {
      await _setLoopingVoice(looping);
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    if (!_disposed) {
      await _setVolumeVoice(volume);
    }
  }

  @override
  Future<void> stop() async {
    if (!_disposed) {
      await _stopVoice();
    }
  }
}

final class _LoveSoLoudVoice {
  _LoveSoLoudVoice({required SoLoud engine, required AudioSource source})
    : _engine = engine,
      _source = source;

  final SoLoud _engine;
  final AudioSource _source;

  SoundHandle? _handle;
  Duration _position = Duration.zero;
  double _volume = 1.0;
  bool _looping = false;

  SoundHandle? get _activeHandle {
    final handle = _handle;
    if (!_engine.isInitialized || handle == null || handle.isError) {
      _handle = null;
      return null;
    }
    if (!_engine.getIsValidVoiceHandle(handle)) {
      _handle = null;
      return null;
    }
    return handle;
  }

  Future<void> dispose() async {
    _handle = null;
    if (_engine.isInitialized && _engine.activeSounds.contains(_source)) {
      await _engine.disposeSource(_source);
    }
  }

  Future<void> pause() async {
    final handle = _activeHandle;
    if (handle != null) {
      _engine.setPause(handle, true);
    }
  }

  Future<void> play() async {
    final existingHandle = _activeHandle;
    if (existingHandle != null) {
      _engine.setPause(existingHandle, false);
      return;
    }

    final handle = await _engine.play(
      _source,
      paused: true,
      looping: _looping,
      volume: _volume,
    );
    if (handle.isError || !_engine.getIsValidVoiceHandle(handle)) {
      throw StateError('SoLoud could not create an audio voice for the source');
    }

    _handle = handle;
    if (_position > Duration.zero) {
      _engine.seek(handle, _position);
    }
    _engine.setPause(handle, false);
  }

  Future<void> seek(Duration position) async {
    _position = position.isNegative ? Duration.zero : position;
    final handle = _activeHandle;
    if (handle != null) {
      _engine.seek(handle, _position);
    }
  }

  Future<void> setLooping(bool looping) async {
    _looping = looping;
    final handle = _activeHandle;
    if (handle != null) {
      _engine.setLooping(handle, looping);
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume;
    final handle = _activeHandle;
    if (handle != null) {
      _engine.setVolume(handle, volume);
    }
  }

  Future<void> stop() async {
    _position = Duration.zero;
    final handle = _activeHandle;
    _handle = null;
    if (handle != null) {
      await _engine.stop(handle);
    }
  }
}
