# DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

#!/bin/bash
# DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

set -e

PROJECT_DIR="/home/niko/development/tool-executor-service"
BINARY_PATH="/usr/local/bin/tool-executor"

echo "Starting high-integrity production redeployment..."

cd "$PROJECT_DIR"

echo "Building production Zig backend (ReleaseSafe)..."
zig build -Doptimize=ReleaseSafe

echo "Stopping tool-executor service..."
sudo systemctl stop tool-executor

echo "Deploying new binary..."
sudo cp zig-out/bin/tool-executor "$BINARY_PATH"

echo "Building and installing Python MCP wheel..."
uv build
uv pip install dist/*.whl --force-reinstall

echo "Restarting tool-executor service..."
sudo systemctl start tool-executor

echo "Verifying service status..."
systemctl status tool-executor --no-pager

echo "Redeployment successful."
