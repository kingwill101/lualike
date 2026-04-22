part of '../love_api_bindings.dart';

/// Binds `love.event.clear`.
///
/// The returned closure drops all queued LOVE events from the runtime event
/// queue.
LoveApiImplementation _bindEventClear(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.events.clear();
    return null;
  };
}

/// Binds `love.event.poll`.
///
/// The polling iterator is cached in the module table so repeated calls reuse
/// the same Lua-visible function object.
LoveApiImplementation _bindEventPoll(LibraryRegistrationContext context) {
  return (args) {
    final eventTable = _eventModuleTableForContext(context);
    final pollIterator = eventTable?['poll_i'];
    if (pollIterator != null) {
      return pollIterator;
    }

    final runtime = _runtimeContext(context);
    final builder = BuiltinFunctionBuilder(context);
    final iterator = builder.create((args) {
      final message = runtime.events.poll();
      if (message == null) {
        return null;
      }

      return Value.multi(message.toValues());
    });

    return Value(iterator, functionName: 'poll_i');
  };
}

/// Binds `love.event.pump`.
///
/// Pumping lets the platform adapter collect pending host events before Lua
/// code reads them from the LOVE queue.
LoveApiImplementation _bindEventPump(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.events.pump();
    return null;
  };
}

/// Binds `love.event.push`.
///
/// Extra arguments are converted to raw Lua values and enqueued as the event
/// payload.
LoveApiImplementation _bindEventPush(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final name = _requireString(args, 0, 'love.event.push');
    final payload = args.skip(1).map(_rawValue).toList(growable: false);
    return runtime.events.pushMessage(name, payload);
  };
}

/// Binds `love.event.quit`.
///
/// LOVE models quit requests as a queued `quit` event carrying an optional exit
/// code, so this binding mirrors that behavior instead of terminating
/// immediately.
LoveApiImplementation _bindEventQuit(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final payload = <Object?>[args.isEmpty ? 0 : _rawValue(args.first)];
    runtime.events.pushMessage('quit', payload);
    return true;
  };
}

/// Binds `love.event.wait`.
///
/// The returned closure resolves asynchronously once a new queued event becomes
/// available.
LoveApiImplementation _bindEventWait(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    final message = await runtime.events.wait();
    return Value.multi(message.toValues());
  };
}

/// Returns the `love.event` module table from [context], if it exists.
Map<dynamic, dynamic>? _eventModuleTableForContext(
  LibraryRegistrationContext context,
) {
  final loveTable = _tableIfPresent(context.environment.get('love'));
  if (loveTable == null) {
    return null;
  }

  return _tableIfPresent(loveTable['event']);
}
