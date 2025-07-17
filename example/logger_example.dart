import 'package:lualike/lualike.dart';

void main() async {
  // Enable logging
  Logger.setEnabled(true);

  print('Running with logging enabled:');
  print('----------------------------');

  // Execute some code with logging enabled
  final result = await executeCode('''
    local x = 10
    local y = 20
    return x + y
  ''');

  print('\nResult: $result');

  print('\nRunning with logging disabled:');
  print('----------------------------');

  // Disable logging
  Logger.setEnabled(false);

  // Execute the same code again
  final result2 = await executeCode('''
    local x = 10
    local y = 20
    return x + y
  ''');

  print('\nResult: $result2');
}
