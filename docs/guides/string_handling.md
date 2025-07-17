# String Handling in LuaLike

This guide covers how strings work in LuaLike, focusing on the `LuaString` class, encoding differences, and proper string handling.

## Core Concepts

### LuaString vs Dart String

LuaLike uses `LuaString` for all string operations to maintain Lua's byte-sequence semantics:

```dart
// Lua strings are byte sequences, not Unicode strings
final luaStr = LuaString.fromDartString("Héllo"); // UTF-8 encoded bytes
final dartStr = "Héllo"; // UTF-16 code units

print(luaStr.length);  // 6 bytes (é is 2 bytes in UTF-8)
print(dartStr.length); // 5 code units
```

### LuaString Class

```dart
class LuaString {
  final Uint8List bytes;  // Raw byte data

  // Create from Dart string (UTF-8 encoded)
  factory LuaString.fromDartString(String s);

  // Create from raw bytes
  factory LuaString.fromBytes(List<int> bytes);

  // Convert to Dart string (UTF-8 decoded)
  String toString();

  // Latin-1 interpretation (for display)
  String toLatin1String();
}
```

## String Creation and Conversion

### From Dart to Lua

```dart
// Automatic conversion via Value
lua.setGlobal('text', 'Hello 世界');  // Becomes LuaString internally

// Explicit LuaString creation
final luaString = LuaString.fromDartString('Hello 世界');
lua.setGlobal('text', Value(luaString));
```

### From Lua to Dart

```dart
await lua.execute('result = "Hello 世界"');
final value = lua.getGlobal('result') as Value;

// Access raw LuaString
final luaString = value.raw as LuaString;
print(luaString.bytes);  // [72, 101, 108, 108, 111, 32, 228, 184, 150, 231, 149, 140]

// Convert to Dart string
final dartString = luaString.toString();  // "Hello 世界"
```

## Encoding Handling

### UTF-8 vs Latin-1

```dart
// UTF-8 encoding (default)
final utf8String = LuaString.fromDartString("café");
print(utf8String.bytes);  // [99, 97, 102, 195, 169] (é = 0xC3 0xA9)

// Raw bytes (for binary data)
final binaryString = LuaString.fromBytes([0xFF, 0xFE, 0x00, 0x41]);
print(binaryString.toLatin1String());  // Shows raw bytes as Latin-1
```

### String Length Semantics

```dart
await lua.execute('''
  local ascii = "hello"
  local utf8 = "café"

  ascii_len = #ascii  -- 5 bytes
  utf8_len = #utf8    -- 5 bytes (c,a,f,é) where é is 2 bytes = 6 total
''');
```

## String Operations

### Byte-level Operations

```dart
// string.byte - get byte values
await lua.execute('''
  local s = "café"
  b1, b2, b3, b4, b5 = string.byte(s, 1, -1)
''');
// b1=99, b2=97, b3=102, b4=195, b5=169 (UTF-8 bytes for "café")

// string.char - create from byte values
await lua.execute('''
  local s = string.char(195, 169)  -- UTF-8 for "é"
''');
```

### String Formatting

The `string.format` function handles different types correctly:

```dart
await lua.execute('''
  -- %q preserves byte sequences
  local bytes = "\\225"  -- Single byte 225
  local quoted = string.format("%q", bytes)  -- "\\225"

  -- %s converts to string representation
  local display = string.format("%s", bytes)  -- Shows as replacement char if invalid UTF-8
''');
```

## Working with Binary Data

### Creating Binary Strings

```dart
// From Dart
final binaryData = LuaString.fromBytes([0x00, 0x01, 0xFF, 0xFE]);
lua.setGlobal('binary', Value(binaryData));

// From Lua
await lua.execute('''
  local binary = string.char(0, 1, 255, 254)
  local packed = string.pack("bbbb", 0, 1, 255, 254)
''');
```

### Handling Null Bytes

```dart
await lua.execute('''
  local with_null = "hello\\0world"
  local length = #with_null  -- 11 (null bytes count)
  local sub = string.sub(with_null, 1, 5)  -- "hello"
''');
```

## Custom String Functions

When exposing string functions, work with the underlying bytes:

```dart
lua.expose('getBytes', (List<Object?> args) {
  final value = args[0] as Value;
  final luaString = value.raw as LuaString;

  // Return byte array as Lua table
  final bytes = <int, int>{};
  for (int i = 0; i < luaString.bytes.length; i++) {
    bytes[i + 1] = luaString.bytes[i];  // 1-indexed
  }
  return Value(bytes);
});

lua.expose('fromBytes', (List<Object?> args) {
  final table = (args[0] as Value).raw as Map;
  final bytes = <int>[];

  for (int i = 1; i <= table.length; i++) {
    final byte = (table[i] as Value).raw as int;
    bytes.add(byte);
  }

  return Value(LuaString.fromBytes(bytes));
});
```

## String Interning

LuaLike implements string interning for short strings:

```dart
// Short strings (≤40 chars) are interned
final str1 = StringInterning.intern("hello");
final str2 = StringInterning.intern("hello");
// str1 and str2 are the same object

// Long strings are not interned
final long1 = StringInterning.intern("a" * 50);
final long2 = StringInterning.intern("a" * 50);
// long1 and long2 are different objects
```
