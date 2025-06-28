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
}
