part of '../love_api_bindings.dart';

/// Binds `love.window.hasFocus`.
///
/// This reports whether the host window is currently focused.
LoveApiImplementation _bindWindowHasFocus(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.host.windowHasFocus;
}

/// Binds `love.window.hasMouseFocus`.
///
/// This reports whether the pointer is currently over the host window.
LoveApiImplementation _bindWindowHasMouseFocus(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.host.windowHasMouseFocus;
}

/// Binds `love.window.close`.
///
/// LOVE models closing as updating the tracked window metrics rather than
/// destroying the host process immediately.
LoveApiImplementation _bindWindowClose(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.host.windowMetrics = runtime.windowMetrics.copyWith(
      open: false,
      visible: false,
    );
    return null;
  };
}

/// Binds `love.window.getDesktopDimensions`.
///
/// When fullscreen mode metadata is available for the chosen display, this
/// binding prefers that size over the fallback desktop metrics stored on the
/// current window state.
LoveApiImplementation _bindWindowGetDesktopDimensions(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final display = _resolveWindowDisplay(
      runtime,
      args,
      symbol: 'love.window.getDesktopDimensions',
      argumentOptional: true,
    );
    final mode = display.fullscreenModes.firstOrNull;
    return Value.multi(<Object?>[
      mode?.width ?? runtime.windowMetrics.desktopWidth,
      mode?.height ?? runtime.windowMetrics.desktopHeight,
    ]);
  };
}

/// Binds `love.window.getDisplayCount`.
///
/// This returns the number of displays reported by the host backend.
LoveApiImplementation _bindWindowGetDisplayCount(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.host.windowDisplays.length;
}

/// Binds `love.window.getDisplayName`.
///
/// This resolves the requested display index and returns that display's name.
LoveApiImplementation _bindWindowGetDisplayName(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    return _resolveWindowDisplay(
      runtime,
      args,
      symbol: 'love.window.getDisplayName',
    ).name;
  };
}

/// Binds `love.window.getDisplayOrientation`.
///
/// Missing display arguments fall back to the current window display, matching
/// LOVE's optional-argument behavior.
LoveApiImplementation _bindWindowGetDisplayOrientation(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    return loveNormalizeWindowDisplayOrientation(
      _resolveWindowDisplay(
        runtime,
        args,
        symbol: 'love.window.getDisplayOrientation',
        argumentOptional: true,
      ).orientation,
    );
  };
}

/// Binds `love.window.getFullscreen`.
///
/// The returned values match LOVE's `(fullscreen, type)` tuple.
LoveApiImplementation _bindWindowGetFullscreen(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final metrics = runtime.windowMetrics;
    return Value.multi(<Object?>[metrics.fullscreen, metrics.fullscreenType]);
  };
}

/// Binds `love.window.getIcon`.
///
/// When no icon has been installed, this returns `nil`.
LoveApiImplementation _bindWindowGetIcon(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final icon = runtime.windowMetrics.icon;
    return icon == null ? null : _wrapImageData(context, icon);
  };
}

/// Binds `love.window.getFullscreenModes`.
///
/// This returns LOVE's array-of-tables shape where each entry contains a
/// fullscreen mode's width and height.
LoveApiImplementation _bindWindowGetFullscreenModes(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final display = _resolveWindowDisplay(
      runtime,
      args,
      symbol: 'love.window.getFullscreenModes',
      argumentOptional: true,
    );
    return Value(_fullscreenModesTable(display.fullscreenModes));
  };
}

/// Binds `love.window.getMode`.
///
/// LOVE can populate a caller-provided flags table, so this binding preserves
/// that behavior when the optional table target is passed in.
LoveApiImplementation _bindWindowGetMode(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final metrics = runtime.windowMetrics;
    final target = _optionalTableTarget(_valueAt(args, 0));
    final flags = metrics.toModeFlags(target: target?.$2);
    final flagsValue = target?.$1 ?? Value(flags);
    return Value.multi(<Object?>[metrics.width, metrics.height, flagsValue]);
  };
}

/// Binds `love.window.getPosition`.
///
/// The returned values match LOVE's `(x, y, display)` tuple.
LoveApiImplementation _bindWindowGetPosition(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final metrics = runtime.windowMetrics;
    return Value.multi(<Object?>[metrics.x, metrics.y, metrics.display]);
  };
}

/// Binds `love.window.getSafeArea`.
///
/// When the host does not report an explicit safe area, this binding falls back
/// to the full window bounds.
LoveApiImplementation _bindWindowGetSafeArea(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final metrics = runtime.windowMetrics;
    final area =
        metrics.safeArea ??
        LoveWindowSafeArea(
          x: 0,
          y: 0,
          width: metrics.width.toDouble(),
          height: metrics.height.toDouble(),
        );
    return Value.multi(<Object?>[area.x, area.y, area.width, area.height]);
  };
}

/// Binds `love.window.getTitle`.
///
/// This returns the current title tracked in window metrics.
LoveApiImplementation _bindWindowGetTitle(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.title;
}

/// Binds `love.window.getVSync`.
///
/// LOVE exposes VSync as an integer mode rather than a boolean flag.
LoveApiImplementation _bindWindowGetVsync(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.vsync;
}

/// Binds `love.window.isMaximized`.
///
/// Fullscreen and minimized windows do not count as maximized, even if the
/// host metrics still carry the maximize flag.
LoveApiImplementation _bindWindowIsMaximized(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final metrics = runtime.windowMetrics;
    return metrics.maximized && !metrics.fullscreen && !metrics.minimized;
  };
}

/// Binds `love.window.isMinimized`.
///
/// This reports the tracked minimized state directly.
LoveApiImplementation _bindWindowIsMinimized(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.minimized;
}

/// Binds `love.window.isDisplaySleepEnabled`.
///
/// This reflects whether the runtime currently allows the display to sleep.
LoveApiImplementation _bindWindowIsDisplaySleepEnabled(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.displaySleepEnabled;
}

/// Binds `love.window.setTitle`.
///
/// This updates the tracked title in host window metrics.
LoveApiImplementation _bindWindowSetTitle(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final title = _requireString(args, 0, 'love.window.setTitle');
    runtime.host.windowMetrics = runtime.windowMetrics.copyWith(title: title);
    return null;
  };
}

/// Binds `love.window.getDPIScale`.
///
/// This returns the current scale factor between LOVE units and physical
/// pixels.
LoveApiImplementation _bindWindowGetDpiScale(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.dpiScale;
}

/// Binds `love.window.maximize`.
///
/// LOVE only allows maximizing resizable, non-fullscreen windows, so this
/// binding silently does nothing when those preconditions are not met.
LoveApiImplementation _bindWindowMaximize(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final metrics = runtime.windowMetrics;
    if (metrics.fullscreen || !metrics.resizable) {
      return null;
    }

    runtime.host.windowMetrics = metrics.copyWith(
      maximized: true,
      minimized: false,
    );
    return null;
  };
}

/// Binds `love.window.minimize`.
///
/// This clears the maximized flag when minimizing, matching LOVE's effective
/// state transitions.
LoveApiImplementation _bindWindowMinimize(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.host.windowMetrics = runtime.windowMetrics.copyWith(
      minimized: true,
      maximized: false,
    );
    return null;
  };
}

/// Binds `love.window.requestAttention`.
///
/// LOVE optionally accepts a boolean that requests continuous attention until
/// the window regains focus.
LoveApiImplementation _bindWindowRequestAttention(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final continuous = args.isNotEmpty
        ? _requireBoolean(args, 0, 'love.window.requestAttention')
        : false;
    runtime.host.windowMetrics = runtime.windowMetrics.copyWith(
      attentionRequested: true,
      attentionRequestContinuous: continuous,
    );
    return null;
  };
}

/// Binds `love.window.restore`.
///
/// This clears minimized and maximized state without changing fullscreen mode.
LoveApiImplementation _bindWindowRestore(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.host.windowMetrics = runtime.windowMetrics.copyWith(
      maximized: false,
      minimized: false,
    );
    return null;
  };
}

/// Binds `love.window.showMessageBox`.
///
/// LOVE returns either a success boolean or the pressed button index depending
/// on whether the caller provided a custom button list, so this binding mirrors
/// that split return shape.
LoveApiImplementation _bindWindowShowMessageBox(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) async {
    const symbol = 'love.window.showMessageBox';
    final title = _requireString(args, 0, symbol);
    final message = _requireString(args, 1, symbol);
    final buttonList = args.length >= 3
        ? _tableIfPresent(_valueAt(args, 2))
        : null;

    if (buttonList != null) {
      final buttons = _messageBoxButtons(buttonList, symbol);
      final response = await runtime.host.showWindowMessageBox(
        LoveWindowMessageBoxData(
          title: title,
          message: message,
          buttons: buttons,
          type: _optionalWindowMessageBoxTypeAt(args, 3, symbol) ?? 'info',
          attachToWindow: args.length >= 5
              ? _requireBoolean(args, 4, symbol)
              : true,
          enterButtonIndex: _tableRoundedInt(buttonList, 'enterbutton') ?? 1,
          escapeButtonIndex:
              _tableRoundedInt(buttonList, 'escapebutton') ?? buttons.length,
        ),
      );
      return response.pressedButtonIndex;
    }

    final response = await runtime.host.showWindowMessageBox(
      LoveWindowMessageBoxData(
        title: title,
        message: message,
        type: _optionalWindowMessageBoxTypeAt(args, 2, symbol) ?? 'info',
        attachToWindow: args.length >= 4
            ? _requireBoolean(args, 3, symbol)
            : true,
      ),
    );
    return response.success;
  };
}

/// Binds `love.window.fromPixels`.
///
/// This converts physical pixels into LOVE's DPI-independent window units.
LoveApiImplementation _bindWindowFromPixels(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final pixels = _requireNumber(args, 0, 'love.window.fromPixels');
    return pixels / runtime.windowMetrics.dpiScale;
  };
}

/// Binds `love.window.toPixels`.
///
/// This converts LOVE's DPI-independent window units into physical pixels.
LoveApiImplementation _bindWindowToPixels(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final value = _requireNumber(args, 0, 'love.window.toPixels');
    return value * runtime.windowMetrics.dpiScale;
  };
}

/// Binds `love.window.setMode`.
///
/// Unlike [_bindWindowUpdateMode], this rebuilds the mode flags from the
/// provided arguments instead of merging unspecified flags from the current
/// window state.
LoveApiImplementation _bindWindowSetMode(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final updated = _windowMetricsFromArgs(
      runtime.windowMetrics,
      args,
      symbol: 'love.window.setMode',
      mergeExistingFlags: false,
    );
    runtime.host.windowMetrics = updated;
    return true;
  };
}

/// Binds `love.window.setFullscreen`.
///
/// This toggles fullscreen state and optionally updates the fullscreen type in
/// the same call.
LoveApiImplementation _bindWindowSetFullscreen(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final fullscreen = _requireBoolean(args, 0, 'love.window.setFullscreen');
    final fullscreenType = args.length >= 2
        ? _requireWindowFullscreenType(args, 1, 'love.window.setFullscreen')
        : runtime.windowMetrics.fullscreenType;
    runtime.host.windowMetrics = runtime.windowMetrics.copyWith(
      fullscreen: fullscreen,
      fullscreenType: fullscreenType,
      maximized: fullscreen ? false : runtime.windowMetrics.maximized,
    );
    return true;
  };
}

/// Binds `love.window.setDisplaySleepEnabled`.
///
/// This updates whether the host should prevent the display from sleeping.
LoveApiImplementation _bindWindowSetDisplaySleepEnabled(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final enabled = _requireBoolean(
      args,
      0,
      'love.window.setDisplaySleepEnabled',
    );
    runtime.host.windowMetrics = runtime.windowMetrics.copyWith(
      displaySleepEnabled: enabled,
    );
    return null;
  };
}

/// Binds `love.window.setIcon`.
///
/// LOVE expects `ImageData` here, so this stores a decoded icon image in the
/// tracked window metrics.
LoveApiImplementation _bindWindowSetIcon(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final icon = _requireImageData(args, 0, 'love.window.setIcon');
    runtime.host.windowMetrics = runtime.windowMetrics.copyWith(icon: icon);
    return true;
  };
}

/// Binds `love.window.updateMode`.
///
/// Unlike [_bindWindowSetMode], this preserves existing mode flags when the
/// caller omits them from the update table.
LoveApiImplementation _bindWindowUpdateMode(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final updated = _windowMetricsFromArgs(
      runtime.windowMetrics,
      args,
      symbol: 'love.window.updateMode',
      mergeExistingFlags: true,
    );
    runtime.host.windowMetrics = updated;
    return true;
  };
}

/// Binds `love.window.setPosition`.
///
/// The optional display argument switches the target display alongside the new
/// window position.
LoveApiImplementation _bindWindowSetPosition(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final x = _requireRoundedInt(args, 0, 'love.window.setPosition');
    final y = _requireRoundedInt(args, 1, 'love.window.setPosition');
    final display = _optionalDisplayIndexAt(args, 2, 'love.window.setPosition');
    runtime.host.windowMetrics = runtime.windowMetrics.copyWith(
      x: x,
      y: y,
      display: display ?? runtime.windowMetrics.display,
    );
    return null;
  };
}

/// Binds `love.window.setVSync`.
///
/// LOVE uses integer VSync modes, so this stores the rounded numeric value.
LoveApiImplementation _bindWindowSetVsync(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final vsync = _requireRoundedInt(args, 0, 'love.window.setVSync');
    runtime.host.windowMetrics = runtime.windowMetrics.copyWith(vsync: vsync);
    return true;
  };
}

/// Binds `love.window.isOpen`.
///
/// This reports whether the tracked window state is still considered open.
LoveApiImplementation _bindWindowIsOpen(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.open;
}

/// Binds `love.window.isVisible`.
///
/// LOVE treats minimized windows as not visible even when their visibility flag
/// is still set.
LoveApiImplementation _bindWindowIsVisible(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final metrics = runtime.windowMetrics;
    return metrics.visible && !metrics.minimized;
  };
}

/// Returns the optional 1-based display index from the first argument.
int? _optionalDisplayIndex(List<Object?> args, String symbol) {
  if (args.isEmpty || _valueAt(args, 0) == null) {
    return null;
  }

  final display = _requireRoundedInt(args, 0, symbol);
  if (display < 1) {
    throw LuaError('$symbol expected a positive display index');
  }
  return display;
}

/// Returns the optional 1-based display index from [index].
int? _optionalDisplayIndexAt(List<Object?> args, int index, String symbol) {
  if (args.length <= index || _valueAt(args, index) == null) {
    return null;
  }

  final display = _requireRoundedInt(args, index, symbol);
  if (display < 1) {
    throw LuaError('$symbol expected a positive display index');
  }
  return display;
}

/// Resolves the target display for a window binding call.
///
/// When [argumentOptional] is `true`, missing display arguments fall back to
/// the current window display tracked in [runtime.windowMetrics].
LoveWindowDisplay _resolveWindowDisplay(
  LoveRuntimeContext runtime,
  List<Object?> args, {
  required String symbol,
  bool argumentOptional = false,
}) {
  final displays = runtime.host.windowDisplays;
  if (displays.isEmpty) {
    throw LuaError('$symbol no displays are available');
  }

  final requestedIndex = argumentOptional
      ? (_optionalDisplayIndex(args, symbol) ?? runtime.windowMetrics.display)
      : _requireRoundedInt(args, 0, symbol);
  if (requestedIndex < 1 || requestedIndex > displays.length) {
    throw LuaError(
      '$symbol expected a display index between 1 and ${displays.length}',
    );
  }

  return displays[requestedIndex - 1];
}

/// Returns the optional validated message-box type at [index].
String? _optionalWindowMessageBoxTypeAt(
  List<Object?> args,
  int index,
  String symbol,
) {
  if (args.length <= index || _valueAt(args, index) == null) {
    return null;
  }

  return switch (_requireString(args, index, symbol)) {
    final value when loveWindowMessageBoxTypeConstants.contains(value) => value,
    final value => throw LuaError('$symbol invalid message box type "$value"'),
  };
}

/// Extracts message-box button labels from a LOVE array table.
///
/// Non-array metadata keys such as `enterbutton` and `escapebutton` are
/// ignored here and read separately by the caller.
List<String> _messageBoxButtons(Map<dynamic, dynamic> table, String symbol) {
  final buttons = <String>[];
  for (var index = 1; ; index++) {
    final entry = _tableIndexedEntry(table, index);
    if (entry == null) {
      break;
    }

    final label = _stringLike(entry);
    if (label == null) {
      throw LuaError('$symbol expected a string button label at index $index');
    }
    buttons.add(label);
  }

  if (buttons.isEmpty) {
    throw LuaError('$symbol expected at least one message box button');
  }

  return List<String>.unmodifiable(buttons);
}

/// Returns the validated LOVE fullscreen type at [index].
///
/// LOVE accepts only the constants exposed by
/// [loveWindowFullscreenTypeConstants].
String _requireWindowFullscreenType(
  List<Object?> args,
  int index,
  String symbol,
) {
  return switch (_requireString(args, index, symbol)) {
    final value when loveWindowFullscreenTypeConstants.contains(value) => value,
    final value => throw LuaError('$symbol invalid fullscreen type "$value"'),
  };
}

/// Builds the LOVE table returned by `love.window.getFullscreenModes`.
///
/// Each entry is a 1-based table containing `width` and `height` fields.
Map<Object?, Object?> _fullscreenModesTable(
  List<LoveWindowFullscreenMode> modes,
) {
  final table = <Object?, Object?>{};
  for (var i = 0; i < modes.length; i++) {
    table[i + 1] = <Object?, Object?>{
      'width': modes[i].width,
      'height': modes[i].height,
    };
  }
  return table;
}
