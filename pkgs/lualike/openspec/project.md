# Project Context

## Purpose
LuaLike is a Lua-compatible interpreter written in Dart, designed to be a drop-in replacement for Lua. It provides a clean AST-based interpreter with seamless interoperability between Dart and Lua code, enabling embedded scripting capabilities in Dart applications.

## Tech Stack
- **Language**: Dart (SDK >=3.9.0 <4.0.0)
- **Parser**: PetitParser for Lua syntax parsing
- **Testing**: Dart's built-in test framework with comprehensive test organization
- **Build Tools**: dart_console, args, logging for CLI functionality
- **Memory Management**: Custom generational garbage collector implementation
- **Standard Library**: Full Lua 5.4 compatible standard library implementation

## Project Conventions

### Code Style
- **Naming**: Follow Dart style guide - lowerCamelCase for variables/methods, UpperCamelCase for classes
- **Imports**: dart: imports first, then package: imports, then relative imports
- **Line Length**: ≤80 characters, enforced by dart format
- **Flow Control**: Use curly braces for all flow control statements
- **Constants**: Use lowerCamelCase (not SCREAMING_CAPS)
- **File Names**: lowercase_with_underscores for files and packages
- **Formatting**: Use `dart format .` and `dart fix --apply` for code formatting

### Architecture Patterns
- **AST-based Interpreter**: Primary execution engine using visitor pattern
- **Mixin-based Design**: Interpreter functionality split into focused mixins (AssignmentMixin, ControlFlowMixin, etc.)
- **Value System**: Unified Value class wrapping all Lua types with Dart interop
- **Environment-based Scoping**: Lexical scoping with upvalue support for closures
- **Generational GC**: Lua 5.4 compatible garbage collector with incremental collection
- **Standard Library**: Modular library system with metamethod support
- **Coroutine Support**: Full coroutine implementation with yield/resume semantics

### Testing Strategy
- **Comprehensive Test Suite**: 13/14 tests passing (calls.lua currently failing)
- **Tagged Test Organization**: Hierarchical tags (interpreter, stdlib, interop, gc, pm)
- **Test Categories**:
  - `interpreter/` - Core VM functionality, statements, expressions, functions
  - `stdlib/` - Standard library implementations (string, table, math, io, etc.)
  - `interop/` - Dart-Lua interoperability features
  - `gc/` - Garbage collection and memory management
  - `pm/` - Pattern matching implementation
- **Test Runner**: Custom compiled test runner (`test_runner`) for Lua compatibility tests
- **Integration Tests**: Tool-based integration testing with reference Lua comparison
- **Debug Support**: Extensive logging with `--debug` flag and `LOGGING_ENABLED` environment variable

### Git Workflow
- **Branching**: Feature branches with descriptive names
- **Commits**: Clear, descriptive commit messages following conventional format
- **Testing**: Always run full test suite before committing changes
- **CI/CD**: GitHub Actions workflow for automated testing

## Domain Context

### Lua Compatibility
- **Syntax**: Full Lua 5.4 syntax support including all control structures
- **Semantics**: Lua-compatible variable scoping, function calls, and table operations
- **Standard Library**: Complete implementation of Lua's standard library
- **Metatables**: Full metamethod support for custom types
- **Coroutines**: Native coroutine implementation with proper state management
- **Garbage Collection**: Generational GC matching Lua 5.4 behavior

### Interpreter Architecture
- **Parser**: PetitParser-based grammar for Lua syntax
- **AST**: Comprehensive AST with source span tracking for debugging
- **VM**: Visitor pattern-based interpreter with mixin-based functionality
- **Memory**: Custom garbage collector with generational collection
- **Interop**: Seamless bidirectional function calls between Dart and Lua

### CLI Interface
- **Drop-in Replacement**: Compatible with standard Lua CLI arguments
- **Execution Modes**: AST interpreter (default), bytecode VM (experimental)
- **Debug Features**: Extensive logging, stack traces, and debugging support
- **REPL Mode**: Interactive shell when no script provided

## Important Constraints

### Performance
- **Call Depth Limit**: 512 levels to prevent stack overflow in tests
- **Memory Management**: Generational GC with configurable thresholds
- **Incremental Collection**: Non-blocking garbage collection for responsiveness

### Compatibility
- **Lua 5.4 Reference**: Must maintain compatibility with Lua 5.4 semantics
- **Test Suite**: Must pass comprehensive Lua compatibility tests
- **API Stability**: Public API changes require careful consideration

### Development
- **Test-First**: Always run tests before reporting changes
- **Minimal Changes**: Keep code changes focused and minimal
- **Documentation**: Update docs directory when adding features

## External Dependencies

### Core Dependencies
- `petitparser`: Lua syntax parsing
- `source_span`: Source code position tracking
- `characters`: Unicode character handling
- `logging`: Debug and diagnostic logging

### CLI Dependencies
- `dart_console`: Terminal interaction
- `args`: Command-line argument parsing
- `glob`: File pattern matching

### Utility Dependencies
- `crypto`: Cryptographic functions for standard library
- `archive`: Archive handling for module loading
- `yaml`: Configuration file parsing
- `convert`: Data format conversion

### Development Dependencies
- `lints`: Dart static analysis
- `test`: Testing framework
- `build_runner`: Code generation
- `nocterm`: Terminal utilities
