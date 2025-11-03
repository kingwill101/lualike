/// A simple generic stack implementation.
///
/// Provides standard stack operations like push, pop, and peek using a List
/// as the underlying data structure. The stack can hold elements of any type T.
class Stack<T> {
  /// Internal list used to store stack elements.
  final List<T> _list = <T>[];

  /// Pushes an element onto the top of the stack.
  ///
  /// [value] - The element to push onto the stack.
  void push(T value) => _list.add(value);

  /// Removes and returns the element on top of the stack.
  ///
  /// Throws [StateError] if the stack is empty.
  /// Returns the element that was on top of the stack.
  T pop() => _list.removeLast();

  /// Returns the element on top of the stack without removing it.
  ///
  /// Throws [StateError] if the stack is empty.
  /// Returns the element on top of the stack.
  T peek() => _list.last;

  /// Whether the stack contains no elements.
  bool get isEmpty => _list.isEmpty;

  /// The number of elements in the stack.
  int get length => _list.length;

  /// Exposes the items currently on the stack without allowing mutation.
  Iterable<T> get items => List.unmodifiable(_list);

  /// Removes all elements from the stack.
  void clear() => _list.clear();

  /// Trims the stack to at most [maxLength] items, removing the oldest entries.
  void trimTo(int maxLength) {
    if (maxLength < 0) {
      return;
    }
    final excess = _list.length - maxLength;
    if (excess > 0) {
      _list.removeRange(0, excess);
    }
  }
}
