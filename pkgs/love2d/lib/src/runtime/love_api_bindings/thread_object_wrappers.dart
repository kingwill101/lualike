part of '../love_api_bindings.dart';

LoveThreadChannel? _channelIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final channel = table[_loveChannelObjectKey];
  return channel is LoveThreadChannel ? channel : null;
}

LoveLuaThread? _threadIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final thread = table[_loveThreadObjectKey];
  return thread is LoveLuaThread ? thread : null;
}

LoveThreadChannel _requireChannel(
  List<Object?> args,
  int index,
  String symbol,
) {
  final channel = _channelIfPresent(_valueAt(args, index));
  if (channel != null) {
    return channel;
  }

  throw LuaError('$symbol expected a Channel at argument ${index + 1}');
}

LoveLuaThread _requireThread(List<Object?> args, int index, String symbol) {
  final thread = _threadIfPresent(_valueAt(args, index));
  if (thread != null) {
    return thread;
  }

  throw LuaError('$symbol expected a Thread at argument ${index + 1}');
}

Object _threadWrapperCacheKey(LibraryContext context) {
  return context.interpreter ?? context.environment;
}

Value _wrapChannel(LibraryContext context, LoveThreadChannel channel) {
  final cacheKey = _threadWrapperCacheKey(context);
  final cached = _loveChannelWrapperCache[channel]?[cacheKey];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final interpreter = context.interpreter;
  const hierarchy = <String>{'Channel', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveChannelObjectKey: channel,
    'clear': Value(
      builder.create((args) {
        _requireChannel(args, 0, 'Channel:clear').clear();
        return null;
      }),
      functionName: 'clear',
    ),
    'demand': Value(
      builder.create((args) async {
        const symbol = 'Channel:demand';
        final channel = _requireChannel(args, 0, symbol);
        final timeout = args.length >= 2
            ? _requireNumber(args, 1, symbol)
            : null;
        final value = await channel.demand(timeout: timeout);
        return _decodeThreadValue(context, value);
      }),
      functionName: 'demand',
    ),
    'getCount': Value(
      builder.create(
        (args) => _requireChannel(args, 0, 'Channel:getCount').getCount(),
      ),
      functionName: 'getCount',
    ),
    'hasRead': Value(
      builder.create(
        (args) => _requireChannel(
          args,
          0,
          'Channel:hasRead',
        ).hasRead(_requireRoundedInt(args, 1, 'Channel:hasRead')),
      ),
      functionName: 'hasRead',
    ),
    'peek': Value(
      builder.create((args) {
        final value = _requireChannel(args, 0, 'Channel:peek').peek();
        return _decodeThreadValue(context, value);
      }),
      functionName: 'peek',
    ),
    'performAtomic': Value(
      builder.create((args) async {
        const symbol = 'Channel:performAtomic';
        final channel = _requireChannel(args, 0, symbol);
        final callback = _requireCallable(args, 1, symbol);
        if (interpreter == null) {
          throw StateError(
            'No interpreter available for Channel:performAtomic',
          );
        }
        return await interpreter.callFunction(
          callback,
          <Object?>[_wrapChannel(context, channel), ...args.skip(2)],
          debugName: symbol,
          debugNameWhat: 'method',
        );
      }),
      functionName: 'performAtomic',
    ),
    'pop': Value(
      builder.create((args) {
        final value = _requireChannel(args, 0, 'Channel:pop').pop();
        return _decodeThreadValue(context, value);
      }),
      functionName: 'pop',
    ),
    'push': Value(
      builder.create((args) {
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
      }),
      functionName: 'push',
    ),
    'supply': Value(
      builder.create((args) async {
        const symbol = 'Channel:supply';
        final channel = _requireChannel(args, 0, symbol);
        final encoded = _encodeThreadValue(
          _valueAt(args, 1),
          symbol: symbol,
          argumentIndex: 2,
          tableMessage:
              'boolean, number, string, Channel, Thread, or table expected',
        );
        final timeout = args.length >= 3
            ? _requireNumber(args, 2, symbol)
            : null;
        return await channel.supply(encoded, timeout: timeout);
      }),
      functionName: 'supply',
    ),
    'release': Value(
      builder.create((args) {
        final channel = _requireChannel(args, 0, 'Object:release');
        if (_loveChannelReleased[channel] == true) {
          return false;
        }
        _loveChannelReleased[channel] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        _requireChannel(args, 0, 'Object:type');
        return 'Channel';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        _requireChannel(args, 0, 'Object:typeOf');
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  (_loveChannelWrapperCache[channel] ??= <Object, Value>{})[cacheKey] = table;
  return table;
}

Value _wrapThread(LibraryContext context, LoveLuaThread thread) {
  final cacheKey = _threadWrapperCacheKey(context);
  final cached = _loveThreadWrapperCache[thread]?[cacheKey];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'Thread', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveThreadObjectKey: thread,
    'getError': Value(
      builder.create(
        (args) => _requireThread(args, 0, 'Thread:getError').error,
      ),
      functionName: 'getError',
    ),
    'isRunning': Value(
      builder.create(
        (args) => _requireThread(args, 0, 'Thread:isRunning').isRunning,
      ),
      functionName: 'isRunning',
    ),
    'start': Value(
      builder.create((args) {
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
      }),
      functionName: 'start',
    ),
    'wait': Value(
      builder.create((args) async {
        await _requireThread(args, 0, 'Thread:wait').wait();
        return null;
      }),
      functionName: 'wait',
    ),
    'release': Value(
      builder.create((args) {
        final thread = _requireThread(args, 0, 'Object:release');
        if (_loveThreadReleased[thread] == true) {
          return false;
        }
        _loveThreadReleased[thread] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        _requireThread(args, 0, 'Object:type');
        return 'Thread';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        _requireThread(args, 0, 'Object:typeOf');
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  (_loveThreadWrapperCache[thread] ??= <Object, Value>{})[cacheKey] = table;
  return table;
}
