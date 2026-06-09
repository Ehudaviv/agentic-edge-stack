#!/bin/bash
set -e

# Get script directory to run from root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Activate virtualenv if present
if [ -d ".venv" ]; then
  echo "Activating Python virtual environment..."
  source .venv/bin/activate
else
  echo "Warning: .venv not found. Running in system Python context."
fi

# Verify or install Locust
if ! python3 -c "import locust" &> /dev/null; then
  echo "Locust is not installed. Installing locust..."
  pip install locust
fi

MODE=${1:-ui}
USERS=${USERS:-100}
SPAWN_RATE=${SPAWN_RATE:-10}
RUN_TIME=${RUN_TIME:-2m}

echo "========================================================="
echo "            Starting Locust Load Testing Tool"
echo "========================================================="
echo "Target: http://localhost:30000 (FastAPI Agent NodePort)"
echo ""

if [ "$MODE" = "headless" ]; then
  echo "Mode: Headless CLI ($USERS users, $SPAWN_RATE spawn rate, $RUN_TIME run time)"
  echo "Executing load test..."
  locust -f tests/load_test.py --headless -u "$USERS" -r "$SPAWN_RATE" --run-time "$RUN_TIME" --host http://localhost:30000
else
  echo "Mode: Web UI server"
  echo "Open http://localhost:8089 in your browser to configure and start the test."
  echo "Press Ctrl+C to terminate."
  echo "========================================================="
  locust -f tests/load_test.py --host http://localhost:30000
fi
