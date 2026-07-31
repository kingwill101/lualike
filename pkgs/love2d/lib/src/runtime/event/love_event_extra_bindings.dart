library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import '../love_binding_helpers.dart';
import '../love_module_table_helpers.dart';
import '../love_runtime.dart';

/// Whether the extra event bindings have already been installed for a runtime.
final Expando<bool> _loveEventExtrasInstalled = Expando<bool>(
  'love2dEventExtrasInstalled',
);

/// The canonical LOVE `Event` enum constants, built once from the generated
/// API reference. Each key maps to itself so that `Event.focus == "focus"`.
final Map<String, Object?> _loveEventEnumMap = loveEnumMapForSymbol('Event');

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

  final eventTable = loveModuleTable(runtime, 'event');
  if (eventTable != null) {
    final builder = loveBindingBuilder(runtime);
    eventTable['poll_i'] = Value(
      builder.create((args) {
        final message = LoveRuntimeContext.of(runtime).events.poll();
        if (message == null) {
          return null;
        }

        return Value.multi(message.toValues());
      }),
      functionName: 'poll_i',
    );
    eventTable['Event'] = enumValue;
  }

  // Install as the global Event table.
  runtime.globals.define('Event', enumValue);
}

