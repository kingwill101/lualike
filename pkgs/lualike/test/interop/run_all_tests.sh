#!/bin/bash

# Run all interop tests
echo "Running all interop tests..."
dart test test/interop

# Run specific categories
echo -e "\nRunning table access tests..."
dart test test/interop/table_access

echo -e "\nRunning function call tests..."
dart test test/interop/function_call

echo -e "\nRunning module tests..."
dart test test/interop/module

# Make the script executable with: chmod +x test/interop/run_all_tests.sh