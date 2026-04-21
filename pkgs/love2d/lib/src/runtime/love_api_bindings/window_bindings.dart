part of '../love_api_bindings.dart';

LoveApiImplementation _bindWindowHasFocus(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.host.windowHasFocus;
}

LoveApiImplementation _bindWindowHasMouseFocus(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.host.windowHasMouseFocus;
}

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

LoveApiImplementation _bindWindowGetDisplayCount(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.host.windowDisplays.length;
}

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

LoveApiImplementation _bindWindowGetFullscreen(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final metrics = runtime.windowMetrics;
    return Value.multi(<Object?>[metrics.fullscreen, metrics.fullscreenType]);
  };
}

LoveApiImplementation _bindWindowGetIcon(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final icon = runtime.windowMetrics.icon;
    return icon == null ? null : _wrapImageData(context, icon);
  };
}

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

LoveApiImplementation _bindWindowGetPosition(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final metrics = runtime.windowMetrics;
    return Value.multi(<Object?>[metrics.x, metrics.y, metrics.display]);
  };
}

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

LoveApiImplementation _bindWindowGetTitle(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.title;
}

LoveApiImplementation _bindWindowGetVsync(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.vsync;
}

LoveApiImplementation _bindWindowIsMaximized(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final metrics = runtime.windowMetrics;
    return metrics.maximized && !metrics.fullscreen && !metrics.minimized;
  };
}

LoveApiImplementation _bindWindowIsMinimized(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.minimized;
}

LoveApiImplementation _bindWindowIsDisplaySleepEnabled(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.displaySleepEnabled;
}

LoveApiImplementation _bindWindowSetTitle(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final title = _requireString(args, 0, 'love.window.setTitle');
    runtime.host.windowMetrics = runtime.windowMetrics.copyWith(title: title);
    return null;
  };
}

LoveApiImplementation _bindWindowGetDpiScale(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.dpiScale;
}

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

LoveApiImplementation _bindWindowFromPixels(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final pixels = _requireNumber(args, 0, 'love.window.fromPixels');
    return pixels / runtime.windowMetrics.dpiScale;
  };
}

LoveApiImplementation _bindWindowToPixels(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final value = _requireNumber(args, 0, 'love.window.toPixels');
    return value * runtime.windowMetrics.dpiScale;
  };
}

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

LoveApiImplementation _bindWindowSetIcon(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final icon = _requireImageData(args, 0, 'love.window.setIcon');
    runtime.host.windowMetrics = runtime.windowMetrics.copyWith(icon: icon);
    return true;
  };
}

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

LoveApiImplementation _bindWindowSetVsync(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final vsync = _requireRoundedInt(args, 0, 'love.window.setVSync');
    runtime.host.windowMetrics = runtime.windowMetrics.copyWith(vsync: vsync);
    return true;
  };
}

LoveApiImplementation _bindWindowIsOpen(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.open;
}

LoveApiImplementation _bindWindowIsVisible(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final metrics = runtime.windowMetrics;
    return metrics.visible && !metrics.minimized;
  };
}

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
