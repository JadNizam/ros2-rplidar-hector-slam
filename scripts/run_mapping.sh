#!/bin/bash
set -e

source /opt/ros/jazzy/setup.bash

if [ ! -e /dev/ttyUSB0 ]; then
    echo "Error: /dev/ttyUSB0 not found."
    echo "Run on Windows PowerShell: usbipd attach --wsl --busid 2-4"
    exit 1
fi

echo "Stopping any leftover ROS nodes..."
pkill -f rplidar_composition 2>/dev/null || true
pkill -f async_slam_toolbox_node 2>/dev/null || true
pkill -f scan_to_scan_filter_chain 2>/dev/null || true
pkill -f rviz2 2>/dev/null || true
sleep 2

sudo chmod 777 /dev/ttyUSB0

echo "Resetting RPLIDAR C1..."
stty -F /dev/ttyUSB0 460800 raw -echo -echoe -echok
printf '\xa5\x25' > /dev/ttyUSB0
sleep 0.5
printf '\xa5\x25' > /dev/ttyUSB0
sleep 0.5
printf '\xa5\x40' > /dev/ttyUSB0
sleep 4
echo "RPLIDAR reset complete."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

cleanup() { kill $LAUNCH_PID 2>/dev/null || true; exit 0; }
trap cleanup INT TERM

echo "Launching RPLIDAR C1 + laser filter + slam_toolbox + RViz..."
ros2 launch launch/mapping.launch.py &
LAUNCH_PID=$!

echo "Waiting for slam_toolbox to initialize..."
sleep 8
ros2 lifecycle set /slam_toolbox configure 2>/dev/null || true
sleep 1
ros2 lifecycle set /slam_toolbox activate 2>/dev/null || true
echo "slam_toolbox active — map is building. Walk around the room."

wait $LAUNCH_PID

