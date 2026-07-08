#!/bin/bash
# Usage: bash scripts/run_localization_auto.sh [mapname]

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$REPO_DIR/scripts"

MAPNAME="${1:-my_room}"
MAPPATH="$REPO_DIR/maps/$MAPNAME"

source "$SCRIPT_DIR/source_ros_env.sh"

[ -f "${MAPPATH}.posegraph" ] || { echo "Missing ${MAPPATH}.posegraph — run: bash scripts/save_map.sh $MAPNAME"; exit 1; }
[ -f "${MAPPATH}.data" ] || { echo "Missing ${MAPPATH}.data — run: bash scripts/save_map.sh $MAPNAME"; exit 1; }
[ -f "${MAPPATH}.yaml" ] || { echo "Missing ${MAPPATH}.yaml — run: bash scripts/save_map.sh $MAPNAME"; exit 1; }

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
    [ "$CLEANED_UP" -eq 1 ] && return 0
    CLEANED_UP=1
    echo "Stopping localization..."
    trap - SIGINT SIGTERM
    stop_all
    exit 0
}
trap cleanup SIGINT SIGTERM

launch_once() {
    echo "Launching auto localization: $MAPNAME"
    ros2 launch launch/localization_auto.launch.py "map_file:=${MAPPATH}" &
    LAUNCH_PID=$!

    echo "Waiting for static map on /map..."
    if ! bash "$SCRIPT_DIR/wait_for_map.sh" 15 /map; then
        LAUNCH_PID=""
        return 1
    fi
    bash "$SCRIPT_DIR/verify_map_topic.sh" || true

    echo "Waiting for slam_toolbox and RViz..."
    bash "$SCRIPT_DIR/wait_for_slam_active.sh" 30 || true
    sleep 3

    if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then
        echo "ERROR: launch exited during startup."
        LAUNCH_PID=""
        return 1
    fi

    if ! bash "$SCRIPT_DIR/wait_for_scan.sh" 25; then
        LAUNCH_PID=""
        return 1
    fi

    echo ""
    echo "Ready — localizing automatically from map origin. Start near where you"
    echo "began mapping, walk slowly, and watch the scan snap to the walls."
    echo "(If it settles wrong, click 2D Pose Estimate to correct.)"
    wait "$LAUNCH_PID"
    local status=$?
    LAUNCH_PID=""
    [ "$status" -eq 0 ] && return 0
    return 1
}

MAX_ATTEMPTS=3
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    if launch_once; then
        stop_all
        exit 0
    fi

    stop_all

    if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
        echo "Retrying localization startup ($attempt/$MAX_ATTEMPTS)..."
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

echo "ERROR: localization failed after $MAX_ATTEMPTS attempts."
stop_all
exit 1
