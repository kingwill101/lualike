library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../../generated/love_api_reference.g.dart' show loveApiEnums;

final Expando<bool> _loveEventExtrasInstalled = Expando<bool>(
  'love2dEventExtrasInstalled',
);

Map<String, Object?> _buildEventEnumMap() {
  final result = <String, Object?>{};
  for (final enumDoc in loveApiEnums) {
    if (enumDoc.symbol == 'Event') {
      for (final constant in enumDoc.constants) {
        result[constant.name] = constant.name;
      }
      break;
    }
  }
  return result;
}

/// The canonical LOVE `Event` enum constants, built once from the generated
/// API reference. Each key maps to itself so that `Event.focus == "focus"`.
final Map<String, Object?> _loveEventEnumMap = _buildEventEnumMap();

/// Extends the installed `love.event` module table with the `Event` enum table
/// and registers a global `Event` table in [runtime].
///
/// After this call:
/// - `love.event.Event.focus == "focus"` (within the module namespace)
/// - `Event.focus == "focus"` (global shorthand, consistent with how LÖVE's
///   C++ compatibility layer exposes enum types to Lua)
///
/// Each [runtime] instance gets its own copy of the table so separate runtimes
/// do not share mutable state.
void installLoveEventExtraBindings(LuaRuntime runtime) {
  if (_loveEventExtrasInstalled[runtime] == true) {
    return;
  }
  _loveEventExtrasInstalled[runtime] = true;

  // Give each runtime its own table copy.
  final enumValue = Value(Map<String, Object?>.from(_loveEventEnumMap));

  // Install as love.event.Event
  final eventTable = _eventModuleTable(runtime);
  eventTable?['Event'] = enumValue;

  // Install as the global Event table.
  runtime.globals.define('Event', enumValue);
}

Map<dynamic, dynamic>? _eventModuleTable(LuaRuntime runtime) {
  final love = runtime.getCurrentEnv().get('love');
  final loveTable = love is Value ? love.raw : love;
  if (loveTable is! Map<dynamic, dynamic>) {
    return null;
  }

  final event = loveTable['event'];
  final eventTable = event is Value ? event.raw : event;
  if (eventTable is! Map<dynamic, dynamic>) {
    return null;
  }

  return eventTable;
}
