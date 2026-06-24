#!/bin/bash
# Wait until /scan is publishing (LiDAR driver is up).

TIMEOUT="${1:-25}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/source_ros_env.sh"

for _ in $(seq 1 "$TIMEOUT"); do
    if ros2 topic echo /scan --once >/dev/null 2>&1; then
        exit 0
    fi
    sleep 1
done

echo "ERROR: /scan not publishing after ${TIMEOUT}s (LiDAR failed to start)."
exit 1
