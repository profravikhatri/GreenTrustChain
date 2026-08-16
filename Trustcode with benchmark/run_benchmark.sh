#!/usr/bin/env bash
set -euo pipefail

# run_benchmark.sh
# Orchestrates a local smoke benchmark for GreenTrustChain.
# Usage: ./run_benchmark.sh [--sample N]

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
INTERFACES_DIR="$ROOT_DIR/Interfaces"
PYTHON_DIR="$ROOT_DIR/Python"
TESTS_DIR="$ROOT_DIR/Tests"
DATASET="$ROOT_DIR/GSCROF_benchmark_95556.csv"
RESULTS_DIR="$ROOT_DIR/results"
SAMPLE_FILE="$ROOT_DIR/sample.csv"
SAMPLE_SIZE=200

if [ "$1" = "--sample" ] 2>/dev/null; then
  SAMPLE_SIZE="$2"
fi

mkdir -p "$RESULTS_DIR"

echo "=== GreenTrustChain benchmark runner ==="

# Create a small sample to run a quick smoke test
if [ -f "$DATASET" ]; then
  echo "Creating sample of $SAMPLE_SIZE rows from dataset"
  head -n $SAMPLE_SIZE "$DATASET" > "$SAMPLE_FILE"
else
  echo "Dataset not found at $DATASET"
  echo "Please place GSCROF_benchmark_95556.csv into: $ROOT_DIR"
  exit 1
fi

# Start Hardhat node if Interfaces has a package.json (assumes dev dependencies installed by user)
if [ -f "$INTERFACES_DIR/package.json" ]; then
  echo "Starting Hardhat node..."
  (cd "$INTERFACES_DIR" && npx hardhat node) > "$RESULTS_DIR/hardhat_node.log" 2>&1 &
  HH_PID=$!
  echo "Hardhat PID: $HH_PID"
  # Give node a moment to start
  sleep 3
else
  echo "No package.json in Interfaces/ — ensure Hardhat is installed and start a node at http://127.0.0.1:8545"
  HH_PID=""
fi

# Deploy contracts
if [ -d "$INTERFACES_DIR" ]; then
  echo "Deploying contracts via Interfaces/deploy.ts"
  (cd "$INTERFACES_DIR" && npx hardhat run --network localhost ./deploy.ts) | tee "$RESULTS_DIR/deploy.log"
else
  echo "Interfaces directory missing; aborting deploy"
  exit 1
fi

# Run Python trust engine on sample
if [ -d "$PYTHON_DIR" ]; then
  echo "Running Python trust engine on sample"
  (cd "$PYTHON_DIR" && python3 -m venv .venv || true)
  # Activate venv for the remaining commands in a subshell
  (
    cd "$PYTHON_DIR"
    if [ -f requirements.txt ]; then
      source .venv/bin/activate || true
      pip install -r requirements.txt || true
    fi
    python trust_engine.py --dataset "$SAMPLE_FILE" --config trust_config_example.json
  )
else
  echo "Python directory missing; aborting trust engine run"
  exit 1
fi

# Replay workload using Tests/replay_workload.ts (expects ts-node and project setup)
if [ -d "$TESTS_DIR" ]; then
  echo "Replaying workload against deployed contracts (sample)"
  (cd "$TESTS_DIR" && npx ts-node replay_workload.ts --dataset "$SAMPLE_FILE") | tee "$RESULTS_DIR/replay.log" || true
else
  echo "Tests directory missing; cannot run replay_workload.ts"
fi

# Collect results
echo "Collecting results"
cp -v "$PYTHON_DIR/results/trust_scores.csv" "$RESULTS_DIR/" || true
cp -v "$PYTHON_DIR/results/trust_metadata.json" "$RESULTS_DIR/" || true

# Stop Hardhat node if we started it
if [ -n "${HH_PID:-}" ]; then
  echo "Stopping Hardhat node (PID $HH_PID)"
  kill "$HH_PID" || true
fi

echo "Benchmark run complete. Results are in: $RESULTS_DIR"
