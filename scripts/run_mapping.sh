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
pkill -f localization_slam_toolbox_node 2>/dev/null || true
pkill -f scan_to_scan_filter_chain 2>/dev/null || true
pkill -f static_transform_publisher 2>/dev/null || true
pkill -f rviz2 2>/dev/null || true
pkill -f "ros2 launch" 2>/dev/null || true
sleep 1
ros2 daemon stop 2>/dev/null || true
sleep 1
ros2 daemon start 2>/dev/null || true
sleep 1

sudo chmod 777 /dev/ttyUSB0
echo "Port ready."

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

