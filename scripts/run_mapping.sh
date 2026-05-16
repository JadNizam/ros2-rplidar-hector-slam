#!/bin/bash
set -e

source /opt/ros/humble/setup.bash

echo "Checking LiDAR port..."
if [ ! -e /dev/ttyUSB0 ]; then
    echo "Error: /dev/ttyUSB0 not found. Is the LiDAR plugged in?"
    exit 1
fi

sudo chmod 777 /dev/ttyUSB0

echo "Launching RPLiDAR + hector_slam..."
ros2 launch launch/mapping.launch.py
