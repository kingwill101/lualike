part of '../love_api_bindings.dart';

String _loveLuaJitNumberToString(num value) {
  final text = value.toString();
  if (text.endsWith('.0')) {
    return text.substring(0, text.length - 2);
  }
  return text;
}
