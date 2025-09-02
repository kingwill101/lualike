# Building a Lua-like Library with Builder Interface

This document shows the easiest way to create a library with a builder interface similar to how strings work in Lua, where you can call methods directly on objects using the colon syntax (`obj:method()`).

## The Pattern

Looking at how the string library is implemented in `lib_string.dart`, the key components are:

### 1. **Library Functions Map**

First, create a map of your library functions:

```dart
class MyBuilderLib {
  static final Map<String, dynamic> functions = {
    "create": Value(_Create()),
    "build": Value(_Build()),
    "add": Value(_Add()),
    "size": Value(_Size()),
    "clear": Value(_Clear()),
  };
}
```

### 2. **ValueClass with `__index` Metamethod**

The magic happens in the `__index` metamethod that enables method calls on objects:

```dart
static final ValueClass builderClass = ValueClass.create({
  '__index': (List<Object?> args) {
    final obj = args[0] as Value;  // The object being accessed
    final key = args[1] as Value;  // The method name
    
    if (key.raw is String) {
      final method = functions[key.raw];
      if (method != null) {
        // Return a function that will be called later
        return Value((callArgs) {
          // Handle both obj:method() and obj.method(obj) syntax
          if (callArgs.isNotEmpty && callArgs.first == obj) {
            return method.call(callArgs);
          }
          return method.call([obj, ...callArgs]);
        });
      }
    }
    
    return Value(null);
  },
  // Other metamethods like __len, __tostring, etc.
});
```

### 3. **Apply Metatable to Objects**

When creating objects, apply the metatable:

```dart
class _Create implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    final builder = MyBuilder();
    final value = Value(builder);
    
    // Apply the metatable to enable method chaining
    value.setMetatable(MyBuilderLib.builderClass.metamethods);
    
    return value;
  }
}
```

### 4. **Library Registration**

Register your library with the environment:

```dart
void defineMyBuilderLibrary({required Environment env}) {
  final builderTable = <String, dynamic>{};
  
  for (final entry in MyBuilderLib.functions.entries) {
    builderTable[entry.key] = entry.value;
  }
  
  env.define(
    "mybuilder", 
    Value(builderTable, metatable: MyBuilderLib.builderClass.metamethods),
  );
}
```

## Complete Example

Here's a complete working example in `lib/src/stdlib/my_builder_lib.dart`:

```dart
import 'package:lualike/lualike.dart';
import 'package:lualike/src/stdlib/metatables.dart';

/// A simple builder class that accumulates items
class MyBuilder {
  final List<String> items = [];
  
  void add(String item) => items.add(item);
  void clear() => items.clear();
  String build() => items.join(' ');
  int get size => items.length;
  
  @override
  String toString() => 'MyBuilder(${items.length} items)';
}

class MyBuilderLib {
  static final Map<String, dynamic> functions = {
    "create": Value(_Create()),
    "build": Value(_Build()),
    "add": Value(_Add()),
    "size": Value(_Size()),
    "clear": Value(_Clear()),
  };
  
  static final ValueClass builderClass = ValueClass.create({
    '__len': (List<Object?> args) {
      final obj = args[0] as Value;
      final builder = obj.raw as MyBuilder;
      return Value(builder.items.length);
    },
    '__index': (List<Object?> args) {
      final obj = args[0] as Value;
      final key = args[1] as Value;
      
      if (key.raw is String) {
        final method = functions[key.raw];
        if (method != null) {
          return Value((callArgs) {
            if (callArgs.isNotEmpty && callArgs.first == obj) {
              return method.call(callArgs);
            }
            return method.call([obj, ...callArgs]);
          });
        }
      }
      
      return Value(null);
    },
    '__tostring': (List<Object?> args) {
      final obj = args[0] as Value;
      final builder = obj.raw as MyBuilder;
      return Value(builder.toString());
    },
  });
}

// Function implementations...
class _Create implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    final builder = MyBuilder();
    final value = Value(builder);
    value.setMetatable(MyBuilderLib.builderClass.metamethods);
    return value;
  }
}

class _Add implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError.typeError("add requires a MyBuilder object and an item");
    }
    
    final obj = args[0] as Value;
    final builder = obj.raw as MyBuilder;
    final item = (args[1] as Value).raw.toString();
    
    builder.add(item);
    return obj; // Return builder for method chaining
  }
}

// ... other function implementations

void defineMyBuilderLibrary({required Environment env}) {
  final builderTable = <String, dynamic>{};
  
  for (final entry in MyBuilderLib.functions.entries) {
    builderTable[entry.key] = entry.value;
  }
  
  env.define(
    "mybuilder", 
    Value(builderTable, metatable: MyBuilderLib.builderClass.metamethods),
  );
}
```

## Usage in Lua

Once registered, you can use it in Lua code like this:

```lua
-- Create a new builder
local builder = mybuilder.create()

-- Use method chaining (like strings in Lua)
builder:add("Hello")
builder:add("World")
builder:add("!")

-- Build the result
local result = builder:build()
print("Result: " .. result)

-- Check size
print("Size: " .. builder:size())

-- Can also use length operator
print("Length: " .. #builder)

-- Clear and rebuild with method chaining
builder:clear()
builder:add("New"):add("Content"):add("Here")
print("New result: " .. builder:build())
```

## Key Points

1. **`__index` metamethod** is what makes `obj:method()` work
2. **Method chaining** works by returning the object from methods that modify it
3. **Metatable application** happens when creating objects, not when defining the library
4. **Both syntaxes** `obj:method()` and `obj.method(obj)` are handled by the same metamethod
5. **Type checking** should be done in each function implementation
6. **Error handling** follows Lua conventions using `LuaError.typeError()`

This pattern allows you to create fluent, chainable APIs that feel natural in Lua while being implemented efficiently in Dart.
