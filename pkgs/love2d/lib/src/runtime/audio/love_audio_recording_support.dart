part of '../love_runtime.dart';

/// Starts recording for [device] with the requested capture settings.
typedef LoveRecordingDeviceStartHandler =
    bool Function(
      LoveRecordingDevice device, {
      required int samples,
      required int sampleRate,
      required int bitDepth,
      required int channels,
    });

/// Returns the next captured audio chunk for [device], if any.
typedef LoveRecordingDeviceDataHandler =
    LoveSoundData? Function(LoveRecordingDevice device);

bool _loveRecordingFormatSupported({
  required int bitDepth,
  required int channels,
}) {
  if (bitDepth != 8 && bitDepth != 16) {
    return false;
  }

  return channels == 1 || channels == 2;
}

/// Recording device state used by LOVE audio capture bindings.
class LoveRecordingDevice {
  /// Creates a recording device with optional callbacks and initial state.
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

  /// The default capture buffer size in samples.
  static const int defaultSamples = 8192;

  /// The default capture sample rate in hertz.
  static const int defaultSampleRate = 8000;

  /// The default capture bit depth.
  static const int defaultBitDepth = 16;

  /// The default capture channel count.
  static const int defaultChannels = 1;

  /// The backend-provided device name.
  String name;

  /// The number of captured samples currently buffered in the device.
  int sampleCount;

  /// The maximum sample count requested when recording started.
  int maxSamples;

  /// The current capture sample rate in hertz.
  int sampleRate;

  /// The current capture bit depth.
  int bitDepth;

  /// The current capture channel count.
  int channelCount;

  /// Whether the device is currently recording.
  bool recording = false;

  /// Callback used to start device recording.
  final LoveRecordingDeviceStartHandler? _onStart;

  /// Callback used to read the next captured audio chunk.
  final LoveRecordingDeviceDataHandler? _onGetData;

  /// Callback used to stop recording and perform backend cleanup.
  final LoveRecordingDeviceDataHandler? _onStop;

  /// Starts recording with the requested capture format and buffer size.
  bool start({
    required int samples,
    required int sampleRate,
    required int bitDepth,
    required int channels,
  }) {
    if (!_loveRecordingFormatSupported(
      bitDepth: bitDepth,
      channels: channels,
    )) {
      throw ArgumentError(
        'Recording $channels channels with $bitDepth bits per sample is not supported.',
      );
    }

    if (samples <= 0) {
      throw ArgumentError('Invalid number of samples.');
    }

    if (sampleRate <= 0) {
      throw ArgumentError('Invalid sample rate.');
    }

    if (recording) {
      stop();
    }

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
      sampleCount = 0;
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

  /// Returns the next captured audio chunk while recording is active.
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

  /// Stops recording and performs any configured backend cleanup.
  void stop() {
    if (!recording) {
      sampleCount = 0;
      return;
    }

    _onStop?.call(this);
    sampleCount = 0;
    recording = false;
  }
}
