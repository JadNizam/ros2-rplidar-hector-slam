#!/bin/bash
# run_localization.sh — Launch RPLIDAR + slam_toolbox in LOCALIZATION mode
# Usage: bash scripts/run_localization.sh [mapname]
# Map must exist as maps/<mapname>.posegraph (create with serialize_map.sh)

set -e
source /opt/ros/jazzy/setup.bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
MAP_DIR="$REPO_DIR/maps"
MAPNAME="${1:-slam_map}"
MAPPATH="$MAP_DIR/$MAPNAME"

if [ ! -f "${MAPPATH}.posegraph" ]; then
    echo "Error: Map not found: ${MAPPATH}.posegraph"
    echo ""
    echo "To create the map:"
    echo "  1. bash scripts/run_mapping.sh       (walk the room)"
    echo "  2. bash scripts/serialize_map.sh $MAPNAME"
    exit 1
fi

if [ ! -e /dev/ttyUSB0 ]; then
    echo "Error: /dev/ttyUSB0 not found."
    echo "Run on Windows PowerShell: usbipd attach --wsl --busid 2-4"
    exit 1
fi

sudo chmod 777 /dev/ttyUSB0

echo "Resetting RPLIDAR C1 (STOP + RESET commands over serial)..."
stty -F /dev/ttyUSB0 460800 raw -echo -echoe -echok
printf '\xa5\x25' > /dev/ttyUSB0
sleep 0.1
printf '\xa5\x40' > /dev/ttyUSB0
sleep 2
echo "RPLIDAR reset complete."

echo "Launching LOCALIZATION mode with map: $MAPNAME"
cd "$REPO_DIR"
ros2 launch launch/localization.launch.py map_file:="$MAPPATH"
