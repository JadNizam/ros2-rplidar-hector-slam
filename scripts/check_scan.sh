#!/bin/bash
# Quick scan diagnostics — run while mapping.launch.py is running

source /opt/ros/jazzy/setup.bash

echo "=== Active topics ==="
ros2 topic list | grep -E '/scan|/map|slam'

echo ""
echo "=== /scan publish rate ==="
timeout 5 ros2 topic hz /scan --window 10 2>&1 | grep -E 'average|no new'

echo ""
echo "=== /scan_filtered publish rate ==="
timeout 5 ros2 topic hz /scan_filtered --window 10 2>&1 | grep -E 'average|no new'

echo ""
echo "=== /odom_rf2o publish rate (laser odometry — makes the pose track you) ==="
echo "If this is silent, rf2o isn't running and the pose WILL freeze."
echo "Fix: re-run 'bash scripts/setup.sh', then relaunch."
timeout 5 ros2 topic hz /odom_rf2o --window 10 2>&1 | grep -E 'average|no new'

echo ""
echo "=== /scan frame_id and range info ==="
ros2 topic echo /scan --once 2>&1 | grep -E 'frame_id|angle_min|angle_max|range_min|range_max|scan_time'

echo ""
echo "=== /map publish rate (should be ~3 Hz while mapping) ==="
timeout 5 ros2 topic hz /map --window 5 2>&1 | grep -E 'average|no new'

echo ""
echo "=== slam_toolbox lifecycle state (should be 'active') ==="
ros2 lifecycle get /slam_toolbox 2>&1

echo ""
echo "=== IS THE MAP GROWING? Walk ~2 m during this 6 s check ==="
echo "Watch the Translation x/y below. If they change as you walk, SLAM is"
echo "tracking and the map IS building. If they stay ~0,0 while you walk,"
echo "scan matching is stuck (map frozen)."
echo "--- pose now ---"
timeout 2 ros2 run tf2_ros tf2_echo map base_link 2>&1 | grep -A1 'Translation' | head -2
echo "--- now walk 2 m, then pose again in 4 s ---"
sleep 4
timeout 2 ros2 run tf2_ros tf2_echo map base_link 2>&1 | grep -A1 'Translation' | head -2

echo ""
echo "=== TF tree ==="
timeout 3 ros2 run tf2_tools view_frames 2>&1 | tail -5
echo "(frames.gv saved if tf2_tools is available)"
