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
echo "=== /scan frame_id and range info ==="
ros2 topic echo /scan --once 2>&1 | grep -E 'frame_id|angle_min|angle_max|range_min|range_max|scan_time'

echo ""
echo "=== TF tree ==="
timeout 3 ros2 run tf2_tools view_frames 2>&1 | tail -5
echo "(frames.gv saved if tf2_tools is available)"
