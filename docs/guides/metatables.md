# Metatables and Metamethods in LuaLike

This guide explains how to work with metatables and metamethods in the LuaLike library, which are essential for implementing Lua's object-oriented features and operator overloading.

## Overview

Metatables in Lua provide a mechanism to change the behavior of tables and other values. Each metatable is a regular table that defines how operations on the associated value should behave. Metamethods are the functions stored in a metatable that define this behavior.

## Metatable Basics

In LuaLike, metatables are represented as `Map<String, dynamic>` objects. You can attach a metatable to a value when creating it:

```dart
// Create a metatable
final metatable = <String, dynamic>{
  "__add": (List<Object?> args) {
    final a = args[0] as Value;
    final b = args[1] as Value;
    return Value((a.raw as num) + (b.raw as num));
  },
};

// Create a value with a metatable
final value = Value(42, metatable);
```

## Common Metamethods

Here are the most common metamethods and their purposes:

### Arithmetic Metamethods

- `__add`: Addition (`+`)
- `__sub`: Subtraction (`-`)
- `__mul`: Multiplication (`*`)
- `__div`: Division (`/`)
- `__mod`: Modulo (`%`)
- `__pow`: Exponentiation (`^`)
- `__unm`: Unary minus (`-`)
- `__idiv`: Integer division (`//`)

### Relational Metamethods

- `__eq`: Equality (`==`)
- `__lt`: Less than (`<`)
- `__le`: Less than or equal (`<=`)

### Table Access Metamethods

- `__index`: Accessing absent fields
- `__newindex`: Assigning to absent fields
- `__len`: Length operator (`#`)

### Function Call Metamethod

- `__call`: Function call (`()`)

### String Representation Metamethod

- `__tostring`: String conversion (`tostring()`)

### Concatenation Metamethod

- `__concat`: Concatenation (`..`)

## Implementing Metamethods

Each metamethod is a function that takes a list of arguments and returns a value. The first argument is always the value with the metatable, and the remaining arguments depend on the specific metamethod.

Here's an example of implementing the `__add` metamethod:

```dart
final metatable = <String, dynamic>{
  "__add": (List<Object?> args) {
    final a = args[0] as Value;
    final b = args[1] as Value;

    if (a.raw is num && b.raw is num) {
      return Value((a.raw as num) + (b.raw as num));
    }

    throw Exception("attempt to perform arithmetic on non-number values");
  },
};
```

## The __index Metamethod

The `__index` metamethod is particularly important as it defines what happens when a key is not found in a table. It can be either a function or a table:

```dart
// __index as a function
final metatable = <String, dynamic>{
  "__index": (List<Object?> args) {
    final table = args[0] as Value;
    final key = args[1] as Value;

    // Custom lookup logic
    if (key.raw == "special") {
      return Value("special value");
    }

    return Value(null); // Key not found
  },
};

// __index as a table
final indexTable = <dynamic, dynamic>{
  "method1": Value((List<Object?> args) {
    return Value("method1 called");
  }),
  "property1": Value("property1 value"),
};

final metatable = <String, dynamic>{
  "__index": Value(indexTable),
};
```

## The __newindex Metamethod

The `__newindex` metamethod defines what happens when a key is not found in a table during assignment. It can be either a function or a table:

```dart
// __newindex as a function
final metatable = <String, dynamic>{
  "__newindex": (List<Object?> args) {
    final table = args[0] as Value;
    final key = args[1] as Value;
    final value = args[2] as Value;

    // Custom assignment logic
    print("Assigning ${value.raw} to ${key.raw}");

    // Store in a different location
    (table.raw as Map)["_${key.raw}"] = value;
  },
};
```

## Creating Classes with Metatables

You can use metatables to implement class-like behavior in Lua. Here's an example of creating a simple Point class:

```dart
// Create the class metatable
final pointClassMetatable = <String, dynamic>{
  "__call": (List<Object?> args) {
    final cls = args[0] as Value;
    final x = args.length > 1 ? (args[1] as Value).raw as num : 0;
    final y = args.length > 2 ? (args[2] as Value).raw as num : 0;

    // Create a new instance
    final instance = <dynamic, dynamic>{
      "x": Value(x),
      "y": Value(y),
    };

    // Set the instance metatable
    return Value(instance, pointInstanceMetatable);
  },
};

// Create the instance metatable
final pointInstanceMetatable = <String, dynamic>{
  "__index": (List<Object?> args) {
    final instance = args[0] as Value;
    final key = args[1] as Value;

    // Method lookup
    if (key.raw == "distance") {
      return Value((List<Object?> methodArgs) {
        final self = methodArgs[0] as Value;
        final x = (self.raw as Map)["x"] as Value;
        final y = (self.raw as Map)["y"] as Value;

        return Value(sqrt(pow((x.raw as num), 2) + pow((y.raw as num), 2)));
      });
    }

    return Value(null);
  },
  "__tostring": (List<Object?> args) {
    final instance = args[0] as Value;
    final x = (instance.raw as Map)["x"] as Value;
    final y = (instance.raw as Map)["y"] as Value;

    return Value("Point(${x.raw}, ${y.raw})");
  },
};

// Create the Point class
final Point = Value(<dynamic, dynamic>{}, pointClassMetatable);

// Usage:
// local p = Point(3, 4)
// print(p:distance()) -- 5
// print(p) -- Point(3, 4)
```

## Using ValueClass for Metatables

The `ValueClass` utility makes it easier to create values with metatables:

```dart
// Create a Point class with ValueClass
final pointClass = ValueClass.create({
  "__call": (List<Object?> args) {
    final cls = args[0] as Value;
    final x = args.length > 1 ? (args[1] as Value).raw as num : 0;
    final y = args.length > 2 ? (args[2] as Value).raw as num : 0;

    // Create a new instance
    final instance = <dynamic, dynamic>{
      "x": Value(x),
      "y": Value(y),
    };

    // Set the instance metatable
    return Value(instance, pointInstanceMetatable);
  },
});

// Create the instance metatable
final pointInstanceMetatable = <String, dynamic>{
  // ... same as before
};
```

## Default Metatables

LuaLike provides default metatables for common types through the `DefaultMetatables` class:

```dart
final defaultMetatables = DefaultMetatables();

// Get the default metatable for a type
final tableMetatable = defaultMetatables.getTypeMetatable('table');
final stringMetatable = defaultMetatables.getTypeMetatable('string');
final numberMetatable = defaultMetatables.getTypeMetatable('number');
final functionMetatable = defaultMetatables.getTypeMetatable('function');
final userdataMetatable = defaultMetatables.getTypeMetatable('userdata');
```

You can use these default metatables as a starting point for your own metatables:

```dart
// Create a custom string metatable based on the default one
final customStringMetatable = <String, dynamic>{
  ...defaultMetatables.getTypeMetatable('string')?.metamethods ?? {},
  "__add": (List<Object?> args) {
    final a = args[0] as Value;
    final b = args[1] as Value;
    return Value("${a.raw}${b.raw}");
  },
};
```

## Best Practices

1. **Use ValueClass**: Use the `ValueClass` utility to create values with metatables.
2. **Follow Lua semantics**: Ensure your metamethods behave like their Lua counterparts.
3. **Handle errors**: Throw appropriate exceptions when metamethods fail.
4. **Document your metatables**: Add comments explaining what each metamethod does.
5. **Test your metatables**: Create tests that verify your metamethods work correctly.
6. **Use default metatables**: Use the default metatables as a starting point for your own metatables.
7. **Be consistent**: Use the same metatable for all instances of a class.

## Common Pitfalls

1. **Forgetting to check types**: Always check the types of arguments in metamethods.
2. **Circular references**: Be careful with `__index` and `__newindex` to avoid infinite recursion.
3. **Missing metamethods**: Ensure you implement all necessary metamethods for your custom types.
4. **Inconsistent behavior**: Ensure your metamethods behave consistently with Lua's semantics.
5. **Performance issues**: Complex metamethods can impact performance, especially in tight loops.

## Conclusion

Metatables and metamethods are powerful features in Lua that allow you to customize the behavior of values. By understanding how to implement them in LuaLike, you can create rich, object-oriented code that behaves like native Lua code. The `ValueClass` utility and default metatables make it easier to work with metatables in a consistent way.