#!/bin/bash
set -e

source /opt/ros/jazzy/setup.bash

if [ ! -e /dev/ttyUSB0 ]; then
    echo "Error: /dev/ttyUSB0 not found."
    echo "Run on Windows PowerShell: usbipd attach --wsl --busid 2-4"
    exit 1
fi

sudo chmod 777 /dev/ttyUSB0

# Reset the RPLIDAR C1 via serial before launching.
# Without this, re-launches fail with "Cannot start scan: 80008000/80008002"
# because the device is still in a prior scan state.
echo "Resetting RPLIDAR C1 (STOP + RESET commands over serial)..."
stty -F /dev/ttyUSB0 460800 raw -echo -echoe -echok
printf '\xa5\x25' > /dev/ttyUSB0   # STOP
sleep 0.1
printf '\xa5\x40' > /dev/ttyUSB0   # RESET (firmware restart)
sleep 2
echo "RPLIDAR reset complete."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "Launching RPLIDAR C1 + laser filter + slam_toolbox + RViz..."
ros2 launch launch/mapping.launch.py
