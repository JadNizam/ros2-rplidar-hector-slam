#!/bin/bash
# Source ROS Jazzy + rf2o overlay. Use: source scripts/source_ros_env.sh

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source /opt/ros/jazzy/setup.bash

if [ ! -f "$REPO_DIR/ros2_ws/install/setup.bash" ]; then
    echo "ERROR: rf2o_laser_odometry not built."
    echo "Run: bash scripts/setup.sh"
    return 1 2>/dev/null || exit 1
fi

source "$REPO_DIR/ros2_ws/install/setup.bash"

if ! ros2 pkg prefix rf2o_laser_odometry >/dev/null 2>&1; then
    echo "ERROR: package rf2o_laser_odometry not on ROS path after sourcing overlay."
    echo "Run: bash scripts/setup.sh"
    return 1 2>/dev/null || exit 1
fi
