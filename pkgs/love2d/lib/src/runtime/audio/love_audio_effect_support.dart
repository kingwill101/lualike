part of '../love_runtime.dart';

const int loveAudioMaxSceneEffects = 64;
const int loveAudioMaxSourceEffects = 64;

typedef LoveAudioSettings = LinkedHashMap<String, Object?>;

final class LoveAudioSceneEffectState {
  final LinkedHashMap<String, LoveAudioSettings> _effects =
      LinkedHashMap<String, LoveAudioSettings>();

  bool setEffect(String name, Map<String, Object?> settings) {
    if (!_effects.containsKey(name) &&
        _effects.length >= loveAudioMaxSceneEffects) {
      return false;
    }

    _effects[name] = loveCopyAudioSettings(settings);
    return true;
  }

  bool unsetEffect(String name) {
    if (!_effects.containsKey(name)) {
      return false;
    }

    _effects.remove(name);
    return true;
  }

  LoveAudioSettings? getEffect(String name) {
    final settings = _effects[name];
    return settings == null ? null : loveCopyAudioSettings(settings);
  }

  List<String> get activeEffectNames =>
      List<String>.from(_effects.keys, growable: false);
}

final class LoveAudioSourceEffectState {
  LoveAudioSettings? _filter;
  final LinkedHashMap<String, LoveAudioSettings?> _effects =
      LinkedHashMap<String, LoveAudioSettings?>();

  LoveAudioSettings? get filter =>
      _filter == null ? null : loveCopyAudioSettings(_filter!);

  bool setFilter([Map<String, Object?>? settings]) {
    _filter = settings == null ? null : loveCopyAudioSettings(settings);
    return true;
  }

  bool setEffect(String name, {Map<String, Object?>? filter}) {
    if (!_effects.containsKey(name) &&
        _effects.length >= loveAudioMaxSourceEffects) {
      return false;
    }

    _effects[name] = filter == null ? null : loveCopyAudioSettings(filter);
    return true;
  }

  bool unsetEffect(String name) {
    if (!_effects.containsKey(name)) {
      return false;
    }

    _effects.remove(name);
    return true;
  }

  bool hasEffect(String name) => _effects.containsKey(name);

  LoveAudioSettings? getEffectFilter(String name) {
    final settings = _effects[name];
    return settings == null ? null : loveCopyAudioSettings(settings);
  }

  List<String> get activeEffectNames =>
      List<String>.from(_effects.keys, growable: false);

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

LoveAudioSettings loveCopyAudioSettings(Map<String, Object?> settings) {
  return LinkedHashMap<String, Object?>.fromEntries(
    settings.entries.map(
      (entry) => MapEntry<String, Object?>(entry.key, entry.value),
    ),
  );
}
