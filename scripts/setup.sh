#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Installing ROS 2 Jazzy dependencies for RPLiDAR SLAM..."

sudo apt update
sudo apt install -y \
    ros-jazzy-rplidar-ros \
    ros-jazzy-slam-toolbox \
    ros-jazzy-laser-filters \
    ros-jazzy-nav2-map-server \
    ros-jazzy-nav2-amcl \
    ros-jazzy-rviz2 \
    ros-jazzy-eigen3-cmake-module \
    python3-colcon-common-extensions \
    libboost-dev \
    libeigen3-dev \
    git

# --- Laser odometry (rf2o) ---------------------------------------------------
# Handheld with no wheels => slam_toolbox needs a motion prior or it freezes
# and ghosts walls. rf2o estimates motion from the scans and publishes
# odom->base_link. It is not packaged for apt, so build it from source here.
echo "Building rf2o_laser_odometry (laser odometry for the motion prior)..."
WS="$REPO_DIR/ros2_ws"
mkdir -p "$WS/src"
if [ ! -d "$WS/src/rf2o_laser_odometry" ]; then
    git clone --depth 1 -b ros2 \
        https://github.com/MAPIRlab/rf2o_laser_odometry.git \
        "$WS/src/rf2o_laser_odometry"
fi

source /opt/ros/jazzy/setup.bash
( cd "$WS" && colcon build --packages-select rf2o_laser_odometry )

echo "Giving serial port permissions..."
sudo usermod -aG dialout "$USER"
echo "Done. Log out and back in for group changes to take effect."
echo "Then plug in the LiDAR and check: ls /dev/ttyUSB*"
