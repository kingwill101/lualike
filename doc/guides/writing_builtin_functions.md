# Writing Native Functions in Dart

This guide explains the supported ways to extend LuaLike with Dart code.

## Table of Contents

- [Choose the right extension surface](#choose-the-right-extension-surface)
- [Implementing a builtin function](#implementing-a-builtin-function)
- [Working with arguments](#working-with-arguments)
- [Returning values](#returning-values)
- [Reporting errors](#reporting-errors)
- [Registering functions in a library](#registering-functions-in-a-library)
- [Async functions](#async-functions)
- [GC-visible references](#gc-visible-references)
- [Complete example](#complete-example)

## Choose the right extension surface

LuaLike exposes two main ways to attach Dart behavior.

### `LuaLike.expose()`

Use this for one-off integration with a specific runtime instance.

```dart
final lua = LuaLike();
lua.expose('double', (List<Object?> args) {
  final value = Value.wrap(args.first).unwrap() as num;
  return Value(value * 2);
});
```

### `Library` and `LibraryRegistry`

Use this when you want a reusable namespaced library or object model that can
be registered in multiple runtimes.

For this surface, import `package:lualike/library_builder.dart`.

## Implementing a builtin function

At the lowest level, a native function is a Dart type that extends
`BuiltinFunction` and implements `call()`.

```dart
import 'package:lualike/library_builder.dart';

class NativeAdd extends BuiltinFunction {
  NativeAdd(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    final a = Value.wrap(args[0]).unwrap() as num;
    final b = Value.wrap(args[1]).unwrap() as num;
    return primitiveValue(a + b);
  }
}
```

If you create builtins inside a `Library`, prefer `BuiltinFunctionBuilder`.
That gives the builtin access to the active runtime automatically.

## Working with arguments

Builtin functions receive `List<Object?> args`.

Recommended pattern:

1. validate arity explicitly
2. normalize arguments with `Value.wrap()`
3. unwrap the raw Dart values you need

```dart
@override
Object? call(List<Object?> args) {
  if (args.length < 2) {
    throw LuaError("add requires two arguments");
  }

  final a = Value.wrap(args[0]).unwrap();
  final b = Value.wrap(args[1]).unwrap();

  if (a is! num || b is! num) {
    throw LuaError("add requires numeric arguments");
  }

  return Value(a + b);
}
```

Use `Value.wrap()` instead of direct casts when you want the same coercion and
wrapping behavior the runtime uses elsewhere.

## Returning values

Return shapes follow LuaLike value conventions:

- single result: `Value(...)`
- multiple results: `Value.multi([...])`
- nil: `Value(null)` or `null`

```dart
return Value(42);

return Value.multi([Value('ok'), Value(true)]);

return Value(null);
```

If your builtin has access to a runtime through `BuiltinFunction`, prefer
`primitiveValue(...)` for scalar results. It lets the runtime reuse cached
wrappers for primitive values when supported.

## Reporting errors

Throw a `LuaError` when you want the runtime to surface a Lua-style failure:

```dart
if (divisor == 0) {
  throw LuaError('division by zero');
}
```

Throwing plain Dart exceptions also works, but `LuaError` is the clearest way
to communicate script-facing failures.

## Registering functions in a library

When you are inside a `Library`, use `LibraryRegistrationContext.define()` to
publish functions or constants:

```dart
class GreetingLibrary extends Library {
  @override
  String get name => 'greeting';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    final builder = BuiltinFunctionBuilder(context);

    context.define('hello', builder.create((args) {
      final who = args.isEmpty ? 'world' : Value.wrap(args.first).unwrap();
      return Value('hello, $who');
    }));
  }
}
```

`define()` wraps plain Dart callables and `BuiltinFunction` instances in
`Value`s once during registration so repeated lookups do not create fresh
wrappers.

## Async functions

`BuiltinFunction.call()` may return a `Future`, so asynchronous native
functions are supported:

```dart
class NativeNow extends BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return Value(DateTime.now().toIso8601String());
  }
}
```

## GC-visible references

If a builtin needs to hold references that the garbage collector should see,
implement `BuiltinFunctionGcRefs`:

```dart
class HolderBuiltin extends BuiltinFunction implements BuiltinFunctionGcRefs {
  HolderBuiltin(this._held);

  final List<Object?> _held;

  @override
  Iterable<Object?> getGcReferences() => _held;

  @override
  Object? call(List<Object?> args) => Value(_held.length);
}
```

This is only needed for builtins that keep state across calls.

## Complete example

```dart
import 'package:lualike/library_builder.dart';
import 'package:lualike/lualike.dart';

class StatsLibrary extends Library {
  @override
  String get name => 'stats';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    final builder = BuiltinFunctionBuilder(context);

    context.define('sum', builder.create((args) {
      if (args.isEmpty) {
        return Value(0);
      }

      final table = Value.wrap(args.first).unwrap();
      if (table is! Map) {
        throw LuaError('stats.sum expects a table');
      }

      num sum = 0;
      for (final entry in table.entries) {
        final raw = Value.wrap(entry.value).unwrap();
        if (raw is num) {
          sum += raw;
        }
      }

      return Value(sum);
    }));
  }
}

Future<void> main() async {
  final lua = LuaLike();
  lua.vm.libraryRegistry.register(StatsLibrary());
  lua.vm.libraryRegistry.initializeLibraryByName('stats');

  final result = await lua.execute('return stats.sum({1, 2, 3, 4})');
  print((result as Value).unwrap());
}
```

For richer object-style APIs, continue with
[Building a Lua-like Library with Builder Interface](./BUILDER_PATTERN.md).
