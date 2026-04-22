library;

import 'dart:typed_data';

import 'package:media_kit/media_kit.dart' as media_kit;

import '../love_runtime.dart';
import '../video/love_media_kit_video_frame_provider.dart'
    show LoveMediaKitInitializer, ensureLoveMediaKitInitialized;

/// An audio backend that drives LOVE sources through `media_kit`.
final class LoveFlameMediaKitAudioSourceBackend
    implements LoveAudioSourceBackend {
  /// Creates a backend backed by an initialized `media_kit` [Player].
  LoveFlameMediaKitAudioSourceBackend._({
    required Future<void> Function() disposePlayer,
    required Future<void> Function() pausePlayer,
    required Future<void> Function() playPlayer,
    required Future<void> Function(Duration position) seekPlayer,
    required Future<void> Function(bool looping) setLoopingPlayer,
    required Future<void> Function(double volume) setVolumePlayer,
    required Future<void> Function() stopPlayer,
  }) : _disposePlayer = disposePlayer,
       _pausePlayer = pausePlayer,
       _playPlayer = playPlayer,
       _seekPlayer = seekPlayer,
       _setLoopingPlayer = setLoopingPlayer,
       _setVolumePlayer = setVolumePlayer,
       _stopPlayer = stopPlayer;

  /// Opens a media-kit audio backend for [source] or in-memory [bytes].
  ///
  /// When [initializer] is omitted, this uses
  /// [ensureLoveMediaKitInitialized] before creating the player.
  static Future<LoveFlameMediaKitAudioSourceBackend> open({
    required String source,
    Uint8List? bytes,
    String? mimeType,
    LoveMediaKitInitializer? initializer,
  }) async {
    final resolvedInitializer = initializer ?? ensureLoveMediaKitInitialized;
    await resolvedInitializer();

    final player = media_kit.Player(
      configuration: const media_kit.PlayerConfiguration(
        title: 'LuaLike LOVE stream audio',
      ),
    );
    try {
      final playable = bytes == null
          ? media_kit.Media(source)
          : await media_kit.Media.memory(bytes, type: mimeType);
      await player.open(playable, play: false);
      return LoveFlameMediaKitAudioSourceBackend._(
        disposePlayer: player.dispose,
        pausePlayer: player.pause,
        playPlayer: player.play,
        seekPlayer: player.seek,
        setLoopingPlayer: (looping) => player.setPlaylistMode(
          looping ? media_kit.PlaylistMode.single : media_kit.PlaylistMode.none,
        ),
        setVolumePlayer: (volume) => player.setVolume(volume * 100.0),
        stopPlayer: () async {
          await player.pause();
          await player.seek(Duration.zero);
        },
      );
    } catch (_) {
      await player.dispose();
      rethrow;
    }
  }

  /// Returns a controllable test backend that delegates to the supplied hooks.
  static LoveFlameMediaKitAudioSourceBackend test({
    Future<void> Function()? play,
    Future<void> Function()? pause,
    Future<void> Function()? stop,
    Future<void> Function(bool looping)? setLooping,
    Future<void> Function(Duration position)? seek,
    Future<void> Function(double volume)? setVolume,
    Future<void> Function()? dispose,
  }) {
    return LoveFlameMediaKitAudioSourceBackend._(
      disposePlayer: dispose ?? () async {},
      pausePlayer: pause ?? () async {},
      playPlayer: play ?? () async {},
      seekPlayer: seek ?? (_) async {},
      setLoopingPlayer: setLooping ?? (_) async {},
      setVolumePlayer: setVolume ?? (_) async {},
      stopPlayer: stop ?? () async {},
    );
  }

  /// Releases the underlying media-kit player.
  final Future<void> Function() _disposePlayer;

  /// Pauses playback without resetting position.
  final Future<void> Function() _pausePlayer;

  /// Starts or resumes playback.
  final Future<void> Function() _playPlayer;

  /// Seeks playback to the requested position.
  final Future<void> Function(Duration position) _seekPlayer;

  /// Enables or disables single-item looping.
  final Future<void> Function(bool looping) _setLoopingPlayer;

  /// Applies the requested normalized volume.
  final Future<void> Function(double volume) _setVolumePlayer;

  /// Stops playback and rewinds to the start of the item.
  final Future<void> Function() _stopPlayer;

  /// Whether the backend has begun disposal.
  bool _disposed = false;

  /// The in-flight disposal action, if teardown has already started.
  Future<void>? _disposeAction;

  @override
  /// Releases the underlying media-kit player.
  Future<void> dispose() {
    final existingDispose = _disposeAction;
    if (existingDispose != null) {
      return existingDispose;
    }

    if (_disposed) {
      return Future<void>.value();
    }

    _disposed = true;
    final action = _disposePlayer();
    _disposeAction = action;
    return action;
  }

  @override
  /// Pauses playback without resetting the current position.
  Future<void> pause() async {
    if (_disposed) {
      return;
    }
    await _pausePlayer();
  }

  @override
  /// Starts or resumes playback.
  Future<void> play() async {
    if (_disposed) {
      return;
    }
    await _playPlayer();
  }

  @override
  /// Seeks playback to [position].
  Future<void> seek(Duration position) async {
    if (_disposed) {
      return;
    }
    await _seekPlayer(position);
  }

  @override
  /// Sets whether playback should loop the current item.
  Future<void> setLooping(bool looping) async {
    if (_disposed) {
      return;
    }
    await _setLoopingPlayer(looping);
  }

  @override
  /// Sets the playback volume using LOVE's normalized `0.0` to `1.0` scale.
  Future<void> setVolume(double volume) async {
    if (_disposed) {
      return;
    }
    await _setVolumePlayer(volume);
  }

  @override
  /// Stops playback and rewinds to the start of the media item.
  Future<void> stop() async {
    if (_disposed) {
      return;
    }
    await _stopPlayer();
  }
}
