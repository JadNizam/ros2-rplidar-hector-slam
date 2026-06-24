#!/bin/bash
# Wait for slam_toolbox lifecycle active; nudge configure/activate if needed.

TIMEOUT="${1:-30}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/source_ros_env.sh"

for _ in $(seq 1 "$TIMEOUT"); do
    STATE=$(ros2 lifecycle get /slam_toolbox 2>/dev/null | awk '{print $1}')
    case "$STATE" in
        active)
            exit 0
            ;;
        unconfigured)
            ros2 lifecycle set /slam_toolbox configure 2>/dev/null || true
            ;;
        inactive)
            ros2 lifecycle set /slam_toolbox activate 2>/dev/null || true
            ;;
    esac
    sleep 1
done

STATE=$(ros2 lifecycle get /slam_toolbox 2>/dev/null | awk '{print $1}')
echo "ERROR: slam_toolbox not active after ${TIMEOUT}s (state: ${STATE:-unknown})."
exit 1
