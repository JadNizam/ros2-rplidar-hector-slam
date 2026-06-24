#!/bin/bash
# Load saved map yaml on /map via nav2 map_server (RViz-compatible latched QoS).
# Usage: bash scripts/start_saved_map.sh /path/to/map.yaml

set -e
MAP_YAML="$1"
TIMEOUT="${2:-25}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$MAP_YAML" ] || [ ! -f "$MAP_YAML" ]; then
    echo "ERROR: map yaml not found: $MAP_YAML"
    exit 1
fi

source "$SCRIPT_DIR/source_ros_env.sh"

# Kill stale map publishers so only one node owns /map.
pkill -f "static_map_publisher.py" 2>/dev/null || true
pkill -f saved_map_publisher 2>/dev/null || true
pkill -f "nav2_map_server.*map_server" 2>/dev/null || true
pkill -f "/map_server" 2>/dev/null || true
sleep 0.5

echo "Loading saved map: $MAP_YAML"
ros2 run nav2_map_server map_server \
    --ros-args -p "yaml_filename:=$MAP_YAML" -r __node:=saved_map_server &
MAP_PID=$!

for _ in $(seq 1 "$TIMEOUT"); do
    if ! kill -0 "$MAP_PID" 2>/dev/null; then
        echo "ERROR: map_server exited during startup."
        exit 1
    fi

    STATE=$(ros2 lifecycle get /saved_map_server 2>/dev/null | awk '{print $1}')
    case "$STATE" in
        active)
            if ros2 topic echo /map --once \
                --qos-durability transient_local \
                --qos-reliability reliable >/dev/null 2>&1; then
                echo "Saved map publishing on /map (pid $MAP_PID)."
                exit 0
            fi
            ;;
        unconfigured|"")
            ros2 lifecycle set /saved_map_server configure 2>/dev/null || true
            ;;
        inactive)
            ros2 lifecycle set /saved_map_server activate 2>/dev/null || true
            ;;
    esac
    sleep 1
done

echo "ERROR: saved map not on /map after ${TIMEOUT}s."
kill "$MAP_PID" 2>/dev/null || true
exit 1
