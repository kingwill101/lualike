part of '../love_runtime.dart';

/// The canonical set of standard LOVE 11.5 event name strings.
///
/// These correspond to the constants of the LOVE [Event] enum. While
/// [LoveEventState.pushMessage] accepts any string (custom events are allowed),
/// only these values are part of the standard LOVE event API contract.
const Set<String> loveEventNames = <String>{
  'focus',
  'joystickpressed',
  'joystickreleased',
  'keypressed',
  'keyreleased',
  'mousepressed',
  'mousereleased',
  'quit',
  'resize',
  'visible',
  'mousefocus',
  'threaderror',
  'joystickadded',
  'joystickremoved',
  'joystickaxis',
  'joystickhat',
  'gamepadpressed',
  'gamepadreleased',
  'gamepadaxis',
  'textinput',
  'mousemoved',
  'lowmemory',
  'textedited',
  'wheelmoved',
  'touchpressed',
  'touchreleased',
  'touchmoved',
  'directorydropped',
  'filedropped',
  // Legacy abbreviated aliases from LOVE < 0.8.0
  'jp',
  'jr',
  'kp',
  'kr',
  'mp',
  'mr',
  'q',
  'f',
};

/// Returns `true` if [name] is a standard LOVE event constant.
///
/// Note that [LoveEventState.pushMessage] accepts arbitrary event names; this
/// helper exists for validation and documentation purposes only.
bool loveIsValidEventName(String name) => loveEventNames.contains(name);

/// One queued LOVE event plus its positional arguments.
class LoveEventMessage {
  /// Creates an event message with [name] and immutable [arguments].
  LoveEventMessage({required this.name, List<Object?> arguments = const []})
    : arguments = List<Object?>.unmodifiable(arguments);

  /// The LOVE event name.
  final String name;

  /// The positional Lua arguments carried by this event.
  final List<Object?> arguments;

  /// The Lua return tuple for this message.
  List<Object?> toValues() {
    return <Object?>[name, ...arguments];
  }
}

/// FIFO event queue and waiter registry for `love.event`.
class LoveEventState {
  final ListQueue<LoveEventMessage> _queue = ListQueue<LoveEventMessage>();
  final ListQueue<Completer<LoveEventMessage>> _waiters =
      ListQueue<Completer<LoveEventMessage>>();

  /// Whether no queued event messages are currently available.
  bool get isEmpty => _queue.isEmpty;

  /// The number of queued event messages waiting to be polled.
  int get length => _queue.length;

  /// Removes all queued event messages.
  void clear() {
    _queue.clear();
  }

  /// Pumps backend events into the queue.
  ///
  /// This runtime keeps event production elsewhere, so this is a no-op.
  void pump() {}

  /// Enqueues a message named [name] with optional [arguments].
  ///
  /// If a waiter is already blocked in [wait], this completes that waiter
  /// immediately instead of adding to the queue.
  bool pushMessage(String name, [List<Object?> arguments = const []]) {
    final message = LoveEventMessage(name: name, arguments: arguments);
    final waiter = _waiters.isEmpty ? null : _waiters.removeFirst();
    if (waiter != null) {
      waiter.complete(message);
      return true;
    }

    _queue.addLast(message);
    return true;
  }

  /// Removes and returns the next queued message, if one is available.
  LoveEventMessage? poll() {
    if (_queue.isEmpty) {
      return null;
    }

    return _queue.removeFirst();
  }

  /// Returns the next event message, waiting asynchronously when needed.
  Future<LoveEventMessage> wait() {
    final message = poll();
    if (message != null) {
      return Future<LoveEventMessage>.value(message);
    }

    final completer = Completer<LoveEventMessage>();
    _waiters.addLast(completer);
    return completer.future;
  }
}
