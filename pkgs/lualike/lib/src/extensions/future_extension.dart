import '../value.dart';

/// Extension methods for Futures to simplify async Value operations
extension FutureValueExtension on Future<dynamic> {
  /// Wait for a Future and ensure the result is wrapped in a Value
  Future<Value> toValue() async {
    final result = await this;
    return result is Value ? result : Value(result);
  }

  /// Unwrap a Future`<Value>` to Future`<dynamic>`
  Future<dynamic> unwrapValue() async {
    final result = await this;
    return result is Value ? result.unwrap() : result;
  }
}
