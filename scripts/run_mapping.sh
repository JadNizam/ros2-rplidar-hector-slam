#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."

source "$SCRIPT_DIR/source_ros_env.sh"
bash "$SCRIPT_DIR/prepare_ros_session.sh"

cd "$REPO_DIR"

LAUNCH_PID=""
CLEANED_UP=0

stop_all() {
    if [ -n "$LAUNCH_PID" ]; then
        kill "$LAUNCH_PID" 2>/dev/null || true
        wait "$LAUNCH_PID" 2>/dev/null || true
    fi
    bash "$SCRIPT_DIR/stop_ros.sh" >/dev/null 2>&1 || true
    LAUNCH_PID=""
}

cleanup() {
    if [ "$CLEANED_UP" -eq 1 ]; then
        return 0
    fi
    CLEANED_UP=1
    echo "Stopping ROS 2 SLAM system..."
    trap - SIGINT SIGTERM
    stop_all
    echo "Shutdown complete."
    exit 0
}
trap cleanup SIGINT SIGTERM

echo "Launching RPLIDAR C1 + laser filter + slam_toolbox + RViz..."
launch_once() {
    ros2 launch launch/mapping.launch.py &
    LAUNCH_PID=$!

    echo "Waiting for slam_toolbox to initialize..."
    sleep 10

    if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then
        echo "ERROR: mapping launch exited during startup (LiDAR failed to start)."
        LAUNCH_PID=""
        return 1
    fi

    if ! bash "$SCRIPT_DIR/wait_for_scan.sh" 25; then
        LAUNCH_PID=""
        return 1
    fi

    ros2 lifecycle set /slam_toolbox configure 2>/dev/null || true
    sleep 1
    ros2 lifecycle set /slam_toolbox activate 2>/dev/null || true
    sleep 1

    if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then
        echo "ERROR: mapping launch exited after lifecycle setup."
        LAUNCH_PID=""
        return 1
    fi

    echo "slam_toolbox active — map is building. Walk around the room."
    wait "$LAUNCH_PID"
    launch_status=$?
    LAUNCH_PID=""

    if [ "$launch_status" -ne 0 ]; then
        echo "ERROR: mapping launch exited unexpectedly (exit $launch_status)."
        return 1
    fi

    return 0
}

MAX_ATTEMPTS=3
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    if launch_once; then
        stop_all
        exit 0
    fi

    stop_all

    if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
        echo "Retrying mapping startup ($attempt/$MAX_ATTEMPTS)..."
        sleep 5
        bash "$SCRIPT_DIR/stop_ros.sh" >/dev/null 2>&1 || true
        sleep 2
        bash "$SCRIPT_DIR/reset_lidar.sh" /dev/ttyUSB0 2>/dev/null || true
        sleep 2
        source "$SCRIPT_DIR/source_ros_env.sh"
        ros2 daemon start 2>/dev/null || true
        sleep 1
    fi
done

echo "ERROR: mapping failed after $MAX_ATTEMPTS attempts."
stop_all
exit 1
