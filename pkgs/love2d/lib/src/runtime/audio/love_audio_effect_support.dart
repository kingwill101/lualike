part of '../love_runtime.dart';

/// The maximum number of simultaneously active scene effects.
const int loveAudioMaxSceneEffects = 64;

/// The maximum number of simultaneously active source effects.
const int loveAudioMaxSourceEffects = 64;

/// Ordered audio effect settings keyed by LOVE parameter name.
typedef LoveAudioSettings = LinkedHashMap<String, Object?>;

/// Scene-wide audio effect state.
final class LoveAudioSceneEffectState {
  final LinkedHashMap<String, LoveAudioSettings> _effects =
      LinkedHashMap<String, LoveAudioSettings>();

  /// Stores scene effect [settings] under [name].
  ///
  /// Returns `false` when adding a new effect would exceed
  /// [loveAudioMaxSceneEffects].
  bool setEffect(String name, Map<String, Object?> settings) {
    if (!_effects.containsKey(name) &&
        _effects.length >= loveAudioMaxSceneEffects) {
      return false;
    }

    _effects[name] = loveCopyAudioSettings(settings);
    return true;
  }

  /// Removes the scene effect named [name].
  bool unsetEffect(String name) {
    if (!_effects.containsKey(name)) {
      return false;
    }

    _effects.remove(name);
    return true;
  }

  /// The copied settings for the active effect named [name], if any.
  LoveAudioSettings? getEffect(String name) {
    final settings = _effects[name];
    return settings == null ? null : loveCopyAudioSettings(settings);
  }

  /// The names of all currently active scene effects.
  List<String> get activeEffectNames =>
      List<String>.from(_effects.keys, growable: false);
}

/// Per-source audio effect state.
final class LoveAudioSourceEffectState {
  LoveAudioSettings? _filter;
  final LinkedHashMap<String, LoveAudioSettings?> _effects =
      LinkedHashMap<String, LoveAudioSettings?>();

  /// The copied filter settings currently applied to this source, if any.
  LoveAudioSettings? get filter =>
      _filter == null ? null : loveCopyAudioSettings(_filter!);

  /// Updates this source filter to [settings], or clears it when omitted.
  bool setFilter([Map<String, Object?>? settings]) {
    _filter = settings == null ? null : loveCopyAudioSettings(settings);
    return true;
  }

  /// Stores source effect [name] with an optional per-effect [filter].
  ///
  /// Returns `false` when adding a new effect would exceed
  /// [loveAudioMaxSourceEffects].
  bool setEffect(String name, {Map<String, Object?>? filter}) {
    if (!_effects.containsKey(name) &&
        _effects.length >= loveAudioMaxSourceEffects) {
      return false;
    }

    _effects[name] = filter == null ? null : loveCopyAudioSettings(filter);
    return true;
  }

  /// Removes the source effect named [name].
  bool unsetEffect(String name) {
    if (!_effects.containsKey(name)) {
      return false;
    }

    _effects.remove(name);
    return true;
  }

  /// Whether the source effect named [name] is currently active.
  bool hasEffect(String name) => _effects.containsKey(name);

  /// The copied filter settings for the source effect named [name], if any.
  LoveAudioSettings? getEffectFilter(String name) {
    final settings = _effects[name];
    return settings == null ? null : loveCopyAudioSettings(settings);
  }

  /// The names of all currently active source effects.
  List<String> get activeEffectNames =>
      List<String>.from(_effects.keys, growable: false);

  /// A deep copy of this source effect state.
  LoveAudioSourceEffectState clone() {
    final clone = LoveAudioSourceEffectState();
    if (_filter != null) {
      clone._filter = loveCopyAudioSettings(_filter!);
    }
    for (final entry in _effects.entries) {
      clone._effects[entry.key] = entry.value == null
          ? null
          : loveCopyAudioSettings(entry.value!);
    }
    return clone;
  }
}

/// Returns a shallow copied, insertion-ordered audio settings map.
LoveAudioSettings loveCopyAudioSettings(Map<String, Object?> settings) {
  return LinkedHashMap<String, Object?>.fromEntries(
    settings.entries.map(
      (entry) => MapEntry<String, Object?>(entry.key, entry.value),
    ),
  );
}
