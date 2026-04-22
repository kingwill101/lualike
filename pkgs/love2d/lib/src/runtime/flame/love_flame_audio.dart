library;

import 'dart:typed_data' show Uint8List;

import 'package:audioplayers/audioplayers.dart';

import '../love_runtime.dart';

/// `audioplayers`-backed audio source backend for Flutter runtimes.
class LoveFlutterAudioSourceBackend implements LoveAudioSourceBackend {
  /// Creates a backend that plays in-memory audio [bytes].
  LoveFlutterAudioSourceBackend({required Uint8List bytes, String? mimeType})
    : _bytes = Uint8List.fromList(bytes),
      _mimeType = mimeType;

  /// The copied source bytes used to initialize the player.
  final Uint8List _bytes;

  /// The MIME type passed to the audio player, when known.
  final String? _mimeType;

  /// The underlying Flutter audio player.
  final AudioPlayer _player = AudioPlayer();

  /// Whether [_player] has already been configured with [_bytes].
  bool _prepared = false;

  @override
  /// Releases the underlying player resources.
  Future<void> dispose() async {
    await _player.dispose();
  }

  @override
  /// Pauses playback.
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  /// Starts or resumes playback, preparing the byte source on first use.
  Future<void> play() async {
    await _ensurePrepared();
    await _player.resume();
  }

  @override
  /// Seeks playback to [position], preparing the byte source on first use.
  Future<void> seek(Duration position) async {
    await _ensurePrepared();
    await _player.seek(position);
  }

  @override
  /// Enables or disables looping playback.
  Future<void> setLooping(bool looping) async {
    await _player.setReleaseMode(looping ? ReleaseMode.loop : ReleaseMode.stop);
  }

  @override
  /// Sets the output [volume].
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  @override
  /// Stops playback.
  Future<void> stop() async {
    await _player.stop();
  }

  /// Lazily configures the player with the in-memory byte source.
  Future<void> _ensurePrepared() async {
    if (_prepared) {
      return;
    }

    await _player.setSource(BytesSource(_bytes, mimeType: _mimeType));
    _prepared = true;
  }
}
