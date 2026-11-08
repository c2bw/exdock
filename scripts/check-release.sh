#!/bin/sh
# Separate VMs keep the normal test application and Docker harness isolated.
set -eu
cd "$(dirname "$0")/.."
python3 -m unittest discover -s test/release -p '*_test.py'
mix precommit
mix test.release
