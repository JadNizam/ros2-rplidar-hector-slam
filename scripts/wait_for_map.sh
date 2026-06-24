#!/bin/bash
# Wait for /map occupancy grid (slam_toolbox transient_local).

TIMEOUT="${1:-45}"
TOPIC="${2:-/map}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/source_ros_env.sh"

MAP_QOS="--qos-durability transient_local --qos-reliability reliable"

for _ in $(seq 1 "$TIMEOUT"); do
    if ros2 topic echo "$TOPIC" --once $MAP_QOS >/dev/null 2>&1; then
        exit 0
    fi
    sleep 1
done

echo "ERROR: ${TOPIC} not published after ${TIMEOUT}s."
exit 1
