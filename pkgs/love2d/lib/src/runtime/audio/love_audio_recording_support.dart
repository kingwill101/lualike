part of '../love_runtime.dart';

typedef LoveRecordingDeviceStartHandler =
    bool Function(
      LoveRecordingDevice device, {
      required int samples,
      required int sampleRate,
      required int bitDepth,
      required int channels,
    });
typedef LoveRecordingDeviceDataHandler =
    LoveSoundData? Function(LoveRecordingDevice device);

class LoveRecordingDevice {
  LoveRecordingDevice({
    this.name = 'null',
    this.sampleCount = 0,
    this.maxSamples = 0,
    this.sampleRate = 0,
    this.bitDepth = 0,
    this.channelCount = 0,
    LoveRecordingDeviceStartHandler? onStart,
    LoveRecordingDeviceDataHandler? onGetData,
    LoveRecordingDeviceDataHandler? onStop,
  }) : _onStart = onStart,
       _onGetData = onGetData,
       _onStop = onStop;

  static const int defaultSamples = 8192;
  static const int defaultSampleRate = 8000;
  static const int defaultBitDepth = 16;
  static const int defaultChannels = 1;

  String name;
  int sampleCount;
  int maxSamples;
  int sampleRate;
  int bitDepth;
  int channelCount;
  bool recording = false;

  final LoveRecordingDeviceStartHandler? _onStart;
  final LoveRecordingDeviceDataHandler? _onGetData;
  final LoveRecordingDeviceDataHandler? _onStop;

  bool start({
    required int samples,
    required int sampleRate,
    required int bitDepth,
    required int channels,
  }) {
    final success =
        _onStart?.call(
          this,
          samples: samples,
          sampleRate: sampleRate,
          bitDepth: bitDepth,
          channels: channels,
        ) ??
        false;
    if (!success) {
      recording = false;
      return false;
    }

    maxSamples = samples;
    this.sampleRate = sampleRate;
    this.bitDepth = bitDepth;
    channelCount = channels;
    recording = true;
    return true;
  }

  LoveSoundData? getData() {
    if (!recording) {
      return null;
    }

    final data = _onGetData?.call(this);
    if (data != null) {
      sampleCount = data.sampleCount;
    }
    return data;
  }

  LoveSoundData? stop() {
    final data = _onStop?.call(this);
    recording = false;
    if (data != null) {
      sampleCount = data.sampleCount;
    }
    return data;
  }
}
