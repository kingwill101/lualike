part of '../love_api_bindings.dart';

/// Binds `love.getVersion`.
LoveApiImplementation _bindGetVersion(LibraryRegistrationContext context) {
  _runtimeContext(context);
  return (args) => Value.multi(<Object?>[
    loveVersionMajor,
    loveVersionMinor,
    loveVersionRevision,
    loveVersionCodename,
  ]);
}

/// Binds `love.hasDeprecationOutput`.
LoveApiImplementation _bindHasDeprecationOutput(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.deprecationOutput;
}

/// Binds `love.isVersionCompatible`.
LoveApiImplementation _bindIsVersionCompatible(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    if (args.isEmpty) {
      throw LuaError(
        'love.isVersionCompatible expects a version string or numbers',
      );
    }

    final first = _rawValue(args.first);
    final version = _stringLike(first);
    if (version != null) {
      return runtime.isVersionCompatibleString(version);
    }

    final major = _requireRoundedInt(args, 0, 'love.isVersionCompatible');
    final minor = _requireRoundedInt(args, 1, 'love.isVersionCompatible');
    final revision = args.length >= 3
        ? _requireRoundedInt(args, 2, 'love.isVersionCompatible')
        : 0;
    return runtime.isVersionCompatible(
      major: major,
      minor: minor,
      revision: revision,
    );
  };
}

/// Binds `love.setDeprecationOutput`.
LoveApiImplementation _bindSetDeprecationOutput(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.deprecationOutput = _luaTruthy(_valueAt(args, 0));
    return null;
  };
}
