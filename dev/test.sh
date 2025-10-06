#!/bin/bash

# Default verbosity level
VERBOSITY="-vvv"
VIA_IR=""
CONTRACT=""
TEST=""

# Parse arguments
for arg in "$@"; do
  case $arg in
    ir)
      VIA_IR="--via-ir"
      ;;
    v|vv|vvv|vvvv)
      VERBOSITY="-vvv$arg"
      ;;
    *)
      # Check if the arg looks like a contract name (PascalCase)
      if [[ $arg =~ ^[A-Z][a-zA-Z0-9]* ]]; then
        CONTRACT="$arg"
      else
        # Otherwise assume it's a test name
        TEST="$arg"
      fi
      ;;
  esac
done

# If a specific contract is specified
if [[ -n "$CONTRACT" ]]; then
  echo "Running tests for contract: $CONTRACT"
  forge test --match-contract "$CONTRACT" $VERBOSITY $VIA_IR
# If a specific test is specified
elif [[ -n "$TEST" ]]; then
  echo "Running test: $TEST"
  forge test --match-test "$TEST" -vvvv $VIA_IR # -vvvv for execution logs, and setup logs if test fails
# If no specific test/contract is provided
else
  echo "Running all tests"
  forge test $VERBOSITY $VIA_IR
fi 