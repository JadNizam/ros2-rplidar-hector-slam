#!/bin/bash
# Stop stale nodes and reset LiDAR. Sources ROS env automatically.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$REPO_DIR/scripts"

source "$SCRIPT_DIR/source_ros_env.sh"

if [ ! -e /dev/ttyUSB0 ]; then
    echo "Error: /dev/ttyUSB0 not found."
    echo "Run on Windows PowerShell: usbipd attach --wsl --busid <BUSID>"
    exit 1
fi

echo "Stopping any leftover ROS nodes..."
bash "$SCRIPT_DIR/stop_ros.sh" >/dev/null 2>&1 || true
sleep 2

ros2 daemon start 2>/dev/null || true
sleep 1

chmod 666 /dev/ttyUSB0 2>/dev/null || sudo -n chmod 666 /dev/ttyUSB0 2>/dev/null || true

echo "Resetting RPLIDAR C1 before launch..."
bash "$SCRIPT_DIR/reset_lidar.sh" /dev/ttyUSB0 || echo "(reset skipped — launch will retry on failure)"
sleep 3
echo "Port ready."
