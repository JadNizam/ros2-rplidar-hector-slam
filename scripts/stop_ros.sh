#!/bin/bash
# stop_ros.sh — Kill all SLAM nodes from this project.
# Run this if Ctrl+C failed or a terminal was closed without clean shutdown.

source /opt/ros/jazzy/setup.bash

echo "Stopping all ROS 2 SLAM nodes..."
# Stop the ROS daemon so stale CLI clients do not keep resources alive.
ros2 daemon stop 2>/dev/null || true
sleep 1
# LiDAR node first — needs time to stop the motor
pkill -SIGTERM -f rplidar_composition 2>/dev/null || true
sleep 2
pkill -f async_slam_toolbox_node 2>/dev/null || true
pkill -f localization_slam_toolbox_node 2>/dev/null || true
pkill -f rf2o_laser_odometry 2>/dev/null || true
pkill -f scan_to_scan_filter_chain 2>/dev/null || true
pkill -f static_transform_publisher 2>/dev/null || true
pkill -f localization_map_viz 2>/dev/null || true
pkill -f "localization_map_viz.py" 2>/dev/null || true
pkill -f rviz_map_publisher 2>/dev/null || true
pkill -f "rviz_map_publisher.py" 2>/dev/null || true
pkill -f "static_map_publisher.py" 2>/dev/null || true
pkill -f static_map_publisher 2>/dev/null || true
pkill -f "nav2_map_server.*map_server" 2>/dev/null || true
pkill -f saved_map_server 2>/dev/null || true
pkill -f map_server 2>/dev/null || true
pkill -f odom_reset_tf 2>/dev/null || true
pkill -f initial_pose_relay 2>/dev/null || true
pkill -f "initial_pose_relay.py" 2>/dev/null || true
pkill -f scan_gate 2>/dev/null || true
pkill -f "scan_gate.py" 2>/dev/null || true
pkill -f rviz2 2>/dev/null || true
pkill -f "ros2 launch" 2>/dev/null || true
pkill -SIGKILL -f rplidar_composition 2>/dev/null || true
pkill -SIGKILL -f async_slam_toolbox_node 2>/dev/null || true
pkill -SIGKILL -f localization_slam_toolbox_node 2>/dev/null || true
pkill -SIGKILL -f rf2o_laser_odometry 2>/dev/null || true
pkill -SIGKILL -f scan_to_scan_filter_chain 2>/dev/null || true
pkill -SIGKILL -f static_transform_publisher 2>/dev/null || true
pkill -SIGKILL -f map_server 2>/dev/null || true
pkill -SIGKILL -f localization_map_viz 2>/dev/null || true
pkill -SIGKILL -f "localization_map_viz.py" 2>/dev/null || true
pkill -SIGKILL -f rviz_map_publisher 2>/dev/null || true
pkill -SIGKILL -f "rviz_map_publisher.py" 2>/dev/null || true
pkill -SIGKILL -f saved_map_publisher 2>/dev/null || true
pkill -SIGKILL -f "static_map_publisher.py" 2>/dev/null || true
pkill -SIGKILL -f static_map_publisher 2>/dev/null || true
pkill -SIGKILL -f saved_map_server 2>/dev/null || true
pkill -SIGKILL -f odom_reset_tf 2>/dev/null || true
pkill -SIGKILL -f initial_pose_relay 2>/dev/null || true
pkill -SIGKILL -f "initial_pose_relay.py" 2>/dev/null || true
pkill -SIGKILL -f scan_gate 2>/dev/null || true
pkill -SIGKILL -f "scan_gate.py" 2>/dev/null || true
pkill -SIGKILL -f rviz2 2>/dev/null || true
pkill -SIGKILL -f "ros2 launch" 2>/dev/null || true
sleep 1
echo "Done. Verify with: ros2 node list"
