part of '../love_api_bindings.dart';

LoveApiImplementation _bindEventClear(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.events.clear();
    return null;
  };
}

LoveApiImplementation _bindEventPoll(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  final builder = BuiltinFunctionBuilder(context);
  final iterator = builder.create((args) {
    final message = runtime.events.poll();
    if (message == null) {
      return null;
    }

    return Value.multi(message.toValues());
  });

  return (args) => Value(iterator, functionName: 'poll_i');
}

LoveApiImplementation _bindEventPump(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.events.pump();
    return null;
  };
}

LoveApiImplementation _bindEventPush(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final name = _requireString(args, 0, 'love.event.push');
    final payload = args.skip(1).map(_rawValue).toList(growable: false);
    return runtime.events.pushMessage(name, payload);
  };
}

LoveApiImplementation _bindEventQuit(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final payload = <Object?>[args.isEmpty ? 0 : _rawValue(args.first)];
    runtime.events.pushMessage('quit', payload);
    return true;
  };
}

LoveApiImplementation _bindEventWait(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    final message = await runtime.events.wait();
    return Value.multi(message.toValues());
  };
}
