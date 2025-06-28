set shell := ["zsh", "-cu"]

peg:
	/home/kingwill101/.pub-cache/bin/peg lib/src/grammar.peg

run +ARG: peg
  ~/.fvm/fvm dart run bin/main.dart --debug -e "{{ARG}}"

check +ARG: peg
  ~/.fvm/fvm dart run bin/main.dart -e "{{ARG}}"

compare *ARG='':
    ~/.fvm/fvm dart run tools/compare.dart {{ARG}}

compile:
    ~/.fvm/fvm dart compile exe --output lualike bin/main.dart

repl: compile
    ./lualike

# Run integration tests with default options
integrate *ARG='':
    ~/.fvm/fvm dart run tools/integration.dart {{ARG}}

# Run integration tests with verbose output
integrate-verbose *ARG='':
    ~/.fvm/fvm dart run tools/integration.dart {{ARG}} --verbose

# Run integration tests in parallel
integrate-parallel *ARG='':
    ~/.fvm/fvm dart run tools/integration.dart {{ARG}} --parallel

# Run integration tests for a specific category
integrate-category CATEGORY *ARG='':
    ~/.fvm/fvm dart run tools/integration.dart {{ARG}} --category {{CATEGORY}}

# List available test categories
list-categories:
    ~/.fvm/fvm dart run tools/integration.dart --list-categories

# Run integration tests with a filter pattern
integrate-filter PATTERN *ARG='':
    ~/.fvm/fvm dart run tools/integration.dart {{ARG}} --filter "{{PATTERN}}"

file +ARG:
    ~/.fvm/fvm dart run bin/main.dart {{ARG}}

example +ARG:
    ~/.fvm/fvm dart run example/{{ARG}}.dart

install-peg:
    dart pub global activate --source git  https://github.com/mezoni/peg.git