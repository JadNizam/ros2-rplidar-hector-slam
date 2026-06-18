#!/bin/bash
# run_localization.sh — Launch RPLIDAR + slam_toolbox in LOCALIZATION mode
# Usage: bash scripts/run_localization.sh [mapname]
# Map must exist as maps/<mapname>.posegraph (create with serialize_map.sh)

source /opt/ros/jazzy/setup.bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."

# Overlay with rf2o_laser_odometry (built by scripts/setup.sh)
if [ -f "$REPO_DIR/ros2_ws/install/setup.bash" ]; then
    source "$REPO_DIR/ros2_ws/install/setup.bash"
else
    echo "WARNING: rf2o overlay not found at ros2_ws/install — run scripts/setup.sh first."
fi
MAP_DIR="$REPO_DIR/maps"
MAPNAME="${1:-slam_map}"
MAPPATH="$MAP_DIR/$MAPNAME"

if [ ! -f "${MAPPATH}.posegraph" ]; then
    echo "Error: Map not found: ${MAPPATH}.posegraph"
    echo ""
    echo "To create the map:"
    echo "  1. bash scripts/run_mapping.sh       (walk the room)"
    echo "  2. bash scripts/serialize_map.sh $MAPNAME"
    exit 1
fi

if [ ! -e /dev/ttyUSB0 ]; then
    echo "Error: /dev/ttyUSB0 not found."
    echo "Run on Windows PowerShell: usbipd attach --wsl --busid 2-4"
    exit 1
fi

sudo chmod 777 /dev/ttyUSB0

echo "Stopping any leftover ROS nodes..."
pkill -f rplidar_composition 2>/dev/null || true
pkill -f async_slam_toolbox_node 2>/dev/null || true
pkill -f localization_slam_toolbox_node 2>/dev/null || true
pkill -f rf2o_laser_odometry 2>/dev/null || true
pkill -f scan_to_scan_filter_chain 2>/dev/null || true
pkill -f static_transform_publisher 2>/dev/null || true
pkill -f rviz2 2>/dev/null || true
pkill -f "ros2 launch" 2>/dev/null || true
sleep 1
ros2 daemon stop 2>/dev/null || true
sleep 1
ros2 daemon start 2>/dev/null || true
sleep 1

python3 - <<'PYEOF'
import serial, time, sys

PORT = '/dev/ttyUSB0'
BAUD = 460800

def get_info(s):
    s.reset_input_buffer()
    s.write(b'\xa5\x50')  # GET_INFO
    s.flush()
    resp = s.read(20)
    return len(resp) >= 7 and resp[0:2] == b'\xa5\x5a'

def stop_and_check(s):
    s.reset_input_buffer()
    s.write(b'\xa5\x25')  # STOP
    s.flush()
    time.sleep(1.0)
    return get_info(s)

s = serial.Serial(PORT, BAUD, timeout=2)

if stop_and_check(s):
    print('LiDAR stopped and responding — ready.')
    s.reset_input_buffer()
    s.close()
    sys.exit(0)

print('STOP did not get response, sending RESET...')
s.reset_input_buffer()
s.write(b'\xa5\x40')  # RESET
s.flush()
time.sleep(6)

if stop_and_check(s):
    print('LiDAR reset and responding — ready.')
    s.reset_input_buffer()
    s.close()
    sys.exit(0)

print('Waiting additional 4s...')
time.sleep(4)
stop_and_check(s)
s.reset_input_buffer()
s.close()
print('Proceeding.')
PYEOF
echo "Port ready."

echo "Launching LOCALIZATION mode with map: $MAPNAME"
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

launch_once() {
    ros2 launch launch/localization.launch.py map_file:="$MAPPATH" &
    LAUNCH_PID=$!

    echo "Waiting for slam_toolbox to initialize..."
    sleep 8
    ros2 lifecycle set /slam_toolbox configure 2>/dev/null || true
    sleep 1
    ros2 lifecycle set /slam_toolbox activate 2>/dev/null || true
    echo "slam_toolbox active — walk around to localize."

    if ! timeout 15 ros2 topic echo /scan --once >/dev/null 2>&1; then
        echo "ERROR: /scan is not publishing."
        return 1
    fi

    if ! timeout 15 ros2 topic echo /scan_filtered --once >/dev/null 2>&1; then
        echo "ERROR: /scan_filtered is not publishing."
        return 1
    fi

    wait "$LAUNCH_PID"
    launch_status=$?
    LAUNCH_PID=""

    if [ "$launch_status" -ne 0 ]; then
        echo "ERROR: localization launch exited unexpectedly."
        return 1
    fi

    return 0
}

MAX_ATTEMPTS=2
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    if launch_once; then
        stop_all
        exit 0
    fi

    stop_all

    if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
        echo "Retrying localization startup ($attempt/$MAX_ATTEMPTS)..."
        sleep 3
    fi
done

echo "ERROR: localization failed after $MAX_ATTEMPTS attempts."
stop_all
exit 1
