import 'package:lualike/src/environment.dart';
import 'package:lualike/src/value.dart';
import 'dart:math' as math;

/// Test library implementation for Lua test suite
/// This implements the T.* functions used in the Lua test suite
class TestLib {
  // Map of GC ages for objects
  static final Map<Object, String> _gcAges = {};

  // Map of GC colors for objects
  static final Map<Object, String> _gcColors = {};

  // Counter for userdata objects
  static int _userdataCounter = 0;

  // Registry for references
  static final Map<int, dynamic> _registry = {};
  static int _nextRef = 1;

  static final Map<String, dynamic> functions = {
    // GC related functions
    'gcage': gcage,
    'gccolor': gccolor,
    'gcstate': gcstate,

    // Userdata related functions
    'newuserdata': newuserdata,
    'pushuserdata': pushuserdata,
    'udataval': udataval,

    // Reference related functions
    'ref': tref,
    'getref': getref,
    'unref': unref,

    // Math related functions
    's2d': s2d,
    'd2s': d2s,
    'num2int': num2int,
    'log2': log2,

    // Table related functions
    'querytab': querytab,

    // String related functions
    'querystr': querystr,
  };

  /// Simulates the gcage function from the Lua test suite
  /// Returns the age of an object in the garbage collector
  /// Possible values: "new", "survival", "old", "old0", "old1", "touched1", "touched2"
  static Value gcage(List<Object?> args) {
    if (args.isEmpty) {
      return Value(null);
    }

    final obj = args[0];
    if (obj == null) {
      return Value("old"); // Default for nil
    }

    // If we have a stored age for this object, return it
    if (_gcAges.containsKey(obj)) {
      return Value(_gcAges[obj]!);
    }

    // For new objects, set them as "new" and return
    if (!_gcAges.containsKey(obj)) {
      _gcAges[obj] = "new";
      return Value("new");
    }

    // Default for other types
    return Value("old");
  }

  /// Simulates the gccolor function from the Lua test suite
  /// Returns the color of an object in the garbage collector
  /// Possible values: "white", "gray", "black", "dead"
  static Value gccolor(List<Object?> args) {
    if (args.isEmpty) {
      return Value(null);
    }

    final obj = args[0];
    if (obj == null) {
      return Value("black"); // Default for nil
    }

    // If we have a stored color for this object, return it
    if (_gcColors.containsKey(obj)) {
      return Value(_gcColors[obj]!);
    }

    // For tables with weak keys or values, we'll return "gray"
    if (obj is Value && obj.raw is Map) {
      if (obj.metatable != null) {
        final metatable = obj.metatable!;
        if (metatable.containsKey('__mode')) {
          _gcColors[obj] = "gray";
          return Value("gray");
        }
      }
    }

    // Default for other types
    _gcColors[obj] = "black";
    return Value("black");
  }

  /// Returns the current state of the garbage collector
  static Value gcstate(List<Object?> args) {
    // In a real implementation, this would return the actual state of the GC
    // Since we don't have access to the Lua GC internals in Dart, we'll simulate it
    return Value(
      "atomic",
    ); // One of: "pause", "propagate", "sweep", "finalize", "atomic"
  }

  /// Creates a new userdata object
  /// In Lua, userdata is a block of raw memory
  /// In our implementation, we'll use a Map to store the data
  static Value newuserdata(List<Object?> args) {
    // In Lua: T.newuserdata(size, tag)
    // We'll ignore the size parameter and just create a new userdata object
    int size = 0;
    if (args.isNotEmpty && args[0] is num) {
      size = (args[0] as num).toInt();
    }

    int tag = 0;
    if (args.length > 1 && args[1] is num) {
      tag = (args[1] as num).toInt();
    }

    final userData = <String, dynamic>{
      '_size': size,
      '_tag': tag,
      '_id': _userdataCounter++,
      '_type': 'userdata',
    };

    // Initialize with "new" age
    final value = Value(userData);
    _gcAges[value] = "new";
    _gcColors[value] = "white";

    return value;
  }

  /// Creates a light userdata object (pointer)
  static Value pushuserdata(List<Object?> args) {
    int pointer = 0;
    if (args.isNotEmpty && args[0] is num) {
      pointer = (args[0] as num).toInt();
    }

    final userData = <String, dynamic>{
      '_pointer': pointer,
      '_type': 'lightuserdata',
    };

    return Value(userData);
  }

  /// Gets the value of a userdata object
  static Value udataval(List<Object?> args) {
    if (args.isEmpty) {
      return Value(null);
    }

    final obj = args[0];
    if (obj == null) {
      return Value(0);
    }

    if (obj is Value && obj.raw is Map) {
      final map = obj.raw as Map;
      if (map.containsKey('_id')) {
        return Value(map['_id']);
      }
    }

    return Value(0);
  }

  /// Creates a reference to an object in the registry
  static Value tref(List<Object?> args) {
    if (args.isEmpty) {
      return Value(null);
    }

    final obj = args[0];
    final ref = _nextRef++;
    _registry[ref] = obj;

    return Value(ref);
  }

  /// Gets an object from the registry by reference
  static Value getref(List<Object?> args) {
    if (args.isEmpty || args[0] == null) {
      return Value(null);
    }

    final ref = args[0] is num ? (args[0] as num).toInt() : 0;
    if (_registry.containsKey(ref)) {
      return Value(_registry[ref]);
    }

    return Value(null);
  }

  /// Removes a reference from the registry
  static Value unref(List<Object?> args) {
    if (args.isEmpty || args[0] == null) {
      return Value(null);
    }

    final ref = args[0] is num ? (args[0] as num).toInt() : 0;
    _registry.remove(ref);

    return Value(null);
  }

  /// Converts a string to a double
  static Value s2d(List<Object?> args) {
    if (args.isEmpty || args[0] == null) {
      return Value(0.0);
    }

    final str = args[0].toString();
    try {
      final number = double.parse(str);
      return Value(number);
    } catch (e) {
      return Value(0.0);
    }
  }

  /// Converts a double to a string
  static Value d2s(List<Object?> args) {
    if (args.isEmpty || args[0] == null) {
      return Value("");
    }

    final number = args[0] is double || args[0] is int
        ? (args[0] as dynamic)
        : 0;
    return Value(number.toString());
  }

  /// Converts a number to an integer
  static Value num2int(List<Object?> args) {
    if (args.isEmpty || args[0] == null) {
      return Value(0);
    }

    if (args[0] is double) {
      return Value((args[0] as double).toInt());
    } else if (args[0] is int) {
      return Value(args[0] as int);
    }

    return Value(0);
  }

  /// Calculates the base-2 logarithm of a number
  static Value log2(List<Object?> args) {
    if (args.isEmpty || args[0] == null) {
      return Value(0.0);
    }

    double number = 0;
    if (args[0] is double) {
      number = args[0] as double;
    } else if (args[0] is int) {
      number = (args[0] as int).toDouble();
    }

    if (number <= 0) {
      return Value(0.0);
    }

    return Value(math.log(number) / math.log(2));
  }

  /// Returns information about a table
  static Value querytab(List<Object?> args) {
    if (args.isEmpty || args[0] == null) {
      return Value(null);
    }

    final obj = args[0];
    if (obj is! Value || obj.raw is! Map) {
      return Value(null);
    }

    final map = obj.raw as Map;
    final result = <String, dynamic>{
      'size': map.length,
      'weakkeys':
          obj.metatable != null &&
          obj.metatable!.containsKey('__mode') &&
          obj.metatable!['__mode'].toString().contains('k'),
      'weakvalues':
          obj.metatable != null &&
          obj.metatable!.containsKey('__mode') &&
          obj.metatable!['__mode'].toString().contains('v'),
    };

    return Value(result);
  }

  /// Returns information about a string
  static Value querystr(List<Object?> args) {
    if (args.isEmpty || args[0] == null) {
      return Value(null);
    }

    final str = args[0].toString();
    final result = <String, dynamic>{'length': str.length};

    return Value(result);
  }
}

/// Define the test library in the environment
void defineTestLibrary({required Environment env}) {
  // Create the T table
  final testTable = <String, dynamic>{};

  // Add all functions to the table
  TestLib.functions.forEach((key, value) {
    testTable[key] = value;
  });

  // Add the table to the environment
  env.define("T", Value(testTable));
}
