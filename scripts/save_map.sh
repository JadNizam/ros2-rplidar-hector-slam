#!/bin/bash
# Save the current map to maps/

source /opt/ros/jazzy/setup.bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP_DIR="$SCRIPT_DIR/../maps"
mkdir -p "$MAP_DIR"

MAPNAME="${1:-my_room_$(date +%Y%m%d_%H%M%S)}"
echo "Saving map to: $MAP_DIR/$MAPNAME"

ros2 run nav2_map_server map_saver_cli -f "$MAP_DIR/$MAPNAME" --ros-args -p save_map_timeout:=5.0
echo "Done. Files: $MAP_DIR/$MAPNAME.pgm + $MAP_DIR/$MAPNAME.yaml"
