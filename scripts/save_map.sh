#!/bin/bash
# Save occupancy grid (.yaml + image) and slam_toolbox posegraph (.posegraph + .data).
# Requires mapping to be running (slam_toolbox active).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/source_ros_env.sh"
MAP_DIR="$SCRIPT_DIR/../maps"
mkdir -p "$MAP_DIR"

MAPNAME="${1:-my_room_$(date +%Y%m%d_%H%M%S)}"
MAPPATH="$MAP_DIR/$MAPNAME"
FMT="${2:-png}"

if ! ros2 node list 2>/dev/null | grep -q '/slam_toolbox'; then
    echo "Error: /slam_toolbox is not running. Start mapping first:"
    echo "  bash scripts/run_mapping.sh"
    exit 1
fi

STATE=$(ros2 lifecycle get /slam_toolbox 2>/dev/null | awk '{print $1}')
case "$STATE" in
    unconfigured)
        ros2 lifecycle set /slam_toolbox configure
        sleep 1
        ros2 lifecycle set /slam_toolbox activate
        sleep 1
        ;;
    inactive)
        ros2 lifecycle set /slam_toolbox activate
        sleep 1
        ;;
    active) ;;
    *)
        echo "Warning: slam_toolbox state '$STATE' — continuing..."
        ;;
esac

if ! ros2 service list 2>/dev/null | grep -q '/slam_toolbox/serialize_map'; then
    echo "Error: /slam_toolbox/serialize_map not available."
    exit 1
fi

echo "Saving posegraph: $MAPPATH.posegraph"
ros2 service call /slam_toolbox/serialize_map \
    slam_toolbox/srv/SerializePoseGraph \
    "{filename: '$MAPPATH'}"

echo "Saving occupancy grid: $MAPPATH.$FMT + $MAPPATH.yaml"
ros2 run nav2_map_server map_saver_cli \
    -f "$MAPPATH" \
    --fmt "$FMT" \
    --ros-args \
    -p save_map_timeout:=20.0 \
    -p map_subscribe_transient_local:=true

echo ""
echo "Done:"
ls -lh "${MAPPATH}.posegraph" "${MAPPATH}.data" "${MAPPATH}.yaml" "${MAPPATH}.${FMT}" 2>/dev/null || true
