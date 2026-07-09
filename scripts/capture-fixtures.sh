#!/bin/bash
# Captures real Apple Container CLI JSON output as test fixtures.
# Run this against a newly installed CLI version before updating DTOs.
# Read-only: only version/status queries are executed; system state is not changed.
set -u

FIXTURES_DIR="$(cd "$(dirname "$0")/.." && pwd)/Tests/ContainerDeckKitTests/Fixtures"

if ! command -v container >/dev/null 2>&1; then
    echo "container CLI not found; cannot capture fixtures" >&2
    exit 1
fi

mkdir -p "$FIXTURES_DIR"

echo "Capturing system version..."
container system version --format json > "$FIXTURES_DIR/system-version.json" </dev/null

echo "Capturing system status (current state)..."
# Note: status exits non-zero when the system is stopped but still emits valid JSON.
if container system status --format json > /tmp/containerdeck-status.json </dev/null; then
    cp /tmp/containerdeck-status.json "$FIXTURES_DIR/system-status-running.json"
    echo "System is running; captured system-status-running.json"
    echo "To capture the stopped fixture, stop the system and re-run this script."
else
    cp /tmp/containerdeck-status.json "$FIXTURES_DIR/system-status-stopped.json"
    echo "System is stopped; captured system-status-stopped.json"
    echo "To capture the running fixture, start the system and re-run this script."
fi
rm -f /tmp/containerdeck-status.json

echo "Done. Review fixtures in $FIXTURES_DIR and update DTOs/tests if the schema changed."
