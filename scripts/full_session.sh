#!/bin/bash
# full_session.sh — map, save, then localize in one script
# Usage: bash scripts/full_session.sh [mapname]
# Requires RPLIDAR attached via usbipd: usbipd attach --wsl --busid 2-4

set -e
source /opt/ros/jazzy/setup.bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
MAP_DIR="$REPO_DIR/maps"
MAPNAME="${1:-my_room}"
MAPPATH="$MAP_DIR/$MAPNAME"

mkdir -p "$MAP_DIR"

if [ ! -e /dev/ttyUSB0 ]; then
    echo "ERROR: /dev/ttyUSB0 not found."
    echo "  Run in PowerShell first:  usbipd attach --wsl --busid 2-4"
    exit 1
fi

sudo chmod 777 /dev/ttyUSB0

echo ""
echo "=== [1/3] Resetting RPLIDAR C1 ==="
stty -F /dev/ttyUSB0 460800 raw -echo -echoe -echok
printf '\xa5\x25' > /dev/ttyUSB0   # STOP
sleep 0.1
printf '\xa5\x40' > /dev/ttyUSB0   # RESET
sleep 2
echo "Reset complete."

echo ""
echo "=== [2/3] Launching mapping (RViz will open) ==="
echo "  Walk around the room to build the map."
echo ""
cd "$REPO_DIR"
ros2 launch launch/mapping.launch.py &
LAUNCH_PID=$!

echo ""
echo "  Map is building. When done walking, press ENTER to save and switch to localization."
read -r

echo ""
echo "=== Saving PGM map to: $MAPPATH ==="
ros2 run nav2_map_server map_saver_cli \
    -f "$MAPPATH" \
    --ros-args -p save_map_timeout:=5.0
echo "  Saved: ${MAPPATH}.pgm + ${MAPPATH}.yaml"

echo ""
echo "=== Saving slam_toolbox pose graph to: $MAPPATH ==="
ros2 service call /slam_toolbox/serialize_map \
    slam_toolbox/srv/SerializePoseGraph \
    "{filename: '$MAPPATH'}" || echo "  (serialize service call failed — localization will not work)"
echo "  Saved: ${MAPPATH}.posegraph + ${MAPPATH}.data"

echo ""
echo "  Press ENTER to stop mapping and relaunch in LOCALIZATION mode."
echo "  (Ctrl+C to stay in mapping.)"
read -r

echo ""
echo "=== Stopping mapping... ==="
kill "$LAUNCH_PID" 2>/dev/null || true
sleep 1
pkill -f "rplidar_composition" 2>/dev/null || true
pkill -f "slam_toolbox" 2>/dev/null || true
pkill -f "scan_to_scan_filter_chain" 2>/dev/null || true
pkill -f "rviz2" 2>/dev/null || true
sleep 2

echo ""
echo "=== [3/3] Resetting RPLIDAR for localization ==="
stty -F /dev/ttyUSB0 460800 raw -echo -echoe -echok
printf '\xa5\x25' > /dev/ttyUSB0
sleep 0.1
printf '\xa5\x40' > /dev/ttyUSB0
sleep 2
echo "Reset complete."

if [ ! -f "${MAPPATH}.posegraph" ]; then
    echo "ERROR: Pose graph not found — cannot localize."
    exit 1
fi

echo ""
echo "=== Launching LOCALIZATION mode with map: $MAPNAME ==="
ros2 launch launch/localization.launch.py map_file:="$MAPPATH"
