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

echo "Stopping any leftover ROS nodes..."
pkill -f rplidar_composition 2>/dev/null || true
pkill -f async_slam_toolbox_node 2>/dev/null || true
pkill -f localization_slam_toolbox_node 2>/dev/null || true
pkill -f scan_to_scan_filter_chain 2>/dev/null || true
pkill -f rviz2 2>/dev/null || true
sleep 2

echo "Resetting RPLIDAR C1..."
stty -F /dev/ttyUSB0 460800 raw -echo -echoe -echok
printf '\xa5\x25' > /dev/ttyUSB0
sleep 0.5
printf '\xa5\x25' > /dev/ttyUSB0
sleep 0.5
printf '\xa5\x40' > /dev/ttyUSB0
sleep 4
echo "RPLIDAR reset complete."

echo "Launching LOCALIZATION mode with map: $MAPNAME"
cd "$REPO_DIR"

cleanup() { kill $LAUNCH_PID 2>/dev/null || true; exit 0; }
trap cleanup INT TERM

ros2 launch launch/localization.launch.py map_file:="$MAPPATH" &
LAUNCH_PID=$!

echo "Waiting for slam_toolbox to initialize..."
sleep 8
ros2 lifecycle set /slam_toolbox configure 2>/dev/null || true
sleep 1
ros2 lifecycle set /slam_toolbox activate 2>/dev/null || true
echo "slam_toolbox active — walk around to localize."

wait $LAUNCH_PID
