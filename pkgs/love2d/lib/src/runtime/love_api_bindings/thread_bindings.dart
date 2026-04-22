part of '../love_api_bindings.dart';

/// Returns the shared thread state attached to the active Lua runtime.
LoveThreadState _threadState(LibraryRegistrationContext context) {
  final runtime = context.interpreter;
  if (runtime == null) {
    throw StateError('No Lua runtime available for LOVE thread bindings');
  }

  return LoveThreadState.attach(runtime);
}

/// Binds `love.thread.newChannel`.
///
/// This creates an unnamed channel backed by the shared thread state.
LoveApiImplementation _bindThreadNewChannel(
  LibraryRegistrationContext context,
) {
  return (args) => _wrapChannel(context, _threadState(context).newChannel());
}

/// Binds `love.thread.getChannel`.
///
/// LOVE channels are global by name within a runtime's shared thread state.
LoveApiImplementation _bindThreadGetChannel(
  LibraryRegistrationContext context,
) {
  return (args) {
    const symbol = 'love.thread.getChannel';
    final name = _requireString(args, 0, symbol);
    return _wrapChannel(context, _threadState(context).getChannel(name));
  };
}

/// Binds `love.thread.newThread`.
///
/// LOVE accepts either a Lua code string or a filesystem-backed source file.
/// This binding creates a child interpreter, installs the LOVE runtime into
/// it, mirrors the parent's filesystem state, and then loads the provided
/// chunk for later execution.
LoveApiImplementation _bindThreadNewThread(LibraryRegistrationContext context) {
  return (args) async {
    const symbol = 'love.thread.newThread';
    if (args.isEmpty) {
      throw LuaError('$symbol expects at least 1 argument');
    }

    final first = _valueAt(args, 0);
    var name = 'Thread code';
    late final String sourceCode;

    if (_stringLike(first) case final String stringValue
        when _looksLikeLoveThreadCodeString(stringValue)) {
      sourceCode = stringValue;
    } else {
      final fileData = await _requireResourceFileData(
        context,
        first,
        symbol,
        expectedKinds: 'filename, FileData, File, or code string',
      );
      sourceCode = utf8.decode(fileData.bytes);
      name = '@${fileData.filename}';
    }

    final parentRuntime = context.interpreter;
    if (parentRuntime == null) {
      throw StateError('No Lua runtime available for LOVE thread bindings');
    }

    final parentRuntimeContext = _runtimeContext(context);
    final parentFilesystem = LoveFilesystemState.of(parentRuntime);
    final sharedThreads = LoveThreadState.attach(parentRuntime);

    final thread = LoveLuaThread(
      name: name,
      runner: (encodedArgs, thread) async {
        final childRuntime = Interpreter();

        ensureLoveApiRuntimeBindingsLoaded();
        ensureLoveFilesystemRuntimeBindingsLoaded();

        LoveRuntimeContext.attach(
          childRuntime,
          host: parentRuntimeContext.host,
        );
        LoveFilesystemState.attach(
          childRuntime,
          adapter: parentFilesystem.adapter,
        );
        LoveThreadState.attach(childRuntime, sharedState: sharedThreads);

        love_api_generated.installLove2d(runtime: childRuntime);
        installLoveAudioExtraBindings(childRuntime);
        installLoveDataExtraBindings(childRuntime);
        installLoveEventExtraBindings(childRuntime);
        installLoveFilesystemEnumBindings(childRuntime);
        installLoveFilesystemExtraBindings(childRuntime);
        installLoveFontExtraBindings(childRuntime);
        installLoveGraphicsEnumBindings(childRuntime);
        installLoveGraphicsExtraBindings(childRuntime);
        installLoveImageExtraBindings(childRuntime);
        installLoveJoystickExtraBindings(childRuntime);
        installLovePhysicsExtraBindings(childRuntime);
        installLoveSystemExtraBindings(childRuntime);
        installLoveWindowExtraBindings(childRuntime);
        syncLoveFilesystemPackageInterop(childRuntime);
        _installLoveThreadCompatibilityAliases(childRuntime);
        _copyThreadFilesystemState(
          parentFilesystem,
          LoveFilesystemState.of(childRuntime),
        );

        final loadResult = await childRuntime.loadChunk(
          LuaChunkLoadRequest(
            source: Value(LuaString.fromDartString(sourceCode)),
            chunkName: name,
          ),
        );
        if (!loadResult.isSuccess) {
          throw LuaError(loadResult.errorMessage ?? '$name failed to load');
        }

        final childContext = LibraryContext(
          environment: childRuntime.getCurrentEnv(),
          interpreter: childRuntime,
        );
        final decodedArgs = encodedArgs
            .map((value) => _decodeThreadValue(childContext, value))
            .toList(growable: false);
        await childRuntime.callFunction(
          loadResult.chunk!,
          decodedArgs,
          debugName: name,
          debugNameWhat: 'thread',
        );
      },
      onError: (thread, error) {
        parentRuntimeContext.events.pushMessage('threaderror', <Object?>[
          _wrapThread(context, thread),
          error,
        ]);
      },
    );

    return _wrapThread(context, thread);
  };
}

/// Binds `Channel:clear`.
LoveApiImplementation _bindChannelClear(LibraryRegistrationContext context) {
  return (args) {
    _requireChannel(args, 0, 'Channel:clear').clear();
    return null;
  };
}

/// Binds `Channel:demand`.
///
/// This optionally waits up to a timeout and decodes the transferred value back
/// into the caller's runtime wrappers.
LoveApiImplementation _bindChannelDemand(LibraryRegistrationContext context) {
  final libraryContext = LibraryContext(
    environment: context.environment,
    interpreter: context.interpreter,
  );
  return (args) async {
    const symbol = 'Channel:demand';
    final channel = _requireChannel(args, 0, symbol);
    final timeout = args.length >= 2 ? _requireNumber(args, 1, symbol) : null;
    final value = await channel.demand(timeout: timeout);
    return _decodeThreadValue(libraryContext, value);
  };
}

/// Binds `Channel:getCount`.
LoveApiImplementation _bindChannelGetCount(LibraryRegistrationContext context) {
  return (args) => _requireChannel(args, 0, 'Channel:getCount').getCount();
}

/// Binds `Channel:hasRead`.
LoveApiImplementation _bindChannelHasRead(LibraryRegistrationContext context) {
  return (args) => _requireChannel(
    args,
    0,
    'Channel:hasRead',
  ).hasRead(_requireRoundedInt(args, 1, 'Channel:hasRead'));
}

/// Binds `Channel:peek`.
///
/// This inspects the next queued value without removing it from the channel.
LoveApiImplementation _bindChannelPeek(LibraryRegistrationContext context) {
  final libraryContext = LibraryContext(
    environment: context.environment,
    interpreter: context.interpreter,
  );
  return (args) {
    final value = _requireChannel(args, 0, 'Channel:peek').peek();
    return _decodeThreadValue(libraryContext, value);
  };
}

/// Binds `Channel:performAtomic`.
///
/// LOVE runs the callback while holding the channel's internal lock so callers
/// can perform compound operations safely.
LoveApiImplementation _bindChannelPerformAtomic(
  LibraryRegistrationContext context,
) {
  final interpreter = context.interpreter;
  if (interpreter == null) {
    throw StateError('No interpreter available for Channel:performAtomic');
  }

  return (args) async {
    const symbol = 'Channel:performAtomic';
    final channel = _requireChannel(args, 0, symbol);
    final callback = _requireCallable(args, 1, symbol);
    return await interpreter.callFunction(
      callback,
      <Object?>[_wrapChannel(context, channel), ...args.skip(2)],
      debugName: symbol,
      debugNameWhat: 'method',
    );
  };
}

/// Binds `Channel:pop`.
///
/// This removes the next queued value immediately and decodes it for the
/// caller's runtime.
LoveApiImplementation _bindChannelPop(LibraryRegistrationContext context) {
  final libraryContext = LibraryContext(
    environment: context.environment,
    interpreter: context.interpreter,
  );
  return (args) {
    final value = _requireChannel(args, 0, 'Channel:pop').pop();
    return _decodeThreadValue(libraryContext, value);
  };
}

/// Binds `Channel:push`.
///
/// Values are encoded into the small transferable subset that LOVE threads
/// support before they are queued.
LoveApiImplementation _bindChannelPush(LibraryRegistrationContext context) {
  return (args) {
    const symbol = 'Channel:push';
    final channel = _requireChannel(args, 0, symbol);
    final encoded = _encodeThreadValue(
      _valueAt(args, 1),
      symbol: symbol,
      argumentIndex: 2,
      tableMessage:
          'boolean, number, string, Channel, Thread, or table expected',
    );
    return channel.push(encoded);
  };
}

/// Binds `Channel:supply`.
///
/// This is the blocking counterpart to [Channel:push], with an optional
/// timeout.
LoveApiImplementation _bindChannelSupply(LibraryRegistrationContext context) {
  return (args) async {
    const symbol = 'Channel:supply';
    final channel = _requireChannel(args, 0, symbol);
    final encoded = _encodeThreadValue(
      _valueAt(args, 1),
      symbol: symbol,
      argumentIndex: 2,
      tableMessage:
          'boolean, number, string, Channel, Thread, or table expected',
    );
    final timeout = args.length >= 3 ? _requireNumber(args, 2, symbol) : null;
    return await channel.supply(encoded, timeout: timeout);
  };
}

/// Binds `Thread:getError`.
LoveApiImplementation _bindThreadGetError(LibraryRegistrationContext context) {
  return (args) => _requireThread(args, 0, 'Thread:getError').error;
}

/// Binds `Thread:isRunning`.
LoveApiImplementation _bindThreadIsRunning(LibraryRegistrationContext context) {
  return (args) => _requireThread(args, 0, 'Thread:isRunning').isRunning;
}

/// Binds `Thread:start`.
///
/// LOVE thread startup arguments must be transferable across runtimes, so this
/// encoding step rejects unsupported values and nested tables.
LoveApiImplementation _bindThreadStart(LibraryRegistrationContext context) {
  return (args) {
    const symbol = 'Thread:start';
    final thread = _requireThread(args, 0, symbol);
    final encodedArgs = <Object?>[];
    for (var index = 1; index < args.length; index++) {
      encodedArgs.add(
        _encodeThreadValue(
          _valueAt(args, index),
          symbol: symbol,
          argumentIndex: index + 1,
          tableMessage:
              'boolean, number, string, Channel, Thread, or flat table expected',
          requireFlatTable: true,
        ),
      );
    }
    return thread.start(encodedArgs);
  };
}

/// Binds `Thread:wait`.
LoveApiImplementation _bindThreadWait(LibraryRegistrationContext context) {
  return (args) async {
    await _requireThread(args, 0, 'Thread:wait').wait();
    return null;
  };
}

/// Returns whether [value] should be treated as inline thread source code.
///
/// LOVE does not have an explicit discriminator here, so long or multiline
/// strings are treated as code while other strings are treated as filenames.
bool _looksLikeLoveThreadCodeString(String value) {
  return value.length >= 1024 || value.contains('\n');
}

/// Copies filesystem configuration from a parent runtime into a child thread
/// runtime.
void _copyThreadFilesystemState(
  LoveFilesystemState source,
  LoveFilesystemState target,
) {
  if (source.initialized) {
    target.init();
  }
  target.setFused(source.fused);
  target.setAndroidSaveExternal(source.androidSaveExternal);
  target.setSymlinksEnabled(source.symlinksEnabled);
  target.setRequirePath(source.getRequirePathString());
  target.setCRequirePath(source.getCRequirePathString());
  if (source.identity.isNotEmpty) {
    target.setIdentity(source.identity);
  }
  if (source.source.isNotEmpty) {
    target.setSource(source.source);
  }
}

/// Installs legacy globals that LOVE thread code may expect.
///
/// In particular this restores the Lua 5.1-style global `unpack` alias when
/// only `table.unpack` is present.
void _installLoveThreadCompatibilityAliases(LuaRuntime runtime) {
  final env = runtime.getCurrentEnv();
  if (env.get('unpack') != null) {
    return;
  }

  final tableValue = env.get('table');
  final tableRaw = switch (tableValue) {
    final Value value => value.raw,
    _ => tableValue,
  };
  if (tableRaw is! Map<dynamic, dynamic>) {
    return;
  }

  final unpack = tableRaw['unpack'];
  if (unpack != null) {
    env.define('unpack', unpack);
  }
}

/// Encodes a Lua-facing value into the transferable LOVE thread subset.
///
/// Scalars, channels, threads, and acyclic tables are supported. When
/// [requireFlatTable] is `true`, nested tables are rejected to match LOVE's
/// `Thread:start` argument rules.
Object? _encodeThreadValue(
  Object? value, {
  required String symbol,
  required int argumentIndex,
  required String tableMessage,
  bool requireFlatTable = false,
  Set<Map<dynamic, dynamic>>? seenTables,
}) {
  final channel = _channelIfPresent(value);
  if (channel != null) {
    return channel;
  }
  final thread = _threadIfPresent(value);
  if (thread != null) {
    return thread;
  }

  final raw = switch (value) {
    final Value wrapped => wrapped.raw,
    _ => value,
  };

  if (raw is bool || raw is num || raw is String) {
    return raw;
  }
  if (raw is LuaString) {
    return raw.toString();
  }
  if (raw is Map<dynamic, dynamic>) {
    final activeSeen = seenTables ?? <Map<dynamic, dynamic>>{};
    if (!activeSeen.add(raw)) {
      throw LuaError('$symbol $tableMessage');
    }

    final encoded = <Object?, Object?>{};
    for (final entry in raw.entries) {
      final encodedKey = _encodeThreadValue(
        entry.key,
        symbol: symbol,
        argumentIndex: argumentIndex,
        tableMessage: tableMessage,
        requireFlatTable: true,
        seenTables: activeSeen,
      );
      if (encodedKey is Map<dynamic, dynamic>) {
        throw LuaError('$symbol $tableMessage');
      }
      final encodedValue = _encodeThreadValue(
        entry.value,
        symbol: symbol,
        argumentIndex: argumentIndex,
        tableMessage: tableMessage,
        requireFlatTable: requireFlatTable,
        seenTables: activeSeen,
      );
      if (requireFlatTable && encodedValue is Map<dynamic, dynamic>) {
        throw LuaError('$symbol $tableMessage');
      }
      encoded[encodedKey] = encodedValue;
    }

    activeSeen.remove(raw);
    return Map<Object?, Object?>.unmodifiable(encoded);
  }

  throw LuaError('$symbol $tableMessage');
}

/// Decodes a transferred thread value into this runtime's wrapper objects.
Object? _decodeThreadValue(LibraryContext context, Object? value) {
  return switch (value) {
    final Map<dynamic, dynamic> table => Value(
      table.map<Object?, Object?>(
        (key, entryValue) => MapEntry(
          _decodeThreadValue(context, key),
          _decodeThreadValue(context, entryValue),
        ),
      ),
    ),
    final LoveImageData imageData => _wrapImageData(context, imageData),
    final LoveThreadChannel channel => _wrapChannel(context, channel),
    final LoveLuaThread thread => _wrapThread(context, thread),
    _ => value,
  };
}
