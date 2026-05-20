#!/bin/bash
set -e
source /opt/ros/jazzy/setup.bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP_DIR="$SCRIPT_DIR/../maps"
mkdir -p "$MAP_DIR"

MAPNAME="${1:-slam_map}"
MAPPATH="$MAP_DIR/$MAPNAME"

echo "Saving map: $MAPPATH"

# slam_toolbox is a lifecycle node — ensure it is active before calling the service
STATE=$(ros2 lifecycle get /slam_toolbox 2>/dev/null | awk '{print $1}')
case "$STATE" in
    unconfigured)
        echo "Configuring slam_toolbox..."
        ros2 lifecycle set /slam_toolbox configure
        sleep 1
        echo "Activating slam_toolbox..."
        ros2 lifecycle set /slam_toolbox activate
        sleep 1
        ;;
    inactive)
        echo "Activating slam_toolbox..."
        ros2 lifecycle set /slam_toolbox activate
        sleep 1
        ;;
    active)
        ;;
    *)
        echo "Warning: unexpected lifecycle state '$STATE'"
        ;;
esac

ros2 service call /slam_toolbox/serialize_map \
    slam_toolbox/srv/SerializePoseGraph \
    "{filename: '$MAPPATH'}"

echo ""
echo "Done. Files:"
ls -lh "${MAPPATH}.posegraph" "${MAPPATH}.data" 2>/dev/null || true
