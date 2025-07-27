# LuaLike Integration Test Suite

This directory contains tools for running integration tests against the official Lua test suite.

## Overview

The integration test suite downloads the official Lua test suite and runs it against the LuaLike implementation. It provides detailed reports on test results, including pass/fail status, execution time, and error messages.

## Files

- `integration.dart` - The main integration test runner
- `skip_tests.yaml` - Configuration file for tests that should be skipped

## Usage

The integration test suite can be run using the `just` command:

```bash
# Run all tests
just integrate

# Run tests with verbose output
just integrate-verbose

# Run tests in parallel
just integrate-parallel

# Run tests for a specific category
just integrate-category core

# List available test categories
just list-categories

# Run tests matching a pattern
just integrate-filter "string.*"
```

You can also run the integration test suite directly:

```bash
dart run tools/integration.dart [options]
```

### Options

- `--ast` - Run tests using AST interpreter (default)
- `--bytecode` - Run tests using bytecode VM
- `--internal` - Enable internal tests (requires specific build)
- `--path <path>` - Specify the path to the test suite (default: .lua-tests)
- `--log-path <path>` - Specify the path for log files
- `--skip-list <path>` - Specify the path to the skip list YAML file (default: tools/skip_tests.yaml)
- `--verbose`, `-v` - Enable verbose output
- `--parallel`, `-p` - Run tests in parallel
- `--jobs`, `-j <n>` - Number of parallel jobs (default: 4)
- `--filter`, `-f <regex>` - Filter tests by name using regex
- `--category`, `-c <cat>` - Run tests from specific category
- `--list-categories` - List available test categories

## Test Categories

Tests are organized into the following categories:

- `core` - Core language features (calls, closures, constructs, errors, events, locals)
- `api` - API tests
- `strings` - String manipulation tests
- `tables` - Table manipulation tests
- `math` - Math library tests
- `io` - I/O tests
- `coroutines` - Coroutine tests
- `gc` - Garbage collection tests
- `metamethods` - Metamethod tests
- `modules` - Module system tests

## Skip List

The `skip_tests.yaml` file contains a list of tests that should be skipped when running the integration tests. This is useful for tests that require features not yet implemented or that are known to fail.

Example:

```yaml
skip_tests:
  - api.lua
  - coroutine.lua
  - gc.lua
```

## Test Reports

Test reports are generated in the specified log directory (default: test-logs/). The following files are created:

- `summary_report.txt` - A human-readable summary of the test results
- `report.json` - A machine-readable JSON report of the test results
- Individual log files for each test

## Adding New Tests

To add new tests, simply add them to the test suite directory. The integration test runner will automatically discover and run them.