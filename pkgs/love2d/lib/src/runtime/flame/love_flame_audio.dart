library;

import 'dart:typed_data' show Uint8List;

import 'package:audioplayers/audioplayers.dart';

import '../love_runtime.dart';

class LoveFlutterAudioSourceBackend implements LoveAudioSourceBackend {
  LoveFlutterAudioSourceBackend({required Uint8List bytes, String? mimeType})
    : _bytes = Uint8List.fromList(bytes),
      _mimeType = mimeType;

  final Uint8List _bytes;
  final String? _mimeType;
  final AudioPlayer _player = AudioPlayer();
  bool _prepared = false;

  @override
  Future<void> dispose() async {
    await _player.dispose();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> play() async {
    await _ensurePrepared();
    await _player.resume();
  }

  @override
  Future<void> setLooping(bool looping) async {
    await _player.setReleaseMode(
      looping ? ReleaseMode.loop : ReleaseMode.stop,
    );
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> _ensurePrepared() async {
    if (_prepared) {
      return;
    }

    await _player.setSource(BytesSource(_bytes, mimeType: _mimeType));
    _prepared = true;
  }
}
