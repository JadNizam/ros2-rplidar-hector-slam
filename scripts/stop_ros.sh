#!/bin/bash
# stop_ros.sh — Kill all SLAM nodes from this project.
# Run this if Ctrl+C failed or a terminal was closed without clean shutdown.

source /opt/ros/jazzy/setup.bash

echo "Stopping all ROS 2 SLAM nodes..."
# LiDAR node first — needs time to stop the motor
pkill -SIGTERM -f rplidar_composition 2>/dev/null || true
sleep 2
pkill -f async_slam_toolbox_node 2>/dev/null || true
pkill -f localization_slam_toolbox_node 2>/dev/null || true
pkill -f scan_to_scan_filter_chain 2>/dev/null || true
pkill -f static_transform_publisher 2>/dev/null || true
pkill -f rviz2 2>/dev/null || true
pkill -f "ros2 launch" 2>/dev/null || true
pkill -SIGKILL -f rplidar_composition 2>/dev/null || true
sleep 1
echo "Done. Verify with: ros2 node list"
