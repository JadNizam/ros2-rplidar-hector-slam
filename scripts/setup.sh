#!/bin/bash
set -e

echo "Installing ROS 2 Jazzy dependencies for RPLiDAR SLAM..."

sudo apt update
sudo apt install -y \
    ros-jazzy-rplidar-ros \
    ros-jazzy-slam-toolbox \
    ros-jazzy-laser-filters \
    ros-jazzy-nav2-map-server \
    ros-jazzy-rviz2

echo "Giving serial port permissions..."
sudo usermod -aG dialout "$USER"
echo "Done. Log out and back in for group changes to take effect."
echo "Then plug in the LiDAR and check: ls /dev/ttyUSB*"
