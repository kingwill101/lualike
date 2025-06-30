Lualike is a lua interpreter written in Dart. It is designed to be a drop-in replacement for Lua, allowing you to run Lua scripts with minimal changes.

1. **Always run the full Dart test suite**  
   Before submitting or merging any code changes, ensure that the entire Dart test suite passes. This helps catch regressions and unintended side effects.

2. **Verify nothing is broken**  
   After making changes, confirm that all existing functionality works as expected. Do not assume that passing a subset of tests is sufficient.

3. **Address test failures individually**  
   If any test fails, address each failure one at a time.
   Add useful debug output to make it easier to understand what's happening.
   Logger class has a Logger.setEnabled(false); which works with --debug flag when using the interpreter (dart run bin/main.dart) Note it can be very noisy.
   Compare results with the reference lua interpreter when uncertain. our interpreter supports the same cli arguments as the reference lua interpreter.

4. **Prefer targeted test cases**  
   When fixing bugs or investigating issues, write dedicated test cases that isolate the failing expression or behavior.  
   - Avoid repeatedly running the full test suite/complete lua script just to reproduce a single error.
   - Construct minimal test cases that include all necessary functions, variables, and context to trigger the issue.

5. **General best practices**
   - Keep code changes minimal and focused.
   - Document any non-obvious decisions or workarounds in code comments.
   - Communicate clearly in pull requests or code reviews about the changes made and why.
   - there is a docs directory, update it where necessary.

6. **Use the dartfmt tool**
   - Use the dartfmt tool to format your code according to the Dart style guide. 
   - run dart fix --apply to apply any fixes suggested by the tool.
7. **Follow Dart's style guide**  
   Adhere to the Dart style guide for code formatting and organization. This ensures consistency and readability across the codebase.