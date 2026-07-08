#!/bin/bash
# Usage: bash scripts/run_localization_amcl.sh [mapname]

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$REPO_DIR/scripts"

MAPNAME="${1:-my_room}"
MAPPATH="$REPO_DIR/maps/$MAPNAME"

source "$SCRIPT_DIR/source_ros_env.sh"

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

trigger_global_localization() {
    echo "Waiting for AMCL global localization service..."
    for _ in $(seq 1 30); do
        if ros2 service list 2>/dev/null | grep -q '/reinitialize_global_localization'; then
            sleep 1
            ros2 service call /reinitialize_global_localization std_srvs/srv/Empty "{}" \
                >/dev/null 2>&1 && echo "Particles scattered across the map." && return 0
        fi
        sleep 1
    done
    echo "(Could not reach global localization service — AMCL may still self-init.)"
    return 0
}

launch_once() {
    echo "Launching AMCL localization: $MAPNAME"
    ros2 launch launch/localization_amcl.launch.py "map_file:=${MAPPATH}" &
    LAUNCH_PID=$!

    echo "Waiting for map on /map..."
    bash "$SCRIPT_DIR/wait_for_map.sh" 20 /map || true

    if ! bash "$SCRIPT_DIR/wait_for_scan.sh" 30; then
        LAUNCH_PID=""
        return 1
    fi

    if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then
        echo "ERROR: launch exited during startup."
        LAUNCH_PID=""
        return 1
    fi

    trigger_global_localization

    echo ""
    echo "Ready — AMCL is localizing. Walk slowly through open space; the blue"
    echo "particle cloud will shrink onto your true position as scans match the"
    echo "walls. The red arrow is the current estimate. (2D Pose Estimate still"
    echo "works if you want to seed it manually.)"
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
