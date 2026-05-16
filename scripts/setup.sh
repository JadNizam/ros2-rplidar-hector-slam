#!/bin/bash
set -e

echo "Installing ROS 2 Humble dependencies for RPLiDAR SLAM..."

sudo apt update
sudo apt install -y \
    ros-humble-rplidar-ros \
    ros-humble-hector-slam \
    ros-humble-nav2-map-server \
    ros-humble-rviz2

echo "Giving serial port permissions..."
sudo usermod -aG dialout "$USER"
echo "Done. Log out and back in for group changes to take effect."
echo "Then plug in the LiDAR and check: ls /dev/ttyUSB*"
